import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';

/// Runs against the real native engine of the device or browser.
///
/// `flutter test integration_test -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
        ReelSource.network('https://example.invalid/$round.mp4'),
      );
      // Allocates (or reuses) a real native player. Source preparation is
      // implemented in milestone 2, so its outcome is not asserted here.
      await controller.initialize().catchError((Object _) {});
      expect(manager.poolStats.allocated, lessThanOrEqualTo(2));
      await controller.dispose();
    }

    expect(manager.poolStats.created, 1);
    expect(manager.poolStats.reused, 9);
    await manager.dispose();
  });
}
