import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import '../samples.dart';

/// A single video with controls built entirely by the app.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static final _sources = <String, ReelSource>{
    'Network MP4': ReelSource.network(sampleVideos.first),
    'Asset': const ReelSource.asset(landscapeAsset),
    'Asset, rotated 90°': const ReelSource.asset(rotatedAsset),
  };

  final ReelKitManager _manager = ReelKitManager();
  ReelPlayerController? _controller;
  String _sourceName = _sources.keys.first;
  BoxFit _fit = BoxFit.contain;
  ReelPositionSnapshot _position = const ReelPositionSnapshot(
    position: Duration.zero,
    buffered: Duration.zero,
  );
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _manager.initialize();
    final previous = _controller;
    final controller = _manager.createController(_sources[_sourceName]!)
      ..addListener(_onState);
    setState(() => _controller = controller);
    await previous?.dispose();
    await controller.initialize().catchError((Object _) {});
  }

  /// Position is pulled by the app, and only while playing.
  void _onState() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing && _positionTimer == null) {
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => unawaited(_readPosition()),
      );
    } else if (!playing) {
      _positionTimer?.cancel();
      _positionTimer = null;
      unawaited(_readPosition());
    }
  }

  Future<void> _readPosition() async {
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    final position = await controller.getPosition();
    if (mounted) setState(() => _position = position);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    unawaited(_manager.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Single player'),
        actions: [
          PopupMenuButton<String>(
            initialValue: _sourceName,
            onSelected: (name) {
              _sourceName = name;
              unawaited(_load());
            },
            itemBuilder: (_) => [
              for (final name in _sources.keys)
                PopupMenuItem(value: name, child: Text(name)),
            ],
          ),
        ],
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<ReelPlaybackState>(
              valueListenable: controller,
              builder: (context, state, _) => Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ReelVideoView(
                          controller: controller,
                          fit: _fit,
                          placeholderBuilder: (_, _) =>
                              const Center(child: CircularProgressIndicator()),
                          errorBuilder: (_, error) => Center(
                            child: Text(
                              '${error.code.name}\n${error.message}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        if (state.isBuffering && state.isPlaying)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    ),
                  ),
                  _Controls(
                    controller: controller,
                    state: state,
                    position: _position,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<BoxFit>(
                      segments: const [
                        ButtonSegment(
                          value: BoxFit.contain,
                          label: Text('contain'),
                        ),
                        ButtonSegment(
                          value: BoxFit.cover,
                          label: Text('cover'),
                        ),
                        ButtonSegment(value: BoxFit.fill, label: Text('fill')),
                      ],
                      selected: {_fit},
                      onSelectionChanged: (s) => setState(() => _fit = s.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${state.status.name} · '
                    '${state.videoInfo?.width ?? 0}x${state.videoInfo?.height ?? 0} · '
                    'rotation ${state.videoInfo?.rotationDegrees ?? 0}°',
                  ),
                ],
              ),
            ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.state,
    required this.position,
  });

  final ReelPlayerController controller;
  final ReelPlaybackState state;
  final ReelPositionSnapshot position;

  static String _format(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final duration = state.duration ?? Duration.zero;
    final max = duration.inMilliseconds.toDouble();
    final value = position.position.inMilliseconds.clamp(0, max).toDouble();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Slider(
            max: max <= 0 ? 1 : max,
            value: max <= 0 ? 0 : value,
            secondaryTrackValue: max <= 0
                ? null
                : position.buffered.inMilliseconds.clamp(0, max).toDouble(),
            onChanged: state.isInitialized
                ? (v) => unawaited(
                    controller.seekTo(Duration(milliseconds: v.round())),
                  )
                : null,
          ),
          Text('${_format(position.position)} / ${_format(duration)}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10),
                onPressed: state.isInitialized
                    ? () => unawaited(controller.rewind())
                    : null,
              ),
              IconButton.filled(
                iconSize: 36,
                icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () => unawaited(
                  state.isPlaying ? controller.pause() : controller.play(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10),
                onPressed: state.isInitialized
                    ? () => unawaited(controller.fastForward())
                    : null,
              ),
              IconButton(
                icon: Icon(state.isMuted ? Icons.volume_off : Icons.volume_up),
                onPressed: () => unawaited(controller.setMuted(!state.isMuted)),
              ),
              IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: state.isLooping
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: () =>
                    unawaited(controller.setLooping(!state.isLooping)),
              ),
              PopupMenuButton<double>(
                tooltip: 'Speed',
                initialValue: state.playbackSpeed,
                onSelected: (s) => unawaited(controller.setPlaybackSpeed(s)),
                itemBuilder: (_) => [
                  for (final s in const [0.5, 1.0, 1.5, 2.0])
                    PopupMenuItem(value: s, child: Text('${s}x')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${state.playbackSpeed}x'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
