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

enum PlatformTrackType { audio, video, text }

enum PlatformNetworkType { none, wifi, cellular, ethernet, other, unknown }

/// iOS `AVAudioSession` category ReelKit sets, or `unmanaged` to leave the
/// host app's session alone.
enum PlatformAudioSessionCategory { unmanaged, ambient, playback }

enum PlatformInterruptionType {
  /// Another app took audio focus (Android) or the system interrupted the
  /// audio session (iOS: call, alarm, Siri).
  audioInterruption,

  /// Headphones or another audio route went away; playback was paused.
  audioRouteLost,
}

/// Engine-wide settings, applied by the first `initialize` call.
class PlatformEngineConfig {
  PlatformEngineConfig({
    required this.cacheEnabled,
    required this.cacheMaxBytes,
    required this.handleAudioFocus,
    required this.pauseOnAudioRouteLoss,
    required this.audioSessionCategory,
    required this.mixWithOthers,
    required this.resumeAfterInterruption,
  });

  bool cacheEnabled;
  int cacheMaxBytes;

  /// Android: request audio focus while playing audibly and pause on loss.
  bool handleAudioFocus;

  /// Pause when headphones are disconnected (Android "becoming noisy"; iOS
  /// AVPlayer already pauses and the engine reports it).
  bool pauseOnAudioRouteLoss;

  PlatformAudioSessionCategory audioSessionCategory;
  bool mixWithOthers;

  /// iOS: resume when an interruption ends with `shouldResume`.
  bool resumeAfterInterruption;
}

class PlatformCacheInfo {
  PlatformCacheInfo({
    required this.enabled,
    required this.usedBytes,
    required this.maxBytes,
  });

  bool enabled;
  int usedBytes;
  int maxBytes;
}

/// Connectivity as seen by the operating system.
class PlatformNetworkStatus {
  PlatformNetworkStatus({
    required this.isConnected,
    required this.isMetered,
    required this.isConstrained,
    required this.type,
  });

  bool isConnected;

  /// Billed by data volume (Android NOT_METERED missing, iOS isExpensive).
  bool isMetered;

  /// The user asked to save data (Android Data Saver, iOS Low Data Mode).
  bool isConstrained;

  PlatformNetworkType type;
}

/// One selectable audio, video or text track of the current source.
class PlatformTrack {
  PlatformTrack({
    required this.id,
    required this.type,
    required this.isSelected,
  });

  /// Engine-defined identifier, stable for the same source.
  String id;
  PlatformTrackType type;
  bool isSelected;
  String? label;

  /// BCP 47 language tag, when known.
  String? language;

  /// Peak or average bitrate in bits per second, when known.
  int? bitrate;
  int? width;
  int? height;
  double? frameRate;
  String? codecs;
  int? channelCount;
}

class PlatformSource {
  PlatformSource({
    required this.type,
    required this.formatHint,
    required this.httpHeaders,
    required this.useCache,
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

  /// Whether this source may be read from and written to the disk cache.
  bool useCache;
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
    required this.supportsVideoTrackSelection,
    required this.supportsVideoQualityLimit,
    required this.supportsPreloadBufferLimit,
    required this.supportsNetworkStatus,
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

  /// Audio and text track listing and selection.
  bool supportsTrackSelection;

  /// Selecting a specific video rendition (quality).
  bool supportsVideoTrackSelection;

  /// Capping adaptive video by bitrate and resolution.
  bool supportsVideoQualityLimit;

  /// `setPreloadBufferLimit` bounds forward buffering of paused players.
  bool supportsPreloadBufferLimit;

  /// `getNetworkStatus` and `networkEvents` report real connectivity.
  bool supportsNetworkStatus;
}

class PlatformPosition {
  PlatformPosition({required this.positionMs, required this.bufferedMs});

  int positionMs;
  int bufferedMs;
}

@HostApi()
abstract class ReelKitHostApi {
  /// Idempotent. Returns device and engine capabilities.
  PlatformCapabilities initialize(PlatformEngineConfig config);

  /// Allocates a native player and its render target.
  PlatformPlayerCreation createPlayer(PlatformPlayerOptions options);

  /// Releases the native player, its decoder and its render target.
  @async
  void disposePlayer(int playerId);

  /// Replaces the player's source and starts preparing it. Completion of
  /// preparation is reported through [PlatformInitializedEvent].
  void setSource(int playerId, PlatformSource source, int generation);

  /// Stops playback and detaches the current source, releasing its decoder
  /// and buffers while keeping the player and its render target for reuse.
  void clearSource(int playerId);

  void play(int playerId);

  void pause(int playerId);

  @async
  void seekTo(int playerId, int positionMs);

  void setLooping(int playerId, bool looping);

  void setVolume(int playerId, double volume);

  void setPlaybackSpeed(int playerId, double speed);

  PlatformPosition getPosition(int playerId);

  List<PlatformTrack> getTracks(int playerId);

  /// Selects [trackId] for [type]. A null [trackId] restores automatic
  /// selection for audio and video and disables text tracks.
  void selectTrack(int playerId, PlatformTrackType type, String? trackId);

  /// Caps adaptive video selection. Null values remove the respective cap.
  void setVideoQualityLimit(
    int playerId,
    int? maxBitrate,
    int? maxWidth,
    int? maxHeight,
  );

  /// Stops forward buffering at [maxBufferMs] while the player is not
  /// playing; null removes the limit. Used for players prepared ahead of
  /// time so they do not download whole videos the user may never watch.
  void setPreloadBufferLimit(int playerId, int? maxBufferMs);

  PlatformNetworkStatus getNetworkStatus();

  @async
  PlatformCacheInfo getCacheInfo();

  /// Deletes every cached entry that is not being read right now.
  @async
  void clearCache();

  /// Deletes the cached data of one source (its cache key or URL).
  @async
  void removeCached(String cacheKey);

  /// Bytes of one source available in the cache.
  @async
  int getCachedBytes(String cacheKey);
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
    required this.isLive,
  });

  int playerId;
  int generation;

  /// Negative when the duration is unknown (for example live streams).
  int durationMs;

  bool isLive;
  double? frameRate;

  /// Bitrate of the selected video in bits per second, when known.
  int? bitrate;

  /// Video codec (RFC 6381 string or FourCC), when known.
  String? videoCodec;
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

/// Playback was requested (`true`) or stopped being requested (`false`), for
/// example by `play`, `pause`, reaching the end, or a system interruption.
/// Stalls while playback is requested are reported as
/// [PlatformPlaybackState.buffering], not as `isPlaying == false`.
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

/// The available or selected tracks changed. Read them with `getTracks`.
class PlatformTracksChangedEvent extends PlatformPlayerEvent {
  PlatformTracksChangedEvent({
    required this.playerId,
    required this.generation,
  });

  int playerId;
  int generation;
}

/// The subtitle text to show changed. An empty list clears the subtitles.
class PlatformCuesEvent extends PlatformPlayerEvent {
  PlatformCuesEvent({
    required this.playerId,
    required this.generation,
    required this.texts,
  });

  int playerId;
  int generation;
  List<String> texts;
}

/// Playback was paused (or resumed) by the system rather than by the app.
class PlatformInterruptionEvent extends PlatformPlayerEvent {
  PlatformInterruptionEvent({
    required this.playerId,
    required this.generation,
    required this.type,
    required this.ended,
  });

  int playerId;
  int generation;
  PlatformInterruptionType type;

  /// False when the interruption began, true when it ended.
  bool ended;
}

@EventChannelApi()
abstract class ReelKitEventApi {
  PlatformPlayerEvent playerEvents();

  /// Connectivity changes. The engine monitors the network only while this
  /// stream has a listener.
  PlatformNetworkStatus networkEvents();
}
