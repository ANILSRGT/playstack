import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';

/// The demo's own layer on a feed page: caption, like and sound buttons, a
/// heart on double tap and the fullscreen switch. It sits on ReelKit's
/// default controls, which keep tap to pause, the progress bar, the
/// delayed buffering indicator and retry.
class ReelOverlay extends StatefulWidget {
  const ReelOverlay({
    super.key,
    required this.page,
    required this.fill,
    required this.fullscreen,
    required this.liked,
    required this.onLike,
    required this.onToggleFill,
    required this.onToggleFullscreen,
  });

  final ReelFeedPage page;
  final bool fill;
  final bool fullscreen;
  final bool liked;
  final ValueChanged<bool> onLike;
  final VoidCallback onToggleFill;
  final VoidCallback onToggleFullscreen;

  @override
  State<ReelOverlay> createState() => _ReelOverlayState();
}

class _ReelOverlayState extends State<ReelOverlay> {
  int _hearts = 0;

  DemoVideo get _video => widget.page.data! as DemoVideo;

  void _doubleTap() {
    setState(() => _hearts++);
    if (!widget.liked) widget.onLike(true);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return ReelDefaultControls(
      page: page,
      onDoubleTap: _doubleTap,
      showMuteButton: false,
      child: ValueListenableBuilder<ReelPlaybackState>(
        valueListenable: page.controller,
        builder: (context, state, _) => Stack(
          fit: StackFit.expand,
          children: [
            if (_hearts > 0) _HeartBurst(key: ValueKey(_hearts)),
            if (widget.fullscreen)
              _exitFullscreen()
            else
              ..._feedOverlay(state),
          ],
        ),
      ),
    );
  }

  Widget _exitFullscreen() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: IconButton.filledTonal(
          tooltip: 'Exit fullscreen',
          icon: const Icon(Icons.fullscreen_exit),
          onPressed: widget.onToggleFullscreen,
        ),
      ),
    );
  }

  List<Widget> _feedOverlay(ReelPlaybackState state) {
    const shadow = [Shadow(blurRadius: 8)];
    final landscape = isLandscape(state, _video);
    final muted = state.isMuted;
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
              icon: muted ? Icons.volume_off : Icons.volume_up,
              label: muted ? 'Muted' : 'Sound',
              onTap: () => widget.page.feed.setMuted(!muted),
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
                _video.author,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  shadows: shadow,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _video.title,
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
    ];
  }

  String _describe(ReelPlaybackState state) {
    final info = state.videoInfo;
    final size = info == null || !info.hasSize
        ? ''
        : ' · ${info.displaySize.width.round()}x${info.displaySize.height.round()}';
    return '${_video.note}$size';
  }
}

/// Whether [video] is wider than tall, from the catalog until the player
/// knows.
bool isLandscape(ReelPlaybackState state, DemoVideo video) {
  final aspect = state.aspectRatio;
  return aspect == null ? !video.isVertical : aspect > 1;
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
