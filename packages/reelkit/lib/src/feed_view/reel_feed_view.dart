import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../controller/reel_playback_state.dart';
import '../controller/reel_player_controller.dart';
import '../feed/reel_feed_item.dart';
import '../feed/reel_feed_manager.dart';
import '../view/reel_video_view.dart';
import 'reel_default_controls.dart';
import 'reel_feed_transition.dart';

/// Builds part of a page of a [ReelFeedView].
typedef ReelFeedPageBuilder = Widget Function(
  BuildContext context,
  ReelFeedPage page,
);

/// Everything a [ReelFeedView] builder needs to know about one page.
@immutable
class ReelFeedPage {
  /// Creates page details. [ReelFeedView] creates these.
  const ReelFeedPage({
    required this.feed,
    required this.view,
    required this.item,
    required this.index,
    required this.controller,
    required this.isActive,
  });

  /// The feed the page belongs to.
  final ReelFeedManager feed;

  /// Moves the view, for example to the next page.
  final ReelFeedViewController view;

  /// The item shown on this page.
  final ReelFeedItem item;

  /// Index of the item in the feed.
  final int index;

  /// The item's player controller.
  final ReelPlayerController controller;

  /// Whether this is the item in view (the one that plays).
  final bool isActive;

  /// The app's data attached to the item ([ReelFeedItem.data]).
  Object? get data => item.data;

  @override
  bool operator ==(Object other) =>
      other is ReelFeedPage &&
      other.feed == feed &&
      other.view == view &&
      other.item == item &&
      other.index == index &&
      other.controller == controller &&
      other.isActive == isActive;

  @override
  int get hashCode =>
      Object.hash(feed, view, item, index, controller, isActive);
}

/// Moves a [ReelFeedView] from code: next, previous or any page, animated
/// with the view's transition or at once.
///
/// Pass one to [ReelFeedView.controller], or read the view's own controller
/// from [ReelFeedPage.view] inside builders.
class ReelFeedViewController {
  _ReelFeedViewState? _view;

  /// Whether a [ReelFeedView] uses this controller.
  bool get isAttached => _view != null;

  /// Index of the page in view, or null when not attached or empty.
  int? get index => _view?.widget.feed.activeIndex.value;

  /// The scroll position in pages (fractional while moving), or null when
  /// not attached or not laid out yet.
  double? get page {
    final pages = _view?._pages;
    if (pages == null || !pages.hasClients) return null;
    return pages.page;
  }

  /// Animates to the next page. Does nothing on the last page.
  Future<void> nextPage({Duration? duration, Curve? curve}) {
    final view = _attached;
    final next = (index ?? -1) + 1;
    if (next >= view.widget.feed.length) return Future<void>.value();
    return animateTo(next, duration: duration, curve: curve);
  }

  /// Animates to the previous page. Does nothing on the first page.
  Future<void> previousPage({Duration? duration, Curve? curve}) {
    _attached;
    final previous = (index ?? 0) - 1;
    if (previous < 0) return Future<void>.value();
    return animateTo(previous, duration: duration, curve: curve);
  }

  /// Animates to the page at [index], with the view's
  /// [ReelFeedView.transitionDuration] and [ReelFeedView.transitionCurve]
  /// unless given.
  Future<void> animateTo(int index, {Duration? duration, Curve? curve}) {
    final view = _attached;
    RangeError.checkValueInInterval(
      index,
      0,
      view.widget.feed.length - 1,
      'index',
    );
    final pages = view._pages;
    if (!pages.hasClients) {
      view.widget.feed.setActiveIndex(index);
      return Future<void>.value();
    }
    return pages.animateToPage(
      index,
      duration: duration ?? view.widget.transitionDuration,
      curve: curve ?? view.widget.transitionCurve,
    );
  }

  /// Shows the page at [index] without animation.
  void jumpTo(int index) {
    final view = _attached;
    RangeError.checkValueInInterval(
      index,
      0,
      view.widget.feed.length - 1,
      'index',
    );
    if (view._pages.hasClients) {
      view._pages.jumpToPage(index);
    } else {
      view.widget.feed.setActiveIndex(index);
    }
  }

  _ReelFeedViewState get _attached {
    final view = _view;
    if (view == null) {
      throw StateError('ReelFeedViewController is not attached to a view.');
    }
    return view;
  }
}

/// A ready-made short-video feed: pages through a [ReelFeedManager], plays
/// the item in view, prepares the next ones and moves between them with a
/// [transition].
///
/// The app supplies the feed and, if it wants, the look of each page:
///
/// * [controlsBuilder] draws everything above the video: buttons, captions,
///   progress. It defaults to [ReelDefaultControls]; pass your own builder
///   for custom controls, or null for none.
/// * [videoBuilder] replaces the video layer, which by default is a
///   [ReelVideoView] with [fit] and the item's poster.
///
/// ```dart
/// ReelFeedView(
///   feed: feed,
///   transition: ReelFeedTransition.stack,
///   controlsBuilder: (context, page) => ReelDefaultControls(
///     page: page,
///     child: MyCaption(post: page.data as Post),
///   ),
///   onEndReached: () => feed.addAll(nextPage()),
/// )
/// ```
///
/// The view never disposes [feed]; dispose it (or its manager) yourself.
class ReelFeedView extends StatefulWidget {
  /// Creates a view of [feed].
  const ReelFeedView({
    super.key,
    required this.feed,
    this.controller,
    this.initialIndex = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.transition = ReelFeedTransition.slide,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.transitionCurve = Curves.easeOutCubic,
    this.physics,
    this.fit = BoxFit.cover,
    this.backgroundColor = const Color(0xFF000000),
    this.videoBuilder,
    this.controlsBuilder = ReelDefaultControls.builder,
    this.emptyBuilder,
    this.onPageChanged,
    this.onEndReached,
    this.endReachedThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
  }) : assert(endReachedThreshold >= 0),
       assert(precachePosters >= 0);

  /// The items, their players and preloading.
  final ReelFeedManager feed;

  /// Moves the view from code. Optional: builders get the view's controller
  /// through [ReelFeedPage.view].
  final ReelFeedViewController? controller;

  /// The page shown first when the feed has no active item yet. Ignored
  /// when the feed already has one, so a rebuilt view returns to where the
  /// user was.
  final int initialIndex;

  /// The swipe direction: [Axis.vertical] for a reels feed, [Axis.horizontal]
  /// for stories or a carousel.
  final Axis scrollDirection;

  /// Whether the next item comes from above (vertical) or from the left
  /// (horizontal) instead.
  final bool reverse;

  /// How pages move from one to the next.
  final ReelFeedTransition transition;

  /// Duration of moves made through [controller] and [autoAdvance].
  final Duration transitionDuration;

  /// Curve of moves made through [controller] and [autoAdvance].
  final Curve transitionCurve;

  /// Scroll physics. Pass `NeverScrollableScrollPhysics` to lock swiping,
  /// for example in fullscreen.
  final ScrollPhysics? physics;

  /// How the default video layer fits the video into the page.
  final BoxFit fit;

  /// Painted behind every page.
  final Color backgroundColor;

  /// Replaces the default video layer of each page.
  final ReelFeedPageBuilder? videoBuilder;

  /// Draws the controls and anything else above the video of each page.
  /// Defaults to [ReelDefaultControls]; null shows none.
  final ReelFeedPageBuilder? controlsBuilder;

  /// Shown while the feed has no items.
  final WidgetBuilder? emptyBuilder;

  /// Called when the page in view changes, by a swipe or from code.
  final ValueChanged<int>? onPageChanged;

  /// Called when the user reaches [endReachedThreshold] items before the
  /// end, once per feed length. Append the next page of items here.
  final VoidCallback? onEndReached;

  /// How many items before the end [onEndReached] is called.
  final int endReachedThreshold;

  /// How many posters of the next items are downloaded ahead of time, so a
  /// swipe never shows black while the video prepares.
  final int precachePosters;

  /// Whether the view moves to the next page when a video ends. Needs
  /// videos that do not loop (`ReelPlayerConfig.looping: false`).
  final bool autoAdvance;

  @override
  State<ReelFeedView> createState() => _ReelFeedViewState();
}

class _ReelFeedViewState extends State<ReelFeedView> {
  late PageController _pages;
  ReelFeedViewController? _ownController;
  ReelPlayerController? _watched;
  bool _advanced = false;
  int _endReachedAtLength = -1;

  ReelFeedViewController get _controller =>
      widget.controller ?? (_ownController ??= ReelFeedViewController());

  @override
  void initState() {
    super.initState();
    final feed = widget.feed;
    final start = _startIndex(feed);
    _pages = PageController(initialPage: start);
    _controller._view = this;
    _listen(feed);
    if (feed.length > 0 && feed.activeIndex.value != start) {
      // Not during build: activating notifies the feed's listeners.
      scheduleMicrotask(() {
        if (!mounted || feed.isDisposed || start >= feed.length) return;
        if (feed.activeIndex.value == null) feed.setActiveIndex(start);
      });
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _onActiveChanged());
  }

  int _startIndex(ReelFeedManager feed) {
    final active = feed.activeIndex.value;
    if (active != null) return active;
    if (feed.length == 0) return 0;
    return widget.initialIndex.clamp(0, feed.length - 1);
  }

  void _listen(ReelFeedManager feed) {
    feed.addListener(_onItemsChanged);
    feed.activeIndex.addListener(_onActiveChanged);
  }

  void _unlisten(ReelFeedManager feed) {
    if (feed.isDisposed) return;
    feed.removeListener(_onItemsChanged);
    feed.activeIndex.removeListener(_onActiveChanged);
  }

  @override
  void didUpdateWidget(ReelFeedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller;
      if (old != null && old._view == this) old._view = null;
      if (oldWidget.controller == null) _ownController?._view = null;
      _controller._view = this;
    }
    if (oldWidget.feed != widget.feed) {
      _unlisten(oldWidget.feed);
      _listen(widget.feed);
      _endReachedAtLength = -1;
      _unwatch();
      final start = _startIndex(widget.feed);
      _pages.dispose();
      _pages = PageController(initialPage: start);
      if (widget.feed.length > 0 && widget.feed.activeIndex.value == null) {
        final feed = widget.feed;
        scheduleMicrotask(() {
          if (mounted && !feed.isDisposed && start < feed.length) {
            feed.setActiveIndex(start);
          }
        });
      }
      SchedulerBinding.instance.addPostFrameCallback((_) => _onActiveChanged());
    }
  }

  @override
  void dispose() {
    _unlisten(widget.feed);
    _unwatch();
    if (_controller._view == this) _controller._view = null;
    _pages.dispose();
    super.dispose();
  }

  void _onItemsChanged() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      // The feed changed during a build; rebuild after it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    _followFeed();
    _watchActive();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    final index = widget.feed.activeIndex.value;
    if (index == null) return;
    _followFeed();
    _watchActive();
    _precache(index);
    _checkEnd(index);
  }

  /// Shows the active item when the feed moved it: items inserted or
  /// removed before it, or `setActiveIndex` called by the app.
  void _followFeed() {
    final index = widget.feed.activeIndex.value;
    if (index == null || !_pages.hasClients) return;
    final position = _pages.position;
    if (!position.hasContentDimensions) return;
    final page = _pages.page;
    if (page == null || page.round() == index) return;
    // While the user drags or an animation runs, the page follows on its
    // own through onPageChanged.
    if (position.isScrollingNotifier.value && (page - index).abs() <= 1) {
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      final current = widget.feed.activeIndex.value;
      if (current != null && _pages.page?.round() != current) {
        _pages.jumpToPage(current);
      }
    });
  }

  void _onPageChanged(int index) {
    final feed = widget.feed;
    if (feed.isDisposed || index >= feed.length) return;
    feed.setActiveIndex(index);
    widget.onPageChanged?.call(index);
  }

  void _checkEnd(int index) {
    final onEndReached = widget.onEndReached;
    final length = widget.feed.length;
    if (onEndReached == null || _endReachedAtLength == length) return;
    if (index < length - 1 - widget.endReachedThreshold) return;
    _endReachedAtLength = length;
    scheduleMicrotask(() {
      if (mounted) onEndReached();
    });
  }

  void _precache(int index) {
    final feed = widget.feed;
    final end = math.min(feed.length, index + 1 + widget.precachePosters);
    for (var i = index + 1; i < end; i++) {
      final poster = feed.itemAt(i).poster;
      if (poster != null) {
        unawaited(precacheImage(poster, context, onError: (_, _) {}));
      }
    }
  }

  void _watchActive() {
    final active = widget.autoAdvance ? widget.feed.activeController : null;
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
    if (watched == null || !mounted) return;
    if (!_advanced && watched.value.status == ReelPlaybackStatus.completed) {
      _advanced = true;
      unawaited(_controller.nextPage());
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    if (feed.length == 0) {
      return widget.emptyBuilder?.call(context) ??
          ColoredBox(color: widget.backgroundColor);
    }
    return ColoredBox(
      color: widget.backgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) => PageView.builder(
          controller: _pages,
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          physics: widget.physics,
          onPageChanged: _onPageChanged,
          itemCount: feed.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final index = feed.indexOf(key.value);
            return index < 0 ? null : index;
          },
          itemBuilder: (context, index) {
            final item = feed.itemAt(index);
            Widget page = _PageContent(
              feed: feed,
              view: _controller,
              item: item,
              index: index,
              videoBuilder: widget.videoBuilder,
              controlsBuilder: widget.controlsBuilder,
              fit: widget.fit,
            );
            if (!widget.transition.isIdentity) {
              page = _TransitionedPage(
                pages: _pages,
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
    );
  }
}

class _PageContent extends StatelessWidget {
  const _PageContent({
    required this.feed,
    required this.view,
    required this.item,
    required this.index,
    required this.videoBuilder,
    required this.controlsBuilder,
    required this.fit,
  });

  final ReelFeedManager feed;
  final ReelFeedViewController view;
  final ReelFeedItem item;
  final int index;
  final ReelFeedPageBuilder? videoBuilder;
  final ReelFeedPageBuilder? controlsBuilder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final controller = feed.controllerAt(index);
    return ValueListenableBuilder<int?>(
      valueListenable: feed.activeIndex,
      builder: (context, active, _) {
        final page = ReelFeedPage(
          feed: feed,
          view: view,
          item: item,
          index: index,
          controller: controller,
          isActive: active == index,
        );
        final controls = controlsBuilder?.call(context, page);
        return Stack(
          fit: StackFit.expand,
          children: [
            videoBuilder?.call(context, page) ??
                ReelVideoView(
                  controller: controller,
                  fit: fit,
                  poster: item.poster,
                ),
            ?controls,
          ],
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
