import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_demo/catalog.dart';

/// Health check of the demo catalog: every stream must prepare and render
/// its first frame on this device. Public test streams disappear over time;
/// run this before relying on the demo.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every catalog stream prepares', (tester) async {
    final manager = ReelKitManager(
      config: const ReelKitConfig(
        pool: ReelPoolConfig(maxPlayers: 2),
        player: ReelPlayerConfig(
          muted: true,
          initializeTimeout: Duration(seconds: 20),
        ),
      ),
    );
    await manager.initialize();
    final failures = <String>[];
    for (final video in demoCatalog) {
      final controller = manager.createController(video.source);
      final watch = Stopwatch()..start();
      try {
        await controller.initialize();
        final info = controller.value.videoInfo;
        // ignore: avoid_print
        print(
          'ok ${watch.elapsedMilliseconds} ms '
          '${info?.displaySize.width.round()}x${info?.displaySize.height.round()} '
          '${video.title}',
        );
      } on ReelKitException catch (error) {
        failures.add('${video.title}: ${error.code.name} ${error.message}');
        // ignore: avoid_print
        print('FAIL ${video.title}: $error');
      }
      await controller.dispose();
    }
    await manager.dispose();
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 15)));
}
