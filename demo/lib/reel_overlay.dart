import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';

/// The demo's own layer on a feed page: caption, a like button and a heart
/// on double tap. Everything else (tap to pause, sound, fullscreen for
/// landscape videos, progress, buffering, retry) comes from ReelKit's
/// default controls underneath.
class ReelOverlay extends StatefulWidget {
  const ReelOverlay({
    super.key,
    required this.page,
    required this.liked,
    required this.onLike,
  });

  final ReelFeedPage<DemoVideo> page;
  final bool liked;
  final ValueChanged<bool> onLike;

  @override
  State<ReelOverlay> createState() => _ReelOverlayState();
}

class _ReelOverlayState extends State<ReelOverlay> {
  int _hearts = 0;

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_hearts > 0) _HeartBurst(key: ValueKey(_hearts)),
          if (!page.isFullscreen) ..._feedOverlay(page),
        ],
      ),
    );
  }

  List<Widget> _feedOverlay(ReelFeedPage<DemoVideo> page) {
    const shadow = [Shadow(blurRadius: 8)];
    final video = page.data;
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
        bottom: 120,
        child: _SideButton(
          icon: widget.liked ? Icons.favorite : Icons.favorite_border,
          color: widget.liked ? Colors.pinkAccent : null,
          label: widget.liked ? 'Liked' : 'Like',
          onTap: () => widget.onLike(!widget.liked),
        ),
      ),
      Positioned(
        left: 16,
        right: 88,
        bottom: 28,
        child: IgnorePointer(
          child: ValueListenableBuilder<ReelPlaybackState>(
            valueListenable: page.controller,
            builder: (context, state, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.author,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    shadows: shadow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  video.title,
                  style: const TextStyle(fontSize: 15, shadows: shadow),
                ),
                const SizedBox(height: 2),
                Text(
                  _describe(video, state),
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
      ),
    ];
  }

  String _describe(DemoVideo video, ReelPlaybackState state) {
    final info = state.videoInfo;
    final size = info == null || !info.hasSize
        ? ''
        : ' · ${info.displaySize.width.round()}x${info.displaySize.height.round()}';
    return '${video.note}$size';
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
