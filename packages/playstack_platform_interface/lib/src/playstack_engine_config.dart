import 'package:flutter/foundation.dart';

/// iOS `AVAudioSession` category set by the engine.
enum PlayStackAudioSessionCategory {
  /// Leave the host app's audio session untouched (default). Note that the
  /// iOS default category (`soloAmbient`) is silenced by the ring/silent
  /// switch.
  unmanaged,

  /// `ambient`: mixes with other audio and follows the silent switch.
  ambient,

  /// `playback` with the `moviePlayback` mode: plays with the silent switch
  /// on and interrupts other audio unless `mixWithOthers` is set.
  playback,
}

/// Engine-wide settings sent by `PlayStackPlatform.initialize`. The first
/// initialization of an engine applies them; later managers share them.
@immutable
class PlayStackEngineConfig {
  /// Creates an engine configuration.
  const PlayStackEngineConfig({
    this.cacheEnabled = false,
    this.cacheMaxBytes = 0,
    this.handleAudioFocus = true,
    this.pauseOnAudioRouteLoss = true,
    this.audioSessionCategory = PlayStackAudioSessionCategory.unmanaged,
    this.mixWithOthers = false,
    this.resumeAfterInterruption = true,
  });

  /// Whether network sources may use the disk cache.
  final bool cacheEnabled;

  /// Disk cache size limit in bytes.
  final int cacheMaxBytes;

  /// Android: request audio focus while audible.
  final bool handleAudioFocus;

  /// Pause when headphones or another audio route are disconnected.
  final bool pauseOnAudioRouteLoss;

  /// iOS audio session category.
  final PlayStackAudioSessionCategory audioSessionCategory;

  /// iOS: mix with other apps' audio instead of interrupting it.
  final bool mixWithOthers;

  /// iOS: resume playback when an interruption ends and the system allows it.
  final bool resumeAfterInterruption;

  @override
  bool operator ==(Object other) =>
      other is PlayStackEngineConfig &&
      other.cacheEnabled == cacheEnabled &&
      other.cacheMaxBytes == cacheMaxBytes &&
      other.handleAudioFocus == handleAudioFocus &&
      other.pauseOnAudioRouteLoss == pauseOnAudioRouteLoss &&
      other.audioSessionCategory == audioSessionCategory &&
      other.mixWithOthers == mixWithOthers &&
      other.resumeAfterInterruption == resumeAfterInterruption;

  @override
  int get hashCode => Object.hash(
    cacheEnabled,
    cacheMaxBytes,
    handleAudioFocus,
    pauseOnAudioRouteLoss,
    audioSessionCategory,
    mixWithOthers,
    resumeAfterInterruption,
  );
}

/// Usage of the engine's disk cache.
@immutable
class PlayStackCacheInfo {
  /// Creates a cache usage snapshot.
  const PlayStackCacheInfo({
    required this.enabled,
    required this.usedBytes,
    required this.maxBytes,
  });

  /// Reported by engines without a disk cache, or with the cache disabled.
  static const disabled = PlayStackCacheInfo(
    enabled: false,
    usedBytes: 0,
    maxBytes: 0,
  );

  /// Whether the engine caches network sources.
  final bool enabled;

  /// Bytes currently stored.
  final int usedBytes;

  /// Size limit in bytes.
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is PlayStackCacheInfo &&
      other.enabled == enabled &&
      other.usedBytes == usedBytes &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(enabled, usedBytes, maxBytes);

  @override
  String toString() =>
      'PlayStackCacheInfo(enabled: $enabled, used: $usedBytes / $maxBytes bytes)';
}
