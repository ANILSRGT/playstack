import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../controller/reel_playback_state.dart';
import '../controller/reel_player_controller.dart';
import '../feed/reel_feed_manager.dart';
import 'reel_feed_view.dart';

/// The controls `ReelFeedView` shows when the app supplies none: tap to
/// pause and play, a sound switch for the whole feed, a fullscreen button
/// for landscape videos, a thin progress bar, a buffering indicator that
/// appears only when a wait gets long, and a retry button on errors.
///
/// Keep the defaults and add your own layer with [child] (captions, like
/// buttons), turn parts off, or replace the whole thing with your own
/// `controlsBuilder`. The parts are public widgets too:
/// [ReelProgressBar], [ReelBufferingIndicator], [ReelMuteButton].
class ReelDefaultControls extends StatefulWidget {
  /// Creates the default controls of [page].
  const ReelDefaultControls({
    super.key,
    required this.page,
    this.child,
    this.tapToPause = true,
    this.onDoubleTap,
    this.showMuteButton = true,
    this.showFullscreenButton = true,
    this.showProgress = true,
    this.showBufferingIndicator = true,
    this.bufferingIndicatorDelay = const Duration(seconds: 2),
    this.color = const Color(0xFFFFFFFF),
  });

  /// The default `ReelFeedView.controlsBuilder`.
  static Widget builder(BuildContext context, ReelFeedPage<Object?> page) =>
      ReelDefaultControls(page: page);

  /// The page these controls belong to.
  final ReelFeedPage<Object?> page;

  /// The app's own layer, drawn above the video and below the controls'
  /// buttons. Taps it does not handle reach [tapToPause].
  final Widget? child;

  /// Whether a tap pauses and resumes the video.
  final bool tapToPause;

  /// Called on a double tap, for example to like the post. Registering it
  /// delays single taps slightly, as Flutter waits to rule out a double tap.
  final VoidCallback? onDoubleTap;

  /// Whether a sound switch is shown. It mutes the whole feed.
  final bool showMuteButton;

  /// Whether landscape videos get a fullscreen button. In fullscreen it
  /// leaves fullscreen.
  final bool showFullscreenButton;

  /// Whether a progress bar runs along the bottom edge.
  final bool showProgress;

  /// Whether [ReelBufferingIndicator] is shown during long waits.
  final bool showBufferingIndicator;

  /// How long a wait lasts before the buffering indicator appears. Until
  /// then the last frame or the poster stays, which reads as a brief freeze.
  final Duration bufferingIndicatorDelay;

  /// Color of icons and the progress bar.
  final Color color;

  @override
  State<ReelDefaultControls> createState() => _ReelDefaultControlsState();
}

class _ReelDefaultControlsState extends State<ReelDefaultControls> {
  bool _pausedByUser = false;

  ReelPlayerController get _controller => widget.page.controller;

  @override
  void didUpdateWidget(ReelDefaultControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.page.isActive) _pausedByUser = false;
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

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return ValueListenableBuilder<ReelPlaybackState>(
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
              child: widget.child ?? const SizedBox.expand(),
            ),
            if (widget.showBufferingIndicator)
              ReelBufferingIndicator(
                controller: _controller,
                active: page.isActive,
                hasPoster: page.item.poster != null,
                delay: widget.bufferingIndicatorDelay,
                color: widget.color,
              ),
            if (_pausedByUser && state.status == ReelPlaybackStatus.paused)
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
                      ReelMuteButton(
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
                child: ReelProgressBar(
                  controller: _controller,
                  active: page.isActive,
                  color: widget.color,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A thin bar showing the playback position of [controller]. It reads the
/// position only while [active] and playing.
class ReelProgressBar extends StatefulWidget {
  /// Creates a progress bar for [controller].
  const ReelProgressBar({
    super.key,
    required this.controller,
    this.active = true,
    this.height = 2,
    this.color = const Color(0xFFFFFFFF),
    this.backgroundColor = const Color(0x3DFFFFFF),
    this.interval = const Duration(milliseconds: 200),
  });

  /// The controller whose position is shown.
  final ReelPlayerController controller;

  /// Whether the position is read. Pass false for pages out of view.
  final bool active;

  /// Height of the bar.
  final double height;

  /// Color of the elapsed part.
  final Color color;

  /// Color of the remaining part.
  final Color backgroundColor;

  /// How often the position is read.
  final Duration interval;

  @override
  State<ReelProgressBar> createState() => _ReelProgressBarState();
}

class _ReelProgressBarState extends State<ReelProgressBar> {
  Stream<ReelPositionSnapshot>? _positions;

  @override
  Widget build(BuildContext context) {
    if (widget.active) {
      _positions ??= widget.controller.positions(interval: widget.interval);
    } else {
      _positions = null;
    }
    final empty = SizedBox(height: widget.height);
    final positions = _positions;
    if (positions == null) return empty;
    return ValueListenableBuilder<ReelPlaybackState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final duration = state.duration;
        if (duration == null || duration <= Duration.zero) return empty;
        return StreamBuilder<ReelPositionSnapshot>(
          stream: positions,
          builder: (context, snapshot) {
            final position = snapshot.data?.position ?? Duration.zero;
            final value = position.inMilliseconds / duration.inMilliseconds;
            return IgnorePointer(
              child: SizedBox(
                height: widget.height,
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  minHeight: widget.height,
                  color: widget.color,
                  backgroundColor: widget.backgroundColor,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A spinner for [controller] that appears only when a wait gets long.
///
/// While [active] and the video prepares or buffers, nothing is drawn for
/// [delay]: the last frame or the poster stays, which reads as a brief
/// freeze. When the screen is still black (no frame rendered and no
/// poster), [blackScreenDelay] applies instead. Then the spinner fades in.
class ReelBufferingIndicator extends StatelessWidget {
  /// Creates a buffering indicator for [controller].
  const ReelBufferingIndicator({
    super.key,
    required this.controller,
    this.active = true,
    this.hasPoster = false,
    this.delay = const Duration(seconds: 2),
    this.blackScreenDelay = const Duration(milliseconds: 800),
    this.color = const Color(0xFFFFFFFF),
    this.size = 36,
  });

  /// The controller whose waits are shown.
  final ReelPlayerController controller;

  /// Whether the controller is the one the user is watching. Preloading
  /// items in the background never show a spinner.
  final bool active;

  /// Whether a poster covers the page until the first frame.
  final bool hasPoster;

  /// Wait before the spinner appears over a frame or poster.
  final Duration delay;

  /// Wait before the spinner appears over a black screen.
  final Duration blackScreenDelay;

  /// Color of the spinner.
  final Color color;

  /// Diameter of the spinner.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReelPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final waiting =
            active &&
            !state.hasError &&
            (state.isBuffering ||
                state.status == ReelPlaybackStatus.initializing ||
                state.status == ReelPlaybackStatus.idle);
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

/// A sound switch. With [feed], it mutes and unmutes every item of the
/// feed (`ReelFeedManager.setMuted`); otherwise only [controller].
class ReelMuteButton extends StatelessWidget {
  /// Creates a sound switch showing the state of [controller].
  const ReelMuteButton({
    super.key,
    required this.controller,
    this.feed,
    this.color = const Color(0xFFFFFFFF),
    this.size = 26,
  });

  /// The controller whose mute state is shown.
  final ReelPlayerController controller;

  /// The feed to mute as a whole.
  final ReelFeedManager? feed;

  /// Color of the icon.
  final Color color;

  /// Size of the icon.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReelPlaybackState>(
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

  final ReelKitException error;
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
