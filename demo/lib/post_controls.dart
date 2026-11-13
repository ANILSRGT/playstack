import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'author_page.dart';
import 'catalog.dart';
import 'comments_sheet.dart';
import 'demo_state.dart';
import 'loading_animation.dart';

/// The controls of one reel: PlayStack's default controls (tap and hold to
/// pause, sound, fullscreen, progress, retry) plus the app's own layer:
/// caption, author, like and comments, and a heart on double tap.
class PostControls extends StatefulWidget {
  const PostControls({super.key, required this.page});

  final PlayStackFeedPage<DemoVideo> page;

  @override
  State<PostControls> createState() => _PostControlsState();
}

class _PostControlsState extends State<PostControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    demoState.like(widget.page.data);
    unawaited(_heart.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    return PlayStackDefaultControls(
      page: page,
      onDoubleTap: _onDoubleTap,
      bufferingIndicator: const LoadingAnimation(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!page.isFullscreen) ...[
            Positioned(
              left: 16,
              right: 88,
              bottom: 32,
              child: _Caption(video: page.data),
            ),
            Positioned(right: 4, bottom: 72, child: _Actions(page: page)),
          ],
          IgnorePointer(child: _Heart(animation: _heart)),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.video});

  final DemoVideo video;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 6)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          // A pushed page covers the feed; PlayStackFeedView pauses until it is
          // popped.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AuthorPage(author: video.author),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white24,
                child: Text(
                  video.author.substring(1, 2).toUpperCase(),
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                video.author,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  shadows: shadow,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          video.title,
          style: const TextStyle(fontSize: 15, shadows: shadow),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.hd_outlined, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                video.note,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  shadows: shadow,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.page});

  final PlayStackFeedPage<DemoVideo> page;

  Future<void> _openComments(BuildContext context) async {
    // A bottom sheet leaves the feed visible, so the video would keep
    // playing under it. This demo pauses it while comments are open.
    page.view.pause();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CommentsSheet(video: page.data),
    );
    page.view.resume();
  }

  @override
  Widget build(BuildContext context) {
    final video = page.data;
    return ListenableBuilder(
      listenable: demoState,
      builder: (context, _) {
        final liked = demoState.isLiked(video);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActionButton(
              icon: liked ? Icons.favorite_rounded : Icons.favorite_border,
              color: liked ? Colors.pinkAccent : Colors.white,
              label: _count(video.likes + (liked ? 1 : 0)),
              tooltip: liked ? 'Unlike' : 'Like',
              onTap: () => demoState.toggleLike(video),
            ),
            _ActionButton(
              icon: Icons.mode_comment_outlined,
              label: _count(video.comments.length),
              tooltip: 'Comments',
              onTap: () => unawaited(_openComments(context)),
            ),
          ],
        );
      },
    );
  }

  static String _count(int value) =>
      value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}K' : '$value';
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 8)];
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color, shadows: shadow),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 12, shadows: shadow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A heart that pops in the middle of the video and fades out.
class _Heart extends StatelessWidget {
  const _Heart({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();
        final scale = Curves.elasticOut.transform((t * 2).clamp(0.0, 1.0));
        final opacity = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
        return Center(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: 0.4 + 0.8 * scale,
              child: const Icon(
                Icons.favorite_rounded,
                size: 110,
                color: Colors.pinkAccent,
                shadows: [Shadow(blurRadius: 24)],
              ),
            ),
          ),
        );
      },
    );
  }
}
