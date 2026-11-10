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
    'Asset, 2 audio + 2 subtitle tracks': const ReelSource.asset(
      multitrackAsset,
    ),
  };

  final ReelKitManager _manager = ReelKitManager();
  ReelPlayerController? _controller;
  String _sourceName = _sources.keys.first;
  BoxFit _fit = BoxFit.contain;
  ReelPositionSnapshot _position = const ReelPositionSnapshot(
    position: Duration.zero,
    buffered: Duration.zero,
  );
  StreamSubscription<ReelPositionSnapshot>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _manager.initialize();
    final source = _sources[_sourceName]!;
    final existing = _controller;
    if (existing != null) {
      // Same controller and native player, new video.
      await existing.setSource(source).catchError((Object _) {});
      return;
    }
    final controller = _manager.createController(source);
    // The stream polls only while playing (and once after seeks and state
    // changes), so a paused player causes no channel traffic.
    _positionSubscription = controller.positions().listen(
      (position) => setState(() => _position = position),
    );
    setState(() => _controller = controller);
    await controller.initialize().catchError((Object _) {});
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
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
          if (controller != null) _TracksMenu(controller: controller),
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
                        // Subtitles are plain text; styling is the app's.
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 12,
                          child: ValueListenableBuilder<List<String>>(
                            valueListenable: controller.subtitles,
                            builder: (_, lines, _) => lines.isEmpty
                                ? const SizedBox.shrink()
                                : Text(
                                    lines.join('\n'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      backgroundColor: Colors.black54,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Controls(
                    controller: controller,
                    state: state,
                    position: _position,
                    onFullscreen: () => unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _FullscreenPage(
                            manager: _manager,
                            controller: controller,
                          ),
                        ),
                      ),
                    ),
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

class _TracksMenu extends StatelessWidget {
  const _TracksMenu({required this.controller});

  final ReelPlayerController controller;

  static String _label(ReelTrack track) {
    final parts = [
      ?track.label,
      ?track.language,
      if (track.height != null) '${track.height}p',
    ];
    return parts.isEmpty ? track.id : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ReelTrack>>(
      valueListenable: controller.tracks,
      builder: (context, tracks, _) => PopupMenuButton<VoidCallback>(
        tooltip: 'Tracks',
        enabled: tracks.isNotEmpty,
        icon: const Icon(Icons.subtitles_outlined),
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          for (final type in ReelTrackType.values) ...[
            if (tracks.any((t) => t.type == type))
              PopupMenuItem<VoidCallback>(
                enabled: false,
                child: Text(type.name.toUpperCase()),
              ),
            for (final track in tracks.where((t) => t.type == type))
              CheckedPopupMenuItem<VoidCallback>(
                checked: track.isSelected,
                value: () => unawaited(
                  controller.selectTrack(track).catchError((Object _) {}),
                ),
                child: Text(_label(track)),
              ),
          ],
          PopupMenuItem<VoidCallback>(
            value: () => unawaited(controller.disableSubtitles()),
            child: const Text('Subtitles off'),
          ),
        ],
      ),
    );
  }
}

/// The app's own fullscreen screen. ReelKit only hides the system UI, locks
/// the orientation to the video's and restores the app policy afterwards.
class _FullscreenPage extends StatefulWidget {
  const _FullscreenPage({required this.manager, required this.controller});

  final ReelKitManager manager;
  final ReelPlayerController controller;

  @override
  State<_FullscreenPage> createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<_FullscreenPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      widget.manager.fullscreen
          .enter(
            orientation: ReelFullscreenOrientation.matchVideo,
            controller: widget.controller,
          )
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    // Also covers the system back gesture.
    unawaited(widget.manager.fullscreen.exit());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: ReelVideoView(controller: widget.controller),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.state,
    required this.position,
    required this.onFullscreen,
  });

  final VoidCallback onFullscreen;
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
              IconButton(
                tooltip: 'Fullscreen',
                icon: const Icon(Icons.fullscreen),
                onPressed: state.isInitialized ? onFullscreen : null,
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
