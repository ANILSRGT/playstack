import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';

import 'support/fake_playstack_platform.dart';

const _a = PlayStackSource.network('https://example.com/a.mp4');
const _b = PlayStackSource.network('https://example.com/b.mp4');
const _c = PlayStackSource.network('https://example.com/c.mp4');

Future<PlayStackManager> _manager(
  FakePlayStackPlatform platform, {
  bool exclusive = true,
  int maxPlayers = 3,
  bool adaptToDecoderFailures = true,
}) async {
  final manager = PlayStackManager(
    config: PlayStackConfig(
      exclusivePlayback: exclusive,
      pool: PlayStackPoolConfig(
        maxPlayers: maxPlayers,
        adaptToDecoderFailures: adaptToDecoderFailures,
      ),
    ),
    platform: platform,
  );
  await manager.initialize();
  return manager;
}

void main() {
  late FakePlayStackPlatform platform;

  setUp(() => platform = FakePlayStackPlatform());

  group('exclusive playback', () {
    test('playing one controller pauses the others', () async {
      final manager = await _manager(platform);
      final a = manager.createController(_a);
      final b = manager.createController(_b);
      await a.play();
      await flush();
      expect(manager.activeController.value, same(a));

      await b.play();
      await flush();

      expect(a.value.status, PlayStackPlaybackStatus.paused);
      expect(a.priority, PlayStackPlayerPriority.visible);
      expect(b.value.isPlaying, isTrue);
      expect(manager.activeController.value, same(b));
      await manager.dispose();
    });

    test('the most recent play call wins when calls overlap', () async {
      final manager = await _manager(platform);
      final a = manager.createController(_a);
      final b = manager.createController(_b);

      await Future.wait([a.play(), b.play()]);
      await flush();

      expect(a.value.isPlaying, isFalse);
      expect(a.priority, isNot(PlayStackPlayerPriority.active));
      expect(b.value.isPlaying, isTrue);
      expect(platform.callCount('play'), 1);
      await manager.dispose();
    });

    test('playing a paused controller again takes over', () async {
      final manager = await _manager(platform);
      final a = manager.createController(_a);
      final b = manager.createController(_b);
      await a.play();
      await b.play();
      await a.play();
      await flush();

      expect(a.value.isPlaying, isTrue);
      expect(b.value.status, PlayStackPlaybackStatus.paused);
      expect(manager.activeController.value, same(a));
      await manager.dispose();
    });

    test('a play issued before playback started is also paused', () async {
      final manager = await _manager(platform);
      final a = manager.createController(_a);
      final b = manager.createController(_b);
      // a's play reaches the engine but its isPlaying event is not yet
      // delivered when b starts.
      await a.play();
      await b.play();
      await flush();
      expect(a.value.isPlaying, isFalse);
      expect(b.value.isPlaying, isTrue);
      await manager.dispose();
    });

    test('can be disabled', () async {
      final manager = await _manager(platform, exclusive: false);
      final a = manager.createController(_a);
      final b = manager.createController(_b);
      await a.play();
      await b.play();
      await flush();

      expect(a.value.isPlaying, isTrue);
      expect(b.value.isPlaying, isTrue);
      expect(manager.activeController.value, same(b));

      await b.pause();
      await flush();
      expect(manager.activeController.value, same(a));
      await manager.dispose();
    });

    test('active controller clears on pause and dispose', () async {
      final manager = await _manager(platform);
      final a = manager.createController(_a);
      await a.play();
      await flush();
      await a.pause();
      await flush();
      expect(manager.activeController.value, isNull);

      await a.play();
      await flush();
      expect(manager.activeController.value, same(a));
      await a.dispose();
      expect(manager.activeController.value, isNull);
      await manager.dispose();
    });
  });

  group('decoder shortage', () {
    const shortage = PlayStackException(
      PlayStackErrorCode.decoderUnavailable,
      'no decoder instance',
    );

    test('shrinks the pool and retries on a lower-priority player', () async {
      final manager = await _manager(platform);
      final visible = manager.createController(_a);
      final preload = manager.createController(_b)
        ..priority = PlayStackPlayerPriority.preload;
      await visible.initialize();
      await preload.initialize();
      final current = manager.createController(_c);
      platform.failingOnce[_c] = shortage;

      await current.play();
      await flush();

      expect(current.value.isPlaying, isTrue);
      expect(preload.value.isAttached, isFalse);
      expect(preload.value.status, PlayStackPlaybackStatus.idle);
      expect(visible.value.isAttached, isTrue);
      expect(manager.poolStats.maxPlayers, 2);
      expect(manager.poolStats.decoderLimitReductions, 1);
      expect(platform.livePlayers, hasLength(2));
      await manager.dispose();
    });

    test('reports the shortage when no player can be taken', () async {
      final manager = await _manager(platform);
      final holder = manager.createController(_a)
        ..priority = PlayStackPlayerPriority.active;
      await holder.initialize();
      final current = manager.createController(_c);
      platform.failingOnce[_c] = shortage;

      await expectLater(
        current.play(),
        throwsA(
          isA<PlayStackException>().having(
            (e) => e.code,
            'code',
            PlayStackErrorCode.decoderUnavailable,
          ),
        ),
      );
      expect(current.value.status, PlayStackPlaybackStatus.error);
      expect(holder.value.isAttached, isTrue);
      expect(manager.poolStats.maxPlayers, 1);
      await manager.dispose();
    });

    test('is not retried without other players or when disabled', () async {
      for (final adapt in [true, false]) {
        final platform = FakePlayStackPlatform();
        final manager = await _manager(platform, adaptToDecoderFailures: adapt);
        if (!adapt) await manager.createController(_a).initialize();
        final current = manager.createController(_c);
        platform.failingOnce[_c] = shortage;
        await expectLater(current.play(), throwsA(isA<PlayStackException>()));
        expect(platform.callCount('setSource'), adapt ? 1 : 2);
        expect(manager.poolStats.maxPlayers, 3);
        await manager.dispose();
      }
    });
  });

  testWidgets('memory pressure releases background controllers', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manager = await _manager(platform);
      final background = manager.createController(_a)
        ..priority = PlayStackPlayerPriority.background;
      final visible = manager.createController(_b);
      await background.initialize();
      await visible.initialize();

      tester.binding.handleMemoryPressure();
      await flush();

      expect(background.value.isAttached, isFalse);
      expect(visible.value.isAttached, isTrue);
      expect(platform.livePlayers, hasLength(1));
      await manager.dispose();
    });
  });

  test('dispose while a player is being created returns it', () async {
    final manager = await _manager(platform);
    final controller = manager.createController(_a);
    final gate = platform.createGate = Completer<void>();
    final initializing = controller.initialize();
    await flush();
    final disposing = controller.dispose();
    gate.complete();
    await initializing.catchError((Object _) {});
    await disposing;
    expect(manager.poolStats.leased, 0);
    await manager.dispose();
  });
}
