import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_example/samples.dart';

import 'support/test_results.dart';

/// Runs against the real engine of the device or browser.
///
/// `flutter test integration_test -d <device>`
void main() {
  ensureBindingWithResults();

  testWidgets('engine reports capabilities', (tester) async {
    final manager = ReelKitManager();
    await manager.initialize();
    final caps = manager.capabilities;
    expect(caps.engineName, isNotEmpty);
    expect(caps.recommendedMaxPlayers, greaterThanOrEqualTo(1));
    expect(manager.poolStats.maxPlayers, greaterThanOrEqualTo(1));
    await manager.dispose();
  });

  testWidgets('native players are allocated, reused and released', (
    tester,
  ) async {
    final manager = ReelKitManager(
      config: const ReelKitConfig(pool: ReelPoolConfig(maxPlayers: 2)),
    );
    await manager.initialize();

    for (var round = 0; round < 10; round++) {
      final controller = manager.createController(
        const ReelSource.asset(landscapeAsset),
      );
      await controller.initialize();
      expect(controller.value.status, ReelPlaybackStatus.ready);
      expect(manager.poolStats.allocated, lessThanOrEqualTo(2));
      await controller.dispose();
    }

    expect(manager.poolStats.created, 1);
    expect(manager.poolStats.reused, 9);
    await manager.dispose();
  });
}
