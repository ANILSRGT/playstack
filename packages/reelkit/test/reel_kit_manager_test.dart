import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';

import 'support/fake_reelkit_platform.dart';

void main() {
  test('initialize is idempotent and shared between callers', () async {
    final platform = FakeReelKitPlatform();
    final manager = ReelKitManager(platform: platform);
    await Future.wait([manager.initialize(), manager.initialize()]);
    await manager.initialize();
    expect(platform.initializeCalls, 1);
    expect(manager.isInitialized, isTrue);
    expect(manager.capabilities.engineName, 'fake');
    await manager.dispose();
  });

  test('a failed initialization can be retried', () async {
    final platform = FakeReelKitPlatform();
    platform.throwOn['initialize'] = const ReelKitException(
      ReelKitErrorCode.unknown,
      'boom',
    );
    final manager = ReelKitManager(platform: platform);
    await expectLater(manager.initialize(), throwsA(isA<ReelKitException>()));
    expect(manager.isInitialized, isFalse);
    platform.throwOn.clear();
    await manager.initialize();
    expect(manager.isInitialized, isTrue);
    await manager.dispose();
  });

  group('pool size', () {
    Future<int> resolve(ReelPoolConfig config, int recommended) async {
      final manager = ReelKitManager(
        config: ReelKitConfig(pool: config),
        platform: FakeReelKitPlatform(recommendedMaxPlayers: recommended),
      );
      await manager.initialize();
      final max = manager.poolStats.maxPlayers;
      await manager.dispose();
      return max;
    }

    test('adapts to the device recommendation', () async {
      expect(await resolve(const ReelPoolConfig(), 2), 2);
      expect(await resolve(const ReelPoolConfig(), 1), 1);
    });

    test('caps the adaptive size', () async {
      expect(await resolve(const ReelPoolConfig(), 8), 4);
      expect(await resolve(const ReelPoolConfig(maxAdaptivePlayers: 6), 8), 6);
    });

    test('uses a fixed size when configured', () async {
      expect(await resolve(const ReelPoolConfig(maxPlayers: 2), 4), 2);
      expect(await resolve(const ReelPoolConfig(maxPlayers: 5), 1), 5);
    });
  });

  test('createController requires initialization', () {
    final manager = ReelKitManager(platform: FakeReelKitPlatform());
    expect(
      () => manager.createController(const ReelSource.file('/a.mp4')),
      throwsA(
        isA<ReelKitException>().having(
          (e) => e.code,
          'code',
          ReelKitErrorCode.notInitialized,
        ),
      ),
    );
    expect(() => manager.capabilities, throwsA(isA<ReelKitException>()));
  });

  test('dispose releases every controller and native player', () async {
    final platform = FakeReelKitPlatform();
    final manager = ReelKitManager(platform: platform);
    await manager.initialize();
    final controllers = [
      for (var i = 0; i < 3; i++)
        manager.createController(ReelSource.network('https://e.com/$i.mp4')),
    ];
    await Future.wait(controllers.map((c) => c.initialize()));
    expect(platform.livePlayers, hasLength(3));

    await manager.dispose();
    await manager.dispose();

    expect(platform.livePlayers, isEmpty);
    expect(controllers.every((c) => c.isDisposed), isTrue);
    expect(manager.isDisposed, isTrue);
    expect(
      () => manager.createController(const ReelSource.file('/a.mp4')),
      throwsA(isA<ReelKitException>()),
    );
    await expectLater(manager.initialize(), throwsA(isA<ReelKitException>()));
  });

  test('events are routed to the controller that owns the player', () async {
    final platform = FakeReelKitPlatform();
    final manager = ReelKitManager(platform: platform);
    await manager.initialize();
    final a = manager.createController(const ReelSource.file('/a.mp4'));
    final b = manager.createController(const ReelSource.file('/b.mp4'));
    await a.initialize();
    await b.initialize();
    await b.play();
    await flush();
    expect(a.value.status, ReelPlaybackStatus.ready);
    expect(b.value.status, ReelPlaybackStatus.playing);
    await manager.dispose();
  });

  test('trimIdlePlayers destroys unassigned players', () async {
    final platform = FakeReelKitPlatform();
    final manager = ReelKitManager(platform: platform);
    await manager.initialize();
    final controller = manager.createController(const ReelSource.file('/a'));
    await controller.initialize();
    await controller.dispose();
    expect(platform.livePlayers, hasLength(1));
    await manager.trimIdlePlayers();
    expect(platform.livePlayers, isEmpty);
    await manager.dispose();
  });
}
