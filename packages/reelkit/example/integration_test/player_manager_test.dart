import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_example/samples.dart';

/// Milestone 4 against the real engine: several controllers on one manager,
/// exclusive and concurrent playback, memory pressure and safe disposal.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final managers = <ReelKitManager>[];

  Future<ReelKitManager> createManager({bool exclusive = true}) async {
    final manager = ReelKitManager(
      config: ReelKitConfig(
        exclusivePlayback: exclusive,
        pool: const ReelPoolConfig(maxPlayers: 2),
        player: const ReelPlayerConfig(looping: true, muted: true),
      ),
    );
    managers.add(manager);
    await manager.initialize();
    return manager;
  }

  tearDown(() async {
    for (final manager in managers) {
      await manager.dispose();
    }
    managers.clear();
  });

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 8),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<bool> advances(ReelPlayerController controller) async {
    final before = (await controller.getPosition()).position;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final after = (await controller.getPosition()).position;
    // Looping clips can wrap around; any change means the clock runs.
    return after != before;
  }

  testWidgets('exclusive playback pauses the previous controller', (
    tester,
  ) async {
    final manager = await createManager();
    final first = manager.createController(
      const ReelSource.asset(landscapeAsset),
    );
    final second = manager.createController(
      const ReelSource.asset(rotatedAsset),
    );
    await first.play();
    await waitUntil(() => first.value.isPlaying, reason: 'first playing');
    expect(manager.activeController.value, same(first));

    await second.play();
    await waitUntil(() => second.value.isPlaying, reason: 'second playing');
    await waitUntil(
      () => first.value.status == ReelPlaybackStatus.paused,
      reason: 'first paused; got ${first.value}',
    );
    expect(manager.activeController.value, same(second));
    expect(await advances(first), isFalse, reason: 'native clock stopped');
    expect(await advances(second), isTrue);
  });

  testWidgets('concurrent playback keeps both controllers playing', (
    tester,
  ) async {
    final manager = await createManager(exclusive: false);
    final first = manager.createController(
      const ReelSource.asset(landscapeAsset),
    );
    final second = manager.createController(
      const ReelSource.asset(rotatedAsset),
    );
    await Future.wait([first.play(), second.play()]);
    await waitUntil(
      () => first.value.isPlaying && second.value.isPlaying,
      reason: 'both playing',
    );
    expect(await advances(first), isTrue);
    expect(await advances(second), isTrue);
    expect(manager.poolStats.allocated, 2);
  });

  testWidgets('memory pressure releases background players', (tester) async {
    final manager = await createManager();
    final background = manager.createController(
      const ReelSource.asset(landscapeAsset),
    )..priority = ReelPlayerPriority.background;
    final visible = manager.createController(
      const ReelSource.asset(rotatedAsset),
    );
    await background.initialize();
    await visible.initialize();
    expect(manager.poolStats.allocated, 2);

    binding.handleMemoryPressure();
    await waitUntil(
      () => manager.poolStats.allocated == 1,
      reason: 'background player destroyed; ${manager.poolStats}',
    );
    expect(background.value.isAttached, isFalse);
    expect(visible.value.isAttached, isTrue);

    // The released controller prepares again on demand.
    await background.play();
    expect(
      background.value.isPlaying || background.value.isInitialized,
      isTrue,
    );
  });

  testWidgets('disposing a manager mid-preparation is safe', (tester) async {
    for (var round = 0; round < 5; round++) {
      final manager = await createManager();
      final controllers = [
        for (var i = 0; i < 4; i++)
          manager.createController(
            ReelSource.asset(i.isEven ? landscapeAsset : rotatedAsset),
          ),
      ];
      for (final controller in controllers) {
        controller.play().ignore();
      }
      await manager.dispose();
      expect(manager.isDisposed, isTrue);
      for (final controller in controllers) {
        expect(controller.value.status, ReelPlaybackStatus.disposed);
      }
    }
    // The engine is still healthy afterwards.
    final manager = await createManager();
    final controller = manager.createController(
      const ReelSource.asset(landscapeAsset),
    );
    await controller.play();
    await waitUntil(() => controller.value.isPlaying, reason: 'playing');
  });
}
