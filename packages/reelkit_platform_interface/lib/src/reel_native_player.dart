import 'package:flutter/foundation.dart';

/// Initial settings applied when a native player is allocated.
@immutable
class ReelNativePlayerOptions {
  /// Creates player options.
  const ReelNativePlayerOptions({
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

/// Identifies a native player allocated by a [ReelKitPlatform].
@immutable
class ReelNativePlayerHandle {
  /// Creates a handle.
  const ReelNativePlayerHandle({
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
      other is ReelNativePlayerHandle &&
      other.playerId == playerId &&
      other.textureId == textureId;

  @override
  int get hashCode => Object.hash(playerId, textureId);

  @override
  String toString() => 'ReelNativePlayerHandle($playerId, texture $textureId)';
}

/// Playback and buffer position read from a native player.
@immutable
class ReelPositionSnapshot {
  /// Creates a snapshot.
  const ReelPositionSnapshot({required this.position, required this.buffered});

  /// Current playback position.
  final Duration position;

  /// Position up to which media is buffered.
  final Duration buffered;

  @override
  bool operator ==(Object other) =>
      other is ReelPositionSnapshot &&
      other.position == position &&
      other.buffered == buffered;

  @override
  int get hashCode => Object.hash(position, buffered);

  @override
  String toString() => 'ReelPositionSnapshot($position, buffered: $buffered)';
}
