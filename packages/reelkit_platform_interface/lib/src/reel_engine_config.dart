import 'package:flutter/foundation.dart';

/// iOS `AVAudioSession` category set by the engine.
enum ReelAudioSessionCategory {
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

/// Engine-wide settings sent by `ReelKitPlatform.initialize`. The first
/// initialization of an engine applies them; later managers share them.
@immutable
class ReelEngineConfig {
  const ReelEngineConfig({
    this.cacheEnabled = false,
    this.cacheMaxBytes = 0,
    this.handleAudioFocus = true,
    this.pauseOnAudioRouteLoss = true,
    this.audioSessionCategory = ReelAudioSessionCategory.unmanaged,
    this.mixWithOthers = false,
    this.resumeAfterInterruption = true,
  });

  final bool cacheEnabled;
  final int cacheMaxBytes;
  final bool handleAudioFocus;
  final bool pauseOnAudioRouteLoss;
  final ReelAudioSessionCategory audioSessionCategory;
  final bool mixWithOthers;
  final bool resumeAfterInterruption;

  @override
  bool operator ==(Object other) =>
      other is ReelEngineConfig &&
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
class ReelCacheInfo {
  const ReelCacheInfo({
    required this.enabled,
    required this.usedBytes,
    required this.maxBytes,
  });

  static const disabled = ReelCacheInfo(
    enabled: false,
    usedBytes: 0,
    maxBytes: 0,
  );

  final bool enabled;
  final int usedBytes;
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is ReelCacheInfo &&
      other.enabled == enabled &&
      other.usedBytes == usedBytes &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(enabled, usedBytes, maxBytes);

  @override
  String toString() =>
      'ReelCacheInfo(enabled: $enabled, used: $usedBytes / $maxBytes bytes)';
}
