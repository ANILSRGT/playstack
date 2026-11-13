import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import '../samples.dart';

/// Four controllers sharing one manager.
///
/// With exclusive playback (the default) starting a tile pauses the others.
/// Turning it off lets every tile play at once; tiles are muted so that the
/// grid stays usable. The pool holds at most four native players.
class GridPage extends StatefulWidget {
  const GridPage({super.key});

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  static const _tiles = 4;

  PlayStackManager? _manager;
  List<PlayStackPlayerController> _controllers = const [];
  bool _exclusive = true;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_rebuild());
    // Pool counters are plain values; refresh them for display.
    _statsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  Future<void> _rebuild() async {
    final previous = _manager;
    setState(() {
      _manager = null;
      _controllers = const [];
    });
    await previous?.dispose();
    final manager = PlayStackManager(
      config: PlayStackConfig(
        exclusivePlayback: _exclusive,
        pool: const PlayStackPoolConfig(maxPlayers: _tiles),
        player: const PlayStackPlayerConfig(looping: true, muted: true),
      ),
    );
    await manager.initialize();
    final controllers = [
      for (var i = 0; i < _tiles; i++)
        manager.createController(
          PlayStackSource.network(sampleVideos[i % sampleVideos.length]),
        ),
    ];
    if (!mounted) {
      await manager.dispose();
      return;
    }
    setState(() {
      _manager = manager;
      _controllers = controllers;
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    unawaited(_manager?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player grid'),
        actions: [
          const Center(child: Text('Exclusive')),
          Switch(
            value: _exclusive,
            onChanged: (value) {
              _exclusive = value;
              unawaited(_rebuild());
            },
          ),
        ],
      ),
      body: manager == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 16 / 9,
                    padding: const EdgeInsets.all(4),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    children: [
                      for (final (index, controller) in _controllers.indexed)
                        _Tile(controller: controller, index: index),
                    ],
                  ),
                ),
                _Footer(manager: manager, controllers: _controllers),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.controller, required this.index});

  final PlayStackPlayerController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('grid-tile-$index'),
      onTap: () => unawaited(
        (controller.value.isPlaying ? controller.pause() : controller.play())
            .catchError((Object _) {}),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayStackVideoView(controller: controller, fit: BoxFit.cover),
          Positioned(
            left: 6,
            bottom: 4,
            child: ValueListenableBuilder<PlayStackPlaybackState>(
              valueListenable: controller,
              builder: (_, state, _) => Text(
                '#${index + 1} ${state.status.name}',
                style: const TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 4)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.manager, required this.controllers});

  final PlayStackManager manager;
  final List<PlayStackPlayerController> controllers;

  @override
  Widget build(BuildContext context) {
    final stats = manager.poolStats;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ValueListenableBuilder<PlayStackPlayerController?>(
          valueListenable: manager.activeController,
          builder: (_, active, _) {
            final index = active == null ? null : controllers.indexOf(active);
            return Text(
              'Active: ${index == null ? 'none' : '#${index + 1}'}\n'
              'Pool ${stats.allocated}/${stats.maxPlayers} · leased '
              '${stats.leased} · created ${stats.created} · '
              'reused ${stats.reused} · revoked ${stats.revoked}',
              textAlign: TextAlign.center,
            );
          },
        ),
      ),
    );
  }
}
