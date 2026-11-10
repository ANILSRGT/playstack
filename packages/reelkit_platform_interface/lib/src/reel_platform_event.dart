import 'package:flutter/foundation.dart';

import 'reel_kit_exception.dart';
import 'reel_video_info.dart';

/// Native playback state, independent of whether playback is requested.
enum ReelNativePlaybackState {
  /// No media, or preparation has not started.
  idle,

  /// Not enough data to play at the current position.
  buffering,

  /// Able to play immediately.
  ready,

  /// Reached the end of the media.
  ended,
}

/// A low-frequency event emitted by a native player.
///
/// [generation] identifies the source the event belongs to. Pooled players
/// switch sources; consumers must drop events whose generation does not match
/// the source they assigned.
@immutable
sealed class ReelPlatformEvent {
  const ReelPlatformEvent({required this.playerId, required this.generation});

  final int playerId;
  final int generation;
}

/// The source finished preparing and its properties are known.
final class ReelInitializedEvent extends ReelPlatformEvent {
  const ReelInitializedEvent({
    required super.playerId,
    required super.generation,
    required this.info,
  });

  final ReelVideoInfo info;
}

/// The native playback state changed.
final class ReelNativeStateEvent extends ReelPlatformEvent {
  const ReelNativeStateEvent({
    required super.playerId,
    required super.generation,
    required this.state,
  });

  final ReelNativePlaybackState state;
}

/// Playback started or stopped advancing.
final class ReelIsPlayingEvent extends ReelPlatformEvent {
  const ReelIsPlayingEvent({
    required super.playerId,
    required super.generation,
    required this.isPlaying,
  });

  final bool isPlaying;
}

/// The rendered video size changed, for example after an ABR switch.
final class ReelVideoSizeEvent extends ReelPlatformEvent {
  const ReelVideoSizeEvent({
    required super.playerId,
    required super.generation,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.pixelAspectRatio,
  });

  final int width;
  final int height;
  final int rotationDegrees;
  final double pixelAspectRatio;
}

/// The first frame of the current source reached the render target.
final class ReelFirstFrameEvent extends ReelPlatformEvent {
  const ReelFirstFrameEvent({
    required super.playerId,
    required super.generation,
  });
}

/// The native player failed.
final class ReelErrorEvent extends ReelPlatformEvent {
  const ReelErrorEvent({
    required super.playerId,
    required super.generation,
    required this.error,
  });

  final ReelKitException error;
}
