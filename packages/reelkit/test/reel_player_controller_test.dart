// fake_async tests drive futures by elapsing time instead of awaiting them.
// ignore_for_file: discarded_futures

import 'dart:ui' show Size;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import 'support/fake_reelkit_platform.dart';

Matcher throwsReelKit(ReelKitErrorCode code) =>
    throwsA(isA<ReelKitException>().having((e) => e.code, 'code', code));

void main() {
  late FakeReelKitPlatform platform;
  late ReelKitManager manager;
  const source = ReelSource.network('https://example.com/a.mp4');
  const other = ReelSource.network('https://example.com/b.mp4');

  Future<ReelKitManager> createManager({int maxPlayers = 3}) async {
    final m = ReelKitManager(
      config: ReelKitConfig(pool: ReelPoolConfig(maxPlayers: maxPlayers)),
      platform: platform,
    );
    await m.initialize();
    return m;
  }

  setUp(() async {
    platform = FakeReelKitPlatform();
    manager = await createManager();
  });

  tearDown(() async {
    await manager.dispose();
  });

  test('initialize prepares the source and reports video info', () async {
    final controller = manager.createController(source);
    expect(controller.value.status, ReelPlaybackStatus.idle);
    expect(platform.createCalls, 0, reason: 'controllers are lazy');

    await controller.initialize();
    await flush();

    expect(controller.value.status, ReelPlaybackStatus.ready);
    expect(controller.value.isAttached, isTrue);
    expect(controller.value.videoInfo, platform.videoInfo);
    expect(controller.value.hasRenderedFirstFrame, isTrue);
    expect(controller.value.aspectRatio, closeTo(1080 / 1920, 1e-9));
  });

  test('concurrent initialize calls share one preparation', () async {
    final controller = manager.createController(source);
    await Future.wait([
      controller.initialize(),
      controller.initialize(),
      controller.initialize(),
    ]);
    await controller.initialize();
    expect(platform.callCount('setSource'), 1);
    expect(platform.createCalls, 1);
  });

  test('play prepares on demand and follows engine events', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    expect(controller.value.status, ReelPlaybackStatus.playing);
    expect(controller.priority, ReelPlayerPriority.active);

    await controller.pause();
    await flush();
    expect(controller.value.status, ReelPlaybackStatus.paused);
    expect(controller.priority, ReelPlayerPriority.visible);
  });

  test('play after completion restarts from the beginning', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final id = platform.livePlayers.single;
    platform.emit(
      ReelNativeStateEvent(
        playerId: id,
        generation: platform.generations[id]!,
        state: ReelNativePlaybackState.ended,
      ),
    );
    expect(controller.value.status, ReelPlaybackStatus.completed);
    await controller.play();
    expect(platform.calls, contains('seekTo($id, 0)'));
  });

  test('commands reach the engine in call order', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    platform.calls.clear();
    final id = platform.livePlayers.single;
    await Future.wait([
      controller.play(),
      controller.pause(),
      controller.play(),
      controller.pause(),
    ]);
    expect(platform.calls, [
      'play($id)',
      'pause($id)',
      'play($id)',
      'pause($id)',
    ]);
  });

  test('events from an earlier generation are ignored', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    final id = platform.livePlayers.single;
    final generation = platform.generations[id]!;
    platform.emit(
      ReelErrorEvent(
        playerId: id,
        generation: generation - 1,
        error: const ReelKitException(ReelKitErrorCode.decoder, 'stale'),
      ),
    );
    expect(controller.value.status, ReelPlaybackStatus.ready);
  });

  test('preparation errors surface in state and can be retried', () async {
    platform.failingSources[source] = const ReelKitException(
      ReelKitErrorCode.sourceNotFound,
      '404',
    );
    final controller = manager.createController(source);
    await expectLater(
      controller.initialize(),
      throwsReelKit(ReelKitErrorCode.sourceNotFound),
    );
    expect(controller.value.status, ReelPlaybackStatus.error);
    expect(controller.value.error?.code, ReelKitErrorCode.sourceNotFound);
    final firstGeneration = platform.generations.values.single;

    platform.failingSources.clear();
    await controller.initialize();
    expect(controller.value.status, ReelPlaybackStatus.ready);
    expect(controller.value.error, isNull);
    expect(platform.generations.values.single, isNot(firstGeneration));
  });

  test('engine errors thrown by commands surface in state', () async {
    platform.throwOn['setSource'] = const ReelKitException(
      ReelKitErrorCode.notImplemented,
      'not yet',
    );
    final controller = manager.createController(source);
    await expectLater(
      controller.initialize(),
      throwsReelKit(ReelKitErrorCode.notImplemented),
    );
    expect(controller.value.error?.code, ReelKitErrorCode.notImplemented);
  });

  test('initialize times out when the engine never answers', () {
    // Futures complete in the zone they were created in, so the whole
    // manager must live inside the fake-async zone.
    fakeAsync((async) {
      final slowPlatform = FakeReelKitPlatform()..autoPrepare = false;
      final slowManager = ReelKitManager(platform: slowPlatform);
      slowManager.initialize();
      async.flushMicrotasks();
      final controller = slowManager.createController(
        source,
        config: const ReelPlayerConfig(
          initializeTimeout: Duration(seconds: 5),
          retry: ReelRetryConfig.none,
        ),
      );
      Object? error;
      controller.initialize().catchError((Object e) => error = e);
      async.elapse(const Duration(seconds: 4));
      expect(error, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(error, isA<ReelKitException>());
      expect((error! as ReelKitException).code, ReelKitErrorCode.timeout);
      expect(controller.value.status, ReelPlaybackStatus.error);
      slowManager.dispose();
      async.flushMicrotasks();
      expect(slowPlatform.livePlayers, isEmpty);
    });
  });

  test(
    'a higher-priority controller takes the player of a lower one',
    () async {
      await manager.dispose();
      manager = await createManager(maxPlayers: 1);
      final preloaded = manager.createController(source)
        ..priority = ReelPlayerPriority.preload;
      await preloaded.initialize();
      expect(preloaded.value.isAttached, isTrue);

      final active = manager.createController(other);
      await active.play();
      await flush();

      expect(active.value.status, ReelPlaybackStatus.playing);
      expect(preloaded.value.status, ReelPlaybackStatus.idle);
      expect(preloaded.value.isAttached, isFalse);
      expect(preloaded.value.videoInfo, isNotNull, reason: 'layout is kept');
      expect(platform.createCalls, 1);
      expect(manager.poolStats.revoked, 1);
    },
  );

  test('controller of equal priority cannot steal a player', () async {
    await manager.dispose();
    manager = await createManager(maxPlayers: 1);
    await manager.createController(source).initialize();
    await expectLater(
      manager.createController(other).initialize(),
      throwsReelKit(ReelKitErrorCode.poolExhausted),
    );
  });

  test('only changed settings are sent to the engine', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    expect(platform.callCount('setVolume'), 0);
    expect(platform.callCount('setLooping'), 0);
    expect(platform.callCount('setPlaybackSpeed'), 0);

    await controller.setMuted(true);
    await controller.setVolume(0.5); // muted: audible volume stays 0
    await controller.setLooping(true);
    await controller.setPlaybackSpeed(1.5);
    final id = platform.livePlayers.single;
    expect(platform.calls, contains('setVolume($id, 0.0)'));
    expect(platform.callCount('setVolume'), 1);
    expect(platform.calls, contains('setLooping($id, true)'));
    expect(platform.calls, contains('setPlaybackSpeed($id, 1.5)'));
    expect(controller.value.volume, 0.5);
    expect(controller.value.isMuted, isTrue);

    await controller.setMuted(false);
    expect(platform.calls, contains('setVolume($id, 0.5)'));
  });

  test('settings are re-applied when a reused player changes owner', () async {
    final looping = manager.createController(
      source,
      config: const ReelPlayerConfig(looping: true),
    );
    await looping.initialize();
    await looping.dispose();
    final plain = manager.createController(other);
    await plain.initialize();
    final id = platform.livePlayers.single;
    expect(platform.calls, contains('setLooping($id, true)'));
    expect(platform.calls, contains('setLooping($id, false)'));
    expect(platform.createCalls, 1, reason: 'the native player was reused');
  });

  test('rejects invalid volume and speed', () async {
    final controller = manager.createController(source);
    await expectLater(
      controller.setVolume(1.5),
      throwsReelKit(ReelKitErrorCode.invalidArgument),
    );
    await expectLater(
      controller.setPlaybackSpeed(0),
      throwsReelKit(ReelKitErrorCode.invalidArgument),
    );
    await expectLater(
      controller.setPlaybackSpeed(double.nan),
      throwsReelKit(ReelKitErrorCode.invalidArgument),
    );
  });

  test('seek requires a prepared video and clamps to the duration', () async {
    final controller = manager.createController(source);
    await expectLater(
      controller.seekTo(Duration.zero),
      throwsReelKit(ReelKitErrorCode.notInitialized),
    );
    await controller.initialize();
    final id = platform.livePlayers.single;
    await controller.seekTo(const Duration(minutes: 5));
    expect(platform.calls.last, 'seekTo($id, 30000)');
    await controller.seekTo(const Duration(seconds: -3));
    expect(platform.calls.last, 'seekTo($id, 0)');
    await controller.seekTo(const Duration(seconds: 10));
    await controller.fastForward();
    expect(platform.calls.last, 'seekTo($id, 20000)');
    await controller.rewind(const Duration(seconds: 15));
    expect(platform.calls.last, 'seekTo($id, 5000)');
    expect(await controller.getRemaining(), const Duration(seconds: 25));
  });

  test('release returns the player and keeps the controller usable', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final id = platform.livePlayers.single;
    await controller.release();
    expect(controller.value.status, ReelPlaybackStatus.idle);
    expect(controller.value.isAttached, isFalse);
    expect(controller.value.videoInfo, isNotNull);
    expect(manager.poolStats.leased, 0);
    expect(platform.calls, contains('clearSource($id)'));

    await controller.play();
    await flush();
    expect(controller.value.status, ReelPlaybackStatus.playing);
    expect(platform.createCalls, 1, reason: 'the idle player was reused');
  });

  test('buffering while playing keeps the playing status', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final id = platform.livePlayers.single;
    platform.emit(
      ReelNativeStateEvent(
        playerId: id,
        generation: platform.generations[id]!,
        state: ReelNativePlaybackState.buffering,
      ),
    );
    expect(controller.value.status, ReelPlaybackStatus.playing);
    expect(controller.value.isBuffering, isTrue);
  });

  test('dispose releases the player and rejects later commands', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    await controller.dispose();
    await controller.dispose(); // idempotent
    expect(controller.isDisposed, isTrue);
    expect(controller.value.status, ReelPlaybackStatus.disposed);
    expect(manager.controllers, isEmpty);
    expect(manager.poolStats.leased, 0);
    await expectLater(
      controller.play(),
      throwsReelKit(ReelKitErrorCode.disposed),
    );
    await expectLater(
      controller.initialize(),
      throwsReelKit(ReelKitErrorCode.disposed),
    );
  });

  test('commands queued before dispose complete without effect', () async {
    final controller = manager.createController(source);
    final play = controller.play();
    final dispose = controller.dispose();
    await play;
    await dispose;
    expect(platform.callCount('play'), 0);
    expect(manager.poolStats.leased, 0);
  });

  test('dispose during preparation cancels it cleanly', () async {
    platform.autoPrepare = false;
    final controller = manager.createController(source);
    final init = controller.initialize();
    await flush();
    await controller.dispose();
    await init; // superseded by dispose: completes without effect
    expect(manager.poolStats.leased, 0);
  });

  test('listeners are notified only on real state changes', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    var notifications = 0;
    controller.addListener(() => notifications++);
    final id = platform.livePlayers.single;
    final generation = platform.generations[id]!;
    for (var i = 0; i < 3; i++) {
      platform.emit(
        ReelNativeStateEvent(
          playerId: id,
          generation: generation,
          state: ReelNativePlaybackState.ready,
        ),
      );
    }
    expect(notifications, 0);
    platform.emit(
      ReelNativeStateEvent(
        playerId: id,
        generation: generation,
        state: ReelNativePlaybackState.buffering,
      ),
    );
    expect(notifications, 1);
    expect(controller.value.isBuffering, isTrue);
  });

  test('video size events update the layout info', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    final id = platform.livePlayers.single;
    platform.emit(
      ReelVideoSizeEvent(
        playerId: id,
        generation: platform.generations[id]!,
        width: 1920,
        height: 1080,
        rotationDegrees: 90,
        pixelAspectRatio: 1,
      ),
    );
    final info = controller.value.videoInfo!;
    expect(info.displaySize, const Size(1080, 1920));
    expect(info.duration, const Duration(seconds: 30));
  });

  group('source replacement', () {
    test('replaces the source on the same native player', () async {
      final controller = manager.createController(source);
      await controller.play();
      await flush();
      final id = platform.livePlayers.single;
      final firstGeneration = platform.generations[id]!;

      await controller.setSource(other);
      await flush();

      expect(controller.source, other);
      expect(platform.createCalls, 1);
      expect(
        platform.calls,
        contains(
          'setSource($id, ${other.description}, '
          '${platform.generations[id]})',
        ),
      );
      expect(platform.generations[id], isNot(firstGeneration));
      expect(
        controller.value.status,
        ReelPlaybackStatus.playing,
        reason: 'playback resumes on the new source',
      );
    });

    test('late events of the replaced source are ignored', () async {
      final controller = manager.createController(source);
      await controller.initialize();
      final id = platform.livePlayers.single;
      final oldGeneration = platform.generations[id]!;
      await controller.setSource(other);
      platform.emit(
        ReelErrorEvent(
          playerId: id,
          generation: oldGeneration,
          error: const ReelKitException(ReelKitErrorCode.decoder, 'old'),
        ),
      );
      expect(controller.value.status, ReelPlaybackStatus.ready);
    });

    test('an idle controller only stores the new source', () async {
      final controller = manager.createController(source);
      await controller.setSource(other);
      expect(platform.callCount('setSource'), 0);
      expect(controller.value.videoInfo, isNull);
      await controller.initialize();
      expect(
        platform.calls.where(
          (c) => c.startsWith('setSource(') && c.contains(other.description),
        ),
        hasLength(1),
      );
    });
  });

  test('stop pauses and rewinds', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final id = platform.livePlayers.single;
    await controller.stop();
    await flush();
    expect(platform.calls.sublist(platform.calls.length - 2), [
      'pause($id)',
      'seekTo($id, 0)',
    ]);
    expect(controller.value.status, ReelPlaybackStatus.paused);
    expect(controller.priority, ReelPlayerPriority.visible);
  });

  group('tracks', () {
    const audioEn = ReelTrack(
      id: 'a:0',
      type: ReelTrackType.audio,
      isSelected: true,
      language: 'en',
    );
    const audioTr = ReelTrack(
      id: 'a:1',
      type: ReelTrackType.audio,
      isSelected: false,
      language: 'tr',
    );
    const textEn = ReelTrack(
      id: 't:0',
      type: ReelTrackType.text,
      isSelected: false,
      language: 'en',
    );

    test('are read after preparation and on change events', () async {
      platform.trackList = const [audioEn, audioTr, textEn];
      final controller = manager.createController(source);
      await controller.initialize();
      await flush();
      expect(controller.tracks.value, hasLength(3));

      final id = platform.livePlayers.single;
      platform.trackList = const [audioEn];
      platform.emit(
        ReelTracksChangedEvent(
          playerId: id,
          generation: platform.generations[id]!,
        ),
      );
      await flush();
      expect(controller.tracks.value, [audioEn]);
    });

    test('selection is applied and refreshed', () async {
      platform.trackList = const [audioEn, audioTr];
      final controller = manager.createController(source);
      await controller.initialize();
      await controller.selectTrack(audioTr);
      final id = platform.livePlayers.single;
      expect(platform.calls, contains('selectTrack($id, audio, a:1)'));
      expect(
        controller.tracks.value.singleWhere((t) => t.isSelected).id,
        'a:1',
      );
    });

    test('preferences are re-applied after losing the player', () async {
      await manager.dispose();
      manager = await createManager(maxPlayers: 1);
      platform.trackList = const [audioEn, audioTr];
      final controller = manager.createController(source)
        ..priority = ReelPlayerPriority.preload;
      await controller.initialize();
      await controller.selectTrack(audioTr);
      await controller.setVideoQualityLimit(
        const ReelVideoQualityLimit(maxHeight: 480),
      );

      final active = manager.createController(other);
      await active.play();
      await active.dispose();
      platform.calls.clear();

      await controller.initialize();
      final id = platform.livePlayers.single;
      expect(platform.calls, contains('selectTrack($id, audio, a:1)'));
      expect(platform.calls, contains('setVideoQualityLimit($id, 480)'));
    });

    test('selections before preparation are applied on preparation', () async {
      platform.trackList = const [textEn];
      final controller = manager.createController(source);
      await controller.selectTrack(textEn);
      expect(platform.callCount('selectTrack'), 0);
      await controller.initialize();
      expect(platform.callCount('selectTrack'), 1);
    });

    test('a new source resets track selections', () async {
      platform.trackList = const [audioEn, audioTr];
      final controller = manager.createController(source);
      await controller.initialize();
      await controller.selectTrack(audioTr);
      platform.calls.clear();
      await controller.setSource(other);
      expect(platform.callCount('selectTrack'), 0);
    });

    test('subtitle cues are exposed and cleared when disabled', () async {
      final controller = manager.createController(source);
      await controller.initialize();
      final id = platform.livePlayers.single;
      platform.emit(
        ReelCuesEvent(
          playerId: id,
          generation: platform.generations[id]!,
          texts: const ['Hello'],
        ),
      );
      expect(controller.subtitles.value, ['Hello']);
      await controller.disableSubtitles();
      expect(controller.subtitles.value, isEmpty);
      platform.emit(
        ReelCuesEvent(
          playerId: id,
          generation: platform.generations[id]!,
          texts: const ['Ignored'],
        ),
      );
      expect(controller.subtitles.value, isEmpty);
    });

    test('engines without track support report no tracks', () async {
      final controller = manager.createController(source);
      platform.throwOn['selectTrack'] = const ReelKitException(
        ReelKitErrorCode.notImplemented,
        'no',
      );
      await controller.initialize();
      await expectLater(
        controller.selectTrack(textEn),
        throwsReelKit(ReelKitErrorCode.notImplemented),
      );
    });
  });

  test('position stream polls only while playing', () async {
    final controller = manager.createController(source);
    await controller.initialize();
    final id = platform.livePlayers.single;
    final received = <Duration>[];
    final sub = controller
        .positions(interval: const Duration(milliseconds: 10))
        .listen((p) => received.add(p.position));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, [Duration.zero], reason: 'one initial read');

    await controller.seekTo(const Duration(seconds: 3));
    await flush();
    expect(received.last, const Duration(seconds: 3));

    platform.positions[id] = const Duration(seconds: 4);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      received.last,
      const Duration(seconds: 3),
      reason: 'paused: no polling',
    );

    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received.last, const Duration(seconds: 4));
    await sub.cancel();
  });

  test('dispose closes position streams', () async {
    final controller = manager.createController(source);
    var done = false;
    controller.positions().listen((_) {}, onDone: () => done = true);
    await controller.dispose();
    await flush();
    expect(done, isTrue);
  });

  test('repeated initialize and dispose does not leak players', () async {
    for (var i = 0; i < 50; i++) {
      final controller = manager.createController(
        ReelSource.network('https://example.com/$i.mp4'),
      );
      await controller.initialize();
      await controller.dispose();
    }
    expect(platform.createCalls, 1);
    expect(manager.poolStats.leased, 0);
    expect(manager.controllers, isEmpty);
  });

  test('preload priority bounds buffering until play', () async {
    final controller = manager.createController(source)
      ..priority = ReelPlayerPriority.preload;
    await controller.initialize();
    final playerId = platform.livePlayers.single;
    expect(platform.bufferLimits[playerId], const Duration(seconds: 5));

    await controller.play();
    expect(platform.bufferLimits[playerId], isNull);

    await controller.pause();
    controller.priority = ReelPlayerPriority.background;
    await flush();
    expect(platform.bufferLimits[playerId], const Duration(seconds: 5));
  });

  test('metrics record preparation and start timing', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final metrics = controller.metrics;
    expect(metrics.preparations, 1);
    expect(metrics.lastPreparationTime, isNotNull);
    expect(metrics.lastTimeToFirstFrame, isNotNull);
    expect(metrics.lastStartLatency, isNotNull);
  });

  test(
    'metrics stay separate when the first frame precedes readiness',
    () async {
      platform.autoPrepare = false;
      final controller = manager.createController(source);
      final preparing = controller.initialize();
      await flush();
      final playerId = platform.livePlayers.single;
      final generation = platform.generations[playerId]!;
      platform.emit(
        ReelFirstFrameEvent(playerId: playerId, generation: generation),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      platform.emit(
        ReelInitializedEvent(
          playerId: playerId,
          generation: generation,
          info: platform.videoInfo,
        ),
      );
      await preparing;
      final metrics = controller.metrics;
      expect(
        metrics.lastPreparationTime! - metrics.lastTimeToFirstFrame!,
        greaterThanOrEqualTo(const Duration(milliseconds: 25)),
      );
    },
  );

  test('release cancels a preparation in flight', () async {
    platform.hangingSources.add(source);
    final controller = manager.createController(source);
    final preparing = controller.initialize();
    await flush();
    final cancelled = expectLater(
      preparing,
      throwsReelKit(ReelKitErrorCode.cancelled),
    );
    await controller.release();
    await cancelled;
    expect(controller.value.status, ReelPlaybackStatus.idle);
    expect(manager.poolStats.leased, 0);
  });
}
