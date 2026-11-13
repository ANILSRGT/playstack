import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import 'support/fake_playstack_platform.dart';

/// Delivers lifecycle changes in the real async zone, where the manager's
/// futures were created, so the resulting commands complete.
Future<void> lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  return tester.runAsync(() async {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await flush();
  });
}

void main() {
  test('initialize is idempotent and shared between callers', () async {
    final platform = FakePlayStackPlatform();
    final manager = PlayStackManager(platform: platform);
    await Future.wait([manager.initialize(), manager.initialize()]);
    await manager.initialize();
    expect(platform.initializeCalls, 1);
    expect(manager.isInitialized, isTrue);
    expect(manager.capabilities.engineName, 'fake');
    await manager.dispose();
  });

  test('a failed initialization can be retried', () async {
    final platform = FakePlayStackPlatform();
    platform.throwOn['initialize'] = const PlayStackException(
      PlayStackErrorCode.unknown,
      'boom',
    );
    final manager = PlayStackManager(platform: platform);
    await expectLater(manager.initialize(), throwsA(isA<PlayStackException>()));
    expect(manager.isInitialized, isFalse);
    platform.throwOn.clear();
    await manager.initialize();
    expect(manager.isInitialized, isTrue);
    await manager.dispose();
  });

  group('pool size', () {
    Future<int> resolve(PlayStackPoolConfig config, int recommended) async {
      final manager = PlayStackManager(
        config: PlayStackConfig(pool: config),
        platform: FakePlayStackPlatform(recommendedMaxPlayers: recommended),
      );
      await manager.initialize();
      final max = manager.poolStats.maxPlayers;
      await manager.dispose();
      return max;
    }

    test('adapts to the device recommendation', () async {
      expect(await resolve(const PlayStackPoolConfig(), 2), 2);
      expect(await resolve(const PlayStackPoolConfig(), 1), 1);
    });

    test('caps the adaptive size', () async {
      expect(await resolve(const PlayStackPoolConfig(), 8), 4);
      expect(
        await resolve(const PlayStackPoolConfig(maxAdaptivePlayers: 6), 8),
        6,
      );
    });

    test('uses a fixed size when configured', () async {
      expect(await resolve(const PlayStackPoolConfig(maxPlayers: 2), 4), 2);
      expect(await resolve(const PlayStackPoolConfig(maxPlayers: 5), 1), 5);
    });
  });

  test('createController requires initialization', () {
    final manager = PlayStackManager(platform: FakePlayStackPlatform());
    expect(
      () => manager.createController(const PlayStackSource.file('/a.mp4')),
      throwsA(
        isA<PlayStackException>().having(
          (e) => e.code,
          'code',
          PlayStackErrorCode.notInitialized,
        ),
      ),
    );
    expect(() => manager.capabilities, throwsA(isA<PlayStackException>()));
  });

  test('dispose releases every controller and native player', () async {
    final platform = FakePlayStackPlatform();
    final manager = PlayStackManager(platform: platform);
    await manager.initialize();
    final controllers = [
      for (var i = 0; i < 3; i++)
        manager.createController(
          PlayStackSource.network('https://e.com/$i.mp4'),
        ),
    ];
    await Future.wait(controllers.map((c) => c.initialize()));
    expect(platform.livePlayers, hasLength(3));

    await manager.dispose();
    await manager.dispose();

    expect(platform.livePlayers, isEmpty);
    expect(controllers.every((c) => c.isDisposed), isTrue);
    expect(manager.isDisposed, isTrue);
    expect(
      () => manager.createController(const PlayStackSource.file('/a.mp4')),
      throwsA(isA<PlayStackException>()),
    );
    await expectLater(manager.initialize(), throwsA(isA<PlayStackException>()));
  });

  test('events are routed to the controller that owns the player', () async {
    final platform = FakePlayStackPlatform();
    final manager = PlayStackManager(platform: platform);
    await manager.initialize();
    final a = manager.createController(const PlayStackSource.file('/a.mp4'));
    final b = manager.createController(const PlayStackSource.file('/b.mp4'));
    await a.initialize();
    await b.initialize();
    await b.play();
    await flush();
    expect(a.value.status, PlayStackPlaybackStatus.ready);
    expect(b.value.status, PlayStackPlaybackStatus.playing);
    await manager.dispose();
  });

  test('trimIdlePlayers destroys unassigned players', () async {
    final platform = FakePlayStackPlatform();
    final manager = PlayStackManager(platform: platform);
    await manager.initialize();
    final controller = manager.createController(
      const PlayStackSource.file('/a'),
    );
    await controller.initialize();
    await controller.dispose();
    expect(platform.livePlayers, hasLength(1));
    await manager.trimIdlePlayers();
    expect(platform.livePlayers, isEmpty);
    await manager.dispose();
  });

  testWidgets('pauses on background and resumes on foreground', (tester) async {
    final platform = FakePlayStackPlatform();
    // Everything is created in the real async zone: futures complete in the
    // zone they were created in, and fake-async microtasks would not run.
    late final PlayStackManager manager;
    late final PlayStackPlayerController playing;
    late final PlayStackPlayerController paused;
    await tester.runAsync(() async {
      manager = PlayStackManager(platform: platform);
      await manager.initialize();
      playing = manager.createController(const PlayStackSource.file('/a'));
      paused = manager.createController(const PlayStackSource.file('/b'));
      await playing.play();
      await paused.initialize();
      await flush();
    });
    expect(playing.value.isPlaying, isTrue);
    await lifecycle(tester, [AppLifecycleState.inactive]);
    expect(playing.value.isPlaying, isTrue, reason: 'inactive is transient');

    await lifecycle(tester, [AppLifecycleState.hidden]);
    expect(playing.value.status, PlayStackPlaybackStatus.paused);

    await lifecycle(tester, [
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(playing.value.status, PlayStackPlaybackStatus.playing);
    expect(
      paused.value.status,
      PlayStackPlaybackStatus.ready,
      reason: 'only controllers paused by the lifecycle resume',
    );
    await tester.runAsync(manager.dispose);
  });

  testWidgets('media controls keep their video playing in the background', (
    tester,
  ) async {
    final platform = FakePlayStackPlatform();
    late final PlayStackManager manager;
    late final PlayStackPlayerController listened;
    late final PlayStackPlayerController other;
    await tester.runAsync(() async {
      manager = PlayStackManager(
        config: const PlayStackConfig(exclusivePlayback: false),
        platform: platform,
      );
      await manager.initialize();
      listened = manager.createController(const PlayStackSource.file('/a'));
      other = manager.createController(const PlayStackSource.file('/b'));
      await listened.play();
      await other.play();
      await manager.mediaSession.show(
        listened,
        const PlayStackMediaInfo(title: 'Episode 1'),
      );
      await flush();
    });
    await lifecycle(tester, [AppLifecycleState.hidden]);
    expect(listened.value.isPlaying, isTrue);
    expect(other.value.isPlaying, isFalse);

    // A pause from the lock screen stays paused when the app comes back.
    platform.systemEventController.add(
      const PlayStackSystemEvent(PlayStackSystemEventType.pause),
    );
    await tester.runAsync(flush);
    expect(listened.value.isPlaying, isFalse);
    await lifecycle(tester, [AppLifecycleState.resumed]);
    expect(listened.value.isPlaying, isFalse);
    expect(other.value.isPlaying, isTrue);

    await tester.runAsync(manager.mediaSession.clear);
    expect(platform.mediaSessions.last, (null, null, false, false));
    await tester.runAsync(manager.dispose);
  });

  testWidgets('Picture-in-Picture keeps its video playing only while open', (
    tester,
  ) async {
    final platform = FakePlayStackPlatform();
    late final PlayStackManager manager;
    late final PlayStackPlayerController controller;
    await tester.runAsync(() async {
      manager = PlayStackManager(platform: platform);
      await manager.initialize();
      controller = manager.createController(const PlayStackSource.file('/a'));
      await controller.play();
      await manager.pictureInPicture.enable(controller);
      await flush();
    });
    expect(platform.pictureInPictures.last.$2, isTrue);
    await lifecycle(tester, [AppLifecycleState.hidden]);
    expect(
      controller.value.isPlaying,
      isFalse,
      reason: 'the window did not open',
    );
    await lifecycle(tester, [AppLifecycleState.resumed]);
    expect(controller.value.isPlaying, isTrue);

    platform.systemEventController.add(
      const PlayStackSystemEvent(
        PlayStackSystemEventType.pictureInPictureStarted,
      ),
    );
    expect(manager.pictureInPicture.isActive.value, isTrue);
    await lifecycle(tester, [AppLifecycleState.hidden]);
    expect(controller.value.isPlaying, isTrue);
    await tester.runAsync(manager.dispose);
    expect(platform.pictureInPictures.last, (null, false));
  });

  testWidgets('lifecycle handling can be disabled', (tester) async {
    late final PlayStackManager manager;
    late final PlayStackPlayerController controller;
    await tester.runAsync(() async {
      manager = PlayStackManager(
        config: const PlayStackConfig(
          lifecycle: PlayStackLifecycleConfig(pauseOnBackground: false),
        ),
        platform: FakePlayStackPlatform(),
      );
      await manager.initialize();
      controller = manager.createController(const PlayStackSource.file('/a'));
      await controller.play();
      await flush();
    });
    await lifecycle(tester, [AppLifecycleState.hidden]);
    expect(controller.value.isPlaying, isTrue);
    await tester.runAsync(manager.dispose);
  });
}
