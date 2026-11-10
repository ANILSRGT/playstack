import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import 'messages.g.dart';

/// Android implementation of [ReelKitPlatform].
///
/// Video frames are rendered into a Flutter `SurfaceProducer` texture by the
/// native engine; only commands and state transitions cross the channel.
class ReelKitAndroid extends ReelKitPlatform with SystemChromeFullscreen {
  /// Creates the Android engine. [api] and [eventStream] exist for tests.
  ReelKitAndroid({
    @visibleForTesting ReelKitHostApi? api,
    @visibleForTesting Stream<PlatformPlayerEvent>? eventStream,
    @visibleForTesting Stream<PlatformNetworkStatus>? networkStream,
  }) : _api = api ?? ReelKitHostApi(),
       _rawEvents = eventStream,
       _rawNetworkEvents = networkStream;

  /// Registers this class as the default [ReelKitPlatform] implementation.
  static void registerWith() {
    ReelKitPlatform.instance = ReelKitAndroid();
  }

  final ReelKitHostApi _api;
  final Stream<PlatformPlayerEvent>? _rawEvents;
  final Stream<PlatformNetworkStatus>? _rawNetworkEvents;
  final Map<int, int> _textureIds = <int, int>{};
  Stream<ReelPlatformEvent>? _events;

  @override
  Future<ReelPlatformCapabilities> initialize([
    ReelEngineConfig config = const ReelEngineConfig(),
  ]) async {
    final caps = await _guard(
      () => _api.initialize(
        PlatformEngineConfig(
          cacheEnabled: config.cacheEnabled,
          cacheMaxBytes: config.cacheMaxBytes,
          handleAudioFocus: config.handleAudioFocus,
          pauseOnAudioRouteLoss: config.pauseOnAudioRouteLoss,
          audioSessionCategory: switch (config.audioSessionCategory) {
            ReelAudioSessionCategory.unmanaged =>
              PlatformAudioSessionCategory.unmanaged,
            ReelAudioSessionCategory.ambient =>
              PlatformAudioSessionCategory.ambient,
            ReelAudioSessionCategory.playback =>
              PlatformAudioSessionCategory.playback,
          },
          mixWithOthers: config.mixWithOthers,
          resumeAfterInterruption: config.resumeAfterInterruption,
        ),
      ),
    );
    return ReelPlatformCapabilities(
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
  Future<ReelNativePlayerHandle> createPlayer(
    ReelNativePlayerOptions options,
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
    return ReelNativePlayerHandle(
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
  Future<void> setSource(int playerId, ReelSource source, int generation) {
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
  Future<ReelPositionSnapshot> getPosition(int playerId) async {
    final position = await _guard(() => _api.getPosition(playerId));
    return ReelPositionSnapshot(
      position: Duration(milliseconds: position.positionMs),
      buffered: Duration(milliseconds: position.bufferedMs),
    );
  }

  @override
  Future<List<ReelTrack>> getTracks(int playerId) async {
    final tracks = await _guard(() => _api.getTracks(playerId));
    return [
      for (final t in tracks)
        ReelTrack(
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
  Future<void> selectTrack(int playerId, ReelTrackType type, String? trackId) =>
      _guard(
        () => _api.selectTrack(playerId, _toPlatformTrackType(type), trackId),
      );

  @override
  Future<void> setVideoQualityLimit(
    int playerId,
    ReelVideoQualityLimit limit,
  ) => _guard(
    () => _api.setVideoQualityLimit(
      playerId,
      limit.maxBitrate,
      limit.maxWidth,
      limit.maxHeight,
    ),
  );

  @override
  Future<ReelCacheInfo> getCacheInfo() async {
    final info = await _guard(_api.getCacheInfo);
    return ReelCacheInfo(
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
  Future<ReelNetworkStatus> getNetworkStatus() async =>
      _toNetworkStatus(await _guard(_api.getNetworkStatus));

  @override
  Stream<ReelNetworkStatus> get networkStatusChanges =>
      (_rawNetworkEvents ?? networkEvents()).map(_toNetworkStatus);

  static ReelNetworkStatus _toNetworkStatus(PlatformNetworkStatus status) =>
      ReelNetworkStatus(
        isConnected: status.isConnected,
        isMetered: status.isMetered,
        isConstrained: status.isConstrained,
        type: switch (status.type) {
          PlatformNetworkType.none => ReelNetworkType.none,
          PlatformNetworkType.wifi => ReelNetworkType.wifi,
          PlatformNetworkType.cellular => ReelNetworkType.cellular,
          PlatformNetworkType.ethernet => ReelNetworkType.ethernet,
          PlatformNetworkType.other => ReelNetworkType.other,
          PlatformNetworkType.unknown => ReelNetworkType.unknown,
        },
      );

  static ReelTrackType _fromPlatformTrackType(PlatformTrackType type) =>
      switch (type) {
        PlatformTrackType.audio => ReelTrackType.audio,
        PlatformTrackType.video => ReelTrackType.video,
        PlatformTrackType.text => ReelTrackType.text,
      };

  static PlatformTrackType _toPlatformTrackType(ReelTrackType type) =>
      switch (type) {
        ReelTrackType.audio => PlatformTrackType.audio,
        ReelTrackType.video => PlatformTrackType.video,
        ReelTrackType.text => PlatformTrackType.text,
      };

  @override
  Stream<ReelPlatformEvent> get events => _events ??=
      (_rawEvents ?? playerEvents()).map(_toReelEvent).asBroadcastStream();

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
      throw ReelKitException.fromPlatformException(error);
    }
  }

  static PlatformSource _toPlatformSource(ReelSource source) {
    final format = switch (source.resolvedFormat) {
      ReelVideoFormat.auto => PlatformVideoFormat.auto,
      ReelVideoFormat.progressive => PlatformVideoFormat.progressive,
      ReelVideoFormat.hls => PlatformVideoFormat.hls,
      ReelVideoFormat.dash => PlatformVideoFormat.dash,
    };
    return switch (source) {
      ReelNetworkSource() => PlatformSource(
        type: PlatformSourceType.network,
        uri: source.url,
        mimeType: source.mimeType,
        formatHint: format,
        httpHeaders: source.headers,
        cacheKey: source.effectiveCacheKey,
        useCache: source.cachePolicy == ReelCachePolicy.cache,
      ),
      ReelFileSource() => PlatformSource(
        type: PlatformSourceType.file,
        uri: source.path,
        formatHint: format,
        httpHeaders: const <String, String>{},
        useCache: false,
      ),
      ReelAssetSource() => PlatformSource(
        type: PlatformSourceType.asset,
        assetName: source.assetName,
        assetPackage: source.package,
        formatHint: format,
        httpHeaders: const <String, String>{},
        useCache: false,
      ),
      ReelMemorySource() => PlatformSource(
        type: PlatformSourceType.memory,
        bytes: source.bytes,
        mimeType: source.mimeType,
        formatHint: format,
        httpHeaders: const <String, String>{},
        useCache: false,
      ),
    };
  }

  static ReelPlatformEvent _toReelEvent(PlatformPlayerEvent event) {
    return switch (event) {
      PlatformInitializedEvent() => ReelInitializedEvent(
        playerId: event.playerId,
        generation: event.generation,
        info: ReelVideoInfo(
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
      PlatformStateEvent() => ReelNativeStateEvent(
        playerId: event.playerId,
        generation: event.generation,
        state: switch (event.state) {
          PlatformPlaybackState.idle => ReelNativePlaybackState.idle,
          PlatformPlaybackState.buffering => ReelNativePlaybackState.buffering,
          PlatformPlaybackState.ready => ReelNativePlaybackState.ready,
          PlatformPlaybackState.ended => ReelNativePlaybackState.ended,
        },
      ),
      PlatformInterruptionEvent() => ReelInterruptionEvent(
        playerId: event.playerId,
        generation: event.generation,
        type: switch (event.type) {
          PlatformInterruptionType.audioInterruption =>
            ReelInterruptionType.audioInterruption,
          PlatformInterruptionType.audioRouteLost =>
            ReelInterruptionType.audioRouteLost,
        },
        ended: event.ended,
      ),
      PlatformIsPlayingEvent() => ReelIsPlayingEvent(
        playerId: event.playerId,
        generation: event.generation,
        isPlaying: event.isPlaying,
      ),
      PlatformVideoSizeEvent() => ReelVideoSizeEvent(
        playerId: event.playerId,
        generation: event.generation,
        width: event.width,
        height: event.height,
        rotationDegrees: event.rotationDegrees,
        pixelAspectRatio: event.pixelAspectRatio,
      ),
      PlatformFirstFrameEvent() => ReelFirstFrameEvent(
        playerId: event.playerId,
        generation: event.generation,
      ),
      PlatformTracksChangedEvent() => ReelTracksChangedEvent(
        playerId: event.playerId,
        generation: event.generation,
      ),
      PlatformCuesEvent() => ReelCuesEvent(
        playerId: event.playerId,
        generation: event.generation,
        texts: List<String>.unmodifiable(event.texts),
      ),
      PlatformErrorEvent() => ReelErrorEvent(
        playerId: event.playerId,
        generation: event.generation,
        error: ReelKitException(
          ReelKitException.codeFromName(event.code),
          event.message,
          details: event.details,
        ),
      ),
    };
  }
}
