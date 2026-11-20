import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';
import '../manager/playstack_manager.dart';

/// A small panel with what a video is doing: state, size, bitrate, codec,
/// position and buffer, timings and the player pool. For finding out why
/// a video stalls or starts slowly while developing.
///
/// ```dart
/// Stack(children: [
///   PlayStackVideoView(controller: controller),
///   if (kDebugMode) PlayStackDebugOverlay(controller: controller, manager: manager),
/// ])
/// ```
///
/// `PlayStackDefaultControls(showDebugInfo: true)` shows it in a feed.
class PlayStackDebugOverlay extends StatefulWidget {
  /// Creates a panel for [controller]; [manager] adds the pool.
  const PlayStackDebugOverlay({
    super.key,
    required this.controller,
    this.manager,
    this.alignment = Alignment.topLeft,
  });

  /// The video.
  final PlayStackPlayerController controller;

  /// Its manager, for pool and network figures.
  final PlayStackManager? manager;

  /// Where the panel sits, top left by default.
  final AlignmentGeometry alignment;

  @override
  State<PlayStackDebugOverlay> createState() => _PlayStackDebugOverlayState();
}

class _PlayStackDebugOverlayState extends State<PlayStackDebugOverlay> {
  Timer? _timer;
  PlayStackPositionSnapshot? _position;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_read()),
    );
    unawaited(_read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    if (widget.controller.isDisposed) return;
    try {
      final position = await widget.controller.getPosition();
      if (mounted) setState(() => _position = position);
    } on Object {
      // Between players.
    }
  }

  static String _ms(Duration? value) =>
      value == null ? '-' : '${value.inMilliseconds} ms';

  static String _time(Duration? value) {
    if (value == null) return '-';
    final seconds = value.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)} s';
  }

  static String _bitrate(int? bits) {
    if (bits == null) return '-';
    if (bits >= 1000000) return '${(bits / 1000000).toStringAsFixed(2)} Mbps';
    return '${(bits / 1000).round()} kbps';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ValueListenableBuilder<PlayStackPlaybackState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final info = state.videoInfo;
        final position = _position;
        final metrics = controller.metrics;
        final selected = controller.tracks.value
            .where((t) => t.type == PlayStackTrackType.video && t.isSelected)
            .firstOrNull;
        final manager = widget.manager;
        final pool = manager != null && manager.isInitialized
            ? manager.poolStats
            : null;
        final lines = <String>[
          if (controller.contentId case final id?) 'id        $id',
          'status    ${state.status.name}'
              '${state.isBuffering ? ' (buffering)' : ''}',
          'source    ${controller.source.description}',
          if (info != null)
            'video     ${info.width}x${info.height}'
                '${info.frameRate != null ? ' @${info.frameRate!.toStringAsFixed(0)}' : ''}'
                ' ${info.videoCodec ?? ''}',
          'bitrate   ${_bitrate(selected?.bitrate ?? info?.bitrate)}',
          'position  ${_time(position?.position)} / ${_time(state.duration)}',
          if (position != null)
            'buffer    ${_time(position.buffered - position.position)} ahead',
          if (position?.behindLive case final behind?)
            'live      ${_time(behind)} behind',
          'prepare   ${_ms(metrics.lastPreparationTime)}'
              '  first frame ${_ms(metrics.lastTimeToFirstFrame)}',
          'start     ${_ms(metrics.lastStartLatency)}'
              '  preparations ${metrics.preparations}',
          'volume    ${state.isMuted ? 'muted' : state.volume.toStringAsFixed(2)}'
              '  speed ${state.playbackSpeed}x',
          if (controller.audioOnly.value) 'audio only',
          if (pool != null)
            'pool      ${pool.leased}/${pool.allocated} used, max ${pool.maxPlayers}',
          if (manager != null && manager.isInitialized)
            'network   ${manager.networkStatus.value.type.name}'
                '${manager.networkStatus.value.isMetered ? ' metered' : ''}',
          if (state.error case final error?) 'error     ${error.code.name}',
        ];
        return Align(
          alignment: widget.alignment,
          child: SafeArea(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  lines.join('\n'),
                  style: const TextStyle(
                    color: Color(0xFF7CFC9A),
                    fontSize: 10,
                    height: 1.35,
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Menlo', 'Courier'],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
