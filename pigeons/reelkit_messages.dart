// Wire contract between the ReelKit Dart layer and the native Android
// (Media3) and iOS (AVFoundation) engines.
//
// This file is the single source of truth for both native packages. Run
// `tool/generate_pigeons.sh` after editing it. Generated files must never be
// edited by hand.
//
// Design rules:
// - No video frames cross this boundary. Frames are rendered through Flutter
//   textures (Android SurfaceProducer, iOS FlutterTexture).
// - No high-frequency events. Playback position is pulled on demand with
//   `getPosition` instead of being pushed on every tick.
// - Every event carries the `generation` of the source it belongs to, so the
//   Dart layer can drop stale events after a pooled player switched sources.

import 'package:pigeon/pigeon.dart';

enum PlatformSourceType { network, file, asset, memory }

enum PlatformVideoFormat { auto, progressive, hls, dash }

/// Coarse native playback state. `isPlaying` is reported separately because
/// a player can be `buffering` while it intends to play.
enum PlatformPlaybackState { idle, buffering, ready, ended }

class PlatformSource {
  PlatformSource({
    required this.type,
    required this.formatHint,
    required this.httpHeaders,
  });

  PlatformSourceType type;

  /// Network URL or absolute file path.
  String? uri;

  /// Flutter asset name, resolved natively through the Flutter asset lookup.
  String? assetName;

  /// Package that owns [assetName], when the asset comes from a package.
  String? assetPackage;

  /// Raw media bytes for memory sources.
  Uint8List? bytes;

  String? mimeType;

  PlatformVideoFormat formatHint;

  Map<String, String> httpHeaders;

  /// Stable key used by the native cache. Defaults to the URI when null.
  String? cacheKey;
}

class PlatformPlayerOptions {
  PlatformPlayerOptions({
    required this.looping,
    required this.volume,
    required this.playbackSpeed,
  });

  bool looping;
  double volume;
  double playbackSpeed;
}

class PlatformPlayerCreation {
  PlatformPlayerCreation({required this.playerId, required this.textureId});

  int playerId;
  int textureId;
}

class PlatformCapabilities {
  PlatformCapabilities({
    required this.engineName,
    required this.engineVersion,
    required this.recommendedMaxPlayers,
    required this.isLowRamDevice,
    required this.supportsHls,
    required this.supportsDash,
    required this.supportsDiskCache,
    required this.supportsMemorySource,
    required this.supportsTrackSelection,
  });

  String engineName;
  String engineVersion;

  /// Device-derived recommendation for concurrent native players.
  int recommendedMaxPlayers;

  /// Hardware decoder instance limit reported by the platform, when known.
  int? maxHardwareDecoderInstances;

  /// Total physical memory in bytes, when known.
  int? totalMemoryBytes;

  bool isLowRamDevice;
  bool supportsHls;
  bool supportsDash;
  bool supportsDiskCache;
  bool supportsMemorySource;
  bool supportsTrackSelection;
}

class PlatformPosition {
  PlatformPosition({required this.positionMs, required this.bufferedMs});

  int positionMs;
  int bufferedMs;
}

@HostApi()
abstract class ReelKitHostApi {
  /// Idempotent. Returns device and engine capabilities.
  PlatformCapabilities initialize();

  /// Allocates a native player and its render target.
  PlatformPlayerCreation createPlayer(PlatformPlayerOptions options);

  /// Releases the native player, its decoder and its render target.
  @async
  void disposePlayer(int playerId);

  /// Replaces the player's source and starts preparing it. Completion of
  /// preparation is reported through [PlatformInitializedEvent].
  void setSource(int playerId, PlatformSource source, int generation);

  void play(int playerId);

  void pause(int playerId);

  @async
  void seekTo(int playerId, int positionMs);

  void setLooping(int playerId, bool looping);

  void setVolume(int playerId, double volume);

  void setPlaybackSpeed(int playerId, double speed);

  PlatformPosition getPosition(int playerId);
}

sealed class PlatformPlayerEvent {}

class PlatformInitializedEvent extends PlatformPlayerEvent {
  PlatformInitializedEvent({
    required this.playerId,
    required this.generation,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.pixelAspectRatio,
  });

  int playerId;
  int generation;

  /// Negative when the duration is unknown (for example live streams).
  int durationMs;
  int width;
  int height;

  /// Clockwise rotation, in degrees, that Flutter must still apply to the
  /// texture to show the video upright. Engines that already rotate frames
  /// report 0.
  int rotationDegrees;

  /// Width-to-height ratio of a single pixel (1.0 for square pixels).
  double pixelAspectRatio;
}

class PlatformStateEvent extends PlatformPlayerEvent {
  PlatformStateEvent({
    required this.playerId,
    required this.generation,
    required this.state,
  });

  int playerId;
  int generation;
  PlatformPlaybackState state;
}

class PlatformIsPlayingEvent extends PlatformPlayerEvent {
  PlatformIsPlayingEvent({
    required this.playerId,
    required this.generation,
    required this.isPlaying,
  });

  int playerId;
  int generation;
  bool isPlaying;
}

class PlatformVideoSizeEvent extends PlatformPlayerEvent {
  PlatformVideoSizeEvent({
    required this.playerId,
    required this.generation,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.pixelAspectRatio,
  });

  int playerId;
  int generation;
  int width;
  int height;

  /// Clockwise rotation, in degrees, that Flutter must still apply to the
  /// texture to show the video upright. Engines that already rotate frames
  /// report 0.
  int rotationDegrees;

  /// Width-to-height ratio of a single pixel (1.0 for square pixels).
  double pixelAspectRatio;
}

class PlatformFirstFrameEvent extends PlatformPlayerEvent {
  PlatformFirstFrameEvent({required this.playerId, required this.generation});

  int playerId;
  int generation;
}

class PlatformErrorEvent extends PlatformPlayerEvent {
  PlatformErrorEvent({
    required this.playerId,
    required this.generation,
    required this.code,
    required this.message,
  });

  int playerId;
  int generation;

  /// One of the `ReelKitErrorCode` names (for example `network`, `decoder`).
  String code;
  String message;
  String? details;
}

@EventChannelApi()
abstract class ReelKitEventApi {
  PlatformPlayerEvent playerEvents();
}
