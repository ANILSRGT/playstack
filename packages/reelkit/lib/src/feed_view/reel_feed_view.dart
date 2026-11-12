import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, MaterialLocalizations, RefreshIndicator;
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

/// Signature of [ReelFeedView.controlsBuilder] and [ReelFeedView.videoBuilder].
///
/// Called for every page that is built (the page in view and its neighbors)
/// and again when the page becomes active or inactive, or when fullscreen
/// changes. [page] tells which item the page shows and gives its controller.
typedef ReelFeedPageBuilder<T> = Widget Function(
  BuildContext context,
  ReelFeedPage<T> page,
);

/// One page of a [ReelFeedView], as passed to its builders.
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
/// A new [ReelFeedPage] is created on every rebuild; do not keep it.
@immutable
class ReelFeedPage<T> {
  /// Creates the details of one page. [ReelFeedView] creates these for its
  /// builders; apps do not need to.
  const ReelFeedPage({
    required this.feed,
    required this.view,
    required this.item,
    required this.index,
    required this.controller,
    required this.isActive,
    required this.isFullscreen,
  });

  /// Your item for this page: the element of [ReelFeedView.items] it shows,
  /// with its type. In a `ReelFeedView<Post>`, `page.data` is a `Post`.
  ///
  /// With [ReelFeedView.feed] it is the [ReelFeedItem.data] you attached.
  T get data => item.data as T;

  /// The video player of this page.
  ///
  /// Read its state to draw controls (`controller.value.isPlaying`,
  /// `isBuffering`, `duration`), and call it to act: `play()`, `pause()`,
  /// `seekTo(...)`, `setMuted(...)`. Rebuild from its state with a
  /// `ValueListenableBuilder<ReelPlaybackState>`.
  ///
  /// The feed plays and pauses it as the user swipes; you only call it for
  /// actions of your own, such as a play button.
  final ReelPlayerController controller;

  /// Whether this page is the one in view, the one that plays.
  ///
  /// Neighbor pages are built too, ready for the next swipe, with
  /// `isActive` false. Use it to run things only on the visible page, such as
  /// a progress bar or an animation.
  final bool isActive;

  /// Whether the feed is in fullscreen (see
  /// [ReelFeedViewController.enterFullscreen]). Hide captions and buttons
  /// there, or show an exit button.
  final bool isFullscreen;

  /// Position of this page in the feed, starting at 0. It changes when items
  /// are inserted above; use [ReelFeedItem.id] of [item] to identify the item.
  final int index;

  /// Controls the whole feed from inside a page: [ReelFeedViewController.nextPage],
  /// [ReelFeedViewController.toggleFullscreen],
  /// [ReelFeedViewController.setMuted] and more.
  final ReelFeedViewController view;

  /// The feed behind the view: the list of entries, their players and
  /// preloading. Most apps never need it; it is here for advanced use such as
  /// reading [ReelFeedManager.stats].
  final ReelFeedManager feed;

  /// The feed entry of this page: its [ReelFeedItem.id], the
  /// [ReelFeedItem.source] being played and the [ReelFeedItem.poster]. Your own
  /// object is [data].
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

/// How long the user watched one item, passed to
/// [ReelFeedView.onItemViewed] when the user leaves the item.
///
/// ```dart
/// onItemViewed: (view) => analytics.log('watched', {
///   'post': view.data.id,
///   'seconds': view.watchTime.inSeconds,
///   'completed': view.completed,
/// }),
/// ```
@immutable
class ReelItemView<T> {
  /// Creates a report. [ReelFeedView] creates these; apps do not need to.
  const ReelItemView({
    required this.item,
    required this.index,
    required this.watchTime,
    required this.duration,
    required this.completed,
  });

  /// Your item, typed, like [ReelFeedPage.data].
  T get data => item.data as T;

  /// The feed entry that was watched.
  final ReelFeedItem item;

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

  /// [watchTime] as a fraction of [duration]: 0.5 for half the video, above
  /// 1 for replays. Null when [duration] is unknown.
  double? get watchedFraction {
    final total = duration;
    if (total == null || total <= Duration.zero) return null;
    return watchTime.inMicroseconds / total.inMicroseconds;
  }

  @override
  String toString() =>
      'ReelItemView(${item.id}, ${watchTime.inMilliseconds} ms'
      '${completed ? ', completed' : ''})';
}

/// Controls a [ReelFeedView] from code: move to the next or previous page,
/// enter fullscreen, mute.
///
/// Inside builders, use [ReelFeedPage.view]. To control the view from
/// elsewhere (an app bar, a button outside the feed), create a controller,
/// pass it to [ReelFeedView.controller] and dispose it with your state:
///
/// ```dart
/// final view = ReelFeedViewController();
///
/// ReelFeedView(items: urls, controller: view);
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
class ReelFeedViewController extends ChangeNotifier {
  /// Creates a controller. Pass it to [ReelFeedView.controller] and call
  /// [dispose] when your state is disposed.
  ReelFeedViewController();

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

  /// Whether a [ReelFeedView] currently uses this controller. False before the
  /// view is built and after it is removed.
  bool get isAttached => _view != null;

  /// The feed shown by the view, or null until the view has started it (the
  /// first frame after the view appears) and after it is removed.
  ReelFeedManager? get feed => _view?._feed;

  /// The manager that plays the feed, or null until the view has started.
  /// Use it for diagnostics: [ReelKitManager.poolStats],
  /// [ReelKitManager.networkStatus], [ReelKitManager.cache].
  ReelKitManager? get manager => feed?.manager;

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
  /// [duration] and [curve] default to [ReelFeedView.transitionDuration] and
  /// [ReelFeedView.transitionCurve]. The returned future completes when the
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
  /// [duration] and [curve] default to [ReelFeedView.transitionDuration] and
  /// [ReelFeedView.transitionCurve].
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
  /// [duration] and [curve] default to [ReelFeedView.transitionDuration] and
  /// [ReelFeedView.transitionCurve]. For far jumps, [jumpTo] is usually
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

  /// Shows the video in view fullscreen.
  ///
  /// The screen rotates to match the video (landscape videos turn the phone
  /// sideways), system bars hide, the quality cap is lifted so the video plays
  /// at full resolution, and swiping is locked. The back button leaves
  /// fullscreen. Builders see [ReelFeedPage.isFullscreen] as true.
  ///
  /// Does nothing when already fullscreen or when no video is in view.
  Future<void> enterFullscreen() => _attached._enterFullscreen();

  /// Leaves fullscreen: restores the orientation, the system bars, the
  /// quality cap and swiping.
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
  /// [ReelFeedView.pauseWhenHidden]).
  void pause() => _attached._setUserPaused(true);

  /// Undoes [pause]: the video in view plays again, unless the view is
  /// hidden.
  void resume() => _attached._setUserPaused(false);

  /// Whether [pause] was called without a matching [resume].
  bool get isPaused => _view?._userPaused ?? false;

  _ReelFeedViewState<dynamic> get _attached {
    final view = _view;
    if (view == null) {
      throw StateError('ReelFeedViewController is not attached to a view.');
    }
    return view;
  }
}

/// A complete short-video feed screen, like Reels, Shorts or TikTok.
///
/// Give it your items and say where each item's video is:
///
/// ```dart
/// ReelFeedView<Post>(
///   items: posts,
///   videoUrl: (post) => post.videoUrl,
///   posterUrl: (post) => post.thumbnailUrl,   // optional
///   onLoadMore: () => api.fetchMorePosts(),   // optional
/// )
/// ```
///
/// A list of URL strings needs nothing else: `ReelFeedView(items: urls)`.
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
///   [ReelDefaultControls]);
/// * the swipe direction: [scrollDirection], [reverse];
/// * how pages move: [transition];
/// * how videos fit: [fit], or the whole video layer with [videoBuilder];
/// * playback and preloading settings: [manager], [feedConfig].
///
/// The defaults ([ReelKitConfig.reels], [ReelFeedConfig.reels]) are tuned for
/// swiping two or three videos a second.
///
/// To add, insert and remove items from your own code, or to share a feed
/// between screens, create a [ReelFeedManager] and use [ReelFeedView.feed].
class ReelFeedView<T> extends StatefulWidget {
  /// Creates a feed of [items].
  ///
  /// Tell the view where each item's video is with [videoUrl] (a URL) or
  /// [source] (assets, files, HTTP headers). Items that are already URL
  /// strings or [ReelSource]s need neither. If the view cannot find a video
  /// for an item, it throws an [ArgumentError] that names the missing
  /// argument.
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
    this.onItemViewed,
    this.onRefresh,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
    this.pauseWhenHidden = true,
  }) : feed = null,
       onEndReached = null,
       assert(loadMoreThreshold >= 0),
       assert(precachePosters >= 0);

  /// Shows a [ReelFeedManager] that you create and own.
  ///
  /// Use this when your code changes the list itself (insert, remove, update
  /// sources) or when several screens share one feed. You add items to the
  /// feed (see [onEndReached]) and dispose it, or its manager, yourself. Your
  /// object is the [ReelFeedItem.data] of each entry and arrives in builders as
  /// [ReelFeedPage.data].
  ///
  /// ```dart
  /// final feed = manager.createFeed(entries, config: ReelFeedConfig.reels);
  /// ReelFeedView<Post>.feed(
  ///   feed: feed,
  ///   onEndReached: () => feed.addAll(nextEntries()),
  /// )
  /// ```
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
    this.onItemViewed,
    this.loadMoreThreshold = 3,
    this.precachePosters = 3,
    this.autoAdvance = false,
    this.pauseWhenHidden = true,
  }) : items = null,
       videoUrl = null,
       source = null,
       posterUrl = null,
       poster = null,
       itemId = null,
       onLoadMore = null,
       onRefresh = null,
       manager = null,
       feedConfig = ReelFeedConfig.reels,
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
  final String Function(T item)? videoUrl;

  /// Returns an item's video as a [ReelSource], when a URL is not enough:
  ///
  /// ```dart
  /// source: (post) => ReelSource.network(post.url, headers: {'Authorization': token}),
  /// source: (clip) => ReelSource.asset('assets/${clip.file}'),
  /// ```
  ///
  /// Takes precedence over [videoUrl]. Not needed when the items are
  /// [ReelSource]s.
  final ReelSource Function(T item)? source;

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
  /// By default the view creates one with [ReelKitConfig.reels] and disposes
  /// it when the view is removed. Pass your own to change settings. Start
  /// from the preset to keep its tuning:
  ///
  /// ```dart
  /// manager: ReelKitManager(config: ReelKitConfig.reels(looping: false)),
  /// ```
  ///
  /// A plain `ReelKitConfig()` drops the preset: no screen-sized quality
  /// cap, fewer players, and the screen may stay sideways after fullscreen
  /// (see `ReelFullscreenConfig.appOrientations`).
  ///
  /// A manager you pass is initialized by the view if needed, and you dispose
  /// it.
  final ReelKitManager? manager;

  /// How many videos are prepared ahead and behind, and how they are limited
  /// on mobile data or low memory. Defaults to [ReelFeedConfig.reels]: five
  /// ahead, one behind. Lower it to save data and memory.
  final ReelFeedConfig feedConfig;

  /// The feed shown by [ReelFeedView.feed]; null with the main constructor.
  final ReelFeedManager? feed;

  /// [ReelFeedView.feed] only: called when the user is [loadMoreThreshold]
  /// items from the end, once per feed length. Append the next items to your
  /// feed there. With the main constructor use [onLoadMore] instead.
  final VoidCallback? onEndReached;

  /// Controls the view from outside it: next page, fullscreen, mute, current
  /// index. Optional; builders get a controller as [ReelFeedPage.view]
  /// anyway. You create and dispose it.
  final ReelFeedViewController? controller;

  /// The page shown first, 0 by default. Use it to open the feed at a tapped
  /// item. Ignored when the feed already has a page in view (a rebuilt
  /// [ReelFeedView.feed]).
  final int initialIndex;

  /// The swipe direction. [Axis.vertical] (default) for a reels feed,
  /// [Axis.horizontal] for stories or a carousel.
  final Axis scrollDirection;

  /// Reverses the swipe direction: the next item comes from above (vertical)
  /// or from the left (horizontal). False by default.
  final bool reverse;

  /// How pages move from one to the next while the user swipes and when the
  /// view moves from code. [ReelFeedTransition.slide] by default; also
  /// [ReelFeedTransition.parallax], [ReelFeedTransition.stack],
  /// [ReelFeedTransition.fade], [ReelFeedTransition.zoom],
  /// [ReelFeedTransition.cube], or your own with [ReelFeedTransition.custom].
  final ReelFeedTransition transition;

  /// How long moves made from code take ([ReelFeedViewController.nextPage]
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
  /// videoBuilder: (context, page) => ReelVideoView(
  ///   controller: page.controller,
  ///   borderRadius: BorderRadius.circular(16),
  /// ),
  /// ```
  final ReelFeedPageBuilder<T>? videoBuilder;

  /// Draws everything above the video on each page: buttons, captions, a
  /// progress bar.
  ///
  /// Defaults to [ReelDefaultControls] (tap to pause, sound, fullscreen for
  /// landscape videos, progress, buffering indicator, retry). Three ways to
  /// customize:
  ///
  /// ```dart
  /// // Keep the defaults and add your own layer.
  /// controlsBuilder: (context, page) => ReelDefaultControls(
  ///   page: page,
  ///   child: Caption(post: page.data),
  /// ),
  ///
  /// // Build your own controls; ReelProgressBar, ReelBufferingIndicator and
  /// // ReelMuteButton are there to reuse.
  /// controlsBuilder: (context, page) => MyControls(page: page),
  ///
  /// // No controls at all.
  /// controlsBuilder: null,
  /// ```
  final ReelFeedPageBuilder<T>? controlsBuilder;

  /// Shown when there are no items, for example "No videos yet". Defaults to
  /// an empty screen in [backgroundColor].
  final WidgetBuilder? emptyBuilder;

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
  /// example `ReelKitManager(config: ReelKitConfig.reels(looping: false))`.
  final bool autoAdvance;

  /// Whether the view pauses itself while it cannot be seen. True by
  /// default.
  ///
  /// The view counts as hidden when a full-screen route is pushed over it
  /// (a profile page, for example) and when it sits in a tab that is not
  /// shown, as with `TabBarView`, `CupertinoTabScaffold` or go_router's
  /// `StatefulShellRoute`. It resumes when it is visible again. Dialogs and
  /// bottom sheets leave the feed visible, so the video keeps playing under
  /// them, as in short-video apps; call [ReelFeedViewController.pause] to
  /// stop it there.
  ///
  /// A plain `IndexedStack` does not tell its hidden children that they are
  /// hidden; wrap each child in `TickerMode(enabled: isSelected, ...)`.
  ///
  /// The app going to the background pauses playback regardless of this
  /// setting (see `ReelLifecycleConfig`).
  final bool pauseWhenHidden;

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
  /// (with a zero [ReelItemView.watchTime]).
  final void Function(ReelItemView<T> view)? onItemViewed;

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

  // Pausing: the view pauses the feed while hidden or paused from the
  // controller, and resumes it only when it paused it itself.
  bool _hidden = false;
  bool _userPaused = false;
  bool _pausedFeed = false;

  // The item in view, for onItemViewed.
  ReelFeedItem? _viewed;
  int _viewedIndex = 0;
  ReelPlayerController? _viewedController;
  final Stopwatch _watch = Stopwatch();
  Duration? _viewedDuration;
  bool _viewedCompleted = false;

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
        widget.manager ??
        ReelKitManager(
          config: ReelKitConfig.reels(looping: !widget.autoAdvance),
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
    final pause = _userPaused || (_hidden && widget.pauseWhenHidden);
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
    if (oldWidget.pauseWhenHidden != widget.pauseWhenHidden) _applyPause();
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
    if (item == null || widget.onItemViewed == null) return;
    _viewed = item;
    _viewedIndex = index!;
    _viewedController = (feed!.activeController ?? feed.controllerAt(index))
      ..addListener(_onViewedState);
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
    if (state.status == ReelPlaybackStatus.completed) _viewedCompleted = true;
  }

  void _reportViewed() {
    final item = _viewed;
    final controller = _viewedController;
    if (controller != null && !controller.isDisposed) {
      controller.removeListener(_onViewedState);
    }
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
    try {
      onItemViewed(
        ReelItemView<T>(
          item: item,
          index: _viewedIndex,
          watchTime: watchTime,
          duration: duration,
          completed: completed,
        ),
      );
    } on Object catch (error, stack) {
      _report(error, stack, 'while reporting a watched item');
    }
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
        child: _withRefresh(
          context,
          LayoutBuilder(
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

  /// Wraps [child] in a refresh indicator when [ReelFeedView.onRefresh] is
  /// set and the feed is vertical.
  Widget _withRefresh(BuildContext context, Widget child) {
    if (widget.onRefresh == null ||
        widget.scrollDirection != Axis.vertical ||
        widget.reverse ||
        _isFullscreen) {
      return child;
    }
    final Widget indicator = RefreshIndicator(
      onRefresh: _refresh,
      semanticsLabel: 'Refresh',
      notificationPredicate: (notification) => notification.depth == 0,
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
