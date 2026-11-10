import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// In-memory engine that behaves like a native engine at the contract level:
/// it allocates numbered players, prepares sources asynchronously and emits
/// generation-tagged events.
class FakeReelKitPlatform extends ReelKitPlatform {
  FakeReelKitPlatform({
    this.recommendedMaxPlayers = 3,
    this.autoPrepare = true,
    this.videoInfo = const ReelVideoInfo(
      width: 1080,
      height: 1920,
      duration: Duration(seconds: 30),
    ),
  });

  final int recommendedMaxPlayers;
  final ReelVideoInfo videoInfo;

  /// When true, every setSource is answered with an initialized event and a
  /// first-frame event.
  bool autoPrepare;

  /// Sources whose preparation fails with this error.
  final Map<ReelSource, ReelKitException> failingSources =
      <ReelSource, ReelKitException>{};

  /// When set, every call of the named method throws this error.
  final Map<String, ReelKitException> throwOn = <String, ReelKitException>{};

  /// Completes createPlayer calls; when null they complete immediately.
  Completer<void>? createGate;

  final StreamController<ReelPlatformEvent> _events =
      StreamController<ReelPlatformEvent>.broadcast(sync: true);

  /// Tracks reported for every prepared source.
  List<ReelTrack> trackList = const <ReelTrack>[];

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

  void emit(ReelPlatformEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  void _check(String method) {
    final error = throwOn[method];
    if (error != null) throw error;
  }

  @override
  Future<ReelPlatformCapabilities> initialize() async {
    initializeCalls++;
    _check('initialize');
    return ReelPlatformCapabilities(
      engineName: 'fake',
      engineVersion: '1.0',
      recommendedMaxPlayers: recommendedMaxPlayers,
      isLowRamDevice: false,
      supportsHls: true,
      supportsDash: true,
      supportsDiskCache: false,
      supportsMemorySource: false,
      supportsTrackSelection: false,
    );
  }

  @override
  Future<ReelNativePlayerHandle> createPlayer(
    ReelNativePlayerOptions options,
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
    return ReelNativePlayerHandle(playerId: id, textureId: 100 + id);
  }

  @override
  Future<void> disposePlayer(int playerId) async {
    calls.add('disposePlayer($playerId)');
    livePlayers.remove(playerId);
  }

  void _requireLive(int playerId) {
    if (!livePlayers.contains(playerId)) {
      throw ReelKitException(
        ReelKitErrorCode.playerNotFound,
        'Player $playerId is not alive.',
      );
    }
  }

  @override
  Future<void> setSource(
    int playerId,
    ReelSource source,
    int generation,
  ) async {
    calls.add('setSource($playerId, ${source.description}, $generation)');
    _check('setSource');
    _requireLive(playerId);
    generations[playerId] = generation;
    positions[playerId] = Duration.zero;
    final failure = failingSources[source];
    if (failure != null) {
      scheduleMicrotask(
        () => emit(
          ReelErrorEvent(
            playerId: playerId,
            generation: generation,
            error: failure,
          ),
        ),
      );
      return;
    }
    if (!autoPrepare) return;
    scheduleMicrotask(() {
      emit(
        ReelInitializedEvent(
          playerId: playerId,
          generation: generation,
          info: videoInfo,
        ),
      );
      emit(ReelFirstFrameEvent(playerId: playerId, generation: generation));
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
        ReelIsPlayingEvent(
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
        ReelIsPlayingEvent(
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
  Future<ReelPositionSnapshot> getPosition(int playerId) async {
    _requireLive(playerId);
    final position = positions[playerId] ?? Duration.zero;
    return ReelPositionSnapshot(position: position, buffered: position);
  }

  @override
  Future<List<ReelTrack>> getTracks(int playerId) async {
    calls.add('getTracks($playerId)');
    _requireLive(playerId);
    return trackList;
  }

  @override
  Future<void> selectTrack(
    int playerId,
    ReelTrackType type,
    String? trackId,
  ) async {
    calls.add('selectTrack($playerId, ${type.name}, $trackId)');
    _check('selectTrack');
    _requireLive(playerId);
    trackList = [
      for (final t in trackList)
        t.type == type
            ? ReelTrack(
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
    ReelVideoQualityLimit limit,
  ) async {
    calls.add('setVideoQualityLimit($playerId, ${limit.maxHeight})');
    _check('setVideoQualityLimit');
    _requireLive(playerId);
  }

  @override
  Stream<ReelPlatformEvent> get events => _events.stream;

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
