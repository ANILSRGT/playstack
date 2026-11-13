import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        DefaultMaterialLocalizations,
        Icons,
        MaterialLocalizations,
        RefreshIndicator;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../config/playstack_config.dart';
import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../feed/playstack_feed_config.dart';
import '../feed/playstack_feed_item.dart';
import '../feed/playstack_feed_manager.dart';
import '../fullscreen/playstack_fullscreen_manager.dart';
import '../manager/playstack_manager.dart';
import '../pool/playstack_player_pool.dart';
import '../view/playstack_video_view.dart';
import 'playstack_default_controls.dart';
import 'playstack_feed_transition.dart';

/// Signature of [PlayStackFeedView.controlsBuilder] and [PlayStackFeedView.videoBuilder].
///
/// Called for every page that is built (the page in view and its neighbors)
/// and again when the page becomes active or inactive, or when fullscreen
/// changes. [page] tells which item the page shows and gives its controller.
typedef PlayStackFeedPageBuilder<T> = Widget Function(
  BuildContext context,
  PlayStackFeedPage<T> page,
);

/// Signature of [PlayStackFeedView.pageBuilder] and
/// [PlayStackFeedView.lockedBuilder]: builds the page of [item], your object.
/// [isActive] tells whether the page is the one in view, for example to
/// count an ad impression only when it is seen.
typedef PlayStackFeedItemBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  bool isActive,
);

/// One page of a [PlayStackFeedView], as passed to its builders.
///
/// Use it to draw the page's controls:
///
/// ```dart
/// controlsBuilder: (context, page) => Stack(
///   children: [
///     Text(page.data.title),                  // your item, typed
///     if (page.isActive) LiveBadge(),         // only on the page in view
///     IconButton(
///       icon: const Icon(Icons.skip_next),
///       onPressed: page.view.nextPage,        // move the feed
///     ),
///   ],
/// ),
/// ```
///
/// A new [PlayStackFeedPage] is created on every rebuild; do not keep it.
@immutable
class PlayStackFeedPage<T> {
  /// Creates the details of one page. [PlayStackFeedView] creates these for its
  /// builders; apps do not need to.
  const PlayStackFeedPage({
    required this.feed,
    required this.view,
    required this.item,
    required this.index,
    required this.controller,
    required this.isActive,
    required this.isFullscreen,
  });

  /// Your item for this page: the element of [PlayStackFeedView.items] it shows,
  /// with its type. In a `PlayStackFeedView<Post>`, `page.data` is a `Post`.
  ///
  /// With [PlayStackFeedView.feed] it is the [PlayStackFeedItem.data] you attached.
  T get data => item.data as T;

  /// This page with [data] typed as [R], for a feed that mixes item types:
  /// in a `PlayStackFeedView<Object>` of videos and ads, the controls of a
  /// video can take a `PlayStackFeedPage<Video>`.
  ///
  /// ```dart
  /// controlsBuilder: (context, page) => VideoControls(page: page.cast<Video>()),
  /// ```
  PlayStackFeedPage<R> cast<R>() => PlayStackFeedPage<R>(
    feed: feed,
    view: view,
    item: item,
    index: index,
    controller: controller,
    isActive: isActive,
    isFullscreen: isFullscreen,
  );

  /// The video player of this page.
  ///
  /// Read its state to draw controls (`controller.value.isPlaying`,
  /// `isBuffering`, `duration`), and call it to act: `play()`, `pause()`,
  /// `seekTo(...)`, `setMuted(...)`. Rebuild from its state with a
  /// `ValueListenableBuilder<PlayStackPlaybackState>`.
  ///
  /// The feed plays and pauses it as the user swipes; you only call it for
  /// actions of your own, such as a play button.
  final PlayStackPlayerController controller;

  /// Whether this page is the one in view, the one that plays.
  ///
  /// Neighbor pages are built too, ready for the next swipe, with
  /// `isActive` false. Use it to run things only on the visible page, such as
  /// a progress bar or an animation.
  final bool isActive;

  /// Whether the feed is in fullscreen (see
  /// [PlayStackFeedViewController.enterFullscreen]). Hide captions and buttons
  /// there, or show an exit button.
  final bool isFullscreen;

  /// Position of this page in the feed, starting at 0. It changes when items
  /// are inserted above; use [PlayStackFeedItem.id] of [item] to identify the item.
  final int index;

  /// Controls the whole feed from inside a page: [PlayStackFeedViewController.nextPage],
  /// [PlayStackFeedViewController.toggleFullscreen],
  /// [PlayStackFeedViewController.setMuted] and more.
  final PlayStackFeedViewController view;

  /// The feed behind the view: the list of entries, their players and
  /// preloading. Most apps never need it; it is here for advanced use such as
  /// reading [PlayStackFeedManager.stats].
  final PlayStackFeedManager feed;

  /// The feed entry of this page: its [PlayStackFeedItem.id], the
  /// [PlayStackFeedItem.source] being played and the [PlayStackFeedItem.poster]. Your own
  /// object is [data].
  final PlayStackFeedItem item;

  @override
  bool operator ==(Object other) =>
      other is PlayStackFeedPage<T> &&
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

/// How long the user watched one item, passed to
/// [PlayStackFeedView.onItemViewed] when the user leaves the item.
///
/// ```dart
/// onItemViewed: (view) => analytics.log('watched', {
///   'post': view.data.id,
///   'seconds': view.watchTime.inSeconds,
///   'completed': view.completed,
/// }),
/// ```
@immutable
class PlayStackItemView<T> {
  /// Creates a report. [PlayStackFeedView] creates these; apps do not need to.
  const PlayStackItemView({
    required this.item,
    required this.index,
    required this.watchTime,
    required this.duration,
    required this.completed,
    this.position,
  });

  /// Your item, typed, like [PlayStackFeedPage.data].
  T get data => item.data as T;

  /// The feed entry that was watched.
  final PlayStackFeedItem item;

  /// Position of the item in the feed when the user left it.
  final int index;

  /// How long the video actually played while it was in view. Time spent
  /// paused, loading or with the app in the background is not counted;
  /// replays of a looping video are. Zero when the user swiped past before
  /// the video started.
  final Duration watchTime;

  /// Length of the video, or null when it was not known yet (the user left
  /// before it loaded) or the video is a live stream.
  final Duration? duration;

  /// Whether the user watched the video to the end at least once: it played
  /// for as long as it lasts, or it reached its end.
  final bool completed;

  /// Where playback was when the user left, within about half a second.
  /// Save it and pass it back through [PlayStackFeedView.startPosition] to
  /// continue there later. Null when the video never played.
  final Duration? position;

  /// [watchTime] as a fraction of [duration]: 0.5 for half the video, above
  /// 1 for replays. Null when [duration] is unknown.
  double? get watchedFraction {
    final total = duration;
    if (total == null || total <= Duration.zero) return null;
    return watchTime.inMicroseconds / total.inMicroseconds;
  }

  @override
  String toString() =>
      'PlayStackItemView(${item.id}, ${watchTime.inMilliseconds} ms'
      '${position == null ? '' : ', at ${position!.inMilliseconds} ms'}'
      '${completed ? ', completed' : ''})';
}

/// Controls a [PlayStackFeedView] from code: move to the next or previous page,
/// enter fullscreen, mute.
///
/// Inside builders, use [PlayStackFeedPage.view]. To control the view from
/// elsewhere (an app bar, a button outside the feed), create a controller,
/// pass it to [PlayStackFeedView.controller] and dispose it with your state:
///
/// ```dart
/// final view = PlayStackFeedViewController();
///
/// PlayStackFeedView(items: urls, controller: view);
/// IconButton(icon: const Icon(Icons.skip_next), onPressed: view.nextPage);
///
/// @override
/// void dispose() {
///   view.dispose();
///   super.dispose();
/// }
/// ```
///
/// It is a [Listenable]: listeners are notified when the page in view, the
/// items or fullscreen change. Wrap widgets that show its state in a
/// `ListenableBuilder`, for example to hide an app bar in fullscreen.
///
/// Methods that move the view throw a [StateError] while no view uses the
/// controller (see [isAttached]).
class PlayStackFeedViewController extends ChangeNotifier {
  /// Creates a controller. Pass it to [PlayStackFeedView.controller] and call
  /// [dispose] when your state is disposed.
  PlayStackFeedViewController();

  _PlayStackFeedViewState<dynamic>? _view;

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

  /// Whether a [PlayStackFeedView] currently uses this controller. False before the
  /// view is built and after it is removed.
  bool get isAttached => _view != null;

  /// The feed shown by the view, or null until the view has started it (the
  /// first frame after the view appears) and after it is removed.
  PlayStackFeedManager? get feed => _view?._feed;

  /// The manager that plays the feed, or null until the view has started.
  /// Use it for diagnostics: [PlayStackManager.poolStats],
  /// [PlayStackManager.networkStatus], [PlayStackManager.cache].
  PlayStackManager? get manager => feed?.manager;

  /// Index of the page in view, or null before the view has started or when
  /// the feed is empty. Changes as soon as a swipe passes the middle of the
  /// screen.
  int? get index => feed?.activeIndex.value;

  /// The exact scroll position in pages: 2.0 when the third page fills the
  /// screen, 2.5 halfway to the fourth. Null before the view is laid out.
  /// Useful for custom animations tied to scrolling.
  double? get page {
    final pages = _view?._pages;
    if (pages == null || !pages.hasClients) return null;
    return pages.page;
  }

  /// Whether the view is in fullscreen. Listen to the controller to rebuild
  /// when it changes.
  bool get isFullscreen => _view?._isFullscreen ?? false;

  /// Animates to the next page with the view's transition, like a swipe up.
  /// Does nothing on the last page.
  ///
  /// [duration] and [curve] default to [PlayStackFeedView.transitionDuration] and
  /// [PlayStackFeedView.transitionCurve]. The returned future completes when the
  /// animation ends.
  Future<void> nextPage({Duration? duration, Curve? curve}) {
    final length = _attached._feed?.length ?? 0;
    final next = (index ?? -1) + 1;
    if (next >= length) return Future<void>.value();
    return animateTo(next, duration: duration, curve: curve);
  }

  /// Animates to the previous page with the view's transition, like a swipe
  /// down. Does nothing on the first page.
  ///
  /// [duration] and [curve] default to [PlayStackFeedView.transitionDuration] and
  /// [PlayStackFeedView.transitionCurve].
  Future<void> previousPage({Duration? duration, Curve? curve}) {
    _attached;
    final previous = (index ?? 0) - 1;
    if (previous < 0) return Future<void>.value();
    return animateTo(previous, duration: duration, curve: curve);
  }

  /// Animates to the page at [index], passing the pages in between, with the
  /// view's transition. Throws a [RangeError] when [index] is not a valid
  /// page.
  ///
  /// [duration] and [curve] default to [PlayStackFeedView.transitionDuration] and
  /// [PlayStackFeedView.transitionCurve]. For far jumps, [jumpTo] is usually
  /// better.
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

  /// Shows the page at [index] immediately, without animation, for example
  /// to open a feed at a tapped thumbnail. Throws a [RangeError] when [index]
  /// is not a valid page.
  void jumpTo(int index) {
    _attached._checkedPages(index)?.jumpToPage(index);
  }

  /// Index of the page that shows [item], your object (an element of
  /// [PlayStackFeedView.items], or a [PlayStackFeedItem.data]), or -1 when the feed
  /// does not have it. Items are compared with `==`.
  int indexOfItem(Object? item) {
    final feed = this.feed;
    if (feed == null) return -1;
    for (var i = 0; i < feed.length; i++) {
      if (feed.itemAt(i).data == item) return i;
    }
    return -1;
  }

  /// Shows the page of [item] immediately, without animation, for example
  /// the episode picked in an episode list. Throws an [ArgumentError] when
  /// the feed does not have it (see [indexOfItem]).
  ///
  /// ```dart
  /// view.jumpToItem(episodes[7]);
  /// ```
  void jumpToItem(Object? item) => jumpTo(_indexOfExisting(item));

  /// Animates to the page of [item] with the view's transition. Throws an
  /// [ArgumentError] when the feed does not have it.
  Future<void> animateToItem(
    Object? item, {
    Duration? duration,
    Curve? curve,
  }) => animateTo(_indexOfExisting(item), duration: duration, curve: curve);

  int _indexOfExisting(Object? item) {
    _attached;
    final index = indexOfItem(item);
    if (index < 0) {
      throw ArgumentError.value(item, 'item', 'Not in this feed');
    }
    return index;
  }

  /// Shows the video in view fullscreen.
  ///
  /// The video opens on its own route above the app's screens, so bottom
  /// navigation bars, app bars and other widgets around the feed are covered.
  /// The screen rotates to match the video (landscape videos turn the phone
  /// sideways), system bars hide and the quality cap is lifted so the video
  /// plays at full resolution. The back button leaves fullscreen.
  ///
  /// The fullscreen page is built with the same
  /// [PlayStackFeedView.controlsBuilder] and [PlayStackFeedView.videoBuilder],
  /// with [PlayStackFeedPage.isFullscreen] true: return different controls
  /// for fullscreen there.
  ///
  /// Does nothing when already fullscreen or when no video is in view.
  Future<void> enterFullscreen() => _attached._enterFullscreen();

  /// Leaves fullscreen: closes the fullscreen page and restores the
  /// orientation, the system bars and the quality cap.
  Future<void> exitFullscreen() => _attached._exitFullscreen();

  /// Enters fullscreen, or leaves it when already fullscreen. Handy for a
  /// single fullscreen button.
  Future<void> toggleFullscreen() =>
      isFullscreen ? exitFullscreen() : enterFullscreen();

  /// Mutes ([muted] true) or unmutes every video of the feed, including videos
  /// added later, like the sound switch of a short-video app. Does nothing
  /// before the view has started.
  void setMuted(bool muted) => feed?.setMuted(muted);

  /// Pauses the feed: the video in view stops and stays stopped until
  /// [resume], even when the user swipes. Use it while something covers the
  /// feed that does not do it already, such as a comment sheet or a dialog.
  ///
  /// You do not need it for routes pushed over the feed, other tabs or the
  /// app going to the background: the view pauses for those itself (see
  /// [PlayStackFeedView.pauseWhenHidden]).
  void pause() => _attached._setUserPaused(true);

  /// Undoes [pause]: the video in view plays again, unless the view is
  /// hidden.
  void resume() => _attached._setUserPaused(false);

  /// Whether [pause] was called without a matching [resume].
  bool get isPaused => _view?._userPaused ?? false;

  _PlayStackFeedViewState<dynamic> get _attached {
    final view = _view;
    if (view == null) {
      throw StateError(
        'PlayStackFeedViewController is not attached to a view.',
      );
    }
    return view;
  }
}

/// Turns one of the app's items into a feed item.
PlayStackFeedItem _mapFeedItem<T>(
  T item, {
  required String Function() nextId,
  required PlayStackSource? Function(T item)? source,
  required String? Function(T item)? videoUrl,
  required String? Function(T item)? posterUrl,
  required ImageProvider? Function(T item)? poster,
  required String Function(T item)? itemId,
  required Duration? Function(T item)? startPosition,
  required bool Function(T item)? isLocked,
}) {
  final PlayStackSource? video;
  if (source != null) {
    video = source(item);
  } else if (videoUrl != null) {
    final url = videoUrl(item);
    video = url == null ? null : PlayStackSource.network(url);
  } else if (item is String) {
    video = PlayStackSource.network(item);
  } else if (item is PlayStackSource) {
    video = item;
  } else {
    throw ArgumentError(
      'PlayStackFeedView does not know where the video of a '
      '${item.runtimeType} is. Pass videoUrl: (item) => item.yourVideoUrl.',
    );
  }
  final url = posterUrl?.call(item);
  final id = itemId?.call(item) ?? nextId();
  final image = poster?.call(item) ?? (url == null ? null : NetworkImage(url));
  if (video == null) {
    return PlayStackFeedItem.page(id: id, poster: image, data: item);
  }
  return PlayStackFeedItem(
    video,
    id: id,
    poster: image,
    data: item,
    startPosition: startPosition?.call(item),
    locked: isLocked?.call(item) ?? false,
  );
}

/// Starts preparing a feed before its screen opens, for example on the
/// splash screen, so the first video plays the moment the feed appears.
///
/// Create it with the same arguments you would give
/// `PlayStackFeedView(items: ...)`, and show it later with
/// [PlayStackFeedView.preloaded]:
///
/// ```dart
/// // Splash screen, while the app loads:
/// final reels = PlayStackFeedPreload<Post>(
///   items: posts,
///   videoUrl: (post) => post.videoUrl,
///   posterUrl: (post) => post.thumbnailUrl,
/// );
///
/// // Reels screen:
/// PlayStackFeedView<Post>.preloaded(reels, onLoadMore: api.fetchMorePosts)
/// ```
///
/// It starts the engine at once, prepares the first [count] videos from
/// [initialIndex] (without playing them) and downloads their posters.
/// Await [ready] to hold the splash screen until the first video is
/// prepared; it is optional.
///
/// A preload is shown by one view, once. That view takes over its players
/// and releases them when it is removed. If no view ever shows it, call
/// [dispose].
class PlayStackFeedPreload<T> {
  /// Starts preparing [items]. The arguments mean the same as in
  /// `PlayStackFeedView(items: ...)`; [count] is how many videos to prepare,
  /// 2 by default (the first one and the next).
  ///
  /// Pass `looping: false` when the view will use
  /// [PlayStackFeedView.autoAdvance].
  PlayStackFeedPreload({
    required this.items,
    this.videoUrl,
    this.source,
    this.posterUrl,
    this.poster,
    this.itemId,
    this.startPosition,
    this.isLocked,
    this.manager,
    this.feedConfig = PlayStackFeedConfig.reels,
    this.initialIndex = 0,
    this.count = 2,
    bool looping = true,
  }) : assert(count >= 0) {
    // Fail right away when the items have no known video.
    final mapped = [
      for (final item in items)
        _mapFeedItem(
          item,
          nextId: () => 'item-${_nextId++}',
          source: source,
          videoUrl: videoUrl,
          posterUrl: posterUrl,
          poster: poster,
          itemId: itemId,
          startPosition: startPosition,
          isLocked: isLocked,
        ),
    ];
    _started = _start(mapped, looping);
    _started.ignore();
    ready = _started.then((_) => _prepared).catchError((Object _) {});
  }

  /// Your items, as in `PlayStackFeedView.items`.
  final List<T> items;

  /// See `PlayStackFeedView.videoUrl`.
  final String? Function(T item)? videoUrl;

  /// See `PlayStackFeedView.source`.
  final PlayStackSource? Function(T item)? source;

  /// See `PlayStackFeedView.posterUrl`.
  final String? Function(T item)? posterUrl;

  /// See `PlayStackFeedView.poster`.
  final ImageProvider? Function(T item)? poster;

  /// See `PlayStackFeedView.itemId`.
  final String Function(T item)? itemId;

  /// See `PlayStackFeedView.startPosition`.
  final Duration? Function(T item)? startPosition;

  /// See `PlayStackFeedView.isLocked`.
  final bool Function(T item)? isLocked;

  /// The manager to play with; null creates one with
  /// [PlayStackConfig.reels]. A manager you pass stays yours to dispose.
  final PlayStackManager? manager;

  /// See `PlayStackFeedView.feedConfig`.
  final PlayStackFeedConfig feedConfig;

  /// The item the feed opens at, 0 by default. Preparing starts there.
  final int initialIndex;

  /// How many videos are prepared from [initialIndex], 2 by default.
  final int count;

  /// Completes when the first video is prepared, or when preparing it
  /// failed (the feed shows the error and its retry button). Never
  /// completes with an error.
  late final Future<void> ready;

  late final Future<PlayStackFeedManager> _started;
  Future<void> _prepared = Future<void>.value();
  PlayStackManager? _ownedManager;
  PlayStackFeedManager? _feed;
  int _nextId = 0;
  bool _claimed = false;
  bool _disposed = false;

  Future<PlayStackFeedManager> _start(
    List<PlayStackFeedItem> mapped,
    bool looping,
  ) async {
    final manager =
        this.manager ??
        (_ownedManager = PlayStackManager(
          config: PlayStackConfig.reels(looping: looping),
        ));
    if (!manager.isInitialized) await manager.initialize();
    if (_disposed) throw StateError('PlayStackFeedPreload was disposed.');
    final feed = _feed = manager.createFeed(mapped, config: feedConfig);
    final preparing = <Future<void>>[];
    final end = math.min(feed.length, initialIndex + count);
    for (var i = initialIndex; i < end; i++) {
      final item = feed.itemAt(i);
      final image = item.poster;
      if (image != null) _precachePoster(image);
      if (!item.isPlayable) continue;
      final controller = feed.controllerAt(i)
        ..priority = i == initialIndex
            ? PlayStackPlayerPriority.visible
            : PlayStackPlayerPriority.preload;
      preparing.add(controller.initialize().catchError((Object _) {}));
    }
    if (preparing.isNotEmpty) _prepared = preparing.first;
    return feed;
  }

  static void _precachePoster(ImageProvider image) {
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) => stream.removeListener(listener),
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  /// Hands the feed to a view; a preload is shown once.
  Future<PlayStackFeedManager> _claim() {
    if (_claimed) {
      throw StateError(
        'This PlayStackFeedPreload is already shown by a view. Create a new '
        'one for each screen.',
      );
    }
    if (_disposed) throw StateError('This PlayStackFeedPreload was disposed.');
    _claimed = true;
    return _started;
  }

  /// Releases the prepared players when no view showed this preload, for
  /// example when the user never opened the feed. Does nothing once a view
  /// took it over.
  void dispose() {
    if (_claimed || _disposed) return;
    _disposed = true;
    _feed?.dispose();
    final manager = _ownedManager;
    if (manager != null) unawaited(manager.dispose());
  }
}

/// A complete short-video feed screen, like Reels, Shorts or TikTok.
///
/// Give it your items and say where each item's video is:
///
/// ```dart
/// PlayStackFeedView<Post>(
///   items: posts,
///   videoUrl: (post) => post.videoUrl,
///   posterUrl: (post) => post.thumbnailUrl,   // optional
///   onLoadMore: () => api.fetchMorePosts(),   // optional
/// )
/// ```
///
/// A list of URL strings needs nothing else: `PlayStackFeedView(items: urls)`.
///
/// The view then does all the work:
///
/// * creates the video players when it appears and releases them when it is
///   removed;
/// * plays the video in view and pauses the others;
/// * prepares the next videos ahead of time, so a swipe starts them at once;
/// * loads more items through [onLoadMore] when the user nears the end;
/// * downloads posters of the next items;
/// * handles fullscreen, the back button in fullscreen, and app lifecycle.
///
/// What you can change:
///
/// * the controls above each video: [controlsBuilder] (defaults to
///   [PlayStackDefaultControls]);
/// * the swipe direction: [scrollDirection], [reverse];
/// * how pages move: [transition];
/// * how videos fit: [fit], or the whole video layer with [videoBuilder];
/// * playback and preloading settings: [manager], [feedConfig].
///
/// The defaults ([PlayStackConfig.reels], [PlayStackFeedConfig.reels]) are tuned for
/// swiping two or three videos a second.
///
/// To add, insert and remove items from your own code, or to share a feed
/// between screens, create a [PlayStackFeedManager] and use [PlayStackFeedView.feed].
class PlayStackFeedView<T> extends StatefulWidget {
  /// Creates a feed of [items].
  ///
  /// Tell the view where each item's video is with [videoUrl] (a URL) or
  /// [source] (assets, files, HTTP headers). Items that are already URL
  /// strings or [PlayStackSource]s need neither. If the view cannot find a video
  /// for an item, it throws an [ArgumentError] that names the missing
  /// argument.
  const PlayStackFeedView({
    super.key,
    required List<T> this.items,
    this.videoUrl,
    this.source,
    this.posterUrl,
    this.poster,
    this.itemId,
    this.startPosition,
    this.onLoadMore,
    this.manager,
    this.feedConfig = PlayStackFeedConfig.reels,
    this.controller,
    this.initialIndex = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.transition = PlayStackFeedTransition.slide,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.transitionCurve = Curves.easeOutCubic,
    this.physics,
    this.fit,
    this.backgroundColor = const Color(0xFF000000),
    this.videoBuilder,
    this.controlsBuilder = PlayStackDefaultControls.builder,
    this.emptyBuilder,
    this.pageBuilder,
    this.isLocked,
    this.lockedBuilder,
    this.onPageChanged,
    this.onItemViewed,
    this.onRefresh,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
    this.pauseWhenHidden = true,
    this.fullscreenOnRotate = true,
  }) : feed = null,
       preload = null,
       onEndReached = null,
       assert(loadMoreThreshold >= 0),
       assert(precachePosters >= 0);

  /// Shows a feed prepared ahead with [PlayStackFeedPreload], for example on
  /// the splash screen. The first video plays as soon as the view appears.
  ///
  /// The items and how to read them come from [preload]; everything else
  /// works as in the main constructor.
  ///
  /// ```dart
  /// PlayStackFeedView<Post>.preloaded(reels, onLoadMore: api.fetchMorePosts)
  /// ```
  PlayStackFeedView.preloaded(
    PlayStackFeedPreload<T> this.preload, {
    super.key,
    this.onLoadMore,
    this.controller,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.transition = PlayStackFeedTransition.slide,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.transitionCurve = Curves.easeOutCubic,
    this.physics,
    this.fit,
    this.backgroundColor = const Color(0xFF000000),
    this.videoBuilder,
    this.controlsBuilder = PlayStackDefaultControls.builder,
    this.emptyBuilder,
    this.pageBuilder,
    this.lockedBuilder,
    this.onPageChanged,
    this.onItemViewed,
    this.onRefresh,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
    this.pauseWhenHidden = true,
    this.fullscreenOnRotate = true,
  }) : items = preload.items,
       videoUrl = preload.videoUrl,
       source = preload.source,
       posterUrl = preload.posterUrl,
       poster = preload.poster,
       itemId = preload.itemId,
       startPosition = preload.startPosition,
       isLocked = preload.isLocked,
       manager = preload.manager,
       feedConfig = preload.feedConfig,
       initialIndex = preload.initialIndex,
       feed = null,
       onEndReached = null,
       assert(loadMoreThreshold >= 0),
       assert(precachePosters >= 0);

  /// Shows a [PlayStackFeedManager] that you create and own.
  ///
  /// Use this when your code changes the list itself (insert, remove, update
  /// sources) or when several screens share one feed. You add items to the
  /// feed (see [onEndReached]) and dispose it, or its manager, yourself. Your
  /// object is the [PlayStackFeedItem.data] of each entry and arrives in builders as
  /// [PlayStackFeedPage.data].
  ///
  /// ```dart
  /// final feed = manager.createFeed(entries, config: PlayStackFeedConfig.reels);
  /// PlayStackFeedView<Post>.feed(
  ///   feed: feed,
  ///   onEndReached: () => feed.addAll(nextEntries()),
  /// )
  /// ```
  const PlayStackFeedView.feed({
    super.key,
    required PlayStackFeedManager this.feed,
    this.onEndReached,
    this.controller,
    this.initialIndex = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.transition = PlayStackFeedTransition.slide,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.transitionCurve = Curves.easeOutCubic,
    this.physics,
    this.fit,
    this.backgroundColor = const Color(0xFF000000),
    this.videoBuilder,
    this.controlsBuilder = PlayStackDefaultControls.builder,
    this.emptyBuilder,
    this.pageBuilder,
    this.lockedBuilder,
    this.onPageChanged,
    this.onItemViewed,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
    this.pauseWhenHidden = true,
    this.fullscreenOnRotate = true,
  }) : items = null,
       preload = null,
       videoUrl = null,
       source = null,
       posterUrl = null,
       poster = null,
       itemId = null,
       startPosition = null,
       isLocked = null,
       onLoadMore = null,
       onRefresh = null,
       manager = null,
       feedConfig = PlayStackFeedConfig.reels,
       assert(loadMoreThreshold >= 0),
       assert(precachePosters >= 0);

  /// Your items, in display order: posts, videos, URLs, anything.
  ///
  /// Keep the list in your state rather than creating it in `build`. When you
  /// pass a different list:
  ///
  /// * if it starts with the previous items, the extra items are appended and
  ///   playback continues;
  /// * otherwise the feed is replaced, for example after pull to refresh.
  ///
  /// Items loaded through [onLoadMore] are added on top; you do not need to
  /// add them to this list.
  final List<T>? items;

  /// Returns the URL of an item's video: an HLS (`.m3u8`) or DASH (`.mpd`)
  /// stream, or a file such as MP4.
  ///
  /// ```dart
  /// videoUrl: (post) => post.videoUrl,
  /// ```
  ///
  /// Not needed when the items are URL strings. Use [source] instead for
  /// assets, local files or HTTP headers.
  ///
  /// Return null for an item without video, such as an ad: the view builds
  /// its page with [pageBuilder].
  final String? Function(T item)? videoUrl;

  /// Returns an item's video as a [PlayStackSource], when a URL is not enough:
  ///
  /// ```dart
  /// source: (post) => PlayStackSource.network(post.url, headers: {'Authorization': token}),
  /// source: (clip) => PlayStackSource.asset('assets/${clip.file}'),
  /// ```
  ///
  /// Takes precedence over [videoUrl]. Not needed when the items are
  /// [PlayStackSource]s. Return null for an item without video (see
  /// [pageBuilder]).
  final PlayStackSource? Function(T item)? source;

  /// Returns the URL of an image shown until the video's first frame appears,
  /// usually a thumbnail of that frame. Return null for items without one.
  ///
  /// Recommended: without a poster the page stays black while the video
  /// loads. Posters of the next items are downloaded ahead of time (see
  /// [precachePosters]).
  final String? Function(T item)? posterUrl;

  /// Like [posterUrl], for any image: an asset (`AssetImage`), a file or a
  /// cached network image provider. Takes precedence over [posterUrl].
  final ImageProvider? Function(T item)? poster;

  /// Returns a unique, stable id of an item, such as a post id.
  ///
  /// Only needed when you pass a new [items] list that reorders or removes
  /// items: with ids, videos keep playing and prepared videos stay prepared.
  /// Without it, a replaced list starts over. Ids must be unique; the same
  /// id twice throws an [ArgumentError].
  final String Function(T item)? itemId;

  /// Returns where an item's video starts, for example where the user
  /// stopped watching an episode. Return null to start at the beginning.
  ///
  /// ```dart
  /// startPosition: (episode) => progress[episode.id],
  /// ```
  ///
  /// The video is prepared at that point, so it starts there without first
  /// showing the beginning. Save the point with [onItemViewed]
  /// ([PlayStackItemView.position]). A point in the last second of a video starts
  /// it over.
  final Duration? Function(T item)? startPosition;

  /// Loads the next items, for an endless feed.
  ///
  /// Called when the user is [loadMoreThreshold] items from the end. Return
  /// the next items; return an empty list when there are no more, and the
  /// view stops asking.
  ///
  /// ```dart
  /// onLoadMore: () => api.fetchPosts(page: ++page),
  /// ```
  ///
  /// Only one call runs at a time. If it throws, the error is reported to
  /// `FlutterError.onError` and the next approach to the end tries again.
  final Future<List<T>> Function()? onLoadMore;

  /// The manager that plays the videos, to change playback settings.
  ///
  /// By default the view creates one with [PlayStackConfig.reels] and disposes
  /// it when the view is removed. Pass your own to change settings. Start
  /// from the preset to keep its tuning:
  ///
  /// ```dart
  /// manager: PlayStackManager(config: PlayStackConfig.reels(looping: false)),
  /// ```
  ///
  /// A plain `PlayStackConfig()` drops the preset: no screen-sized quality
  /// cap and fewer players.
  ///
  /// An app locked to portrait with `SystemChrome.setPreferredOrientations`
  /// passes the same list here, so that the lock comes back after
  /// fullscreen:
  ///
  /// ```dart
  /// manager: PlayStackManager(
  ///   config: PlayStackConfig.reels(
  ///     appOrientations: [DeviceOrientation.portraitUp],
  ///   ),
  /// ),
  /// ```
  ///
  /// A manager you pass is initialized by the view if needed, and you dispose
  /// it.
  final PlayStackManager? manager;

  /// How many videos are prepared ahead and behind, and how they are limited
  /// on mobile data or low memory. Defaults to [PlayStackFeedConfig.reels]: five
  /// ahead, one behind. Lower it to save data and memory.
  final PlayStackFeedConfig feedConfig;

  /// The feed shown by [PlayStackFeedView.feed]; null with the main constructor.
  final PlayStackFeedManager? feed;

  /// The preload shown by [PlayStackFeedView.preloaded]; null with the other
  /// constructors.
  final PlayStackFeedPreload<T>? preload;

  /// [PlayStackFeedView.feed] only: called when the user is [loadMoreThreshold]
  /// items from the end, once per feed length. Append the next items to your
  /// feed there. With the main constructor use [onLoadMore] instead.
  final VoidCallback? onEndReached;

  /// Controls the view from outside it: next page, fullscreen, mute, current
  /// index. Optional; builders get a controller as [PlayStackFeedPage.view]
  /// anyway. You create and dispose it.
  final PlayStackFeedViewController? controller;

  /// The page shown first, 0 by default. Use it to open the feed at a tapped
  /// item. Ignored when the feed already has a page in view (a rebuilt
  /// [PlayStackFeedView.feed]).
  final int initialIndex;

  /// The swipe direction. [Axis.vertical] (default) for a reels feed,
  /// [Axis.horizontal] for stories or a carousel.
  final Axis scrollDirection;

  /// Reverses the swipe direction: the next item comes from above (vertical)
  /// or from the left (horizontal). False by default.
  final bool reverse;

  /// How pages move from one to the next while the user swipes and when the
  /// view moves from code. [PlayStackFeedTransition.slide] by default; also
  /// [PlayStackFeedTransition.parallax], [PlayStackFeedTransition.stack],
  /// [PlayStackFeedTransition.fade], [PlayStackFeedTransition.zoom],
  /// [PlayStackFeedTransition.cube], or your own with [PlayStackFeedTransition.custom].
  final PlayStackFeedTransition transition;

  /// How long moves made from code take ([PlayStackFeedViewController.nextPage]
  /// and similar) and moves made by [autoAdvance]. Swipes follow the finger
  /// instead. 350 ms by default.
  final Duration transitionDuration;

  /// The easing of moves made from code and by [autoAdvance].
  /// [Curves.easeOutCubic] by default.
  final Curve transitionCurve;

  /// How swiping feels. Null uses the platform's page physics. Pass
  /// `NeverScrollableScrollPhysics()` to turn swiping off, for example while a
  /// comment sheet is open. Swiping is always locked in fullscreen.
  final ScrollPhysics? physics;

  /// How videos fit the page, for every video.
  ///
  /// Null (the default) fills the page with portrait videos (cropping a
  /// little at the edges) and shows landscape videos whole with bars above and
  /// below. Pass [BoxFit.cover] to always fill, [BoxFit.contain] to always
  /// show the whole video.
  final BoxFit? fit;

  /// Color behind the videos, visible around videos that do not fill the page
  /// and while a page has nothing to show. Black by default.
  final Color backgroundColor;

  /// Replaces the video layer of each page, below the controls.
  ///
  /// Rarely needed: use [fit] to change how videos fit. Use this for a
  /// different layout, such as rounded corners or a blurred background:
  ///
  /// ```dart
  /// videoBuilder: (context, page) => PlayStackVideoView(
  ///   controller: page.controller,
  ///   borderRadius: BorderRadius.circular(16),
  /// ),
  /// ```
  final PlayStackFeedPageBuilder<T>? videoBuilder;

  /// Draws everything above the video on each page: buttons, captions, a
  /// progress bar.
  ///
  /// Defaults to [PlayStackDefaultControls] (tap to pause, sound, fullscreen for
  /// landscape videos, progress, buffering indicator, retry). Three ways to
  /// customize:
  ///
  /// ```dart
  /// // Keep the defaults and add your own layer.
  /// controlsBuilder: (context, page) => PlayStackDefaultControls(
  ///   page: page,
  ///   child: Caption(post: page.data),
  /// ),
  ///
  /// // Build your own controls; PlayStackProgressBar, PlayStackBufferingIndicator and
  /// // PlayStackMuteButton are there to reuse.
  /// controlsBuilder: (context, page) => MyControls(page: page),
  ///
  /// // No controls at all.
  /// controlsBuilder: null,
  /// ```
  final PlayStackFeedPageBuilder<T>? controlsBuilder;

  /// Shown when there are no items, for example "No videos yet". Defaults to
  /// an empty screen in [backgroundColor].
  final WidgetBuilder? emptyBuilder;

  /// Builds the pages of items without video: ads, photo posts, "people to
  /// follow" cards. An item has no video when [videoUrl] (or [source])
  /// returns null for it.
  ///
  /// ```dart
  /// PlayStackFeedView<FeedEntry>(
  ///   items: entries,
  ///   videoUrl: (entry) => entry is VideoPost ? entry.url : null,
  ///   pageBuilder: (context, entry, isActive) => AdCard(ad: entry as Ad),
  /// )
  /// ```
  ///
  /// These pages take no player and are never preloaded; the videos around
  /// them still are. Swiping works across them like any page. Without a
  /// builder they show [backgroundColor].
  ///
  /// A page may scroll on its own, for example a `ListView` taller than the
  /// screen. The list scrolls first; once it is at its end and the user
  /// keeps dragging, the feed moves to the next (or previous) page.
  final PlayStackFeedItemBuilder<T>? pageBuilder;

  /// Returns whether an item's video is locked, for example an episode the
  /// user has not unlocked yet.
  ///
  /// ```dart
  /// isLocked: (episode) => episode.number > 9 && !purchases.has(episode),
  /// lockedBuilder: (context, episode, isActive) => Paywall(episode: episode),
  /// ```
  ///
  /// A locked item is never prepared or played, and its page shows its
  /// poster with [lockedBuilder] on top. It is asked again on every rebuild:
  /// after the user unlocks an episode, call `setState` and the video plays.
  /// [autoAdvance] stops at a locked episode.
  final bool Function(T item)? isLocked;

  /// Builds what a locked item shows over its poster: a paywall, a "watch an
  /// ad to unlock" button. Without one, a lock icon is shown. See
  /// [isLocked].
  final PlayStackFeedItemBuilder<T>? lockedBuilder;

  /// Called with the new index when the page in view changes, by a swipe or
  /// from code. Use it for analytics or to sync other UI.
  final ValueChanged<int>? onPageChanged;

  /// How many items before the end [onLoadMore] (or [onEndReached]) is
  /// called. 3 by default: with three items left, the next page is requested.
  /// Raise it if loading is slow.
  final int loadMoreThreshold;

  /// How many posters of the upcoming items are downloaded ahead of time, so
  /// a fast swipe shows a poster instead of black. 3 by default; 0 turns it
  /// off.
  final int precachePosters;

  /// Whether the view moves to the next video when the current one ends,
  /// like stories. False by default.
  ///
  /// Needs videos that do not loop. The view's own manager stops looping
  /// when this is true. A [manager] you pass must not loop either, for
  /// example `PlayStackManager(config: PlayStackConfig.reels(looping: false))`.
  final bool autoAdvance;

  /// Whether the view pauses itself while it cannot be seen. True by
  /// default.
  ///
  /// The view counts as hidden when a full-screen route is pushed over it
  /// (a profile page, for example) and when it sits in a tab that is not
  /// shown, as with `TabBarView`, `CupertinoTabScaffold` or go_router's
  /// `StatefulShellRoute`. It resumes when it is visible again. Dialogs and
  /// bottom sheets leave the feed visible, so the video keeps playing under
  /// them, as in short-video apps; call [PlayStackFeedViewController.pause] to
  /// stop it there.
  ///
  /// A plain `IndexedStack` does not tell its hidden children that they are
  /// hidden; wrap each child in `TickerMode(enabled: isSelected, ...)`.
  ///
  /// The app going to the background pauses playback regardless of this
  /// setting (see `PlayStackLifecycleConfig`).
  final bool pauseWhenHidden;

  /// Whether turning the device sideways while a video is in view opens it
  /// fullscreen, and turning it back upright closes it. On by default.
  ///
  /// On Android and iOS the view reads the motion sensors, so this also
  /// works in an app locked to portrait; the lock comes back when
  /// fullscreen ends. Nothing happens while the user locked rotation in the
  /// system settings. On web the view follows the browser window turning.
  ///
  /// After the user leaves fullscreen with the button while holding the
  /// device sideways, the feed stays as it is until the device is turned
  /// upright again.
  final bool fullscreenOnRotate;

  /// Called when the user leaves an item (swipes to another one, or the view
  /// is removed) with how long they watched it: watch time, whether they
  /// watched to the end, and your item. Use it for view counts and
  /// recommendations.
  ///
  /// ```dart
  /// onItemViewed: (view) {
  ///   if (view.watchTime > const Duration(seconds: 3)) api.countView(view.data.id);
  /// },
  /// ```
  ///
  /// Called once per visit, also for items skipped before they started
  /// (with a zero [PlayStackItemView.watchTime]).
  ///
  /// It runs just after the change that caused it, outside of any build, so
  /// it may call `setState` or notify listeners.
  final void Function(PlayStackItemView<T> view)? onItemViewed;

  /// Enables pull to refresh: when set, pulling down on the first page shows
  /// a refresh indicator and calls this. Return the new items; they replace
  /// the feed and the view goes back to the first one. Null (the default)
  /// turns pull to refresh off.
  ///
  /// ```dart
  /// onRefresh: () => api.fetchPosts(page: 0),
  /// ```
  ///
  /// Only for vertical feeds ([scrollDirection] [Axis.vertical], not
  /// [reverse]). If it throws, the error is reported to
  /// `FlutterError.onError` and the feed stays as it was.
  final Future<List<T>> Function()? onRefresh;

  @override
  State<PlayStackFeedView<T>> createState() => _PlayStackFeedViewState<T>();
}

class _PlayStackFeedViewState<T> extends State<PlayStackFeedView<T>> {
  PlayStackManager? _ownedManager;
  PlayStackFeedManager? _ownedFeed;
  PlayStackFeedManager? _listened;
  PageController? _pages;
  PlayStackFeedViewController? _ownController;
  PlayStackPlayerController? _watched;
  PlayStackFullscreenManager? _fullscreen;
  PlayStackPlayerController? _fullscreenController;
  PlayStackVideoQualityLimit? _limitBeforeFullscreen;
  bool _isFullscreen = false;

  /// The route that shows the video fullscreen, while it is open.
  Route<void>? _fullscreenRoute;

  // Fullscreen on rotation (fullscreenOnRotate).
  Orientation? _orientation;
  bool _rotatedIn = false;
  bool _leavingUpright = false;
  bool _awaitUpright = false;
  DateTime? _rotateBlockedUntil;
  // With the device's motion sensors (Android, iOS): also works while the
  // app is locked to portrait.
  StreamSubscription<DeviceOrientation>? _deviceOrientations;
  DeviceOrientation? _device;
  bool _sawSideways = false;

  static bool _isSideways(DeviceOrientation? orientation) =>
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;

  /// Bumped when the widget changes, to rebuild the fullscreen page with
  /// the new builders.
  final ValueNotifier<int> _widgetUpdates = ValueNotifier<int>(0);
  bool _advanced = false;
  bool _loadingMore = false;
  bool _exhausted = false;
  int _endReachedAtLength = -1;
  int _nextId = 0;

  // Pausing: the view pauses the feed while hidden or paused from the
  // controller, and resumes it only when it paused it itself.
  bool _hidden = false;
  bool _userPaused = false;
  bool _pausedFeed = false;

  // The item in view, for onItemViewed.
  PlayStackFeedItem? _viewed;
  int _viewedIndex = 0;
  PlayStackPlayerController? _viewedController;
  final Stopwatch _watch = Stopwatch();
  Duration? _viewedDuration;
  bool _viewedCompleted = false;
  Duration? _viewedPosition;
  StreamSubscription<PlayStackPositionSnapshot>? _viewedPositions;

  PlayStackFeedManager? get _feed => widget.feed ?? _ownedFeed;

  PlayStackFeedViewController get _controller =>
      widget.controller ?? (_ownController ??= PlayStackFeedViewController());

  @override
  void initState() {
    super.initState();
    _controller._view = this;
    final feed = widget.feed;
    if (feed != null) {
      _attach(feed);
    } else if (widget.preload != null) {
      unawaited(_startPreloaded(widget.preload!));
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

  Future<void> _startPreloaded(PlayStackFeedPreload<T> preload) async {
    final PlayStackFeedManager feed;
    try {
      feed = await preload._claim();
    } on Object catch (error, stack) {
      _report(error, stack, 'while starting a preloaded feed');
      return;
    }
    // The view owns what the preload created.
    _ownedManager = preload._ownedManager;
    _nextId = preload._nextId;
    if (!mounted) {
      feed.dispose();
      final manager = _ownedManager;
      if (manager != null) unawaited(manager.dispose());
      return;
    }
    _ownedFeed = feed;
    setState(() => _attach(feed));
    _controller._changed();
  }

  Future<void> _start() async {
    final manager =
        widget.manager ??
        PlayStackManager(
          config: PlayStackConfig.reels(looping: !widget.autoAdvance),
        );
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Disabled tickers mean the view is hidden: covered by an opaque route
    // or in a tab that is not shown.
    _onOrientation(MediaQuery.orientationOf(context));
    final hidden = !TickerMode.valuesOf(context).enabled;
    if (hidden == _hidden) return;
    _hidden = hidden;
    // Not during build: pausing notifies the feed's listeners.
    scheduleMicrotask(() {
      if (mounted) _applyPause();
    });
  }

  void _setUserPaused(bool paused) {
    if (_userPaused == paused) return;
    _userPaused = paused;
    _applyPause();
    _controller._changed();
  }

  void _applyPause() {
    final feed = _feed;
    if (feed == null || feed.isDisposed) return;
    // The fullscreen route covers the feed but shows its video.
    final hidden = _hidden && _fullscreenRoute == null;
    final pause = _userPaused || (hidden && widget.pauseWhenHidden);
    if (pause) {
      if (!feed.isPaused) {
        feed.pause();
        _pausedFeed = true;
      }
    } else if (_pausedFeed) {
      _pausedFeed = false;
      if (feed.isPaused) feed.resume();
    }
  }

  PlayStackFeedItem _toFeedItem(T item) => _mapFeedItem(
    item,
    nextId: () => 'item-${_nextId++}',
    source: widget.source,
    videoUrl: widget.videoUrl,
    posterUrl: widget.posterUrl,
    poster: widget.poster,
    itemId: widget.itemId,
    startPosition: widget.startPosition,
    isLocked: widget.isLocked,
  );

  /// Asks [PlayStackFeedView.isLocked] again for every video, after a
  /// rebuild of the app (an episode was unlocked).
  void _syncLocks(PlayStackFeedManager feed) {
    final isLocked = widget.isLocked;
    if (isLocked == null) return;
    for (var i = 0; i < feed.length; i++) {
      final item = feed.itemAt(i);
      if (!item.isVideo) continue;
      final locked = isLocked(item.data as T);
      if (locked != item.locked) feed.setLocked(item.id, locked);
    }
  }

  void _attach(PlayStackFeedManager feed) {
    final start = _startIndex(feed);
    _pages?.dispose();
    _pages = PageController(initialPage: start);
    _listened = feed..addListener(_onItemsChanged);
    feed.activeIndex.addListener(_onActiveChanged);
    final fullscreen = feed.manager.fullscreen;
    _fullscreen = fullscreen;
    fullscreen.isFullscreen.addListener(_onFullscreenChanged);
    _isFullscreen = fullscreen.isFullscreen.value;
    _syncDeviceOrientations();
    if (feed.length > 0 && feed.activeIndex.value == null) {
      // Not during build: activating notifies the feed's listeners.
      scheduleMicrotask(() {
        if (mounted && !feed.isDisposed && start < feed.length) {
          if (feed.activeIndex.value == null) feed.setActiveIndex(start);
        }
      });
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _onActiveChanged());
    scheduleMicrotask(() {
      if (mounted) _applyPause();
    });
  }

  void _detach() {
    final feed = _listened;
    _listened = null;
    _unwatch();
    _reportViewed();
    if (_pausedFeed && feed != null && !feed.isDisposed) {
      _pausedFeed = false;
      if (feed.isPaused) feed.resume();
    }
    _fullscreen?.isFullscreen.removeListener(_onFullscreenChanged);
    _stopDeviceOrientations();
    if (feed == null || feed.isDisposed) return;
    feed.removeListener(_onItemsChanged);
    feed.activeIndex.removeListener(_onActiveChanged);
  }

  int _startIndex(PlayStackFeedManager feed) {
    final active = feed.activeIndex.value;
    if (active != null) return active;
    if (feed.length == 0) return 0;
    return widget.initialIndex.clamp(0, feed.length - 1);
  }

  @override
  void didUpdateWidget(PlayStackFeedView<T> oldWidget) {
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
    if (oldWidget.pauseWhenHidden != widget.pauseWhenHidden) _applyPause();
    if (oldWidget.fullscreenOnRotate != widget.fullscreenOnRotate) {
      _syncDeviceOrientations();
    }
    final items = widget.items;
    final owned = _ownedFeed;
    if (owned != null && items != null && !identical(items, oldWidget.items)) {
      _syncItems(owned, oldWidget.items ?? const [], items);
    }
    if (owned != null && !owned.isDisposed) _syncLocks(owned);
    // The fullscreen page uses this widget's builders.
    if (_fullscreenRoute != null) _widgetUpdates.value++;
  }

  /// Applies a new [PlayStackFeedView.items] list: appends when it extends the
  /// previous one, otherwise replaces the feed.
  void _syncItems(PlayStackFeedManager feed, List<T> before, List<T> after) {
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
    final route = _fullscreenRoute;
    _fullscreenRoute = null;
    if (route != null) {
      // Not while the tree is being finalized.
      scheduleMicrotask(() {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    if (_isFullscreen && fullscreen != null) unawaited(fullscreen.exit());
    // Disposed after the route is gone; the route may rebuild until then.
    final updates = _widgetUpdates;
    if (route == null) {
      updates.dispose();
    } else {
      scheduleMicrotask(updates.dispose);
    }
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
    _trackViewed();
    _controller._changed();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    _trackViewed();
    final index = _feed?.activeIndex.value;
    if (index == null) return;
    _followFeed();
    _watchActive();
    // The feed hides the active page's video while fullscreen.
    if (_fullscreenRoute != null) setState(() {});
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

  /// A list inside a page reached its end and the user keeps dragging:
  /// move the feed on, so the page does not trap the swipe.
  void _onInnerEdge(bool forward) {
    if (_isFullscreen || widget.physics is NeverScrollableScrollPhysics) {
      return;
    }
    final move = forward ? _controller.nextPage() : _controller.previousPage();
    unawaited(move.catchError((Object _) {}));
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

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    final feed = _ownedFeed;
    if (refresh == null || feed == null) return;
    try {
      final items = await refresh();
      if (!mounted || feed.isDisposed) return;
      _exhausted = false;
      _endReachedAtLength = -1;
      feed.replaceAll([for (final item in items) _toFeedItem(item)]);
      // Items with ids can keep the one in view; a refresh starts at the top.
      if (feed.length > 0 && feed.activeIndex.value != 0) {
        feed.setActiveIndex(0);
      }
    } on Object catch (error, stack) {
      _report(error, stack, 'while refreshing the feed');
    }
  }

  // --- watch reports --------------------------------------------------------

  /// Follows the item in view; reports the previous one when it changes.
  void _trackViewed() {
    if (widget.onItemViewed == null && _viewed == null) return;
    final feed = _feed;
    final index = feed?.activeIndex.value;
    final item = feed == null || feed.isDisposed || index == null
        ? null
        : feed.itemAt(index);
    if (item != null && item.id == _viewed?.id) {
      _viewedIndex = index!;
      return;
    }
    _reportViewed();
    if (item == null || widget.onItemViewed == null || !item.isPlayable) {
      return;
    }
    _viewed = item;
    _viewedIndex = index!;
    final controller = (feed!.activeController ?? feed.controllerAt(index))
      ..addListener(_onViewedState);
    _viewedController = controller;
    // Polled only while the video plays.
    _viewedPositions = controller
        .positions(interval: const Duration(milliseconds: 500))
        .listen(
          (snapshot) => _viewedPosition = snapshot.position,
          onError: (Object _) {},
        );
    _onViewedState();
  }

  void _onViewedState() {
    final controller = _viewedController;
    if (controller == null) return;
    final state = controller.value;
    if (state.isPlaying && !state.isBuffering) {
      _watch.start();
    } else {
      _watch.stop();
    }
    _viewedDuration = state.duration ?? _viewedDuration;
    if (state.status == PlayStackPlaybackStatus.completed) {
      _viewedCompleted = true;
    }
  }

  void _reportViewed() {
    final item = _viewed;
    final controller = _viewedController;
    if (controller != null && !controller.isDisposed) {
      controller.removeListener(_onViewedState);
    }
    unawaited(_viewedPositions?.cancel());
    _viewedPositions = null;
    final position = _viewedPosition;
    _viewedPosition = null;
    _watch.stop();
    final watchTime = _watch.elapsed;
    final duration = _viewedDuration;
    final completed =
        _viewedCompleted ||
        (duration != null &&
            duration > Duration.zero &&
            // Positions are reported in steps; allow for the last one.
            watchTime + const Duration(milliseconds: 500) >= duration);
    _watch.reset();
    _viewed = null;
    _viewedController = null;
    _viewedDuration = null;
    _viewedCompleted = false;
    final onItemViewed = widget.onItemViewed;
    if (item == null || onItemViewed == null) return;
    final view = PlayStackItemView<T>(
      item: item,
      index: _viewedIndex,
      watchTime: watchTime,
      duration: duration,
      completed: completed,
      position: position,
    );
    // Reports can happen during a build or while the view is disposed; the
    // app's callback may rebuild widgets, so it runs right after.
    scheduleMicrotask(() {
      try {
        onItemViewed(view);
      } on Object catch (error, stack) {
        _report(error, stack, 'while reporting a watched item');
      }
    });
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
    if (!_advanced &&
        watched.value.status == PlayStackPlaybackStatus.completed) {
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

  Future<void> _enterFullscreen({bool rotated = false}) async {
    final controller = _feed?.activeController;
    final fullscreen = _fullscreen;
    if (controller == null || fullscreen == null || _isFullscreen) return;
    if (_fullscreenRoute != null) return;
    _rotatedIn = rotated;
    _sawSideways = _isSideways(_device);
    _fullscreenController = controller;
    _limitBeforeFullscreen = controller.videoQualityLimit;
    // Fullscreen shows the video at the screen's long side.
    unawaited(
      controller
          .setVideoQualityLimit(PlayStackVideoQualityLimit.none)
          .catchError(_ignore),
    );
    _openFullscreenRoute();
    try {
      await fullscreen.enter(
        // Turned by the user: sideways, whatever the video. With the
        // sensors this also turns an app locked to portrait; without them
        // the interface already turned, and its orientation stays free so
        // that turning upright leaves fullscreen.
        orientation: !rotated
            ? PlayStackFullscreenOrientation.matchVideo
            : _deviceOrientations != null
            ? PlayStackFullscreenOrientation.landscape
            : PlayStackFullscreenOrientation.keepCurrent,
        controller: controller,
      );
    } on Object {
      _closeFullscreenRoute();
      _restoreQuality();
      rethrow;
    }
  }

  Future<void> _exitFullscreen() async {
    _closeFullscreenRoute();
    await _fullscreen?.exit();
    _restoreQuality();
  }

  void _onFullscreenChanged() {
    final value = _fullscreen?.isFullscreen.value ?? false;
    if (value == _isFullscreen || !mounted) return;
    setState(() => _isFullscreen = value);
    if (!value) {
      // Left from outside the view (Escape in a browser).
      _closeFullscreenRoute();
      _restoreQuality();
      // Unlocking the orientation can turn the screen sideways again right
      // away when the device is held sideways; that must not reopen
      // fullscreen. Neither does staying sideways after leaving it.
      _rotatedIn = false;
      if (_leavingUpright) {
        // Left by turning the device upright: the next turn opens it again.
        _leavingUpright = false;
      } else if (_deviceOrientations != null) {
        // Left with the button while holding the device sideways: wait
        // until it is upright before a turn opens fullscreen again.
        _awaitUpright = _isSideways(_device);
      } else {
        _rotateBlockedUntil = DateTime.now().add(const Duration(seconds: 1));
        _awaitUpright = _orientation == Orientation.landscape;
      }
    }
    _controller._changed();
  }

  void _onOrientation(Orientation orientation) {
    final previous = _orientation;
    _orientation = orientation;
    if (previous == null || previous == orientation) return;
    // Not during build: entering fullscreen pushes a route.
    scheduleMicrotask(() {
      if (mounted && _orientation == orientation) _onRotated(orientation);
    });
  }

  void _onRotated(Orientation orientation) {
    // The sensors know better: an unlocked interface turns with the device.
    if (!widget.fullscreenOnRotate || _deviceOrientations != null) return;
    if (orientation == Orientation.portrait) {
      _awaitUpright = false;
      if (_isFullscreen && _rotatedIn) {
        _leavingUpright = true;
        unawaited(_exitFullscreen().catchError(_ignore));
      }
      return;
    }
    final blocked = _rotateBlockedUntil;
    if (_awaitUpright ||
        (blocked != null && DateTime.now().isBefore(blocked))) {
      _awaitUpright = true;
      return;
    }
    if (_isFullscreen || _fullscreenRoute != null || _hidden) return;
    final feed = _feed;
    if (feed == null || feed.isDisposed || feed.activeController == null) {
      return;
    }
    unawaited(_enterFullscreen(rotated: true).catchError(_ignore));
  }

  /// Follows the device's motion sensors while [PlayStackFeedView.fullscreenOnRotate]
  /// is on and the platform has them.
  void _syncDeviceOrientations() {
    final changes = _fullscreen?.deviceOrientationChanges;
    if (!widget.fullscreenOnRotate || changes == null) {
      _stopDeviceOrientations();
      return;
    }
    if (_deviceOrientations != null) return;
    _device = _fullscreen?.deviceOrientation;
    _deviceOrientations = changes.listen(_onDeviceOrientation);
  }

  void _stopDeviceOrientations() {
    unawaited(_deviceOrientations?.cancel());
    _deviceOrientations = null;
    _device = null;
  }

  void _onDeviceOrientation(DeviceOrientation orientation) {
    // Before the first report (the sensors may not know yet, for example
    // lying flat), the device is taken to be held like the interface.
    final previous =
        _device ??
        (_orientation == Orientation.portrait
            ? DeviceOrientation.portraitUp
            : null);
    _device = orientation;
    if (previous == null || previous == orientation || !mounted) return;
    if (orientation == DeviceOrientation.portraitDown) return;
    if (orientation == DeviceOrientation.portraitUp) {
      _awaitUpright = false;
      // Fullscreen opened by turning the device, or opened with the button
      // and then held sideways: upright closes it.
      if (_isFullscreen && (_rotatedIn || _sawSideways)) {
        _leavingUpright = true;
        unawaited(_exitFullscreen().catchError(_ignore));
      }
      return;
    }
    if (_isFullscreen || _fullscreenRoute != null) {
      // A landscape video shown sideways and now held sideways.
      if (_orientation == Orientation.landscape) _sawSideways = true;
      return;
    }
    if (_awaitUpright || _hidden) return;
    final feed = _feed;
    if (feed == null || feed.isDisposed || feed.activeController == null) {
      return;
    }
    unawaited(_enterFullscreen(rotated: true).catchError(_ignore));
  }

  /// Shows the video on a route above the app's screens, so bars around the
  /// feed (a bottom navigation bar, an app bar) are covered. Without a
  /// navigator the feed goes fullscreen where it is.
  void _openFullscreenRoute() {
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null || _fullscreenRoute != null) return;
    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'playstack-fullscreen'),
      // No transition: the feed hides its own view of the video while the
      // route shows it (a web video element can be in one place only).
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _onFullscreenRoutePopped();
        },
        child: _buildFullscreenPage(context),
      ),
    );
    setState(() => _fullscreenRoute = route);
    unawaited(navigator.push(route));
    // The feed under the route stays playing.
    _applyPause();
  }

  void _closeFullscreenRoute() {
    final route = _fullscreenRoute;
    if (route == null) return;
    if (mounted) setState(() => _fullscreenRoute = null);
    // The feed is shown again on the next frame; its tickers then tell the
    // view it is visible (didChangeDependencies).
    if (route.isActive) route.navigator?.removeRoute(route);
  }

  /// The back button or gesture closed the fullscreen route.
  void _onFullscreenRoutePopped() {
    if (_fullscreenRoute == null) return;
    setState(() => _fullscreenRoute = null);
    unawaited(_exitFullscreen().catchError(_ignore));
  }

  Widget _buildFullscreenPage(BuildContext context) {
    final feed = _feed;
    final background = ColoredBox(color: widget.backgroundColor);
    if (feed == null || feed.isDisposed) return background;
    return ColoredBox(
      color: widget.backgroundColor,
      child: ListenableBuilder(
        listenable: Listenable.merge([feed, feed.activeIndex, _widgetUpdates]),
        builder: (context, _) {
          final index = feed.activeIndex.value;
          if (!mounted || feed.isDisposed || index == null) return background;
          if (index >= feed.length) return background;
          final item = feed.itemAt(index);
          if (!item.isPlayable) return background;
          return KeyedSubtree(
            key: ValueKey<String>(item.id),
            child: _PageContent<T>(
              feed: feed,
              view: _controller,
              item: item,
              index: index,
              isFullscreen: true,
              videoBuilder: widget.videoBuilder,
              controlsBuilder: widget.controlsBuilder,
              pageBuilder: widget.pageBuilder,
              lockedBuilder: widget.lockedBuilder,
              fit: widget.fit,
            ),
          );
        },
      ),
    );
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
        library: 'playstack',
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
    // Fullscreen in place, when there was no navigator for a route.
    final inPlace = _isFullscreen && _fullscreenRoute == null;
    return PopScope(
      canPop: !inPlace,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inPlace) unawaited(_exitFullscreen());
      },
      child: ColoredBox(
        color: widget.backgroundColor,
        child: _withRefresh(
          context,
          LayoutBuilder(
            builder: (context, constraints) => PageView.builder(
              controller: pages,
              scrollDirection: widget.scrollDirection,
              reverse: widget.reverse,
              physics: inPlace
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
                Widget page =
                    _fullscreenRoute != null && index == feed.activeIndex.value
                    // Shown by the fullscreen route.
                    ? const SizedBox.expand()
                    : _PageContent<T>(
                        feed: feed,
                        view: _controller,
                        item: item,
                        index: index,
                        isFullscreen: inPlace,
                        videoBuilder: widget.videoBuilder,
                        controlsBuilder: widget.controlsBuilder,
                        pageBuilder: widget.pageBuilder,
                        lockedBuilder: widget.lockedBuilder,
                        fit: widget.fit,
                      );
                page = _ScrollHandoff(
                  axis: widget.scrollDirection,
                  reverse: widget.reverse,
                  onEdge: _onInnerEdge,
                  child: page,
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
                return KeyedSubtree(
                  key: ValueKey<String>(item.id),
                  child: page,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps [child] in a refresh indicator when [PlayStackFeedView.onRefresh] is
  /// set and the feed is vertical.
  Widget _withRefresh(BuildContext context, Widget child) {
    // Not removed in fullscreen: changing the tree above the PageView would
    // rebuild it at its first page.
    if (widget.onRefresh == null ||
        widget.scrollDirection != Axis.vertical ||
        widget.reverse) {
      return child;
    }
    final Widget indicator = RefreshIndicator(
      onRefresh: _refresh,
      semanticsLabel: 'Refresh',
      notificationPredicate: (notification) =>
          notification.depth == 0 && !_isFullscreen,
      child: child,
    );
    // The indicator needs Material localizations; apps built on
    // CupertinoApp or WidgetsApp have none.
    if (Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) !=
        null) {
      return indicator;
    }
    final locale = Localizations.maybeLocaleOf(context);
    if (locale != null) {
      return Localizations.override(
        context: context,
        delegates: const [DefaultMaterialLocalizations.delegate],
        child: indicator,
      );
    }
    return Localizations(
      locale: const Locale('en', 'US'),
      delegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: indicator,
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
    required this.pageBuilder,
    required this.lockedBuilder,
    required this.fit,
  });

  final PlayStackFeedManager feed;
  final PlayStackFeedViewController view;
  final PlayStackFeedItem item;
  final int index;
  final bool isFullscreen;
  final PlayStackFeedPageBuilder<T>? videoBuilder;
  final PlayStackFeedPageBuilder<T>? controlsBuilder;
  final PlayStackFeedItemBuilder<T>? pageBuilder;
  final PlayStackFeedItemBuilder<T>? lockedBuilder;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    if (!item.isPlayable) {
      return ValueListenableBuilder<int?>(
        valueListenable: feed.activeIndex,
        builder: (context, active, _) {
          final data = item.data as T;
          final isActive = active == index;
          if (!item.isVideo) {
            return pageBuilder?.call(context, data, isActive) ??
                const SizedBox.expand();
          }
          final poster = item.poster;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (poster != null)
                Image(
                  image: poster,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              lockedBuilder?.call(context, data, isActive) ??
                  const _DefaultLocked(),
            ],
          );
        },
      );
    }
    final controller = feed.controllerAt(index);
    return ValueListenableBuilder<int?>(
      valueListenable: feed.activeIndex,
      builder: (context, active, _) {
        final page = PlayStackFeedPage<T>(
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

  Widget _video(PlayStackPlayerController controller) {
    final fixed = fit;
    if (fixed != null) {
      return PlayStackVideoView(
        controller: controller,
        fit: fixed,
        poster: item.poster,
      );
    }
    return ValueListenableBuilder<PlayStackPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final landscape = (state.aspectRatio ?? 0) > 1;
        return PlayStackVideoView(
          controller: controller,
          fit: landscape || isFullscreen ? BoxFit.contain : BoxFit.cover,
          poster: item.poster,
        );
      },
    );
  }
}

/// Hands a drag over to the feed when a scrollable inside the page (a list
/// on a page without video, a long caption) is at its end along the feed's
/// axis and the user keeps dragging past it.
class _ScrollHandoff extends StatefulWidget {
  const _ScrollHandoff({
    required this.axis,
    required this.reverse,
    required this.onEdge,
    required this.child,
  });

  final Axis axis;
  final bool reverse;

  /// Called once per drag; true moves to the next page.
  final ValueChanged<bool> onEdge;
  final Widget child;

  @override
  State<_ScrollHandoff> createState() => _ScrollHandoffState();
}

class _ScrollHandoffState extends State<_ScrollHandoff> {
  /// How far past its end a list is pulled before the feed moves.
  static const double _threshold = 48;

  double _overscroll = 0;
  bool _handedOff = false;

  static bool _isPositive(AxisDirection direction) =>
      direction == AxisDirection.down || direction == AxisDirection.right;

  bool _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != widget.axis) return false;
    if (notification is ScrollStartNotification) {
      _overscroll = 0;
      _handedOff = false;
      return false;
    }
    if (_handedOff) return false;
    double? past;
    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      // Clamping lists (Android) report the overscroll as deltas.
      _overscroll += notification.overscroll;
      past = _overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        metrics.outOfRange) {
      // Bouncing lists (iOS) move past their end instead.
      past = metrics.pixels > metrics.maxScrollExtent
          ? metrics.pixels - metrics.maxScrollExtent
          : metrics.pixels - metrics.minScrollExtent;
    }
    if (past == null || past.abs() < _threshold) return false;
    _handedOff = true;
    // The same finger movement scrolls the list and the feed forward when
    // both grow in the same screen direction.
    // A feed grows down (or right) unless reversed.
    final feedPositive = !widget.reverse;
    final listPositive = _isPositive(metrics.axisDirection);
    widget.onEdge((past > 0) == (listPositive == feedPositive));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.child,
    );
  }
}

/// A locked video without a `lockedBuilder`: a dimmed poster and a lock.
class _DefaultLocked extends StatelessWidget {
  const _DefaultLocked();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x99000000),
      child: Center(
        child: Icon(
          Icons.lock_rounded,
          size: 56,
          color: Color(0xFFFFFFFF),
          semanticLabel: 'Locked',
        ),
      ),
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
  final PlayStackFeedTransition transition;
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
          PlayStackFeedTransitionDetails(
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
