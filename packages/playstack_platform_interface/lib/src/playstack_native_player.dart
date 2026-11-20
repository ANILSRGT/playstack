import 'package:flutter/foundation.dart';

/// Initial settings applied when a native player is allocated.
@immutable
class PlayStackNativePlayerOptions {
  /// Creates player options.
  const PlayStackNativePlayerOptions({
    this.looping = false,
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
  });

  /// Whether playback restarts at the end.
  final bool looping;

  /// Volume from 0.0 to 1.0.
  final double volume;

  /// Playback rate; 1.0 is normal speed.
  final double playbackSpeed;
}

/// Identifies a native player allocated by a [PlayStackPlatform].
@immutable
class PlayStackNativePlayerHandle {
  /// Creates a handle.
  const PlayStackNativePlayerHandle({
    required this.playerId,
    required this.textureId,
  });

  /// Engine-assigned player id.
  final int playerId;

  /// Flutter texture id, or -1 when the platform renders with a platform
  /// view instead of a texture.
  final int textureId;

  @override
  bool operator ==(Object other) =>
      other is PlayStackNativePlayerHandle &&
      other.playerId == playerId &&
      other.textureId == textureId;

  @override
  int get hashCode => Object.hash(playerId, textureId);

  @override
  String toString() =>
      'PlayStackNativePlayerHandle($playerId, texture $textureId)';
}

/// Playback and buffer position read from a native player.
@immutable
class PlayStackPositionSnapshot {
  /// Creates a snapshot.
  const PlayStackPositionSnapshot({
    required this.position,
    required this.buffered,
    this.windowStart,
    this.liveEdge,
  });

  /// Current playback position.
  final Duration position;

  /// Position up to which media is buffered.
  final Duration buffered;

  /// Live streams: the earliest point the user can go back to (the DVR
  /// window), on the same clock as [position]. Null for other videos.
  final Duration? windowStart;

  /// Live streams: the live edge, on the same clock as [position]. Null for
  /// other videos.
  final Duration? liveEdge;

  /// Live streams: how far behind live playback is, or null.
  Duration? get behindLive {
    final edge = liveEdge;
    if (edge == null) return null;
    final behind = edge - position;
    return behind.isNegative ? Duration.zero : behind;
  }

  @override
  bool operator ==(Object other) =>
      other is PlayStackPositionSnapshot &&
      other.position == position &&
      other.buffered == buffered &&
      other.windowStart == windowStart &&
      other.liveEdge == liveEdge;

  @override
  int get hashCode => Object.hash(position, buffered, windowStart, liveEdge);

  @override
  String toString() =>
      'PlayStackPositionSnapshot($position, buffered: $buffered)';
}
