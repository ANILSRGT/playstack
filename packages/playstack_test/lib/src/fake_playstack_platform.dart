import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// A video engine for tests: it behaves like the native engines at the
/// contract level (numbered players, sources prepared asynchronously,
/// events, downloads, media controls) without a device.
///
/// Install it before the widget under test creates a `PlayStackManager`
/// or a `PlayStackFeedView`:
///
/// ```dart
/// testWidgets('the feed plays the first video', (tester) async {
///   final engine = FakePlayStackPlatform.install();
///   await tester.pumpWidget(MaterialApp(home: MyReelsScreen()));
///   await tester.pumpPlayStack();
///   expect(engine.calls, contains('play(1)'));
/// });
/// ```
///
/// Change its behaviour with the constructor arguments and the public
/// fields: [failingSources] fails a source, [setNetwork] goes offline,
/// [positions] moves the playback position, [emit] sends any event.
class FakePlayStackPlatform extends PlayStackPlatform {
  /// Creates a fake engine with the default settings and makes it the
  /// engine PlayStack uses.
  static FakePlayStackPlatform install() => FakePlayStackPlatform().register();

  /// Creates a fake engine. See [install] to make it the engine PlayStack
  /// uses.
  FakePlayStackPlatform({
    this.recommendedMaxPlayers = 3,
    this.autoPrepare = true,
    this.supportsVideoQualityLimit = false,
    this.isLowRamDevice = false,
    this.supportsNetworkStatus = true,
    this.supportsDiskCache = false,
    this.supportsDeviceOrientation = false,
    this.videoInfo = const PlayStackVideoInfo(
      width: 1080,
      height: 1920,
      duration: Duration(seconds: 30),
    ),
  });

  /// Reported as the recommended player count.
  final int recommendedMaxPlayers;
  /// Reported as a low-memory device.
  final bool isLowRamDevice;
  /// Whether the network status is reported.
  final bool supportsNetworkStatus;
  /// Whether the disk cache is reported as supported.
  final bool supportsDiskCache;

  /// Whether [deviceOrientationChanges] exists, as on Android and iOS.
  final bool supportsDeviceOrientation;

  /// Sends how the user holds the device; see [supportsDeviceOrientation].
  // Closed with the test process.
  // ignore: close_sinks
  final StreamController<DeviceOrientation> deviceOrientations =
      StreamController<DeviceOrientation>.broadcast(sync: true);

  /// Returned by getAppOrientations.
  List<DeviceOrientation>? appOrientations;

  /// Cached bytes per cache key.
  final Map<String, int> cache = <String, int>{};

  /// Every enterFullscreen request, in order.
  final List<PlayStackFullscreenRequest> fullscreenRequests =
      <PlayStackFullscreenRequest>[];
  /// Every exitFullscreen request, in order.
  final List<PlayStackFullscreenRestore> fullscreenRestores =
      <PlayStackFullscreenRestore>[];
  // Closed with the test process.
  /// Sends fullscreen changes made outside the app (browser fullscreen).
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

  /// Changes the network status and reports it, for offline tests.
  void setNetwork(PlayStackNetworkStatus status) {
    network = status;
    _network.add(status);
  }

  /// What every prepared source reports: size and duration.
  final PlayStackVideoInfo videoInfo;

  /// When true, every setSource is answered with an initialized event and a
  /// first-frame event.
  bool autoPrepare;
  /// Whether quality limits are reported as supported.
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

  /// Every engine call as text, such as `play(1)` or `seekTo(1, 5000)`.
  final List<String> calls = <String>[];
  /// The ids of the players that exist now.
  final Set<int> livePlayers = <int>{};
  /// The current source generation per player.
  final Map<int, int> generations = <int, int>{};
  /// The live edge per player, for live streams.
  final Map<int, Duration> liveEdges = <int, Duration>{};

  /// The playback position per player; set it to move playback.
  final Map<int, Duration> positions = <int, Duration>{};
  /// How often initialize was called.
  int initializeCalls = 0;
  /// How many players were created.
  int createCalls = 0;
  /// The most players that existed at the same time.
  int maxLivePlayers = 0;
  int _nextId = 1;

  /// How many [calls] were made to [method].
  int callCount(String method) =>
      calls.where((c) => c.startsWith('$method(')).length;

  /// Sends an engine event, such as an error or the end of a video.
  void emit(PlayStackPlatformEvent event) => _events.add(event);

  /// Closes the event stream.
  Future<void> close() => _events.close();

  void _check(String method) {
    final error = throwOn[method];
    if (error != null) throw error;
  }

  /// The configuration initialize received.
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
  Future<void> setVideoDisabled(int playerId, bool disabled) async {
    calls.add('setVideoDisabled($playerId, $disabled)');
    _check('setVideoDisabled');
  }

  @override
  Future<void> seekToLiveEdge(int playerId) async {
    calls.add('seekToLiveEdge($playerId)');
    _check('seekToLiveEdge');
    final edge = liveEdges[playerId];
    if (edge != null) positions[playerId] = edge;
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
    final edge = liveEdges[playerId];
    return PlayStackPositionSnapshot(
      position: position,
      buffered: position,
      windowStart: edge == null ? null : Duration.zero,
      liveEdge: edge,
    );
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
  Stream<DeviceOrientation> get deviceOrientationChanges {
    if (!supportsDeviceOrientation) return super.deviceOrientationChanges;
    return deviceOrientations.stream;
  }

  @override
  Future<List<DeviceOrientation>?> getAppOrientations() async =>
      appOrientations;

  /// Every list passed to setPreferredOrientations.
  final List<List<DeviceOrientation>> preferredOrientations =
      <List<DeviceOrientation>>[];

  @override
  Future<void> setPreferredOrientations(
    List<DeviceOrientation> orientations,
  ) async => preferredOrientations.add(orientations);

  /// Every setMediaSession call, as (playerId, info, canSkipNext,
  /// canSkipPrevious).
  final List<(int?, PlayStackMediaInfo?, bool, bool)> mediaSessions =
      <(int?, PlayStackMediaInfo?, bool, bool)>[];

  @override
  Future<void> setMediaSession(
    int? playerId,
    PlayStackMediaInfo? info, {
    bool canSkipNext = false,
    bool canSkipPrevious = false,
  }) async => mediaSessions.add((playerId, info, canSkipNext, canSkipPrevious));

  /// Every setPictureInPicture call, as (playerId, autoEnter).
  final List<(int?, bool)> pictureInPictures = <(int?, bool)>[];

  /// Returned by isPictureInPictureSupported.
  bool supportsPictureInPicture = true;
  /// How often Picture-in-Picture was started.
  int pictureInPictureStarts = 0;

  @override
  Future<void> setPictureInPicture(
    int? playerId, {
    required bool autoEnter,
  }) async => pictureInPictures.add((playerId, autoEnter));

  @override
  Future<bool> startPictureInPicture() async {
    pictureInPictureStarts++;
    return supportsPictureInPicture;
  }

  @override
  Future<bool> isPictureInPictureSupported() async => supportsPictureInPicture;

  /// Sends media control commands and Picture-in-Picture changes.
  // Closed with the test process.
  // ignore: close_sinks
  final StreamController<PlayStackSystemEvent> systemEventController =
      StreamController<PlayStackSystemEvent>.broadcast(sync: true);

  @override
  Stream<PlayStackSystemEvent> get systemEvents => systemEventController.stream;

  /// Whether downloads exist on this fake engine.
  bool supportsDownloads = true;

  /// The last value passed to setDownloadsEnabled.
  bool downloadsEnabled = false;

  /// Every download, as the engine keeps them.
  final Map<String, PlayStackDownload> savedDownloads =
      <String, PlayStackDownload>{};

  /// Every startDownload request.
  final List<PlayStackDownloadRequest> downloadRequests =
      <PlayStackDownloadRequest>[];

  // Closed with the test process.
  // ignore: close_sinks
  /// Sends download changes.
  final StreamController<PlayStackDownloadChange> downloadController =
      StreamController<PlayStackDownloadChange>.broadcast(sync: true);

  /// Reports [download] as the engine would.
  void updateDownload(PlayStackDownload download) {
    savedDownloads[download.id] = download;
    downloadController.add(PlayStackDownloadChange.updated(download));
  }

  @override
  Future<bool> isDownloadSupported() async => supportsDownloads;

  @override
  Future<void> setDownloadsEnabled(bool enabled) async {
    calls.add('setDownloadsEnabled($enabled)');
    downloadsEnabled = enabled;
  }

  @override
  Future<void> startDownload(PlayStackDownloadRequest request) async {
    downloadRequests.add(request);
    updateDownload(
      PlayStackDownload(
        id: request.id,
        key: request.source.effectiveCacheKey,
        state: PlayStackDownloadState.queued,
        title: request.title,
        metadata: request.metadata,
      ),
    );
  }

  @override
  Future<void> pauseDownload(String id) async =>
      calls.add('pauseDownload($id)');

  @override
  Future<void> resumeDownload(String id) async =>
      calls.add('resumeDownload($id)');

  @override
  Future<void> removeDownload(String id) async {
    calls.add('removeDownload($id)');
    savedDownloads.remove(id);
    downloadController.add(PlayStackDownloadChange.removed(id));
  }

  @override
  Future<List<PlayStackDownload>> getDownloads() async =>
      savedDownloads.values.toList();

  @override
  Stream<PlayStackDownloadChange> get downloadChanges =>
      downloadController.stream;

  @override
  Stream<PlayStackNetworkStatus> get networkStatusChanges => _network.stream;

  @override
  Stream<PlayStackPlatformEvent> get events => _events.stream;

  @override
  Widget buildView(int playerId) =>
      SizedBox(key: ValueKey<String>('native-view-$playerId'));
}

/// Lets queued microtasks and zero-delay timers run.
/// Lets the fake engine's asynchronous work (preparation, events) finish.
Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Makes [FakePlayStackPlatform] the engine of PlayStack.
extension FakePlayStackPlatformInstall on FakePlayStackPlatform {
  /// Sets this fake as `PlayStackPlatform.instance` and returns it.
  FakePlayStackPlatform register() {
    PlayStackPlatform.instance = this;
    return this;
  }
}
