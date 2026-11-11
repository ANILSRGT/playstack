import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../config/reel_kit_config.dart';
import '../controller/reel_playback_state.dart';
import '../controller/reel_player_controller.dart';
import '../feed/reel_feed_config.dart';
import '../feed/reel_feed_item.dart';
import '../feed/reel_feed_manager.dart';
import '../fullscreen/reel_fullscreen_manager.dart';
import '../manager/reel_kit_manager.dart';
import '../view/reel_video_view.dart';
import 'reel_default_controls.dart';
import 'reel_feed_transition.dart';

/// Builds part of a page of a [ReelFeedView].
typedef ReelFeedPageBuilder<T> = Widget Function(
  BuildContext context,
  ReelFeedPage<T> page,
);

/// Everything a [ReelFeedView] builder needs to know about one page.
@immutable
class ReelFeedPage<T> {
  /// Creates page details. [ReelFeedView] creates these.
  const ReelFeedPage({
    required this.feed,
    required this.view,
    required this.item,
    required this.index,
    required this.controller,
    required this.isActive,
    required this.isFullscreen,
  });

  /// Your item: an element of [ReelFeedView.items].
  T get data => item.data as T;

  /// The item's player controller: play, pause, seek, state.
  final ReelPlayerController controller;

  /// Whether this is the item in view (the one that plays).
  final bool isActive;

  /// Whether the view is in fullscreen.
  final bool isFullscreen;

  /// Index of the item in the feed.
  final int index;

  /// Moves the view and switches fullscreen and sound.
  final ReelFeedViewController view;

  /// The feed the page belongs to.
  final ReelFeedManager feed;

  /// The feed entry of the item (id, source, poster).
  final ReelFeedItem item;

  @override
  bool operator ==(Object other) =>
      other is ReelFeedPage<T> &&
      other.feed == feed &&
      other.view == view &&
      other.item == item &&
      other.index == index &&
      other.controller == controller &&
      other.isActive == isActive &&
      other.isFullscreen == isFullscreen;

  @override
  int get hashCode =>
      Object.hash(feed, view, item, index, controller, isActive, isFullscreen);
}

/// Controls a [ReelFeedView] from code: next and previous page, fullscreen,
/// sound.
///
/// Builders get the view's controller as [ReelFeedPage.view]. To use it
/// outside the view, create one and pass it to [ReelFeedView.controller].
/// It notifies its listeners when the page in view, the items or
/// fullscreen change, so a `ListenableBuilder` can show them, for example
/// to hide an app bar in fullscreen.
class ReelFeedViewController extends ChangeNotifier {
  _ReelFeedViewState<dynamic>? _view;

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _notify());
    } else {
      _notify();
    }
  }

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Whether a [ReelFeedView] uses this controller.
  bool get isAttached => _view != null;

  /// The feed shown, or null until the view has started it.
  ReelFeedManager? get feed => _view?._feed;

  /// The manager playing the feed, for stats, cache or network status.
  ReelKitManager? get manager => feed?.manager;

  /// Index of the page in view, or null.
  int? get index => feed?.activeIndex.value;

  /// The scroll position in pages (fractional while moving), or null.
  double? get page {
    final pages = _view?._pages;
    if (pages == null || !pages.hasClients) return null;
    return pages.page;
  }

  /// Whether the view is in fullscreen.
  bool get isFullscreen => _view?._isFullscreen ?? false;

  /// Animates to the next page. Does nothing on the last page.
  Future<void> nextPage({Duration? duration, Curve? curve}) {
    final length = _attached._feed?.length ?? 0;
    final next = (index ?? -1) + 1;
    if (next >= length) return Future<void>.value();
    return animateTo(next, duration: duration, curve: curve);
  }

  /// Animates to the previous page. Does nothing on the first page.
  Future<void> previousPage({Duration? duration, Curve? curve}) {
    _attached;
    final previous = (index ?? 0) - 1;
    if (previous < 0) return Future<void>.value();
    return animateTo(previous, duration: duration, curve: curve);
  }

  /// Animates to the page at [index], with the view's transition.
  Future<void> animateTo(int index, {Duration? duration, Curve? curve}) {
    final view = _attached;
    final pages = view._checkedPages(index);
    if (pages == null) return Future<void>.value();
    return pages.animateToPage(
      index,
      duration: duration ?? view.widget.transitionDuration,
      curve: curve ?? view.widget.transitionCurve,
    );
  }

  /// Shows the page at [index] without animation.
  void jumpTo(int index) {
    _attached._checkedPages(index)?.jumpToPage(index);
  }

  /// Shows the video in view fullscreen, rotated to match it, at full
  /// quality. Swiping is locked and the back button leaves fullscreen.
  Future<void> enterFullscreen() => _attached._enterFullscreen();

  /// Leaves fullscreen.
  Future<void> exitFullscreen() => _attached._exitFullscreen();

  /// Enters or leaves fullscreen.
  Future<void> toggleFullscreen() =>
      isFullscreen ? exitFullscreen() : enterFullscreen();

  /// Mutes or unmutes every video of the feed.
  void setMuted(bool muted) => feed?.setMuted(muted);

  _ReelFeedViewState<dynamic> get _attached {
    final view = _view;
    if (view == null) {
      throw StateError('ReelFeedViewController is not attached to a view.');
    }
    return view;
  }
}

/// A complete short-video feed screen.
///
/// Give it your items and say where each video is. It creates the players,
/// plays the video in view, prepares the next ones, loads more items when
/// the user nears the end and cleans up when it leaves the screen:
///
/// ```dart
/// ReelFeedView<Post>(
///   items: posts,
///   videoUrl: (post) => post.videoUrl,
///   posterUrl: (post) => post.thumbnailUrl,      // optional
///   onLoadMore: () => api.fetchPosts(after: ...), // optional
/// )
/// ```
///
/// A list of URLs needs nothing else: `ReelFeedView(items: urls)`.
///
/// It shows [ReelDefaultControls]: tap to pause, sound, progress, a
/// fullscreen button for landscape videos, retry. Draw your own with
/// [controlsBuilder], which gets each page with your item as
/// [ReelFeedPage.data]. Change how pages move with [transition] and
/// [scrollDirection].
///
/// The defaults ([ReelKitConfig.reels], [ReelFeedConfig.reels]) are tuned
/// for fast swiping; pass [manager] or [feedConfig] to change them. To
/// manage the items yourself, create a feed and use [ReelFeedView.feed].
class ReelFeedView<T> extends StatefulWidget {
  /// Creates a feed of [items].
  ///
  /// Where the video of an item is: [videoUrl], or [source] for assets,
  /// files and headers. Items that are themselves URL strings or
  /// [ReelSource]s need neither.
  const ReelFeedView({
    super.key,
    required List<T> this.items,
    this.videoUrl,
    this.source,
    this.posterUrl,
    this.poster,
    this.itemId,
    this.onLoadMore,
    this.manager,
    this.feedConfig = ReelFeedConfig.reels,
    this.controller,
    this.initialIndex = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.transition = ReelFeedTransition.slide,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.transitionCurve = Curves.easeOutCubic,
    this.physics,
    this.fit,
    this.backgroundColor = const Color(0xFF000000),
    this.videoBuilder,
    this.controlsBuilder = ReelDefaultControls.builder,
    this.emptyBuilder,
    this.onPageChanged,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
  }) : feed = null,
       onEndReached = null,
       assert(loadMoreThreshold >= 0),
       assert(precachePosters >= 0);

  /// Shows a [ReelFeedManager] you created and manage: you add and remove
  /// items, and dispose it. Your item is the [ReelFeedItem.data] of each
  /// entry.
  const ReelFeedView.feed({
    super.key,
    required ReelFeedManager this.feed,
    this.onEndReached,
    this.controller,
    this.initialIndex = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.transition = ReelFeedTransition.slide,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.transitionCurve = Curves.easeOutCubic,
    this.physics,
    this.fit,
    this.backgroundColor = const Color(0xFF000000),
    this.videoBuilder,
    this.controlsBuilder = ReelDefaultControls.builder,
    this.emptyBuilder,
    this.onPageChanged,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
  }) : items = null,
       videoUrl = null,
       source = null,
       posterUrl = null,
       poster = null,
       itemId = null,
       onLoadMore = null,
       manager = null,
       feedConfig = ReelFeedConfig.reels,
       assert(loadMoreThreshold >= 0),
       assert(precachePosters >= 0);

  /// Your items, in order. When you pass a new list that starts with the
  /// old one, the new items are appended; any other list replaces the feed.
  final List<T>? items;

  /// The URL of an item's video (HLS, DASH or a file such as MP4).
  final String Function(T item)? videoUrl;

  /// An item's video as a [ReelSource], for assets, files or HTTP headers.
  final ReelSource Function(T item)? source;

  /// The URL of an image shown until the video's first frame, usually the
  /// first frame itself. Without a poster the page is black meanwhile.
  final String? Function(T item)? posterUrl;

  /// Like [posterUrl], for any image (an asset, a memory image).
  final ImageProvider? Function(T item)? poster;

  /// A unique, stable id of an item. Needed only when you pass a new
  /// [items] list that reorders or removes items: players then follow
  /// their items instead of starting over.
  final String Function(T item)? itemId;

  /// Called when the user nears the end; return the next items, or an
  /// empty list when there are no more. Called again only after the
  /// previous call completed. Errors are reported to `FlutterError` and
  /// the next approach to the end tries again.
  final Future<List<T>> Function()? onLoadMore;

  /// The manager that plays the feed. By default the view creates one with
  /// [ReelKitConfig.reels] and disposes it with the view. A manager you
  /// pass is initialized if needed and never disposed by the view.
  final ReelKitManager? manager;

  /// Preloading settings, [ReelFeedConfig.reels] by default.
  final ReelFeedConfig feedConfig;

  /// The feed of [ReelFeedView.feed].
  final ReelFeedManager? feed;

  /// [ReelFeedView.feed] only: called when the user is [loadMoreThreshold]
  /// items from the end, once per feed length. Append items to the feed
  /// there.
  final VoidCallback? onEndReached;

  /// Controls the view from code. Optional: builders get the view's
  /// controller as [ReelFeedPage.view].
  final ReelFeedViewController? controller;

  /// The page shown first.
  final int initialIndex;

  /// The swipe direction: [Axis.vertical] for reels, [Axis.horizontal] for
  /// stories or a carousel.
  final Axis scrollDirection;

  /// Whether the next item comes from above (vertical) or from the left
  /// (horizontal) instead.
  final bool reverse;

  /// How pages move from one to the next.
  final ReelFeedTransition transition;

  /// Duration of moves made from code and by [autoAdvance].
  final Duration transitionDuration;

  /// Curve of moves made from code and by [autoAdvance].
  final Curve transitionCurve;

  /// Scroll physics. Swiping is locked in fullscreen regardless.
  final ScrollPhysics? physics;

  /// How videos fit the page. By default portrait videos fill it and
  /// landscape videos are shown whole.
  final BoxFit? fit;

  /// Painted behind every page.
  final Color backgroundColor;

  /// Replaces the video layer of each page.
  final ReelFeedPageBuilder<T>? videoBuilder;

  /// Draws everything above the video: buttons, captions, progress.
  /// Defaults to [ReelDefaultControls]; null shows nothing.
  final ReelFeedPageBuilder<T>? controlsBuilder;

  /// Shown while the feed has no items.
  final WidgetBuilder? emptyBuilder;

  /// Called when the page in view changes.
  final ValueChanged<int>? onPageChanged;

  /// How many items before the end [onLoadMore] (or [onEndReached]) is
  /// called.
  final int loadMoreThreshold;

  /// How many posters of the next items are downloaded ahead of time.
  final int precachePosters;

  /// Whether the view moves to the next page when a video ends. Needs
  /// videos that do not loop (`ReelPlayerConfig.looping: false`).
  final bool autoAdvance;

  @override
  State<ReelFeedView<T>> createState() => _ReelFeedViewState<T>();
}

class _ReelFeedViewState<T> extends State<ReelFeedView<T>> {
  ReelKitManager? _ownedManager;
  ReelFeedManager? _ownedFeed;
  ReelFeedManager? _listened;
  PageController? _pages;
  ReelFeedViewController? _ownController;
  ReelPlayerController? _watched;
  ReelFullscreenManager? _fullscreen;
  ReelPlayerController? _fullscreenController;
  ReelVideoQualityLimit? _limitBeforeFullscreen;
  bool _isFullscreen = false;
  bool _advanced = false;
  bool _loadingMore = false;
  bool _exhausted = false;
  int _endReachedAtLength = -1;
  int _nextId = 0;

  ReelFeedManager? get _feed => widget.feed ?? _ownedFeed;

  ReelFeedViewController get _controller =>
      widget.controller ?? (_ownController ??= ReelFeedViewController());

  @override
  void initState() {
    super.initState();
    _controller._view = this;
    final feed = widget.feed;
    if (feed != null) {
      _attach(feed);
    } else {
      // Fail right away, not after the engine started, when the view
      // cannot know where the videos are.
      for (final item in widget.items!.take(1)) {
        _toFeedItem(item);
      }
      _nextId = 0;
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    final manager =
        widget.manager ?? ReelKitManager(config: ReelKitConfig.reels());
    if (widget.manager == null) _ownedManager = manager;
    try {
      if (!manager.isInitialized) await manager.initialize();
    } on Object catch (error, stack) {
      _report(error, stack, 'while starting the feed');
      return;
    }
    if (!mounted) return;
    final feed = manager.createFeed([
      for (final item in widget.items!) _toFeedItem(item),
    ], config: widget.feedConfig);
    _ownedFeed = feed;
    setState(() => _attach(feed));
    _controller._changed();
  }

  ReelFeedItem _toFeedItem(T item) {
    final ReelSource source;
    if (widget.source case final toSource?) {
      source = toSource(item);
    } else if (widget.videoUrl case final toUrl?) {
      source = ReelSource.network(toUrl(item));
    } else if (item is String) {
      source = ReelSource.network(item);
    } else if (item is ReelSource) {
      source = item;
    } else {
      throw ArgumentError(
        'ReelFeedView does not know where the video of a ${item.runtimeType} '
        'is. Pass videoUrl: (item) => item.yourVideoUrl.',
      );
    }
    final url = widget.posterUrl?.call(item);
    return ReelFeedItem(
      source,
      id: widget.itemId?.call(item) ?? 'reel-${_nextId++}',
      poster:
          widget.poster?.call(item) ?? (url == null ? null : NetworkImage(url)),
      data: item,
    );
  }

  void _attach(ReelFeedManager feed) {
    final start = _startIndex(feed);
    _pages?.dispose();
    _pages = PageController(initialPage: start);
    _listened = feed..addListener(_onItemsChanged);
    feed.activeIndex.addListener(_onActiveChanged);
    final fullscreen = feed.manager.fullscreen;
    _fullscreen = fullscreen;
    fullscreen.isFullscreen.addListener(_onFullscreenChanged);
    _isFullscreen = fullscreen.isFullscreen.value;
    if (feed.length > 0 && feed.activeIndex.value == null) {
      // Not during build: activating notifies the feed's listeners.
      scheduleMicrotask(() {
        if (mounted && !feed.isDisposed && start < feed.length) {
          if (feed.activeIndex.value == null) feed.setActiveIndex(start);
        }
      });
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _onActiveChanged());
  }

  void _detach() {
    final feed = _listened;
    _listened = null;
    _unwatch();
    _fullscreen?.isFullscreen.removeListener(_onFullscreenChanged);
    if (feed == null || feed.isDisposed) return;
    feed.removeListener(_onItemsChanged);
    feed.activeIndex.removeListener(_onActiveChanged);
  }

  int _startIndex(ReelFeedManager feed) {
    final active = feed.activeIndex.value;
    if (active != null) return active;
    if (feed.length == 0) return 0;
    return widget.initialIndex.clamp(0, feed.length - 1);
  }

  @override
  void didUpdateWidget(ReelFeedView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller;
      if (old != null && old._view == this) old._view = null;
      if (old == null) _ownController?._view = null;
      _controller._view = this;
    }
    final feed = widget.feed;
    if (feed != null && feed != oldWidget.feed) {
      _detach();
      _endReachedAtLength = -1;
      _attach(feed);
    }
    final items = widget.items;
    final owned = _ownedFeed;
    if (owned != null && items != null && !identical(items, oldWidget.items)) {
      _syncItems(owned, oldWidget.items ?? const [], items);
    }
  }

  /// Applies a new [ReelFeedView.items] list: appends when it extends the
  /// previous one, otherwise replaces the feed.
  void _syncItems(ReelFeedManager feed, List<T> before, List<T> after) {
    var extendsBefore = after.length >= before.length;
    for (var i = 0; extendsBefore && i < before.length; i++) {
      if (after[i] != before[i]) extendsBefore = false;
    }
    if (extendsBefore) {
      if (after.length > before.length) {
        feed.addAll([
          for (final item in after.skip(before.length)) _toFeedItem(item),
        ]);
      }
      return;
    }
    _exhausted = false;
    _endReachedAtLength = -1;
    feed.replaceAll([for (final item in after) _toFeedItem(item)]);
  }

  @override
  void dispose() {
    final fullscreen = _fullscreen;
    _detach();
    if (_isFullscreen && fullscreen != null) unawaited(fullscreen.exit());
    if (_controller._view == this) _controller._view = null;
    _ownController?.dispose();
    _pages?.dispose();
    _ownedFeed?.dispose();
    final manager = _ownedManager;
    if (manager != null) unawaited(manager.dispose());
    super.dispose();
  }

  // --- feed events ----------------------------------------------------------

  void _onItemsChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // The feed changed during a build; rebuild after it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    _followFeed();
    _watchActive();
    _controller._changed();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    final index = _feed?.activeIndex.value;
    if (index == null) return;
    _followFeed();
    _watchActive();
    _precache(index);
    _checkEnd(index);
    _controller._changed();
  }

  /// Shows the active item when the feed moved it: items inserted or
  /// removed before it, or `setActiveIndex` called by the app.
  void _followFeed() {
    final pages = _pages;
    final index = _feed?.activeIndex.value;
    if (index == null || pages == null || !pages.hasClients) return;
    final position = pages.position;
    if (!position.hasContentDimensions) return;
    final page = pages.page;
    if (page == null || page.round() == index) return;
    // While the user drags or an animation runs, the page follows on its
    // own through onPageChanged.
    if (position.isScrollingNotifier.value && (page - index).abs() <= 1) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final current = _feed?.activeIndex.value;
      if (!mounted || current == null || !pages.hasClients) return;
      if (pages.page?.round() != current) pages.jumpToPage(current);
    });
  }

  void _onPageChanged(int index) {
    final feed = _feed;
    if (feed == null || feed.isDisposed || index >= feed.length) return;
    feed.setActiveIndex(index);
    widget.onPageChanged?.call(index);
  }

  void _checkEnd(int index) {
    final feed = _feed;
    if (feed == null || index < feed.length - 1 - widget.loadMoreThreshold) {
      return;
    }
    final onEndReached = widget.onEndReached;
    if (onEndReached != null && _endReachedAtLength != feed.length) {
      _endReachedAtLength = feed.length;
      scheduleMicrotask(() {
        if (mounted) onEndReached();
      });
    }
    if (widget.onLoadMore != null) unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    final load = widget.onLoadMore;
    if (load == null || _loadingMore || _exhausted) return;
    _loadingMore = true;
    var added = false;
    try {
      final more = await load();
      final feed = _ownedFeed;
      if (!mounted || feed == null || feed.isDisposed) return;
      if (more.isEmpty) {
        _exhausted = true;
      } else {
        feed.addAll([for (final item in more) _toFeedItem(item)]);
        added = true;
      }
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading more feed items');
    } finally {
      _loadingMore = false;
    }
    // A short page can leave the user near the end still.
    final index = _feed?.activeIndex.value;
    if (added && mounted && index != null) _checkEnd(index);
  }

  void _precache(int index) {
    final feed = _feed;
    if (feed == null) return;
    final end = math.min(feed.length, index + 1 + widget.precachePosters);
    for (var i = index + 1; i < end; i++) {
      final poster = feed.itemAt(i).poster;
      if (poster != null) {
        unawaited(precacheImage(poster, context, onError: (_, _) {}));
      }
    }
  }

  void _watchActive() {
    final active = widget.autoAdvance ? _feed?.activeController : null;
    if (active == _watched) return;
    _unwatch();
    _advanced = false;
    _watched = active?..addListener(_onActiveState);
  }

  void _unwatch() {
    final watched = _watched;
    _watched = null;
    if (watched != null && !watched.isDisposed) {
      watched.removeListener(_onActiveState);
    }
  }

  void _onActiveState() {
    final watched = _watched;
    if (watched == null || !mounted || _isFullscreen) return;
    if (!_advanced && watched.value.status == ReelPlaybackStatus.completed) {
      _advanced = true;
      unawaited(_controller.nextPage());
    }
  }

  // --- navigation and fullscreen ------------------------------------------

  PageController? _checkedPages(int index) {
    final feed = _feed;
    if (feed == null) return null;
    RangeError.checkValueInInterval(index, 0, feed.length - 1, 'index');
    final pages = _pages;
    if (pages == null || !pages.hasClients) {
      feed.setActiveIndex(index);
      return null;
    }
    return pages;
  }

  Future<void> _enterFullscreen() async {
    final controller = _feed?.activeController;
    final fullscreen = _fullscreen;
    if (controller == null || fullscreen == null || _isFullscreen) return;
    _fullscreenController = controller;
    _limitBeforeFullscreen = controller.videoQualityLimit;
    // Fullscreen shows the video at the screen's long side.
    unawaited(
      controller
          .setVideoQualityLimit(ReelVideoQualityLimit.none)
          .catchError(_ignore),
    );
    try {
      await fullscreen.enter(
        orientation: ReelFullscreenOrientation.matchVideo,
        controller: controller,
      );
    } on Object {
      _restoreQuality();
      rethrow;
    }
  }

  Future<void> _exitFullscreen() async {
    await _fullscreen?.exit();
    _restoreQuality();
  }

  void _onFullscreenChanged() {
    final value = _fullscreen?.isFullscreen.value ?? false;
    if (value == _isFullscreen || !mounted) return;
    setState(() => _isFullscreen = value);
    if (!value) _restoreQuality();
    _controller._changed();
  }

  void _restoreQuality() {
    final controller = _fullscreenController;
    final limit = _limitBeforeFullscreen;
    _fullscreenController = null;
    _limitBeforeFullscreen = null;
    if (controller == null || limit == null || controller.isDisposed) return;
    unawaited(controller.setVideoQualityLimit(limit).catchError(_ignore));
  }

  static void _ignore(Object _) {}

  void _report(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'reelkit',
        context: ErrorDescription(context),
      ),
    );
  }

  // --- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final pages = _pages;
    final background = ColoredBox(color: widget.backgroundColor);
    if (feed == null || pages == null) return background;
    if (feed.length == 0) {
      return widget.emptyBuilder?.call(context) ?? background;
    }
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) unawaited(_exitFullscreen());
      },
      child: ColoredBox(
        color: widget.backgroundColor,
        child: LayoutBuilder(
          builder: (context, constraints) => PageView.builder(
            controller: pages,
            scrollDirection: widget.scrollDirection,
            reverse: widget.reverse,
            physics: _isFullscreen
                ? const NeverScrollableScrollPhysics()
                : widget.physics,
            onPageChanged: _onPageChanged,
            itemCount: feed.length,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final index = feed.indexOf(key.value);
              return index < 0 ? null : index;
            },
            itemBuilder: (context, index) {
              final item = feed.itemAt(index);
              Widget page = _PageContent<T>(
                feed: feed,
                view: _controller,
                item: item,
                index: index,
                isFullscreen: _isFullscreen,
                videoBuilder: widget.videoBuilder,
                controlsBuilder: widget.controlsBuilder,
                fit: widget.fit,
              );
              if (!widget.transition.isIdentity) {
                page = _TransitionedPage(
                  pages: pages,
                  index: index,
                  transition: widget.transition,
                  axis: widget.scrollDirection,
                  reverse: widget.reverse,
                  size: constraints.biggest,
                  child: page,
                );
              }
              return KeyedSubtree(key: ValueKey<String>(item.id), child: page);
            },
          ),
        ),
      ),
    );
  }
}

class _PageContent<T> extends StatelessWidget {
  const _PageContent({
    required this.feed,
    required this.view,
    required this.item,
    required this.index,
    required this.isFullscreen,
    required this.videoBuilder,
    required this.controlsBuilder,
    required this.fit,
  });

  final ReelFeedManager feed;
  final ReelFeedViewController view;
  final ReelFeedItem item;
  final int index;
  final bool isFullscreen;
  final ReelFeedPageBuilder<T>? videoBuilder;
  final ReelFeedPageBuilder<T>? controlsBuilder;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final controller = feed.controllerAt(index);
    return ValueListenableBuilder<int?>(
      valueListenable: feed.activeIndex,
      builder: (context, active, _) {
        final page = ReelFeedPage<T>(
          feed: feed,
          view: view,
          item: item,
          index: index,
          controller: controller,
          isActive: active == index,
          isFullscreen: isFullscreen,
        );
        final controls = controlsBuilder?.call(context, page);
        return Stack(
          fit: StackFit.expand,
          children: [
            videoBuilder?.call(context, page) ?? _video(controller),
            ?controls,
          ],
        );
      },
    );
  }

  Widget _video(ReelPlayerController controller) {
    final fixed = fit;
    if (fixed != null) {
      return ReelVideoView(
        controller: controller,
        fit: fixed,
        poster: item.poster,
      );
    }
    return ValueListenableBuilder<ReelPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final landscape = (state.aspectRatio ?? 0) > 1;
        return ReelVideoView(
          controller: controller,
          fit: landscape || isFullscreen ? BoxFit.contain : BoxFit.cover,
          poster: item.poster,
        );
      },
    );
  }
}

class _TransitionedPage extends StatelessWidget {
  const _TransitionedPage({
    required this.pages,
    required this.index,
    required this.transition,
    required this.axis,
    required this.reverse,
    required this.size,
    required this.child,
  });

  final PageController pages;
  final int index;
  final ReelFeedTransition transition;
  final Axis axis;
  final bool reverse;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pages,
      child: child,
      builder: (context, child) {
        var page = pages.initialPage.toDouble();
        if (pages.hasClients && pages.position.hasContentDimensions) {
          page = pages.page ?? page;
        }
        return transition.build(
          context,
          ReelFeedTransitionDetails(
            offset: index - page,
            axis: axis,
            reverse: reverse,
            size: size,
          ),
          child!,
        );
      },
    );
  }
}
