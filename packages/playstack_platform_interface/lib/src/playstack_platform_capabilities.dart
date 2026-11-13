import 'package:flutter/foundation.dart';

/// What the active playback engine and device can do.
///
/// Every flag describes what PlayStack's engine on this platform actually
/// provides today; unsupported features are reported as `false` rather than
/// emulated.
@immutable
class PlayStackPlatformCapabilities {
  /// Creates a capability description. Engines create these.
  const PlayStackPlatformCapabilities({
    required this.engineName,
    required this.engineVersion,
    required this.recommendedMaxPlayers,
    required this.isLowRamDevice,
    required this.supportsHls,
    required this.supportsDash,
    required this.supportsDiskCache,
    required this.supportsMemorySource,
    required this.supportsTrackSelection,
    this.supportsVideoTrackSelection = false,
    this.supportsVideoQualityLimit = false,
    this.supportsPreloadBufferLimit = false,
    this.supportsNetworkStatus = false,
    this.maxHardwareDecoderInstances,
    this.totalMemoryBytes,
  });

  /// Name of the playback engine, for example `media3`.
  final String engineName;

  /// Version of the playback engine or platform.
  final String engineVersion;

  /// Device-derived recommendation for concurrent native players. This is a
  /// heuristic based on memory and, where the platform exposes it, decoder
  /// instance limits.
  final int recommendedMaxPlayers;

  /// Hardware H.264 decoder instance limit, when the platform reports it.
  final int? maxHardwareDecoderInstances;

  /// Total physical memory in bytes, when the platform reports it.
  final int? totalMemoryBytes;

  /// Whether the operating system classifies the device as low on memory.
  final bool isLowRamDevice;

  /// Whether HLS (`.m3u8`) sources play.
  final bool supportsHls;

  /// Whether DASH (`.mpd`) sources play.
  final bool supportsDash;

  /// Whether network sources can be cached on disk.
  final bool supportsDiskCache;

  /// Whether `PlayStackMemorySource` plays.
  final bool supportsMemorySource;

  /// Audio and text (subtitle) track listing and selection.
  final bool supportsTrackSelection;

  /// Selecting a specific video rendition (quality).
  final bool supportsVideoTrackSelection;

  /// Capping adaptive video by bitrate and resolution.
  final bool supportsVideoQualityLimit;

  /// Bounding the forward buffer of paused, preloaded players.
  final bool supportsPreloadBufferLimit;

  /// Reporting connectivity, metering and data saver state.
  final bool supportsNetworkStatus;

  @override
  bool operator ==(Object other) =>
      other is PlayStackPlatformCapabilities &&
      other.engineName == engineName &&
      other.engineVersion == engineVersion &&
      other.recommendedMaxPlayers == recommendedMaxPlayers &&
      other.maxHardwareDecoderInstances == maxHardwareDecoderInstances &&
      other.totalMemoryBytes == totalMemoryBytes &&
      other.isLowRamDevice == isLowRamDevice &&
      other.supportsHls == supportsHls &&
      other.supportsDash == supportsDash &&
      other.supportsDiskCache == supportsDiskCache &&
      other.supportsMemorySource == supportsMemorySource &&
      other.supportsTrackSelection == supportsTrackSelection &&
      other.supportsVideoTrackSelection == supportsVideoTrackSelection &&
      other.supportsVideoQualityLimit == supportsVideoQualityLimit &&
      other.supportsPreloadBufferLimit == supportsPreloadBufferLimit &&
      other.supportsNetworkStatus == supportsNetworkStatus;

  @override
  int get hashCode => Object.hash(
    engineName,
    engineVersion,
    recommendedMaxPlayers,
    maxHardwareDecoderInstances,
    totalMemoryBytes,
    isLowRamDevice,
    supportsHls,
    supportsDash,
    supportsDiskCache,
    supportsMemorySource,
    supportsTrackSelection,
    supportsVideoTrackSelection,
    supportsVideoQualityLimit,
    supportsPreloadBufferLimit,
    supportsNetworkStatus,
  );

  @override
  String toString() =>
      'PlayStackPlatformCapabilities($engineName $engineVersion, '
      'recommendedMaxPlayers: $recommendedMaxPlayers, '
      'lowRam: $isLowRamDevice, hls: $supportsHls, dash: $supportsDash)';
}
