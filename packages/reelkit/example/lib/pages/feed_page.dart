import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import '../samples.dart';

/// A vertical feed driven by the app's own PageView.
///
/// Until the feed manager lands (milestone 5) the app coordinates the
/// controllers itself: the current item plays, the next one is prepared
/// with `preload` priority, and items further away give their native player
/// back. The pool never holds more than three native players. Exclusive
/// playback (the manager default) pauses the previous item when the current
/// one starts.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _itemCount = 50;

  final ReelKitManager _manager = ReelKitManager(
    config: const ReelKitConfig(
      pool: ReelPoolConfig(maxPlayers: 3),
      player: ReelPlayerConfig(looping: true),
    ),
  );
  final List<ReelPlayerController> _controllers = <ReelPlayerController>[];
  int _current = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    await _manager.initialize();
    for (var i = 0; i < _itemCount; i++) {
      _controllers.add(
        _manager.createController(
          ReelSource.network(sampleVideos[i % sampleVideos.length]),
        ),
      );
    }
    if (!mounted) return;
    setState(() {});
    _onPageChanged(0);
  }

  void _onPageChanged(int index) {
    _current = index;
    for (var i = 0; i < _controllers.length; i++) {
      final controller = _controllers[i];
      final distance = i - index;
      if (distance == 0) {
        unawaited(controller.play().catchError((Object _) {}));
      } else if (distance == 1) {
        controller.priority = ReelPlayerPriority.preload;
        unawaited(controller.initialize().catchError((Object _) {}));
      } else if (distance == -1) {
        controller.priority = ReelPlayerPriority.background;
      } else if (controller.value.isAttached) {
        unawaited(controller.release());
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    unawaited(_manager.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: _manager.isInitialized
            ? Text(
                'Item ${_current + 1} · pool '
                '${_manager.poolStats.allocated}/${_manager.poolStats.maxPlayers}',
              )
            : null,
      ),
      body: _controllers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: _controllers.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) =>
                  _FeedItem(controller: _controllers[index], index: index),
            ),
    );
  }
}

class _FeedItem extends StatelessWidget {
  const _FeedItem({required this.controller, required this.index});

  final ReelPlayerController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(
        controller.value.isPlaying ? controller.pause() : controller.play(),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ReelVideoView(
            controller: controller,
            fit: BoxFit.cover,
            placeholderBuilder: (_, _) => const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
            errorBuilder: (_, error) => Center(
              child: Text(
                error.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          // Overlay owned by the app.
          Positioned(
            left: 16,
            bottom: 32,
            child: ValueListenableBuilder<ReelPlaybackState>(
              valueListenable: controller,
              builder: (_, state, _) => Text(
                '#${index + 1} · ${state.status.name}'
                '${state.isBuffering ? ' · buffering' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
