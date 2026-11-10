import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// Top-level configuration of a `ReelKitManager`.
@immutable
class ReelKitConfig {
  const ReelKitConfig({
    this.pool = const ReelPoolConfig(),
    this.player = const ReelPlayerConfig(),
  });

  /// How native players are allocated and reused.
  final ReelPoolConfig pool;

  /// Default settings of controllers created by the manager.
  final ReelPlayerConfig player;

  @override
  bool operator ==(Object other) =>
      other is ReelKitConfig && other.pool == pool && other.player == player;

  @override
  int get hashCode => Object.hash(pool, player);
}

/// Configuration of the native player pool.
///
/// A native player owns a decoder, buffers and a render target. Each one is
/// expensive, so ReelKit keeps a bounded set and reassigns them between
/// controllers instead of allocating one per video.
@immutable
class ReelPoolConfig {
  const ReelPoolConfig({
    this.maxPlayers,
    this.maxAdaptivePlayers = 4,
    this.idleTimeout = const Duration(seconds: 30),
  }) : assert(maxPlayers == null || maxPlayers > 0),
       assert(maxAdaptivePlayers > 0);

  /// Fixed upper bound of native players. When null (the default), the
  /// limit adapts to the device: the engine's
  /// [ReelPlatformCapabilities.recommendedMaxPlayers], capped at
  /// [maxAdaptivePlayers].
  final int? maxPlayers;

  /// Ceiling for the adaptive limit when [maxPlayers] is null.
  final int maxAdaptivePlayers;

  /// How long a released native player is kept for reuse before it is
  /// destroyed. [Duration.zero] destroys players as soon as they are
  /// released.
  final Duration idleTimeout;

  /// The player limit for a device with [capabilities].
  int resolveMaxPlayers(ReelPlatformCapabilities capabilities) {
    final fixed = maxPlayers;
    if (fixed != null) return fixed;
    return capabilities.recommendedMaxPlayers.clamp(1, maxAdaptivePlayers);
  }

  @override
  bool operator ==(Object other) =>
      other is ReelPoolConfig &&
      other.maxPlayers == maxPlayers &&
      other.maxAdaptivePlayers == maxAdaptivePlayers &&
      other.idleTimeout == idleTimeout;

  @override
  int get hashCode => Object.hash(maxPlayers, maxAdaptivePlayers, idleTimeout);
}

/// Initial playback settings of a controller.
@immutable
class ReelPlayerConfig {
  const ReelPlayerConfig({
    this.looping = false,
    this.volume = 1.0,
    this.muted = false,
    this.playbackSpeed = 1.0,
    this.initializeTimeout = const Duration(seconds: 30),
  }) : assert(volume >= 0 && volume <= 1),
       assert(playbackSpeed > 0);

  final bool looping;

  /// Volume from 0.0 to 1.0, applied when not [muted].
  final double volume;

  final bool muted;

  final double playbackSpeed;

  /// Maximum time to wait for a source to finish preparing.
  final Duration initializeTimeout;

  ReelPlayerConfig copyWith({
    bool? looping,
    double? volume,
    bool? muted,
    double? playbackSpeed,
    Duration? initializeTimeout,
  }) {
    return ReelPlayerConfig(
      looping: looping ?? this.looping,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      initializeTimeout: initializeTimeout ?? this.initializeTimeout,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReelPlayerConfig &&
      other.looping == looping &&
      other.volume == volume &&
      other.muted == muted &&
      other.playbackSpeed == playbackSpeed &&
      other.initializeTimeout == initializeTimeout;

  @override
  int get hashCode =>
      Object.hash(looping, volume, muted, playbackSpeed, initializeTimeout);
}
