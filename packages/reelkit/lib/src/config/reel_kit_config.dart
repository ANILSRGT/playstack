import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// Top-level configuration of a `ReelKitManager`.
@immutable
class ReelKitConfig {
  const ReelKitConfig({
    this.pool = const ReelPoolConfig(),
    this.player = const ReelPlayerConfig(),
    this.lifecycle = const ReelLifecycleConfig(),
    this.exclusivePlayback = true,
  });

  /// How native players are allocated and reused.
  final ReelPoolConfig pool;

  /// Default settings of controllers created by the manager.
  final ReelPlayerConfig player;

  /// How playback reacts to the app moving to the background.
  final ReelLifecycleConfig lifecycle;

  /// Whether at most one controller of the manager plays at a time.
  ///
  /// When true (the default), calling `play` on a controller pauses every
  /// other playing controller of the same manager, and the most recent
  /// `play` call wins when several are in flight. A `play` call that is
  /// superseded before playback started completes without starting playback.
  /// Set to false for layouts that intentionally play several videos at once,
  /// such as a muted preview grid.
  final bool exclusivePlayback;

  @override
  bool operator ==(Object other) =>
      other is ReelKitConfig &&
      other.pool == pool &&
      other.player == player &&
      other.lifecycle == lifecycle &&
      other.exclusivePlayback == exclusivePlayback;

  @override
  int get hashCode => Object.hash(pool, player, lifecycle, exclusivePlayback);
}

/// Reaction to the application being hidden and shown again.
///
/// "Hidden" follows Flutter's `AppLifecycleState.hidden`: the app is no
/// longer visible (backgrounded on mobile, tab hidden or window minimized on
/// web). Transient `inactive` states such as an incoming call banner or the
/// control center do not pause playback.
@immutable
class ReelLifecycleConfig {
  const ReelLifecycleConfig({
    this.pauseOnBackground = true,
    this.resumeOnForeground = true,
  });

  /// Pauses every playing controller of the manager when the app is hidden.
  /// Disable for background audio, which also requires the platform's
  /// background audio setup.
  final bool pauseOnBackground;

  /// Resumes the controllers that were paused because the app was hidden.
  final bool resumeOnForeground;

  @override
  bool operator ==(Object other) =>
      other is ReelLifecycleConfig &&
      other.pauseOnBackground == pauseOnBackground &&
      other.resumeOnForeground == resumeOnForeground;

  @override
  int get hashCode => Object.hash(pauseOnBackground, resumeOnForeground);
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
    this.adaptToDecoderFailures = true,
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

  /// Whether the pool shrinks when a decoder cannot be allocated.
  ///
  /// Hardware decoder instances are shared with other apps, so the number a
  /// device sustains is only known at run time. When preparing a video fails
  /// with [ReelKitErrorCode.decoderUnavailable] while other players of the
  /// pool hold prepared videos, the limit drops to the number of those
  /// players and the preparation is retried once on a player taken from a
  /// lower-priority controller. The lowered limit applies, also to a fixed
  /// [maxPlayers], for the lifetime of the manager.
  final bool adaptToDecoderFailures;

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
      other.idleTimeout == idleTimeout &&
      other.adaptToDecoderFailures == adaptToDecoderFailures;

  @override
  int get hashCode => Object.hash(
    maxPlayers,
    maxAdaptivePlayers,
    idleTimeout,
    adaptToDecoderFailures,
  );
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
    this.preloadBufferDuration = const Duration(seconds: 5),
  }) : assert(volume >= 0 && volume <= 1),
       assert(playbackSpeed > 0);

  final bool looping;

  /// Volume from 0.0 to 1.0, applied when not [muted].
  final double volume;

  final bool muted;

  final double playbackSpeed;

  /// Maximum time to wait for a source to finish preparing.
  final Duration initializeTimeout;

  /// How far ahead a paused controller with priority
  /// `ReelPlayerPriority.preload` or `ReelPlayerPriority.background` buffers.
  ///
  /// Prepared-ahead videos would otherwise download up to the engine's
  /// default buffer (50 s on Android) although the user may never watch
  /// them. Playing removes the limit. Null leaves buffering to the engine.
  /// Applied where `ReelPlatformCapabilities.supportsPreloadBufferLimit` is
  /// true (Android, iOS; on iOS it is a preference AVFoundation may exceed).
  final Duration? preloadBufferDuration;

  ReelPlayerConfig copyWith({
    bool? looping,
    double? volume,
    bool? muted,
    double? playbackSpeed,
    Duration? initializeTimeout,
    Duration? preloadBufferDuration,
  }) {
    return ReelPlayerConfig(
      looping: looping ?? this.looping,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      initializeTimeout: initializeTimeout ?? this.initializeTimeout,
      preloadBufferDuration:
          preloadBufferDuration ?? this.preloadBufferDuration,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReelPlayerConfig &&
      other.looping == looping &&
      other.volume == volume &&
      other.muted == muted &&
      other.playbackSpeed == playbackSpeed &&
      other.initializeTimeout == initializeTimeout &&
      other.preloadBufferDuration == preloadBufferDuration;

  @override
  int get hashCode => Object.hash(
    looping,
    volume,
    muted,
    playbackSpeed,
    initializeTimeout,
    preloadBufferDuration,
  );
}
