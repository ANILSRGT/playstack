import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';

/// One page of the feed: the video plus the app's own overlay.
class ReelTile extends StatefulWidget {
  const ReelTile({
    super.key,
    required this.controller,
    required this.video,
    required this.isActive,
    required this.muted,
    required this.fill,
    required this.fullscreen,
    required this.liked,
    required this.onLike,
    required this.onToggleMute,
    required this.onToggleFill,
    required this.onToggleFullscreen,
  });

  final ReelPlayerController controller;
  final DemoVideo video;
  final bool isActive;
  final bool muted;
  final bool fill;
  final bool fullscreen;
  final bool liked;
  final ValueChanged<bool> onLike;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFill;
  final VoidCallback onToggleFullscreen;

  @override
  State<ReelTile> createState() => _ReelTileState();
}

class _ReelTileState extends State<ReelTile> {
  Stream<ReelPositionSnapshot>? _positions;
  int _hearts = 0;
  bool _showPauseIcon = false;

  ReelPlayerController get _controller => widget.controller;

  void _togglePlay() {
    final state = _controller.value;
    if (state.hasError) return;
    if (state.isPlaying) {
      unawaited(_controller.pause());
      setState(() => _showPauseIcon = true);
    } else {
      unawaited(_controller.play().catchError(_ignore));
      setState(() => _showPauseIcon = false);
    }
  }

  void _doubleTap() {
    setState(() => _hearts++);
    if (!widget.liked) widget.onLike(true);
  }

  static void _ignore(Object _) {}

  @override
  void didUpdateWidget(ReelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive) _showPauseIcon = false;
  }

  @override
  Widget build(BuildContext context) {
    // A fresh position stream each time the tile becomes active; it polls
    // only while listened to and playing.
    if (widget.isActive) {
      _positions ??= _controller.positions(
        interval: const Duration(milliseconds: 200),
      );
    } else {
      _positions = null;
    }

    return ValueListenableBuilder<ReelPlaybackState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        // Known from the catalog before the video is prepared, so the
        // poster is laid out like the video.
        final aspect = state.aspectRatio;
        final landscape = aspect == null
            ? !widget.video.isVertical
            : aspect > 1;
        final fit = !landscape || (widget.fill && !widget.fullscreen)
            ? BoxFit.cover
            : BoxFit.contain;
        final loading =
            widget.isActive &&
            !state.hasError &&
            (state.isBuffering ||
                state.status == ReelPlaybackStatus.initializing ||
                state.status == ReelPlaybackStatus.idle);

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlay,
              onDoubleTap: _doubleTap,
              child: ReelVideoView(
                controller: _controller,
                fit: fit,
                poster: switch (widget.video.poster) {
                  final url? => NetworkImage(url),
                  null => null,
                },
                errorBuilder: (context, error) => _ErrorPanel(
                  error: error,
                  onRetry: () => unawaited(_controller.retry()),
                ),
              ),
            ),
            if (loading)
              // Nothing to look at yet: say so soon. A video already on
              // screen that waits briefly (a rendition switch, a slow
              // segment) keeps its frame without a spinner.
              _DelayedSpinner(
                delay: state.hasRenderedFirstFrame
                    ? const Duration(milliseconds: 1200)
                    : const Duration(milliseconds: 400),
              ),
            if (_showPauseIcon && state.status == ReelPlaybackStatus.paused)
              const IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 96,
                    color: Colors.white70,
                  ),
                ),
              ),
            if (_hearts > 0) _HeartBurst(key: ValueKey(_hearts)),
            if (widget.fullscreen)
              ..._fullscreenOverlay(state)
            else
              ..._feedOverlay(state, landscape),
          ],
        );
      },
    );
  }

  List<Widget> _feedOverlay(ReelPlaybackState state, bool landscape) {
    const shadow = [Shadow(blurRadius: 8)];
    return [
      // Darken the bottom so the caption stays readable.
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 96,
        child: Column(
          children: [
            _SideButton(
              icon: widget.liked ? Icons.favorite : Icons.favorite_border,
              color: widget.liked ? Colors.pinkAccent : null,
              label: widget.liked ? 'Liked' : 'Like',
              onTap: () => widget.onLike(!widget.liked),
            ),
            _SideButton(
              icon: widget.muted ? Icons.volume_off : Icons.volume_up,
              label: widget.muted ? 'Muted' : 'Sound',
              onTap: widget.onToggleMute,
            ),
            if (landscape) ...[
              _SideButton(
                icon: widget.fill ? Icons.fit_screen : Icons.zoom_out_map,
                label: widget.fill ? 'Fit' : 'Fill',
                onTap: widget.onToggleFill,
              ),
              _SideButton(
                icon: Icons.fullscreen,
                label: 'Full',
                onTap: state.isInitialized ? widget.onToggleFullscreen : null,
              ),
            ],
          ],
        ),
      ),
      Positioned(
        left: 16,
        right: 88,
        bottom: 28,
        child: IgnorePointer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.video.author,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  shadows: shadow,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.video.title,
                style: const TextStyle(fontSize: 15, shadows: shadow),
              ),
              const SizedBox(height: 2),
              Text(
                _describe(state),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  shadows: shadow,
                ),
              ),
            ],
          ),
        ),
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: _progress(state)),
    ];
  }

  List<Widget> _fullscreenOverlay(ReelPlaybackState state) {
    return [
      SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: IconButton.filledTonal(
            tooltip: 'Exit fullscreen',
            icon: const Icon(Icons.fullscreen_exit),
            onPressed: widget.onToggleFullscreen,
          ),
        ),
      ),
      Positioned(left: 0, right: 0, bottom: 0, child: _progress(state)),
    ];
  }

  String _describe(ReelPlaybackState state) {
    final info = state.videoInfo;
    final size = info == null || !info.hasSize
        ? ''
        : ' · ${info.displaySize.width.round()}x${info.displaySize.height.round()}';
    return '${widget.video.note}$size';
  }

  Widget _progress(ReelPlaybackState state) {
    final positions = _positions;
    final duration = state.duration;
    if (positions == null || duration == null || duration == Duration.zero) {
      return const SizedBox(height: 2);
    }
    return StreamBuilder<ReelPositionSnapshot>(
      stream: positions,
      builder: (context, snapshot) {
        final position = snapshot.data?.position ?? Duration.zero;
        final value = position.inMilliseconds / duration.inMilliseconds;
        return LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: 2,
          backgroundColor: Colors.white24,
          color: Colors.white,
        );
      },
    );
  }
}

/// A spinner that appears only when loading takes noticeably long, so
/// quick starts do not flash it.
class _DelayedSpinner extends StatefulWidget {
  const _DelayedSpinner({required this.delay});

  final Duration delay;

  @override
  State<_DelayedSpinner> createState() => _DelayedSpinnerState();
}

class _DelayedSpinnerState extends State<_DelayedSpinner> {
  late final Timer _timer;
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
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const IgnorePointer(
      child: Center(
        child: SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          children: [
            Icon(
              icon,
              size: 34,
              color: color,
              shadows: const [Shadow(blurRadius: 8)],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                shadows: [Shadow(blurRadius: 6)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final ReelKitException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                error.code.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(error.message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A heart that pops and fades once.
class _HeartBurst extends StatefulWidget {
  const _HeartBurst({super.key});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_animation.forward());
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final t = _animation.value;
            final scale = Curves.elasticOut.transform((t * 1.6).clamp(0, 1));
            return Opacity(
              opacity: t < 0.7 ? 1 : (1 - t) / 0.3,
              child: Transform.scale(
                scale: 0.4 + scale * 0.8,
                child: const Icon(
                  Icons.favorite,
                  size: 120,
                  color: Colors.pinkAccent,
                  shadows: [Shadow(blurRadius: 16)],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
