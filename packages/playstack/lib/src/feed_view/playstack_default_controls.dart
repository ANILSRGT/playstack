import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../controller/playstack_video_quality.dart';
import '../feed/playstack_feed_manager.dart';
import 'playstack_feed_view.dart';
import '../manager/playstack_manager.dart';
import 'playstack_debug_overlay.dart';
import 'playstack_thumbnails.dart';

/// What [PlayStackDefaultControls] does while the user holds a finger on the
/// video.
enum PlayStackHoldAction {
  /// Nothing; a long press is ignored.
  none,

  /// The video pauses while held and plays again on release, so the user
  /// can look at a frame. The default.
  pause,

  /// The video plays faster while held ([PlayStackDefaultControls.holdSpeed],
  /// 2x by default) and returns to normal speed on release. A badge shows
  /// the speed.
  speedUp,
}

/// Where [PlayStackDefaultControls] lets vertical drags change the
/// brightness (left half) and the volume (right half).
enum PlayStackDragGestures {
  /// Never (the default).
  off,

  /// Only in fullscreen, where swiping does not move the feed.
  fullscreen,

  /// Everywhere. Only for horizontal feeds and single players: in a
  /// vertical feed the drag would no longer move to the next video.
  always,
}

/// The controls a [PlayStackFeedView] shows when you pass no `controlsBuilder`.
///
/// They provide:
///
/// * tap anywhere to pause, tap again to play (a play icon shows while
///   paused);
/// * a sound switch at the bottom right that mutes the whole feed;
/// * a fullscreen button next to it on landscape videos (an exit button in
///   fullscreen);
/// * a settings button that opens [PlayStackSettingsSheet]: playback speed,
///   quality and subtitles;
/// * the subtitle text, when a subtitle track is on (see
///   [PlayStackSubtitles]);
/// * hold to pause (or to play faster, see [holdAction]);
/// * a thin progress bar along the bottom edge; drag along it to move in
///   the video;
/// * a spinner that appears only when loading takes long (see
///   [bufferingIndicatorDelay]);
/// * a retry button when a video fails;
/// * in fullscreen, a cinema button that hides the controls until the next
///   tap, and a lock button (see [PlayStackFeedViewController.lockScreen]).
///
/// In cinema mode and while the screen is locked only the video, the
/// subtitles and the loading spinner stay on screen.
///
/// Keep them and add your own layer on top with [child]:
///
/// ```dart
/// controlsBuilder: (context, page) => PlayStackDefaultControls(
///   page: page,
///   onDoubleTap: () => like(page.data),
///   child: Caption(post: page.data),
/// ),
/// ```
///
/// Turn parts off with the `show...` flags, or replace the controls
/// completely with your own `controlsBuilder`. The parts are public widgets
/// to reuse there: [PlayStackProgressBar], [PlayStackBufferingIndicator],
/// [PlayStackMuteButton].
class PlayStackDefaultControls extends StatefulWidget {
  /// Creates the default controls of [page], the page passed to the
  /// `controlsBuilder`.
  const PlayStackDefaultControls({
    super.key,
    required this.page,
    this.child,
    this.tapToPause = true,
    this.onDoubleTap,
    this.holdAction = PlayStackHoldAction.pause,
    this.holdSpeed = 2.0,
    this.showMuteButton = true,
    this.showFullscreenButton = true,
    this.showProgress = true,
    this.showSettingsButton = true,
    this.showSubtitles = true,
    this.showCinemaModeButton = true,
    this.showLockButton = true,
    this.playbackSpeeds = PlayStackSettingsSheet.defaultSpeeds,
    this.seekable = true,
    this.showBufferingIndicator = true,
    this.bufferingIndicatorDelay = const Duration(seconds: 2),
    this.bufferingIndicator,
    this.color = const Color(0xFFFFFFFF),
    this.doubleTapToSeek,
    this.dragGestures = PlayStackDragGestures.off,
    this.thumbnails,
    this.scrubPreviewBuilder,
    this.showDebugInfo = false,
    this.showLiveBadge = true,
    this.horizontalDragToSeek = false,
  });

  /// The default value of `PlayStackFeedView.controlsBuilder`: the default controls
  /// with no changes. Pass it explicitly to restore the defaults.
  static Widget builder(
    BuildContext context,
    PlayStackFeedPage<Object?> page,
  ) => PlayStackDefaultControls(page: page);

  /// The page these controls belong to: the `page` argument of
  /// `controlsBuilder`.
  final PlayStackFeedPage<Object?> page;

  /// Your own layer: captions, like buttons, an avatar. Drawn above the video
  /// and below the default buttons.
  ///
  /// Buttons in it receive their taps at once, even with [onDoubleTap] set.
  /// Taps on empty parts of it fall through to [tapToPause], double tap and
  /// hold; taps on its widgets (text, icons, buttons) do not. Check
  /// `page.isFullscreen` to hide it in fullscreen.
  final Widget? child;

  /// Whether tapping the video pauses it and tapping again plays it. True by
  /// default.
  final bool tapToPause;

  /// Called when the user double-taps the video, for example to like the
  /// post. Null by default.
  ///
  /// Setting it delays tap-to-pause by about 300 ms, because Flutter waits
  /// to see whether a second tap follows. Buttons in [child] are not
  /// delayed.
  final VoidCallback? onDoubleTap;

  /// What happens while the user holds a finger on the video:
  /// [PlayStackHoldAction.pause] (default), [PlayStackHoldAction.speedUp] or
  /// [PlayStackHoldAction.none].
  final PlayStackHoldAction holdAction;

  /// Playback speed while held with [PlayStackHoldAction.speedUp], 2.0 by
  /// default.
  final double holdSpeed;

  /// Whether the sound switch is shown at the bottom right. True by default.
  /// It mutes and unmutes every video of the feed. Turn it off when you draw
  /// your own, for example with [PlayStackMuteButton].
  final bool showMuteButton;

  /// Whether landscape videos get a fullscreen button next to the sound
  /// switch. True by default. In fullscreen it shows an exit button for every
  /// video. Portrait videos already fill the screen and get none.
  final bool showFullscreenButton;

  /// Whether a thin progress bar runs along the bottom edge. True by default.
  final bool showProgress;

  /// Whether a settings button next to the sound switch opens
  /// [PlayStackSettingsSheet] (speed and subtitles). True by default; turn it
  /// off for short clips where nobody changes the speed.
  final bool showSettingsButton;

  /// Whether the subtitle text is shown above the progress bar while a
  /// subtitle track is on. True by default. Subtitles are off until the user
  /// picks a track in the settings sheet, unless the stream turns one on.
  final bool showSubtitles;

  /// Whether a cinema button hides the controls until the next tap
  /// ([PlayStackFeedViewController.enterCinemaMode]). True by default.
  final bool showCinemaModeButton;

  /// Whether a lock button is shown
  /// ([PlayStackFeedViewController.lockScreen]): touches, swipes and
  /// turning the device are ignored until the user unlocks. True by
  /// default.
  final bool showLockButton;

  /// The speeds offered in the settings sheet.
  /// [PlayStackSettingsSheet.defaultSpeeds] (0.5x to 2x) by default.
  final List<double> playbackSpeeds;

  /// Whether the user can drag along the progress bar to move in the video.
  /// True by default. See [PlayStackProgressBar.seekable].
  final bool seekable;

  /// Whether a spinner appears when loading takes long. True by default.
  final bool showBufferingIndicator;

  /// How long loading may take before the spinner appears, 2 seconds by
  /// default. Until then the last frame or the poster stays on screen, which
  /// looks like a brief pause rather than a loading screen. Over a black
  /// screen (no frame and no poster yet) the spinner appears after 800 ms.
  final Duration bufferingIndicatorDelay;

  /// What is shown while the video loads, for example your own animation.
  /// Null shows a spinner. Appears after the same delays.
  final Widget? bufferingIndicator;

  /// Color of the icons, the spinner and the progress bar. White by default.
  final Color color;

  /// How far a double tap on the left or right third of the video jumps
  /// back or forward, like video apps. Null (the default) turns it off; a
  /// double tap then calls [onDoubleTap] anywhere. With both, the middle
  /// third calls [onDoubleTap]. Keep tapping the same side to jump again.
  final Duration? doubleTapToSeek;

  /// Where dragging up and down changes the brightness (left half) and the
  /// volume (right half). [PlayStackDragGestures.off] by default. The
  /// brightness returns to the system's when fullscreen ends.
  final PlayStackDragGestures dragGestures;

  /// Preview images shown above the progress bar while it is dragged. See
  /// [PlayStackThumbnails].
  final PlayStackThumbnails? thumbnails;

  /// Replaces the preview shown while the progress bar is dragged.
  final PlayStackScrubPreviewBuilder? scrubPreviewBuilder;

  /// Whether a [PlayStackDebugOverlay] shows state, bitrate, buffer and
  /// timings. False by default; for development.
  final bool showDebugInfo;

  /// Whether live streams show a [PlayStackLiveBadge] at the top left
  /// (tap it to go back to live). True by default.
  final bool showLiveBadge;

  /// Whether dragging sideways anywhere on the video moves in it, like
  /// short-video apps: the progress bar grows and shows the preview while
  /// the finger moves, and the video jumps when it lifts. False by default.
  ///
  /// Easier than hitting the thin bar at the bottom edge, where the system's
  /// home gesture lives. Only for vertical feeds and single players: in a
  /// horizontal feed sideways drags move to the next video.
  final bool horizontalDragToSeek;

  @override
  State<PlayStackDefaultControls> createState() =>
      _PlayStackDefaultControlsState();
}

class _PlayStackDefaultControlsState extends State<PlayStackDefaultControls> {
  bool _pausedByUser = false;

  // Double tap to seek.
  double _width = 0;
  double _height = 0;
  Offset? _doubleTapAt;

  /// The side being tapped to seek (-1 back, 1 forward), while taps keep
  /// seeking.
  int? _seekSide;
  Duration _seekTotal = Duration.zero;
  Timer? _seekStreak;

  // Sideways drag to seek: the point being dragged to, from 0 to 1.
  double? _scrubValue;

  bool get _scrubEnabled =>
      widget.horizontalDragToSeek &&
      widget.seekable &&
      widget.page.isActive &&
      !(widget.page.view.scrollDirection == Axis.horizontal &&
          !widget.page.isFullscreen) &&
      !(_controller.value.videoInfo?.isLive ?? false);

  bool _scrubbing = false;
  double _scrubDelta = 0;

  Future<void> _onScrubStart(DragStartDetails _) async {
    final duration = _controller.value.duration;
    if (duration == null || duration <= Duration.zero) return;
    _scrubbing = true;
    _scrubDelta = 0;
    final thumbnails = widget.thumbnails;
    if (thumbnails != null) unawaited(thumbnails.load().catchError(_ignore));
    final snapshot = await _controller.getPosition().catchError(
      (Object _) => const PlayStackPositionSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
      ),
    );
    if (!mounted || !_scrubbing) return;
    final start = snapshot.position.inMilliseconds / duration.inMilliseconds;
    setState(() => _scrubValue = (start + _scrubDelta).clamp(0.0, 1.0));
  }

  void _onScrubUpdate(DragUpdateDetails details) {
    if (!_scrubbing || _width <= 0) return;
    // The whole width spans the whole video, whatever its length.
    final delta = details.delta.dx / _width;
    final value = _scrubValue;
    if (value == null) {
      _scrubDelta += delta;
      return;
    }
    setState(() => _scrubValue = (value + delta).clamp(0.0, 1.0));
  }

  void _onScrubEnd([DragEndDetails? _]) {
    _scrubbing = false;
    final value = _scrubValue;
    final duration = _controller.value.duration;
    setState(() => _scrubValue = null);
    if (value == null || duration == null) return;
    unawaited(
      _controller
          .seekTo(
            Duration(microseconds: (duration.inMicroseconds * value).round()),
          )
          .catchError(_ignore),
    );
  }

  // Drag for brightness and volume.
  bool? _draggingBrightness;
  double _dragValue = 0;
  bool _changedBrightness = false;
  Timer? _dragHud;
  bool _showDragHud = false;

  PlayStackManager get _manager => widget.page.feed.manager;

  bool get _dragEnabled => switch (widget.dragGestures) {
    PlayStackDragGestures.off => false,
    PlayStackDragGestures.fullscreen => widget.page.isFullscreen,
    PlayStackDragGestures.always => true,
  };

  /// -1, 0 or 1 for the left, middle and right third of the video.
  int _sideAt(double dx) {
    if (_width <= 0) return 0;
    if (dx < _width / 3) return -1;
    if (dx > _width * 2 / 3) return 1;
    return 0;
  }

  void _seekStep(int side) {
    final step = widget.doubleTapToSeek;
    if (step == null || side == 0) return;
    if (_seekSide != side) _seekTotal = Duration.zero;
    _seekSide = side;
    _seekTotal += step;
    unawaited(_controller.seekBy(step * side).catchError(_ignore));
    _seekStreak?.cancel();
    _seekStreak = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekSide = null);
    });
    setState(() {});
  }

  void _onTapUp(TapUpDetails details) {
    // While the user keeps tapping one side, each tap jumps again.
    final side = _sideAt(details.localPosition.dx);
    if (_seekSide != null && side == _seekSide) {
      _seekStep(side);
      return;
    }
    if (widget.tapToPause) _togglePlay();
  }

  void _onDoubleTap() {
    final at = _doubleTapAt;
    final side = at == null ? 0 : _sideAt(at.dx);
    if (widget.doubleTapToSeek != null && side != 0) {
      if (!widget.page.isActive || !_controller.value.isInitialized) return;
      _seekStep(side);
      return;
    }
    widget.onDoubleTap?.call();
  }

  Future<void> _onDragStart(DragStartDetails details) async {
    final brightness = details.localPosition.dx < _width / 2;
    _draggingBrightness = brightness;
    _dragValue = brightness
        ? (await _manager.getScreenBrightness().catchError(
                (Object _) => null,
              ) ??
              0.5)
        : (_controller.value.isMuted ? 0 : _controller.value.volume);
    _dragHud?.cancel();
    if (mounted) setState(() => _showDragHud = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final brightness = _draggingBrightness;
    if (brightness == null || _height <= 0) return;
    _dragValue = (_dragValue - details.delta.dy / (_height * 0.7)).clamp(
      0.0,
      1.0,
    );
    if (brightness) {
      _changedBrightness = true;
      unawaited(_manager.setScreenBrightness(_dragValue).catchError(_ignore));
    } else {
      if (_controller.value.isMuted && _dragValue > 0) {
        unawaited(_controller.setMuted(false).catchError(_ignore));
      }
      unawaited(_controller.setVolume(_dragValue).catchError(_ignore));
    }
    setState(() {});
  }

  void _onDragEnd([DragEndDetails? _]) {
    _dragHud?.cancel();
    _dragHud = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showDragHud = false);
    });
  }

  void _restoreBrightness() {
    if (!_changedBrightness) return;
    _changedBrightness = false;
    unawaited(_manager.setScreenBrightness(null).catchError(_ignore));
  }

  /// The action of the finger held down right now, if any.
  PlayStackHoldAction? _holding;
  double _speedBeforeHold = 1;

  PlayStackPlayerController get _controller => widget.page.controller;

  @override
  void didUpdateWidget(PlayStackDefaultControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.isFullscreen && !widget.page.isFullscreen) {
      _restoreBrightness();
    }
    if (!widget.page.isActive) {
      _pausedByUser = false;
      _endHold();
    }
  }

  @override
  void dispose() {
    _endHold();
    _seekStreak?.cancel();
    _dragHud?.cancel();
    _restoreBrightness();
    super.dispose();
  }

  void _startHold() {
    final state = _controller.value;
    if (!widget.page.isActive || state.hasError || !state.isPlaying) return;
    final action = widget.holdAction;
    switch (action) {
      case PlayStackHoldAction.none:
        return;
      case PlayStackHoldAction.pause:
        unawaited(_controller.pause().catchError(_ignore));
      case PlayStackHoldAction.speedUp:
        _speedBeforeHold = state.playbackSpeed;
        unawaited(
          _controller.setPlaybackSpeed(widget.holdSpeed).catchError(_ignore),
        );
    }
    setState(() => _holding = action);
  }

  void _endHold() {
    final action = _holding;
    if (action == null) return;
    _holding = null;
    if (_controller.isDisposed) return;
    switch (action) {
      case PlayStackHoldAction.none:
        break;
      case PlayStackHoldAction.pause:
        if (widget.page.isActive) {
          unawaited(_controller.play().catchError(_ignore));
        }
      case PlayStackHoldAction.speedUp:
        unawaited(
          _controller.setPlaybackSpeed(_speedBeforeHold).catchError(_ignore),
        );
    }
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final state = _controller.value;
    if (state.hasError || !widget.page.isActive) return;
    if (state.isPlaying) {
      setState(() => _pausedByUser = true);
      unawaited(_controller.pause().catchError(_ignore));
    } else {
      setState(() => _pausedByUser = false);
      unawaited(_controller.play().catchError(_ignore));
    }
  }

  static void _ignore(Object _) {}

  static String _formatSpeed(double speed) => speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return ValueListenableBuilder<PlayStackPlaybackState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final error = state.error;
        if (state.hasError && error != null) {
          return PlayStackErrorView(
            error: error,
            color: widget.color,
            onRetry: () => unawaited(_controller.retry().catchError(_ignore)),
          );
        }
        final shadow = [const Shadow(blurRadius: 8)];
        // Cinema mode and the screen lock leave the picture alone; the view
        // takes the touches meanwhile.
        final hidden = page.isCinemaMode || page.isScreenLocked;
        Widget chrome(Widget child) => _Chrome(hidden: hidden, child: child);
        return Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                _width = constraints.maxWidth;
                _height = constraints.maxHeight;
                final seekGestures = widget.doubleTapToSeek != null;
                final drags = _dragEnabled;
                final scrub = _scrubEnabled;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: widget.tapToPause || seekGestures ? _onTapUp : null,
                  // Only with a double tap action: listening for one delays
                  // every single tap.
                  onDoubleTapDown: widget.onDoubleTap != null || seekGestures
                      ? (details) => _doubleTapAt = details.localPosition
                      : null,
                  onDoubleTap: widget.onDoubleTap != null || seekGestures
                      ? _onDoubleTap
                      : null,
                  onVerticalDragStart: drags
                      ? (details) => unawaited(_onDragStart(details))
                      : null,
                  onVerticalDragUpdate: drags ? _onDragUpdate : null,
                  onVerticalDragEnd: drags ? _onDragEnd : null,
                  onVerticalDragCancel: drags ? _onDragEnd : null,
                  onHorizontalDragStart: scrub
                      ? (details) => unawaited(_onScrubStart(details))
                      : null,
                  onHorizontalDragUpdate: scrub ? _onScrubUpdate : null,
                  onHorizontalDragEnd: scrub ? _onScrubEnd : null,
                  onHorizontalDragCancel: scrub ? _onScrubEnd : null,
                  onLongPressStart:
                      widget.holdAction == PlayStackHoldAction.none
                      ? null
                      : (_) => _startHold(),
                  onLongPressEnd: widget.holdAction == PlayStackHoldAction.none
                      ? null
                      : (_) => _endHold(),
                  onLongPressCancel:
                      widget.holdAction == PlayStackHoldAction.none
                      ? null
                      : _endHold,
                  child: const SizedBox.expand(),
                );
              },
            ),
            if (_seekSide case final side? when !hidden)
              _SeekFeedback(
                forward: side > 0,
                amount: _seekTotal,
                color: widget.color,
              ),
            if (_showDragHud && _draggingBrightness != null)
              _LevelHud(
                icon: _draggingBrightness!
                    ? Icons.brightness_6_rounded
                    : _dragValue == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                value: _dragValue,
                color: widget.color,
              ),
            if (widget.showDebugInfo)
              PlayStackDebugOverlay(controller: _controller, manager: _manager),
            if (widget.showLiveBadge && (state.videoInfo?.isLive ?? false))
              Positioned(
                left: 12,
                top: 12,
                child: chrome(
                  SafeArea(
                    child: PlayStackLiveBadge(
                      controller: _controller,
                      active: page.isActive,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
            // Above the gesture layer, not inside it: its buttons get their
            // taps at once instead of waiting for a possible double tap.
            if (widget.child case final child?) chrome(child),
            if (_holding == PlayStackHoldAction.speedUp && !hidden)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            '${_formatSpeed(widget.holdSpeed)}x',
                            style: TextStyle(
                              color: widget.color,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.showBufferingIndicator)
              PlayStackBufferingIndicator(
                controller: _controller,
                active: page.isActive,
                hasPoster: page.item.poster != null,
                delay: widget.bufferingIndicatorDelay,
                color: widget.color,
                indicator: widget.bufferingIndicator,
              ),
            if (_pausedByUser &&
                state.status == PlayStackPlaybackStatus.paused &&
                !hidden)
              IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 88,
                    color: widget.color.withValues(alpha: 0.8),
                    shadows: shadow,
                  ),
                ),
              ),
            Positioned(
              right: 4,
              bottom: 12,
              child: chrome(
                SafeArea(
                  top: false,
                  left: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showLockButton)
                        _IconButton(
                          icon: Icons.lock_outline_rounded,
                          label: 'Lock screen',
                          color: widget.color,
                          onTap: () => unawaited(
                            page.view.lockScreen().catchError(_ignore),
                          ),
                        ),
                      if (widget.showCinemaModeButton)
                        _IconButton(
                          icon: Icons.visibility_off_outlined,
                          label: 'Hide controls',
                          color: widget.color,
                          onTap: page.view.enterCinemaMode,
                        ),
                      if (widget.showFullscreenButton &&
                          (page.isFullscreen || (state.aspectRatio ?? 0) > 1))
                        _IconButton(
                          icon: page.isFullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          label: page.isFullscreen
                              ? 'Exit fullscreen'
                              : 'Fullscreen',
                          color: widget.color,
                          onTap: () => unawaited(
                            page.view.toggleFullscreen().catchError(_ignore),
                          ),
                        ),
                      if (widget.showSettingsButton)
                        _IconButton(
                          icon: Icons.tune_rounded,
                          label: 'Playback settings',
                          color: widget.color,
                          onTap: () => unawaited(
                            PlayStackSettingsSheet.show(
                              context,
                              controller: _controller,
                              speeds: widget.playbackSpeeds,
                            ),
                          ),
                        ),
                      if (widget.showMuteButton)
                        PlayStackMuteButton(
                          controller: _controller,
                          feed: page.feed,
                          color: widget.color,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.showSubtitles)
              Positioned(
                left: 24,
                right: 24,
                bottom: page.isFullscreen || hidden ? 32 : 120,
                child: IgnorePointer(
                  child: PlayStackSubtitles(controller: _controller),
                ),
              ),
            if (widget.showProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: chrome(
                  PlayStackProgressBar(
                    controller: _controller,
                    active: page.isActive,
                    color: widget.color,
                    seekable: widget.seekable,
                    thumbnails: widget.thumbnails,
                    scrubPreviewBuilder: widget.scrubPreviewBuilder,
                    scrubValue: _scrubValue,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A thin bar showing how far a video has played, like the one at the
/// bottom of short-video apps.
///
/// ```dart
/// Positioned(
///   left: 0,
///   right: 0,
///   bottom: 0,
///   child: PlayStackProgressBar(controller: page.controller, active: page.isActive),
/// ),
/// ```
///
/// It reads the position only while [active] and the video plays, so bars
/// on pages out of view cost nothing. With [seekable], the user can drag
/// along it to move in the video.
class PlayStackProgressBar extends StatefulWidget {
  /// Creates a progress bar for the video of [controller].
  const PlayStackProgressBar({
    super.key,
    required this.controller,
    this.active = true,
    this.height = 2,
    this.color = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0x3DFFFFFF),
    this.interval = const Duration(milliseconds: 200),
    this.seekable = false,
    this.touchHeight = 36,
    this.thumbnails,
    this.showScrubPreview = true,
    this.scrubPreviewBuilder,
    this.scrubValue,
  });

  /// The video whose progress is shown, usually `page.controller`.
  final PlayStackPlayerController controller;

  /// Whether the bar follows the video. Pass `page.isActive` so that only the
  /// page in view reads positions. True by default.
  final bool active;

  /// Thickness of the bar in logical pixels, 2 by default.
  final double height;

  /// Color of the played part, white by default.
  final Color color;

  /// Color of the part not played yet, translucent white by default.
  final Color backgroundColor;

  /// How often the position is read while playing, 200 ms by default. Lower
  /// values move the bar more smoothly and cost more.
  final Duration interval;

  /// Whether the user can drag along the bar, or tap it, to move in the
  /// video. False by default. While dragging the bar grows thicker and the
  /// video jumps to the chosen point when the finger lifts.
  final bool seekable;

  /// Height of the area that reacts to the finger when [seekable], 36 by
  /// default. The bar stays [height] thick at the bottom of it; the area
  /// makes it easy to hit.
  final double touchHeight;

  /// Preview images shown above the finger while dragging, for example
  /// `PlayStackThumbnails.webVtt(url)`. Null shows the time only.
  final PlayStackThumbnails? thumbnails;

  /// Whether a preview (time, and the thumbnail when [thumbnails] is set)
  /// floats above the finger while dragging. True by default.
  final bool showScrubPreview;

  /// Replaces the default preview ([PlayStackScrubPreview]). It receives
  /// the position under the finger and its thumbnail, if any.
  final PlayStackScrubPreviewBuilder? scrubPreviewBuilder;

  /// A drag run from outside the bar, from 0 to 1, for example a sideways
  /// drag on the whole video (see
  /// [PlayStackDefaultControls.horizontalDragToSeek]). While set the bar
  /// shows it like its own drag: thicker, with the preview. Seek yourself
  /// when the drag ends. Null by default.
  final double? scrubValue;

  @override
  State<PlayStackProgressBar> createState() => _PlayStackProgressBarState();
}

class _PlayStackProgressBarState extends State<PlayStackProgressBar> {
  static const double _previewWidth = 160;

  Widget _preview(
    BuildContext context,
    double value,
    double width,
    Duration duration,
  ) {
    final position = Duration(
      microseconds: (duration.inMicroseconds * value).round(),
    );
    Widget build(BuildContext context) {
      final thumbnail = widget.thumbnails?.at(position);
      return widget.scrubPreviewBuilder?.call(context, position, thumbnail) ??
          PlayStackScrubPreview(
            position: position,
            thumbnail: thumbnail,
            color: widget.color,
          );
    }

    final updates = widget.thumbnails?.updates;
    final preview = updates == null
        ? build(context)
        : ListenableBuilder(
            listenable: updates,
            builder: (context, _) => build(context),
          );
    final left = (value * width - _previewWidth / 2).clamp(
      0.0,
      (width - _previewWidth).clamp(0.0, double.infinity),
    );
    return Positioned(
      left: left,
      bottom: widget.touchHeight + 8,
      width: _previewWidth,
      child: IgnorePointer(child: Center(child: preview)),
    );
  }

  Stream<PlayStackPositionSnapshot>? _positions;

  /// The point being dragged to, from 0 to 1; null when not dragging.
  double? _dragValue;

  /// The bar's own drag, or the one run from outside.
  double? get _drag => _dragValue ?? widget.scrubValue;

  /// The point last seeked to, shown until the position catches up.
  double? _seekValue;

  static void _ignore(Object _) {}

  double _valueAt(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  void _startDrag(double value) {
    final thumbnails = widget.thumbnails;
    if (thumbnails != null) {
      unawaited(
        thumbnails.load().then((_) {
          if (mounted) setState(() {});
        }, onError: (Object _) {}),
      );
    }
    setState(() => _dragValue = value);
  }

  void _seek(double value, Duration duration) {
    setState(() {
      _dragValue = null;
      _seekValue = value;
    });
    final target = Duration(
      microseconds: (duration.inMicroseconds * value).round(),
    );
    unawaited(
      widget.controller.seekTo(target).catchError(_ignore).whenComplete(() {
        if (mounted) setState(() => _seekValue = null);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active) {
      _positions ??= widget.controller.positions(interval: widget.interval);
    } else {
      _positions = null;
      _dragValue = null;
    }
    final seekable = widget.seekable && widget.active;
    final empty = SizedBox(
      height: seekable ? widget.touchHeight : widget.height,
    );
    final positions = _positions;
    if (positions == null) return empty;
    return ValueListenableBuilder<PlayStackPlaybackState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final duration = state.duration;
        if (duration == null || duration <= Duration.zero) return empty;
        // Live streams have no fixed length; PlayStackLiveBadge shows them.
        if (state.videoInfo?.isLive ?? false) return empty;
        final bar = StreamBuilder<PlayStackPositionSnapshot>(
          stream: positions,
          builder: (context, snapshot) {
            final position = snapshot.data?.position ?? Duration.zero;
            final value =
                _drag ??
                _seekValue ??
                position.inMilliseconds / duration.inMilliseconds;
            final height = _drag != null
                ? widget.height * 2.5
                : widget.height;
            return SizedBox(
              height: height,
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: height,
                color: widget.color,
                backgroundColor: widget.backgroundColor,
              ),
            );
          },
        );
        if (!seekable) return IgnorePointer(child: bar);
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Semantics(
              slider: true,
              label: 'Video position',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) =>
                    _startDrag(_valueAt(details.localPosition.dx, width)),
                onHorizontalDragUpdate: (details) => setState(
                  () => _dragValue = _valueAt(details.localPosition.dx, width),
                ),
                onHorizontalDragEnd: (_) {
                  final value = _dragValue;
                  if (value != null) _seek(value, duration);
                },
                onHorizontalDragCancel: () => setState(() => _dragValue = null),
                onTapUp: (details) =>
                    _seek(_valueAt(details.localPosition.dx, width), duration),
                child: SizedBox(
                  height: widget.touchHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Align(alignment: Alignment.bottomCenter, child: bar),
                      if (_drag case final value?
                          when widget.showScrubPreview)
                        _preview(context, value, width, duration),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Builds what floats above the finger while the user drags a
/// [PlayStackProgressBar].
typedef PlayStackScrubPreviewBuilder = Widget Function(
  BuildContext context,
  Duration position,
  PlayStackThumbnail? thumbnail,
);

/// The default preview above a dragged progress bar: the thumbnail (when
/// there is one) and the time.
class PlayStackScrubPreview extends StatelessWidget {
  /// Creates a preview of [position].
  const PlayStackScrubPreview({
    super.key,
    required this.position,
    this.thumbnail,
    this.color = const Color(0xFFFFFFFF),
    this.thumbnailSize = const Size(160, 90),
  });

  /// The position under the finger.
  final Duration position;

  /// Its image, or null.
  final PlayStackThumbnail? thumbnail;

  /// Text and border color.
  final Color color;

  /// The size of the image, 160 by 90 by default.
  final Size thumbnailSize;

  /// "1:05" or "1:02:05".
  static String format(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60);
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final label = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          format(position),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    final image = thumbnail;
    if (image == null) return label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: thumbnailSize.width,
          height: thumbnailSize.height,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(6),
            color: const Color(0xFF000000),
          ),
          clipBehavior: Clip.antiAlias,
          child: PlayStackThumbnailImage(thumbnail: image),
        ),
        const SizedBox(height: 4),
        label,
      ],
    );
  }
}

/// A loading spinner that appears only when the video makes the user wait
/// long.
///
/// While a video prepares or rebuffers, nothing is drawn at first: the last
/// frame or the poster stays on screen, which feels like a short pause.
/// Only after [delay] (or [blackScreenDelay] over a black screen) does the
/// spinner fade in. Short waits during fast swiping therefore never flash a
/// spinner.
///
/// ```dart
/// PlayStackBufferingIndicator(
///   controller: page.controller,
///   active: page.isActive,
///   hasPoster: page.item.poster != null,
/// )
/// ```
class PlayStackBufferingIndicator extends StatelessWidget {
  /// Creates a spinner for the waits of [controller].
  const PlayStackBufferingIndicator({
    super.key,
    required this.controller,
    this.active = true,
    this.hasPoster = false,
    this.delay = const Duration(seconds: 2),
    this.blackScreenDelay = const Duration(milliseconds: 800),
    this.color = const Color(0xFFFFFFFF),
    this.size = 36,
    this.indicator,
  });

  /// The video whose loading is shown, usually `page.controller`.
  final PlayStackPlayerController controller;

  /// Whether this video is the one the user watches. Pass `page.isActive`:
  /// pages preparing in the background never show a spinner. True by
  /// default.
  final bool active;

  /// Whether a poster covers the page until the first frame. With a poster,
  /// [delay] applies from the start; without one, the screen is black and
  /// [blackScreenDelay] applies. Pass `page.item.poster != null`.
  final bool hasPoster;

  /// Wait before the spinner appears over a frame or a poster, 2 seconds by default.
  final Duration delay;

  /// Wait before the spinner appears over a black screen, 800 ms by default.
  final Duration blackScreenDelay;

  /// Color of the spinner, white by default.
  final Color color;

  /// Diameter of the spinner in logical pixels, 36 by default.
  final double size;

  /// Shown instead of the spinner, for example an animation of your app.
  /// It is centered and sized by itself; [color] and [size] do not apply.
  final Widget? indicator;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayStackPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final waiting =
            active &&
            !state.hasError &&
            (state.isBuffering ||
                state.status == PlayStackPlaybackStatus.initializing ||
                state.status == PlayStackPlaybackStatus.idle);
        if (!waiting) return const SizedBox.shrink();
        return _Delayed(
          delay: state.hasRenderedFirstFrame || hasPoster
              ? delay
              : blackScreenDelay,
          child: IgnorePointer(
            child: Center(
              child:
                  indicator ??
                  SizedBox.square(
                    dimension: size,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: color,
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }
}

/// Shows [child] after [delay], fading in.
class _Delayed extends StatefulWidget {
  const _Delayed({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: widget.child,
    );
  }
}

/// The subtitle text of a video, centered on a translucent background.
///
/// Shows `controller.subtitles`, which is empty while subtitles are off, so
/// nothing is drawn until the user turns a subtitle track on (for example in
/// [PlayStackSettingsSheet]).
///
/// ```dart
/// Positioned(
///   left: 24,
///   right: 24,
///   bottom: 120,
///   child: PlayStackSubtitles(controller: page.controller),
/// )
/// ```
class PlayStackSubtitles extends StatelessWidget {
  /// Creates the subtitle text of [controller].
  const PlayStackSubtitles({
    super.key,
    required this.controller,
    this.style = const TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 16,
      height: 1.3,
    ),
    this.backgroundColor = const Color(0x99000000),
  });

  /// The video whose subtitles are shown, usually `page.controller`.
  final PlayStackPlayerController controller;

  /// Style of the text: white, 16 logical pixels by default.
  final TextStyle style;

  /// Color behind each line, translucent black by default.
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: controller.subtitles,
      builder: (context, lines, _) {
        final text = lines.where((line) => line.trim().isNotEmpty).join('\n');
        if (text.isEmpty) return const SizedBox.shrink();
        return Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(text, textAlign: TextAlign.center, style: style),
            ),
          ),
        );
      },
    );
  }
}

/// A bottom sheet to change a video's playback speed, quality and
/// subtitles, opened by the settings button of [PlayStackDefaultControls].
///
/// Open it from your own controls with [show]:
///
/// ```dart
/// IconButton(
///   icon: const Icon(Icons.tune),
///   onPressed: () => PlayStackSettingsSheet.show(
///     context,
///     controller: page.controller,
///   ),
/// )
/// ```
///
/// The quality section lists [PlayStackPlayerController.videoQualities] and
/// appears only for streams with several renditions; the subtitle section
/// lists the text tracks and appears only when there are some. The sheet
/// uses the app's Material theme.
class PlayStackSettingsSheet extends StatelessWidget {
  /// Creates the sheet's content for [controller]. Usually opened with
  /// [show] instead.
  const PlayStackSettingsSheet({
    super.key,
    required this.controller,
    this.speeds = defaultSpeeds,
  });

  /// 0.5x, 0.75x, 1x, 1.25x, 1.5x and 2x.
  static const List<double> defaultSpeeds = [0.5, 0.75, 1, 1.25, 1.5, 2];

  /// Opens the sheet for [controller] as a modal bottom sheet. Completes
  /// when it closes.
  static Future<void> show(
    BuildContext context, {
    required PlayStackPlayerController controller,
    List<double> speeds = defaultSpeeds,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) =>
          PlayStackSettingsSheet(controller: controller, speeds: speeds),
    );
  }

  /// The video to change, usually `page.controller`.
  final PlayStackPlayerController controller;

  /// The speeds offered, [defaultSpeeds] by default.
  final List<double> speeds;

  static String _speedLabel(double speed) {
    final text = speed == speed.roundToDouble()
        ? speed.toStringAsFixed(0)
        : speed.toString();
    return speed == 1 ? 'Normal' : '${text}x';
  }

  static String _trackLabel(PlayStackTrack track, int index) =>
      track.label ?? track.language ?? 'Subtitles ${index + 1}';

  static void _ignore(Object _) {}

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ValueListenableBuilder<PlayStackPlaybackState>(
          valueListenable: controller,
          builder: (context, state, _) =>
              ValueListenableBuilder<List<PlayStackTrack>>(
                valueListenable: controller.tracks,
                builder: (context, tracks, _) {
                  final subtitles = [
                    for (final track in tracks)
                      if (track.type == PlayStackTrackType.text) track,
                  ];
                  final subtitlesOff = !subtitles.any(
                    (track) => track.isSelected,
                  );
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Playback speed', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final speed in speeds)
                            ChoiceChip(
                              label: Text(_speedLabel(speed)),
                              selected: state.playbackSpeed == speed,
                              onSelected: (_) => unawaited(
                                controller
                                    .setPlaybackSpeed(speed)
                                    .catchError(_ignore),
                              ),
                            ),
                        ],
                      ),
                      _QualityChoice(controller: controller),
                      if (subtitles.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Subtitles', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Off'),
                              selected: subtitlesOff,
                              onSelected: (_) => unawaited(
                                controller.disableSubtitles().catchError(
                                  _ignore,
                                ),
                              ),
                            ),
                            for (final (i, track) in subtitles.indexed)
                              ChoiceChip(
                                label: Text(_trackLabel(track, i)),
                                selected: track.isSelected,
                                onSelected: (_) => unawaited(
                                  controller
                                      .selectTrack(track)
                                      .catchError(_ignore),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }
}

/// The quality chips of [PlayStackSettingsSheet]; nothing when the video has
/// a single rendition.
class _QualityChoice extends StatelessWidget {
  const _QualityChoice({required this.controller});

  final PlayStackPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final qualities = controller.videoQualities;
    if (qualities.length < 2) return const SizedBox.shrink();
    return ValueListenableBuilder<PlayStackVideoQuality?>(
      valueListenable: controller.videoQuality,
      builder: (context, chosen, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text('Quality', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Auto'),
                selected: chosen == null,
                onSelected: (_) => unawaited(
                  controller.setVideoQuality(null).catchError((Object _) {}),
                ),
              ),
              for (final quality in qualities)
                ChoiceChip(
                  label: Text(quality.label),
                  selected: chosen == quality,
                  onSelected: (_) => unawaited(
                    controller
                        .setVideoQuality(quality)
                        .catchError((Object _) {}),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A sound on/off button with a speaker icon that shows the current state.
///
/// Pass [feed] to mute every video of the feed at once, as short-video apps
/// do; without it only [controller] is muted.
///
/// ```dart
/// PlayStackMuteButton(controller: page.controller, feed: page.feed)
/// ```
class PlayStackMuteButton extends StatelessWidget {
  /// Creates a sound switch that shows whether [controller] is muted.
  const PlayStackMuteButton({
    super.key,
    required this.controller,
    this.feed,
    this.color = const Color(0xFFFFFFFF),
    this.size = 26,
  });

  /// The video whose mute state the icon shows, usually `page.controller`.
  final PlayStackPlayerController controller;

  /// The feed to mute as a whole, usually `page.feed`. Null mutes only
  /// [controller].
  final PlayStackFeedManager? feed;

  /// Color of the icon, white by default.
  final Color color;

  /// Size of the icon in logical pixels, 26 by default.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayStackPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final muted = state.isMuted;
        return Semantics(
          button: true,
          label: muted ? 'Unmute' : 'Mute',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final feed = this.feed;
              if (feed != null) {
                feed.setMuted(!muted);
              } else {
                unawaited(controller.setMuted(!muted).catchError((_) {}));
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: size,
                color: color,
                shadows: const [Shadow(blurRadius: 8)],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A "LIVE" badge for live streams: red at the live edge, grey with how far
/// behind while the user paused or went back. A tap returns to live
/// ([PlayStackPlayerController.seekToLiveEdge]).
///
/// [PlayStackDefaultControls] shows it on live streams; place it yourself
/// in your own controls.
class PlayStackLiveBadge extends StatefulWidget {
  /// Creates a badge for [controller].
  const PlayStackLiveBadge({
    super.key,
    required this.controller,
    this.active = true,
    this.color = const Color(0xFFFFFFFF),
    this.liveColor = const Color(0xFFE53935),
    this.tolerance = const Duration(seconds: 6),
    this.label = 'LIVE',
  });

  /// The live stream.
  final PlayStackPlayerController controller;

  /// Whether to follow the position. Pass `page.isActive`.
  final bool active;

  /// Text color.
  final Color color;

  /// Badge color at the live edge, red by default.
  final Color liveColor;

  /// How far behind still counts as live, 6 seconds by default (streams
  /// play a few segments behind the edge).
  final Duration tolerance;

  /// The text, "LIVE" by default.
  final String label;

  @override
  State<PlayStackLiveBadge> createState() => _PlayStackLiveBadgeState();
}

class _PlayStackLiveBadgeState extends State<PlayStackLiveBadge> {
  Stream<PlayStackPositionSnapshot>? _positions;

  @override
  Widget build(BuildContext context) {
    if (widget.active) {
      _positions ??= widget.controller.positions(
        interval: const Duration(seconds: 1),
      );
    } else {
      _positions = null;
    }
    return StreamBuilder<PlayStackPositionSnapshot>(
      stream: _positions,
      builder: (context, snapshot) {
        final behind = snapshot.data?.behindLive ?? Duration.zero;
        final atLive = behind <= widget.tolerance;
        return Semantics(
          button: !atLive,
          label: atLive ? widget.label : 'Go to live',
          child: GestureDetector(
            onTap: atLive
                ? null
                : () => unawaited(
                    widget.controller.seekToLiveEdge().catchError(
                      (Object _) {},
                    ),
                  ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: atLive ? widget.liveColor : const Color(0x99000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  atLive
                      ? widget.label
                      : '${widget.label}  -${PlayStackScrubPreview.format(behind)}',
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "+10 s" on the side being tapped.
class _SeekFeedback extends StatelessWidget {
  const _SeekFeedback({
    required this.forward,
    required this.amount,
    required this.color,
  });

  final bool forward;
  final Duration amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: forward ? const Alignment(0.7, 0) : const Alignment(-0.7, 0),
        child: Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            color: Color(0x40000000),
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                forward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: color,
                size: 32,
              ),
              Text(
                '${forward ? '+' : '-'}${amount.inSeconds} s',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The brightness or volume level while dragging.
class _LevelHud extends StatelessWidget {
  const _LevelHud({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.5),
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 28,
            color: color,
            shadows: const [Shadow(blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}

/// What [PlayStackDefaultControls] shows when a video failed: an icon, a
/// short message for the user and a retry button.
///
/// Use it in your own controls, or give `PlayStackFeedView.errorBuilder` a
/// screen of your own. [messageOf] replaces the texts, for example to
/// translate them:
///
/// ```dart
/// PlayStackErrorView(
///   error: error,
///   onRetry: page.controller.retry,
///   messageOf: (error) => switch (error.code) {
///     PlayStackErrorCode.network => 'İnternet bağlantını kontrol et.',
///     _ => 'Video oynatılamadı.',
///   },
///   retryLabel: 'Tekrar dene',
/// )
/// ```
class PlayStackErrorView extends StatelessWidget {
  /// Creates the error message of [error].
  const PlayStackErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.messageOf,
    this.retryLabel = 'Try again',
    this.color = const Color(0xFFFFFFFF),
    this.background = const Color(0xFF000000),
  });

  /// Why the video failed.
  final PlayStackException error;

  /// Called by the retry button, usually `controller.retry`.
  final VoidCallback? onRetry;

  /// The text for [error]; [defaultMessage] when null.
  final String Function(PlayStackException error)? messageOf;

  /// Text of the retry button.
  final String retryLabel;

  /// Color of the icon and texts.
  final Color color;

  /// Behind the message, black by default.
  final Color background;

  /// A short text for the user about [error], in English.
  static String defaultMessage(PlayStackException error) =>
      switch (error.code) {
        PlayStackErrorCode.network ||
        PlayStackErrorCode.timeout => 'Check your connection and try again.',
        PlayStackErrorCode.sourceNotFound ||
        PlayStackErrorCode.invalidSource => 'This video is not available.',
        PlayStackErrorCode.unsupportedFormat =>
          'This video cannot be played on this device.',
        PlayStackErrorCode.decoderUnavailable =>
          'Too many videos are playing. Try again.',
        PlayStackErrorCode.playbackNotAllowed => 'Tap to play.',
        _ => 'This video could not be played.',
      };

  /// An icon for [error].
  static IconData iconOf(PlayStackException error) => switch (error.code) {
    PlayStackErrorCode.network ||
    PlayStackErrorCode.timeout => Icons.wifi_off_rounded,
    PlayStackErrorCode.sourceNotFound ||
    PlayStackErrorCode.invalidSource => Icons.videocam_off_outlined,
    PlayStackErrorCode.playbackNotAllowed => Icons.play_arrow_rounded,
    _ => Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final message = (messageOf ?? defaultMessage)(error);
    return ColoredBox(
      color: background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iconOf(error), size: 44, color: color),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  inherit: false,
                  color: color,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRetry,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: color.withValues(alpha: 0.6)),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 18, color: color),
                            const SizedBox(width: 6),
                            Text(
                              retryLabel,
                              style: TextStyle(
                                inherit: false,
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades out the parts of the controls hidden in cinema mode and while the
/// screen is locked, and keeps touches off them meanwhile.
class _Chrome extends StatelessWidget {
  const _Chrome({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
    );
  }
}

/// What a locked screen shows (see [PlayStackFeedViewController.lockScreen]):
/// nothing until the user taps, then an unlock button for a few seconds.
///
/// It is the default `PlayStackFeedView.screenLockBuilder`. It takes every
/// touch, so the controls under it cannot be used until the screen is
/// unlocked.
class PlayStackScreenLockOverlay extends StatefulWidget {
  /// Creates the lock overlay of [page].
  const PlayStackScreenLockOverlay({
    super.key,
    required this.page,
    this.color = const Color(0xFFFFFFFF),
    this.visibleFor = const Duration(seconds: 3),
  });

  /// The page, whose `view` is unlocked by the button.
  final PlayStackFeedPage<Object?> page;

  /// Color of the button's icon and text, white by default.
  final Color color;

  /// How long the unlock button stays after a tap, 3 seconds by default.
  final Duration visibleFor;

  @override
  State<PlayStackScreenLockOverlay> createState() =>
      _PlayStackScreenLockOverlayState();
}

class _PlayStackScreenLockOverlayState
    extends State<PlayStackScreenLockOverlay> {
  bool _shown = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show() {
    _timer?.cancel();
    _timer = Timer(widget.visibleFor, () {
      if (mounted) setState(() => _shown = false);
    });
    if (!_shown) setState(() => _shown = true);
  }

  void _unlock() {
    _timer?.cancel();
    unawaited(widget.page.view.unlockScreen().catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _show,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: _Chrome(
                hidden: !_shown,
                child: Semantics(
                  button: true,
                  label: 'Unlock screen',
                  child: GestureDetector(
                    onTap: _unlock,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_open_rounded,
                              color: widget.color,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Unlock',
                              style: TextStyle(
                                inherit: false,
                                color: widget.color,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
