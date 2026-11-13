import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../feed/playstack_feed_manager.dart';
import 'playstack_feed_view.dart';

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

/// The controls a [PlayStackFeedView] shows when you pass no `controlsBuilder`.
///
/// They provide:
///
/// * tap anywhere to pause, tap again to play (a play icon shows while
///   paused);
/// * a sound switch at the bottom right that mutes the whole feed;
/// * a fullscreen button next to it on landscape videos (an exit button in
///   fullscreen);
/// * hold to pause (or to play faster, see [holdAction]);
/// * a thin progress bar along the bottom edge; drag along it to move in
///   the video;
/// * a spinner that appears only when loading takes long (see
///   [bufferingIndicatorDelay]);
/// * a retry button when a video fails.
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
    this.seekable = true,
    this.showBufferingIndicator = true,
    this.bufferingIndicatorDelay = const Duration(seconds: 2),
    this.color = const Color(0xFFFFFFFF),
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

  /// Color of the icons, the spinner and the progress bar. White by default.
  final Color color;

  @override
  State<PlayStackDefaultControls> createState() =>
      _PlayStackDefaultControlsState();
}

class _PlayStackDefaultControlsState extends State<PlayStackDefaultControls> {
  bool _pausedByUser = false;

  /// The action of the finger held down right now, if any.
  PlayStackHoldAction? _holding;
  double _speedBeforeHold = 1;

  PlayStackPlayerController get _controller => widget.page.controller;

  @override
  void didUpdateWidget(PlayStackDefaultControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.page.isActive) {
      _pausedByUser = false;
      _endHold();
    }
  }

  @override
  void dispose() {
    _endHold();
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
          return _ErrorRetry(
            error: error,
            color: widget.color,
            onRetry: () => unawaited(_controller.retry().catchError(_ignore)),
          );
        }
        final shadow = [const Shadow(blurRadius: 8)];
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.tapToPause ? _togglePlay : null,
              onDoubleTap: widget.onDoubleTap,
              onLongPressStart: widget.holdAction == PlayStackHoldAction.none
                  ? null
                  : (_) => _startHold(),
              onLongPressEnd: widget.holdAction == PlayStackHoldAction.none
                  ? null
                  : (_) => _endHold(),
              onLongPressCancel: widget.holdAction == PlayStackHoldAction.none
                  ? null
                  : _endHold,
              child: const SizedBox.expand(),
            ),
            // Above the gesture layer, not inside it: its buttons get their
            // taps at once instead of waiting for a possible double tap.
            ?widget.child,
            if (_holding == PlayStackHoldAction.speedUp)
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
              ),
            if (_pausedByUser && state.status == PlayStackPlaybackStatus.paused)
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
              child: SafeArea(
                top: false,
                left: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
            if (widget.showProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PlayStackProgressBar(
                  controller: _controller,
                  active: page.isActive,
                  color: widget.color,
                  seekable: widget.seekable,
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
    this.touchHeight = 24,
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

  /// Height of the area that reacts to the finger when [seekable], 24 by
  /// default. The bar stays [height] thick at the bottom of it; the area
  /// makes it easy to hit.
  final double touchHeight;

  @override
  State<PlayStackProgressBar> createState() => _PlayStackProgressBarState();
}

class _PlayStackProgressBarState extends State<PlayStackProgressBar> {
  Stream<PlayStackPositionSnapshot>? _positions;

  /// The point being dragged to, from 0 to 1; null when not dragging.
  double? _dragValue;

  /// The point last seeked to, shown until the position catches up.
  double? _seekValue;

  static void _ignore(Object _) {}

  double _valueAt(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

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
        final bar = StreamBuilder<PlayStackPositionSnapshot>(
          stream: positions,
          builder: (context, snapshot) {
            final position = snapshot.data?.position ?? Duration.zero;
            final value =
                _dragValue ??
                _seekValue ??
                position.inMilliseconds / duration.inMilliseconds;
            final height = _dragValue != null
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
                onHorizontalDragStart: (details) => setState(
                  () => _dragValue = _valueAt(details.localPosition.dx, width),
                ),
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
                  child: Align(alignment: Alignment.bottomCenter, child: bar),
                ),
              ),
            );
          },
        );
      },
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
              child: SizedBox.square(
                dimension: size,
                child: CircularProgressIndicator(strokeWidth: 3, color: color),
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

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({
    required this.error,
    required this.color,
    required this.onRetry,
  });

  final PlayStackException error;
  final Color color;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, size: 48, color: color),
                const SizedBox(height: 8),
                Text(
                  error.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
