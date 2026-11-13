import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import 'messages.g.dart';
import 'messages.g.dart' as pigeon show systemEvents;

/// Android implementation of [PlayStackPlatform].
///
/// Video frames are rendered into a Flutter `SurfaceProducer` texture by the
/// native engine; only commands and state transitions cross the channel.
class PlayStackAndroid extends PlayStackPlatform with SystemChromeFullscreen {
  /// Creates the Android engine. [api] and [eventStream] exist for tests.
  PlayStackAndroid({
    @visibleForTesting PlayStackHostApi? api,
    @visibleForTesting Stream<PlatformPlayerEvent>? eventStream,
    @visibleForTesting Stream<PlatformNetworkStatus>? networkStream,
    @visibleForTesting
    Stream<PlatformDeviceOrientationEvent>? deviceOrientationStream,
    @visibleForTesting Stream<PlatformSystemEvent>? systemStream,
  }) : _rawSystemEvents = systemStream,
       _api = api ?? PlayStackHostApi(),
       _rawEvents = eventStream,
       _rawNetworkEvents = networkStream,
       _rawDeviceOrientations = deviceOrientationStream;

  /// Registers this class as the default [PlayStackPlatform] implementation.
  static void registerWith() {
    PlayStackPlatform.instance = PlayStackAndroid();
  }

  final PlayStackHostApi _api;
  final Stream<PlatformPlayerEvent>? _rawEvents;
  final Stream<PlatformNetworkStatus>? _rawNetworkEvents;
  final Stream<PlatformDeviceOrientationEvent>? _rawDeviceOrientations;
  final Stream<PlatformSystemEvent>? _rawSystemEvents;
  final Map<int, int> _textureIds = <int, int>{};
  Stream<PlayStackPlatformEvent>? _events;

  @override
  Future<PlayStackPlatformCapabilities> initialize([
    PlayStackEngineConfig config = const PlayStackEngineConfig(),
  ]) async {
    final caps = await _guard(
      () => _api.initialize(
        PlatformEngineConfig(
          cacheEnabled: config.cacheEnabled,
          cacheMaxBytes: config.cacheMaxBytes,
          handleAudioFocus: config.handleAudioFocus,
          pauseOnAudioRouteLoss: config.pauseOnAudioRouteLoss,
          audioSessionCategory: switch (config.audioSessionCategory) {
            PlayStackAudioSessionCategory.unmanaged =>
              PlatformAudioSessionCategory.unmanaged,
            PlayStackAudioSessionCategory.ambient =>
              PlatformAudioSessionCategory.ambient,
            PlayStackAudioSessionCategory.playback =>
              PlatformAudioSessionCategory.playback,
          },
          mixWithOthers: config.mixWithOthers,
          resumeAfterInterruption: config.resumeAfterInterruption,
        ),
      ),
    );
    return PlayStackPlatformCapabilities(
      engineName: caps.engineName,
      engineVersion: caps.engineVersion,
      recommendedMaxPlayers: caps.recommendedMaxPlayers,
      maxHardwareDecoderInstances: caps.maxHardwareDecoderInstances,
      totalMemoryBytes: caps.totalMemoryBytes,
      isLowRamDevice: caps.isLowRamDevice,
      supportsHls: caps.supportsHls,
      supportsDash: caps.supportsDash,
      supportsDiskCache: caps.supportsDiskCache,
      supportsMemorySource: caps.supportsMemorySource,
      supportsTrackSelection: caps.supportsTrackSelection,
      supportsVideoTrackSelection: caps.supportsVideoTrackSelection,
      supportsVideoQualityLimit: caps.supportsVideoQualityLimit,
      supportsPreloadBufferLimit: caps.supportsPreloadBufferLimit,
      supportsNetworkStatus: caps.supportsNetworkStatus,
    );
  }

  @override
  Future<PlayStackNativePlayerHandle> createPlayer(
    PlayStackNativePlayerOptions options,
  ) async {
    final created = await _guard(
      () => _api.createPlayer(
        PlatformPlayerOptions(
          looping: options.looping,
          volume: options.volume,
          playbackSpeed: options.playbackSpeed,
        ),
      ),
    );
    _textureIds[created.playerId] = created.textureId;
    return PlayStackNativePlayerHandle(
      playerId: created.playerId,
      textureId: created.textureId,
    );
  }

  @override
  Future<void> disposePlayer(int playerId) async {
    _textureIds.remove(playerId);
    await _guard(() => _api.disposePlayer(playerId));
  }

  @override
  Future<void> setSource(int playerId, PlayStackSource source, int generation) {
    return _guard(
      () => _api.setSource(playerId, _toPlatformSource(source), generation),
    );
  }

  @override
  Future<void> clearSource(int playerId) =>
      _guard(() => _api.clearSource(playerId));

  @override
  Future<void> play(int playerId) => _guard(() => _api.play(playerId));

  @override
  Future<void> pause(int playerId) => _guard(() => _api.pause(playerId));

  @override
  Future<void> seekTo(int playerId, Duration position) =>
      _guard(() => _api.seekTo(playerId, position.inMilliseconds));

  @override
  Future<void> setLooping(int playerId, bool looping) =>
      _guard(() => _api.setLooping(playerId, looping));

  @override
  Future<void> setVolume(int playerId, double volume) =>
      _guard(() => _api.setVolume(playerId, volume));

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) =>
      _guard(() => _api.setPlaybackSpeed(playerId, speed));

  @override
  Future<PlayStackPositionSnapshot> getPosition(int playerId) async {
    final position = await _guard(() => _api.getPosition(playerId));
    return PlayStackPositionSnapshot(
      position: Duration(milliseconds: position.positionMs),
      buffered: Duration(milliseconds: position.bufferedMs),
    );
  }

  @override
  Future<List<PlayStackTrack>> getTracks(int playerId) async {
    final tracks = await _guard(() => _api.getTracks(playerId));
    return [
      for (final t in tracks)
        PlayStackTrack(
          id: t.id,
          type: _fromPlatformTrackType(t.type),
          isSelected: t.isSelected,
          label: t.label,
          language: t.language,
          bitrate: t.bitrate,
          width: t.width,
          height: t.height,
          frameRate: t.frameRate,
          codecs: t.codecs,
          channelCount: t.channelCount,
        ),
    ];
  }

  @override
  Future<void> selectTrack(
    int playerId,
    PlayStackTrackType type,
    String? trackId,
  ) => _guard(
    () => _api.selectTrack(playerId, _toPlatformTrackType(type), trackId),
  );

  @override
  Future<void> setVideoQualityLimit(
    int playerId,
    PlayStackVideoQualityLimit limit,
  ) => _guard(
    () => _api.setVideoQualityLimit(
      playerId,
      limit.maxBitrate,
      limit.maxWidth,
      limit.maxHeight,
    ),
  );

  @override
  Future<PlayStackCacheInfo> getCacheInfo() async {
    final info = await _guard(_api.getCacheInfo);
    return PlayStackCacheInfo(
      enabled: info.enabled,
      usedBytes: info.usedBytes,
      maxBytes: info.maxBytes,
    );
  }

  @override
  Future<void> clearCache() => _guard(_api.clearCache);

  @override
  Future<void> removeCached(String cacheKey) =>
      _guard(() => _api.removeCached(cacheKey));

  @override
  Future<int> getCachedBytes(String cacheKey) =>
      _guard(() => _api.getCachedBytes(cacheKey));

  @override
  Future<void> setPreloadBufferLimit(int playerId, Duration? limit) =>
      _guard(() => _api.setPreloadBufferLimit(playerId, limit?.inMilliseconds));

  @override
  Future<PlayStackNetworkStatus> getNetworkStatus() async =>
      _toNetworkStatus(await _guard(_api.getNetworkStatus));

  @override
  Stream<PlayStackNetworkStatus> get networkStatusChanges =>
      (_rawNetworkEvents ?? networkEvents()).map(_toNetworkStatus);

  @override
  Future<void> setMediaSession(
    int? playerId,
    PlayStackMediaInfo? info, {
    bool canSkipNext = false,
    bool canSkipPrevious = false,
  }) => _guard(
    () => _api.setMediaSession(
      playerId,
      info == null
          ? null
          : PlatformMediaInfo(
              title: info.title,
              artist: info.artist,
              album: info.album,
              artworkUrl: info.artworkUrl,
              canSkipNext: canSkipNext,
              canSkipPrevious: canSkipPrevious,
            ),
    ),
  );

  @override
  Future<void> setPictureInPicture(int? playerId, {required bool autoEnter}) =>
      _guard(() => _api.setPictureInPicture(playerId, autoEnter));

  @override
  Future<bool> startPictureInPicture() => _guard(_api.startPictureInPicture);

  @override
  Future<void> stopPictureInPicture() => _guard(_api.stopPictureInPicture);

  @override
  Future<bool> isPictureInPictureSupported() =>
      _guard(_api.isPictureInPictureSupported);

  @override
  Stream<PlayStackSystemEvent> get systemEvents =>
      (_rawSystemEvents ?? pigeon.systemEvents()).map(
        (event) => PlayStackSystemEvent(
          switch (event.type) {
            PlatformSystemEventType.play => PlayStackSystemEventType.play,
            PlatformSystemEventType.pause => PlayStackSystemEventType.pause,
            PlatformSystemEventType.seek => PlayStackSystemEventType.seek,
            PlatformSystemEventType.next => PlayStackSystemEventType.next,
            PlatformSystemEventType.previous =>
              PlayStackSystemEventType.previous,
            PlatformSystemEventType.pictureInPictureStarted =>
              PlayStackSystemEventType.pictureInPictureStarted,
            PlatformSystemEventType.pictureInPictureStopped =>
              PlayStackSystemEventType.pictureInPictureStopped,
          },
          position: event.positionMs == null
              ? null
              : Duration(milliseconds: event.positionMs!),
        ),
      );

  @override
  Stream<DeviceOrientation> get deviceOrientationChanges =>
      (_rawDeviceOrientations ?? deviceOrientationEvents()).map(
        (event) => _toDeviceOrientation(event.orientation),
      );

  @override
  Future<List<DeviceOrientation>?> getAppOrientations() async {
    final orientations = await _guard(_api.getAppOrientations);
    return [for (final o in orientations) _toDeviceOrientation(o)];
  }

  static DeviceOrientation _toDeviceOrientation(
    PlatformOrientation orientation,
  ) => switch (orientation) {
    PlatformOrientation.portraitUp => DeviceOrientation.portraitUp,
    PlatformOrientation.portraitDown => DeviceOrientation.portraitDown,
    PlatformOrientation.landscapeLeft => DeviceOrientation.landscapeLeft,
    PlatformOrientation.landscapeRight => DeviceOrientation.landscapeRight,
  };

  static PlayStackNetworkStatus _toNetworkStatus(
    PlatformNetworkStatus status,
  ) => PlayStackNetworkStatus(
    isConnected: status.isConnected,
    isMetered: status.isMetered,
    isConstrained: status.isConstrained,
    type: switch (status.type) {
      PlatformNetworkType.none => PlayStackNetworkType.none,
      PlatformNetworkType.wifi => PlayStackNetworkType.wifi,
      PlatformNetworkType.cellular => PlayStackNetworkType.cellular,
      PlatformNetworkType.ethernet => PlayStackNetworkType.ethernet,
      PlatformNetworkType.other => PlayStackNetworkType.other,
      PlatformNetworkType.unknown => PlayStackNetworkType.unknown,
    },
  );

  static PlayStackTrackType _fromPlatformTrackType(PlatformTrackType type) =>
      switch (type) {
        PlatformTrackType.audio => PlayStackTrackType.audio,
        PlatformTrackType.video => PlayStackTrackType.video,
        PlatformTrackType.text => PlayStackTrackType.text,
      };

  static PlatformTrackType _toPlatformTrackType(PlayStackTrackType type) =>
      switch (type) {
        PlayStackTrackType.audio => PlatformTrackType.audio,
        PlayStackTrackType.video => PlatformTrackType.video,
        PlayStackTrackType.text => PlatformTrackType.text,
      };

  @override
  Stream<PlayStackPlatformEvent> get events => _events ??=
      (_rawEvents ?? playerEvents()).map(_toPlayStackEvent).asBroadcastStream();

  @override
  Widget buildView(int playerId) {
    final textureId = _textureIds[playerId];
    if (textureId == null) return const SizedBox.shrink();
    return Texture(textureId: textureId);
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      throw PlayStackException.fromPlatformException(error);
    }
  }

  static PlatformSource _toPlatformSource(PlayStackSource source) {
    final format = switch (source.resolvedFormat) {
      PlayStackVideoFormat.auto => PlatformVideoFormat.auto,
      PlayStackVideoFormat.progressive => PlatformVideoFormat.progressive,
      PlayStackVideoFormat.hls => PlatformVideoFormat.hls,
      PlayStackVideoFormat.dash => PlatformVideoFormat.dash,
    };
    return switch (source) {
      PlayStackNetworkSource() => PlatformSource(
        type: PlatformSourceType.network,
        uri: source.url,
        mimeType: source.mimeType,
        formatHint: format,
        httpHeaders: source.headers,
        cacheKey: source.effectiveCacheKey,
        useCache: source.cachePolicy == PlayStackCachePolicy.cache,
      ),
      PlayStackFileSource() => PlatformSource(
        type: PlatformSourceType.file,
        uri: source.path,
        formatHint: format,
        httpHeaders: const <String, String>{},
        useCache: false,
      ),
      PlayStackAssetSource() => PlatformSource(
        type: PlatformSourceType.asset,
        assetName: source.assetName,
        assetPackage: source.package,
        formatHint: format,
        httpHeaders: const <String, String>{},
        useCache: false,
      ),
      PlayStackMemorySource() => PlatformSource(
        type: PlatformSourceType.memory,
        bytes: source.bytes,
        mimeType: source.mimeType,
        formatHint: format,
        httpHeaders: const <String, String>{},
        useCache: false,
      ),
    };
  }

  static PlayStackPlatformEvent _toPlayStackEvent(PlatformPlayerEvent event) {
    return switch (event) {
      PlatformInitializedEvent() => PlayStackInitializedEvent(
        playerId: event.playerId,
        generation: event.generation,
        info: PlayStackVideoInfo(
          width: event.width,
          height: event.height,
          duration: event.durationMs < 0
              ? null
              : Duration(milliseconds: event.durationMs),
          rotationDegrees: event.rotationDegrees,
          pixelAspectRatio: event.pixelAspectRatio,
          isLive: event.isLive,
          frameRate: event.frameRate,
          bitrate: event.bitrate,
          videoCodec: event.videoCodec,
        ),
      ),
      PlatformStateEvent() => PlayStackNativeStateEvent(
        playerId: event.playerId,
        generation: event.generation,
        state: switch (event.state) {
          PlatformPlaybackState.idle => PlayStackNativePlaybackState.idle,
          PlatformPlaybackState.buffering =>
            PlayStackNativePlaybackState.buffering,
          PlatformPlaybackState.ready => PlayStackNativePlaybackState.ready,
          PlatformPlaybackState.ended => PlayStackNativePlaybackState.ended,
        },
      ),
      PlatformInterruptionEvent() => PlayStackInterruptionEvent(
        playerId: event.playerId,
        generation: event.generation,
        type: switch (event.type) {
          PlatformInterruptionType.audioInterruption =>
            PlayStackInterruptionType.audioInterruption,
          PlatformInterruptionType.audioRouteLost =>
            PlayStackInterruptionType.audioRouteLost,
        },
        ended: event.ended,
      ),
      PlatformIsPlayingEvent() => PlayStackIsPlayingEvent(
        playerId: event.playerId,
        generation: event.generation,
        isPlaying: event.isPlaying,
      ),
      PlatformVideoSizeEvent() => PlayStackVideoSizeEvent(
        playerId: event.playerId,
        generation: event.generation,
        width: event.width,
        height: event.height,
        rotationDegrees: event.rotationDegrees,
        pixelAspectRatio: event.pixelAspectRatio,
      ),
      PlatformFirstFrameEvent() => PlayStackFirstFrameEvent(
        playerId: event.playerId,
        generation: event.generation,
      ),
      PlatformTracksChangedEvent() => PlayStackTracksChangedEvent(
        playerId: event.playerId,
        generation: event.generation,
      ),
      PlatformCuesEvent() => PlayStackCuesEvent(
        playerId: event.playerId,
        generation: event.generation,
        texts: List<String>.unmodifiable(event.texts),
      ),
      PlatformErrorEvent() => PlayStackErrorEvent(
        playerId: event.playerId,
        generation: event.generation,
        error: PlayStackException(
          PlayStackException.codeFromName(event.code),
          event.message,
          details: event.details,
        ),
      ),
    };
  }
}
