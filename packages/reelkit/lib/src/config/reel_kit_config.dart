import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../fullscreen/reel_fullscreen_manager.dart';

/// All settings of a `ReelKitManager`, grouped by topic. Every setting has a
/// sensible default, so pass only what you change:
///
/// ```dart
/// final manager = ReelKitManager(
///   config: const ReelKitConfig(
///     player: ReelPlayerConfig(looping: true, muted: true),
///     cache: ReelCacheConfig(maxBytes: 512 * 1024 * 1024),
///   ),
/// );
/// ```
///
/// For a short-video feed, start from [ReelKitConfig.reels].
@immutable
class ReelKitConfig {
  /// Creates a configuration. Every argument has a default suitable for production.
  const ReelKitConfig({
    this.pool = const ReelPoolConfig(),
    this.player = const ReelPlayerConfig(),
    this.lifecycle = const ReelLifecycleConfig(),
    this.exclusivePlayback = true,
    this.cache = const ReelCacheConfig(),
    this.audio = const ReelAudioConfig(),
    this.fullscreen = const ReelFullscreenConfig(),
  });

  /// Settings tuned for a full-screen short-video feed where users swipe
  /// two or three videos a second. `ReelFeedView` uses them when it creates
  /// its own manager.
  ///
  /// * Room for the video in view, five ahead and one behind.
  /// * Videos loop. On the web they start muted, because browsers block
  ///   autoplay with sound until the user taps.
  /// * No rendition larger than the screen ([screenQualityLimit]); feed
  ///   fullscreen lifts this.
  /// * Preparation at up to ~720p, switching up once playing, so several
  ///   videos prepare in the time of one swipe.
  /// * On iOS, sound plays with the silent switch on, like video apps.
  /// * The app is portrait outside fullscreen: leaving fullscreen turns a
  ///   landscape video's screen back to portrait, even when the phone is
  ///   still held sideways. For a feed that also rotates, pass a manager
  ///   whose [fullscreen] lists the orientations your app allows.
  factory ReelKitConfig.reels() => ReelKitConfig(
    pool: const ReelPoolConfig(maxPlayers: 7),
    player: ReelPlayerConfig(
      looping: true,
      muted: kIsWeb,
      videoQualityLimit: screenQualityLimit(),
      startupQualityLimit: const ReelVideoQualityLimit(maxBitrate: 3400000),
    ),
    audio: const ReelAudioConfig(
      iosAudioSessionCategory: ReelAudioSessionCategory.playback,
    ),
    // Short-video feeds are portrait. Without this, leaving fullscreen
    // would unlock every orientation and the screen would stay sideways.
    fullscreen: const ReelFullscreenConfig(
      appOrientations: [DeviceOrientation.portraitUp],
    ),
  );

  /// A quality limit of the screen's size in physical pixels, portrait:
  /// as wide as the short side, as tall as the long side. A landscape video
  /// in a portrait feed is only as wide as the screen, so larger renditions
  /// are wasted there. Unlimited when the size is not known yet.
  static ReelVideoQualityLimit screenQualityLimit() {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isEmpty) return ReelVideoQualityLimit.none;
    final size = views.first.physicalSize;
    if (size.isEmpty) return ReelVideoQualityLimit.none;
    return ReelVideoQualityLimit(
      maxWidth: size.shortestSide.round(),
      maxHeight: size.longestSide.round(),
    );
  }

  /// How many native players may exist and how they are reused. The default
  /// adapts to the device.
  final ReelPoolConfig pool;

  /// Starting settings of every controller the manager creates: looping,
  /// volume, mute, speed, quality caps, retries. A controller can change them
  /// later.
  final ReelPlayerConfig player;

  /// Whether playback pauses when the app goes to the background and resumes
  /// when it comes back. Both on by default.
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

  /// Disk cache of network videos, 256 MB by default. Shared by the whole
  /// app: the first manager's setting applies.
  final ReelCacheConfig cache;

  /// How playback shares audio with other apps: audio focus on Android, the
  /// audio session on iOS. Shared by the whole app.
  final ReelAudioConfig audio;

  /// The app's normal orientations and system bars, restored when fullscreen
  /// ends.
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
  /// Creates a cache configuration. By default the cache is on with a 256 MB
  /// limit.
  const ReelCacheConfig({
    this.enabled = true,
    this.maxBytes = 256 * 1024 * 1024,
  }) : assert(maxBytes >= 0);

  /// No disk cache: every video is downloaded each time it plays. Use it when
  /// the app has its own cache or must not store videos.
  static const disabled = ReelCacheConfig(enabled: false);

  /// Whether network videos are cached on disk where the engine supports it. True by default.
  final bool enabled;

  /// Size limit of the cache in bytes, 256 MB by default. Beyond it, the
  /// least recently watched videos are removed first.
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is ReelCacheConfig &&
      other.enabled == enabled &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(enabled, maxBytes);
}

/// How video sound coexists with other apps' audio, such as music players
/// and calls. The defaults suit most apps.
@immutable
class ReelAudioConfig {
  /// Creates an audio configuration. Defaults: audio focus handled, pause when
  /// headphones are unplugged, the iOS session left to the app, no mixing,
  /// resume after interruptions.
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
  /// Creates a lifecycle configuration. By default playback pauses when the
  /// app is hidden and resumes when it is shown again.
  const ReelLifecycleConfig({
    this.pauseOnBackground = true,
    this.resumeOnForeground = true,
  });

  /// Pauses every playing video of the manager when the app is hidden. True
  /// by default. Turn it off only for background audio, which also needs the
  /// platform's background audio setup.
  final bool pauseOnBackground;

  /// Resumes the videos that were paused because the app was hidden, when it
  /// is shown again. True by default. Videos the user paused stay paused.
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
  /// Creates a pool configuration. By default the player limit adapts to the
  /// device, up to 4, and idle players are kept 30 seconds for reuse.
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

  /// The most players the adaptive limit allows when [maxPlayers] is null, 4
  /// by default.
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
  /// Creates a retry configuration. By default failures are retried twice, after 1 s and then 2 s.
  const ReelRetryConfig({
    this.maxAttempts = 2,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 8),
    this.multiplier = 2,
  }) : assert(maxAttempts >= 0),
       assert(multiplier >= 1);

  /// No automatic retries. `ReelPlayerController.retry` still works.
  static const none = ReelRetryConfig(maxAttempts: 0);

  /// How many times a failure is retried automatically, 2 by default. Zero
  /// turns automatic retries off.
  final int maxAttempts;

  /// Wait before the first retry, 1 second by default.
  final Duration initialDelay;

  /// Longest wait between retries, however many retries there were. 8 seconds by default.
  final Duration maxDelay;

  /// How much the wait grows after each retry, 2 by default: 1 s, 2 s, 4 s...
  /// At least 1.
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

/// Starting settings of a `ReelPlayerController`: looping, volume, speed,
/// quality caps, timeouts and retries.
///
/// Set them for all controllers in `ReelKitConfig.player`, or for one
/// controller in `ReelKitManager.createController(config: ...)`. A
/// controller can change most of them later (`setLooping`, `setVolume`...).
@immutable
class ReelPlayerConfig {
  /// Creates player settings. Defaults: no looping, full volume, not muted,
  /// normal speed, 30-second preparation timeout, 5 seconds buffered ahead
  /// while preloading, no quality caps, two automatic retries.
  const ReelPlayerConfig({
    this.looping = false,
    this.volume = 1.0,
    this.muted = false,
    this.playbackSpeed = 1.0,
    this.initializeTimeout = const Duration(seconds: 30),
    this.preloadBufferDuration = const Duration(seconds: 5),
    this.videoQualityLimit = ReelVideoQualityLimit.none,
    this.startupQualityLimit,
    this.retry = const ReelRetryConfig(),
  }) : assert(volume >= 0 && volume <= 1),
       assert(playbackSpeed > 0);

  /// Whether the video starts over when it ends. False by default; reels usually loop.
  final bool looping;

  /// Volume from 0.0 (silent) to 1.0 (full), 1.0 by default. Not heard while [muted].
  final double volume;

  /// Whether the video starts without sound. False by default. On the web,
  /// browsers only autoplay muted videos until the user taps.
  final bool muted;

  /// Starting speed: 1.0 (default) is normal, 2.0 double speed.
  final double playbackSpeed;

  /// How long a video may take to prepare before it fails with
  /// `ReelKitErrorCode.timeout`, 30 seconds by default. Timeouts are retried
  /// like network errors (see [retry]).
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

  /// Initial `ReelPlayerController.videoQualityLimit`: caps adaptive
  /// quality (HLS, DASH) for the controller's whole life, until the app
  /// changes it.
  ///
  /// A video shown in part of a phone screen does not need a rendition
  /// larger than its view; capping to the view's size in physical pixels
  /// saves bandwidth and avoids switching up to renditions the network
  /// cannot sustain while preloads run. Lift it with
  /// `setVideoQualityLimit(ReelVideoQualityLimit.none)`, for example in
  /// fullscreen.
  final ReelVideoQualityLimit videoQualityLimit;

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

  /// Automatic retries after network errors and timeouts: twice by default,
  /// after 1 s and 2 s. [ReelRetryConfig.none] turns them off.
  final ReelRetryConfig retry;

  /// Returns a copy with the given fields replaced.
  ReelPlayerConfig copyWith({
    bool? looping,
    double? volume,
    bool? muted,
    double? playbackSpeed,
    Duration? initializeTimeout,
    Duration? preloadBufferDuration,
    ReelVideoQualityLimit? videoQualityLimit,
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
      videoQualityLimit: videoQualityLimit ?? this.videoQualityLimit,
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
      other.videoQualityLimit == videoQualityLimit &&
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
    videoQualityLimit,
    startupQualityLimit,
    retry,
  );
}
