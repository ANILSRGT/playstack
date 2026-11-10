import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import 'messages.g.dart';

/// Android implementation of [ReelKitPlatform].
///
/// Video frames are rendered into a Flutter `SurfaceProducer` texture by the
/// native engine; only commands and state transitions cross the channel.
class ReelKitAndroid extends ReelKitPlatform {
  /// Creates the Android engine. [api] and [eventStream] exist for tests.
  ReelKitAndroid({
    @visibleForTesting ReelKitHostApi? api,
    @visibleForTesting Stream<PlatformPlayerEvent>? eventStream,
  }) : _api = api ?? ReelKitHostApi(),
       _rawEvents = eventStream;

  /// Registers this class as the default [ReelKitPlatform] implementation.
  static void registerWith() {
    ReelKitPlatform.instance = ReelKitAndroid();
  }

  final ReelKitHostApi _api;
  final Stream<PlatformPlayerEvent>? _rawEvents;
  final Map<int, int> _textureIds = <int, int>{};
  Stream<ReelPlatformEvent>? _events;

  @override
  Future<ReelPlatformCapabilities> initialize() async {
    final caps = await _guard(_api.initialize);
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
      ),
      ReelFileSource() => PlatformSource(
        type: PlatformSourceType.file,
        uri: source.path,
        formatHint: format,
        httpHeaders: const <String, String>{},
      ),
      ReelAssetSource() => PlatformSource(
        type: PlatformSourceType.asset,
        assetName: source.assetName,
        assetPackage: source.package,
        formatHint: format,
        httpHeaders: const <String, String>{},
      ),
      ReelMemorySource() => PlatformSource(
        type: PlatformSourceType.memory,
        bytes: source.bytes,
        mimeType: source.mimeType,
        formatHint: format,
        httpHeaders: const <String, String>{},
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
