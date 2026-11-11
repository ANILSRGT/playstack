import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../fullscreen/reel_fullscreen_manager.dart';

/// Top-level configuration of a `ReelKitManager`.
@immutable
class ReelKitConfig {
  /// Creates a configuration; every argument has a production default.
  const ReelKitConfig({
    this.pool = const ReelPoolConfig(),
    this.player = const ReelPlayerConfig(),
    this.lifecycle = const ReelLifecycleConfig(),
    this.exclusivePlayback = true,
    this.cache = const ReelCacheConfig(),
    this.audio = const ReelAudioConfig(),
    this.fullscreen = const ReelFullscreenConfig(),
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

  /// Disk cache of network videos (engine-wide; the first manager's
  /// configuration applies).
  final ReelCacheConfig cache;

  /// Audio focus and audio session behaviour (engine-wide).
  final ReelAudioConfig audio;

  /// The app's orientation and system UI policy restored after fullscreen.
  final ReelFullscreenConfig fullscreen;

  @override
  bool operator ==(Object other) =>
      other is ReelKitConfig &&
      other.pool == pool &&
      other.player == player &&
      other.lifecycle == lifecycle &&
      other.exclusivePlayback == exclusivePlayback &&
      other.cache == cache &&
      other.audio == audio &&
      other.fullscreen == fullscreen;

  @override
  int get hashCode => Object.hash(
    pool,
    player,
    lifecycle,
    exclusivePlayback,
    cache,
    audio,
    fullscreen,
  );
}

/// Disk cache of network videos.
///
/// Watched videos and preloaded segments are kept on disk up to [maxBytes]
/// and evicted least-recently-used first, so scrolling back or replaying
/// does not download again. Android caches progressive files and HLS/DASH
/// segments; iOS caches progressive files; browsers use their own HTTP
/// cache, which ReelKit does not control. Per source, see
/// `ReelNetworkSource.cachePolicy`.
@immutable
class ReelCacheConfig {
  /// Creates a cache configuration. The default enables a 256 MB cache.
  const ReelCacheConfig({
    this.enabled = true,
    this.maxBytes = 256 * 1024 * 1024,
  }) : assert(maxBytes >= 0);

  /// Disables the disk cache.
  static const disabled = ReelCacheConfig(enabled: false);

  /// Whether network sources are cached on disk where the engine supports it.
  final bool enabled;

  /// Size limit in bytes; least recently used videos are evicted beyond it.
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is ReelCacheConfig &&
      other.enabled == enabled &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(enabled, maxBytes);
}

/// How playback shares audio with the rest of the device.
@immutable
class ReelAudioConfig {
  /// Creates an audio configuration.
  const ReelAudioConfig({
    this.handleAudioFocus = true,
    this.pauseOnAudioRouteLoss = true,
    this.iosAudioSessionCategory = ReelAudioSessionCategory.unmanaged,
    this.mixWithOthers = false,
    this.resumeAfterInterruption = true,
  });

  /// Android: audible players request audio focus when they play and pause
  /// when another app takes it; muted players never take focus, so muted
  /// autoplay does not stop the user's music.
  final bool handleAudioFocus;

  /// Pause when headphones are unplugged (Android). iOS pauses `AVPlayer`
  /// itself; ReelKit reports it either way.
  final bool pauseOnAudioRouteLoss;

  /// iOS audio session category. [ReelAudioSessionCategory.unmanaged]
  /// (default) respects the host app's configuration; choose
  /// [ReelAudioSessionCategory.playback] for video apps that should play
  /// with the silent switch on.
  final ReelAudioSessionCategory iosAudioSessionCategory;

  /// iOS, with a managed category: mix with other apps' audio instead of
  /// interrupting it.
  final bool mixWithOthers;

  /// iOS: resume after an interruption (call, alarm) when the system says
  /// playback should resume.
  final bool resumeAfterInterruption;

  @override
  bool operator ==(Object other) =>
      other is ReelAudioConfig &&
      other.handleAudioFocus == handleAudioFocus &&
      other.pauseOnAudioRouteLoss == pauseOnAudioRouteLoss &&
      other.iosAudioSessionCategory == iosAudioSessionCategory &&
      other.mixWithOthers == mixWithOthers &&
      other.resumeAfterInterruption == resumeAfterInterruption;

  @override
  int get hashCode => Object.hash(
    handleAudioFocus,
    pauseOnAudioRouteLoss,
    iosAudioSessionCategory,
    mixWithOthers,
    resumeAfterInterruption,
  );
}

/// Reaction to the application being hidden and shown again.
///
/// "Hidden" follows Flutter's `AppLifecycleState.hidden`: the app is no
/// longer visible (backgrounded on mobile, tab hidden or window minimized on
/// web). Transient `inactive` states such as an incoming call banner or the
/// control center do not pause playback.
@immutable
class ReelLifecycleConfig {
  /// Creates a lifecycle configuration.
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
  /// Creates a pool configuration.
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

/// Automatic retries after transient failures (network errors and
/// timeouts).
///
/// A failed preparation is retried within the same `initialize` or `play`
/// call; the controller stays `initializing` meanwhile. A failure during
/// playback is recovered by preparing again, seeking back to the position
/// and resuming if the video was playing. Delays grow from [initialDelay]
/// by [multiplier] up to [maxDelay].
@immutable
class ReelRetryConfig {
  /// Creates a retry configuration. The default retries twice, after 1 s
  /// and 2 s.
  const ReelRetryConfig({
    this.maxAttempts = 2,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 8),
    this.multiplier = 2,
  }) : assert(maxAttempts >= 0),
       assert(multiplier >= 1);

  /// No automatic retries. `ReelPlayerController.retry` still works.
  static const none = ReelRetryConfig(maxAttempts: 0);

  /// Retries after the first failure. Zero disables automatic retries.
  final int maxAttempts;

  /// Wait before the first retry.
  final Duration initialDelay;

  /// Upper bound of the wait between retries.
  final Duration maxDelay;

  /// Factor applied to the wait after each retry; at least 1.
  final double multiplier;

  /// Whether a failure with [code] is retried automatically.
  bool isRetryable(ReelKitErrorCode code) =>
      code == ReelKitErrorCode.network || code == ReelKitErrorCode.timeout;

  /// The wait before retry number [attempt] (1-based).
  Duration delayFor(int attempt) {
    var delay = initialDelay.inMicroseconds.toDouble();
    for (var i = 1; i < attempt; i++) {
      delay *= multiplier;
    }
    final capped = delay.clamp(0, maxDelay.inMicroseconds.toDouble());
    return Duration(microseconds: capped.round());
  }

  @override
  bool operator ==(Object other) =>
      other is ReelRetryConfig &&
      other.maxAttempts == maxAttempts &&
      other.initialDelay == initialDelay &&
      other.maxDelay == maxDelay &&
      other.multiplier == multiplier;

  @override
  int get hashCode =>
      Object.hash(maxAttempts, initialDelay, maxDelay, multiplier);
}

/// Initial playback settings of a controller.
@immutable
class ReelPlayerConfig {
  /// Creates a player configuration.
  const ReelPlayerConfig({
    this.looping = false,
    this.volume = 1.0,
    this.muted = false,
    this.playbackSpeed = 1.0,
    this.initializeTimeout = const Duration(seconds: 30),
    this.preloadBufferDuration = const Duration(seconds: 5),
    this.startupQualityLimit,
    this.retry = const ReelRetryConfig(),
  }) : assert(volume >= 0 && volume <= 1),
       assert(playbackSpeed > 0);

  /// Whether playback restarts from the beginning when it reaches the end.
  final bool looping;

  /// Volume from 0.0 to 1.0, applied when not [muted].
  final double volume;

  /// Whether the controller starts muted.
  final bool muted;

  /// Initial playback rate; 1.0 is normal speed.
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

  /// Caps adaptive quality (HLS, DASH) while the video prepares and until
  /// it starts playing; playing lifts the cap and the engine switches up as
  /// bandwidth allows.
  ///
  /// Engines start with the first rendition of the master playlist, often
  /// the best one. In a feed that prepares several items ahead, starting
  /// them all at full quality competes for bandwidth, so a fast swipe
  /// reaches items that are not ready yet. A low startup rendition makes
  /// each preparation a fraction of the download, the way short-video apps
  /// start: for example `ReelVideoQualityLimit(maxBitrate: 1600000)`. The
  /// first seconds then play at that quality.
  ///
  /// Combined with `ReelPlayerController.setVideoQualityLimit` (the lower
  /// of both applies). Null starts at the engine's choice. Applied where
  /// `ReelPlatformCapabilities.supportsVideoQualityLimit` is true (Android,
  /// iOS); browsers choose renditions themselves.
  final ReelVideoQualityLimit? startupQualityLimit;

  /// Automatic retries after network errors and timeouts.
  final ReelRetryConfig retry;

  /// Returns a copy with the given fields replaced.
  ReelPlayerConfig copyWith({
    bool? looping,
    double? volume,
    bool? muted,
    double? playbackSpeed,
    Duration? initializeTimeout,
    Duration? preloadBufferDuration,
    ReelVideoQualityLimit? startupQualityLimit,
    ReelRetryConfig? retry,
  }) {
    return ReelPlayerConfig(
      looping: looping ?? this.looping,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      initializeTimeout: initializeTimeout ?? this.initializeTimeout,
      preloadBufferDuration:
          preloadBufferDuration ?? this.preloadBufferDuration,
      startupQualityLimit: startupQualityLimit ?? this.startupQualityLimit,
      retry: retry ?? this.retry,
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
      other.preloadBufferDuration == preloadBufferDuration &&
      other.startupQualityLimit == startupQualityLimit &&
      other.retry == retry;

  @override
  int get hashCode => Object.hash(
    looping,
    volume,
    muted,
    playbackSpeed,
    initializeTimeout,
    preloadBufferDuration,
    startupQualityLimit,
    retry,
  );
}
