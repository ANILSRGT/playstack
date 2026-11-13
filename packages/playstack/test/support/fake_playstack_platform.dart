import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// In-memory engine that behaves like a native engine at the contract level:
/// it allocates numbered players, prepares sources asynchronously and emits
/// generation-tagged events.
class FakePlayStackPlatform extends PlayStackPlatform {
  FakePlayStackPlatform({
    this.recommendedMaxPlayers = 3,
    this.autoPrepare = true,
    this.supportsVideoQualityLimit = false,
    this.isLowRamDevice = false,
    this.supportsNetworkStatus = true,
    this.supportsDiskCache = false,
    this.videoInfo = const PlayStackVideoInfo(
      width: 1080,
      height: 1920,
      duration: Duration(seconds: 30),
    ),
  });

  final int recommendedMaxPlayers;
  final bool isLowRamDevice;
  final bool supportsNetworkStatus;
  final bool supportsDiskCache;

  /// Cached bytes per cache key.
  final Map<String, int> cache = <String, int>{};

  final List<PlayStackFullscreenRequest> fullscreenRequests =
      <PlayStackFullscreenRequest>[];
  final List<PlayStackFullscreenRestore> fullscreenRestores =
      <PlayStackFullscreenRestore>[];
  // Closed with the test process.
  // ignore: close_sinks
  final StreamController<bool> fullscreenEvents =
      StreamController<bool>.broadcast(sync: true);

  /// Reported by getNetworkStatus; change with [setNetwork].
  PlayStackNetworkStatus network = const PlayStackNetworkStatus(
    isConnected: true,
    type: PlayStackNetworkType.wifi,
  );

  final StreamController<PlayStackNetworkStatus> _network =
      StreamController<PlayStackNetworkStatus>.broadcast(sync: true);

  /// Buffer limit last applied per player.
  final Map<int, Duration?> bufferLimits = <int, Duration?>{};

  /// Sources whose setSource never answers (no event), for in-flight tests.
  final Set<PlayStackSource> hangingSources = <PlayStackSource>{};

  void setNetwork(PlayStackNetworkStatus status) {
    network = status;
    _network.add(status);
  }

  final PlayStackVideoInfo videoInfo;

  /// When true, every setSource is answered with an initialized event and a
  /// first-frame event.
  bool autoPrepare;
  bool supportsVideoQualityLimit;

  /// The last quality limit set on each player.
  final Map<int, PlayStackVideoQualityLimit> limits =
      <int, PlayStackVideoQualityLimit>{};

  /// Sources whose preparation fails with this error.
  final Map<PlayStackSource, PlayStackException> failingSources =
      <PlayStackSource, PlayStackException>{};

  /// Sources whose next preparation fails with this error; later attempts
  /// succeed.
  final Map<PlayStackSource, PlayStackException> failingOnce =
      <PlayStackSource, PlayStackException>{};

  /// When set, every call of the named method throws this error.
  final Map<String, PlayStackException> throwOn =
      <String, PlayStackException>{};

  /// Completes createPlayer calls; when null they complete immediately.
  Completer<void>? createGate;

  final StreamController<PlayStackPlatformEvent> _events =
      StreamController<PlayStackPlatformEvent>.broadcast(sync: true);

  /// Tracks reported for every prepared source.
  List<PlayStackTrack> trackList = const <PlayStackTrack>[];

  final List<String> calls = <String>[];
  final Set<int> livePlayers = <int>{};
  final Map<int, int> generations = <int, int>{};
  final Map<int, Duration> positions = <int, Duration>{};
  int initializeCalls = 0;
  int createCalls = 0;
  int maxLivePlayers = 0;
  int _nextId = 1;

  int callCount(String method) =>
      calls.where((c) => c.startsWith('$method(')).length;

  void emit(PlayStackPlatformEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  void _check(String method) {
    final error = throwOn[method];
    if (error != null) throw error;
  }

  PlayStackEngineConfig? engineConfig;

  @override
  Future<PlayStackPlatformCapabilities> initialize([
    PlayStackEngineConfig config = const PlayStackEngineConfig(),
  ]) async {
    engineConfig = config;
    initializeCalls++;
    _check('initialize');
    return PlayStackPlatformCapabilities(
      engineName: 'fake',
      engineVersion: '1.0',
      recommendedMaxPlayers: recommendedMaxPlayers,
      isLowRamDevice: isLowRamDevice,
      supportsHls: true,
      supportsDash: true,
      supportsDiskCache: supportsDiskCache,
      supportsMemorySource: false,
      supportsTrackSelection: false,
      supportsPreloadBufferLimit: true,
      supportsVideoQualityLimit: supportsVideoQualityLimit,
      supportsNetworkStatus: supportsNetworkStatus,
    );
  }

  @override
  Future<PlayStackNativePlayerHandle> createPlayer(
    PlayStackNativePlayerOptions options,
  ) async {
    createCalls++;
    _check('createPlayer');
    final gate = createGate;
    if (gate != null) await gate.future;
    final id = _nextId++;
    livePlayers.add(id);
    if (livePlayers.length > maxLivePlayers) {
      maxLivePlayers = livePlayers.length;
    }
    calls.add('createPlayer($id)');
    return PlayStackNativePlayerHandle(playerId: id, textureId: 100 + id);
  }

  @override
  Future<void> disposePlayer(int playerId) async {
    calls.add('disposePlayer($playerId)');
    livePlayers.remove(playerId);
  }

  void _requireLive(int playerId) {
    if (!livePlayers.contains(playerId)) {
      throw PlayStackException(
        PlayStackErrorCode.playerNotFound,
        'Player $playerId is not alive.',
      );
    }
  }

  @override
  Future<void> setSource(
    int playerId,
    PlayStackSource source,
    int generation,
  ) async {
    calls.add('setSource($playerId, ${source.description}, $generation)');
    _check('setSource');
    _requireLive(playerId);
    generations[playerId] = generation;
    positions[playerId] = Duration.zero;
    final failure = failingSources[source] ?? failingOnce.remove(source);
    if (failure != null) {
      scheduleMicrotask(
        () => emit(
          PlayStackErrorEvent(
            playerId: playerId,
            generation: generation,
            error: failure,
          ),
        ),
      );
      return;
    }
    if (!autoPrepare || hangingSources.contains(source)) return;
    scheduleMicrotask(() {
      emit(
        PlayStackInitializedEvent(
          playerId: playerId,
          generation: generation,
          info: videoInfo,
        ),
      );
      emit(
        PlayStackFirstFrameEvent(playerId: playerId, generation: generation),
      );
    });
  }

  @override
  Future<void> clearSource(int playerId) async {
    calls.add('clearSource($playerId)');
    _check('clearSource');
    _requireLive(playerId);
    generations.remove(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play($playerId)');
    _check('play');
    _requireLive(playerId);
    final generation = generations[playerId]!;
    scheduleMicrotask(
      () => emit(
        PlayStackIsPlayingEvent(
          playerId: playerId,
          generation: generation,
          isPlaying: true,
        ),
      ),
    );
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause($playerId)');
    _check('pause');
    _requireLive(playerId);
    final generation = generations[playerId]!;
    scheduleMicrotask(
      () => emit(
        PlayStackIsPlayingEvent(
          playerId: playerId,
          generation: generation,
          isPlaying: false,
        ),
      ),
    );
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seekTo($playerId, ${position.inMilliseconds})');
    _check('seekTo');
    _requireLive(playerId);
    positions[playerId] = position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('setLooping($playerId, $looping)');
    _check('setLooping');
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    calls.add('setVolume($playerId, $volume)');
    _check('setVolume');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    calls.add('setPlaybackSpeed($playerId, $speed)');
    _check('setPlaybackSpeed');
  }

  @override
  Future<PlayStackPositionSnapshot> getPosition(int playerId) async {
    _requireLive(playerId);
    final position = positions[playerId] ?? Duration.zero;
    return PlayStackPositionSnapshot(position: position, buffered: position);
  }

  @override
  Future<List<PlayStackTrack>> getTracks(int playerId) async {
    calls.add('getTracks($playerId)');
    _requireLive(playerId);
    return trackList;
  }

  @override
  Future<void> selectTrack(
    int playerId,
    PlayStackTrackType type,
    String? trackId,
  ) async {
    calls.add('selectTrack($playerId, ${type.name}, $trackId)');
    _check('selectTrack');
    _requireLive(playerId);
    trackList = [
      for (final t in trackList)
        t.type == type
            ? PlayStackTrack(
                id: t.id,
                type: t.type,
                isSelected: t.id == trackId,
                language: t.language,
              )
            : t,
    ];
  }

  @override
  Future<void> setVideoQualityLimit(
    int playerId,
    PlayStackVideoQualityLimit limit,
  ) async {
    calls.add(
      'setVideoQualityLimit($playerId, ${limit.maxHeight}, ${limit.maxBitrate})',
    );
    limits[playerId] = limit;
    _check('setVideoQualityLimit');
    _requireLive(playerId);
  }

  @override
  Future<void> setPreloadBufferLimit(int playerId, Duration? limit) async {
    calls.add('setPreloadBufferLimit($playerId, ${limit?.inMilliseconds})');
    _requireLive(playerId);
    bufferLimits[playerId] = limit;
  }

  @override
  Future<PlayStackNetworkStatus> getNetworkStatus() async => network;

  @override
  Future<PlayStackCacheInfo> getCacheInfo() async => PlayStackCacheInfo(
    enabled: engineConfig?.cacheEnabled ?? false,
    usedBytes: cache.values.fold(0, (a, b) => a + b),
    maxBytes: engineConfig?.cacheMaxBytes ?? 0,
  );

  @override
  Future<void> clearCache() async => cache.clear();

  @override
  Future<void> removeCached(String cacheKey) async => cache.remove(cacheKey);

  @override
  Future<int> getCachedBytes(String cacheKey) async => cache[cacheKey] ?? 0;

  @override
  Future<void> enterFullscreen(PlayStackFullscreenRequest request) async =>
      fullscreenRequests.add(request);

  @override
  Future<void> exitFullscreen(PlayStackFullscreenRestore restore) async =>
      fullscreenRestores.add(restore);

  @override
  Stream<bool> get fullscreenChanges => fullscreenEvents.stream;

  @override
  Stream<PlayStackNetworkStatus> get networkStatusChanges => _network.stream;

  @override
  Stream<PlayStackPlatformEvent> get events => _events.stream;

  @override
  Widget buildView(int playerId) =>
      SizedBox(key: ValueKey<String>('native-view-$playerId'));
}

/// Lets queued microtasks and zero-delay timers run.
Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
