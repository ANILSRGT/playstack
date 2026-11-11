import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_demo/catalog.dart';
import 'package:reelkit_demo/settings.dart';

/// Swipes through the demo feed with the demo's settings at about three
/// videos a second and prints, per swipe, whether the item was prepared on
/// arrival and when it showed a frame and started moving. A measurement,
/// not a pass/fail check: results depend on the network.
///
///     flutter test integration_test/swipe_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fast swipes', (tester) async {
    const dwell = Duration(milliseconds: 350);
    final manager = ReelKitManager(config: demoKitConfig(muted: true));
    await manager.initialize();
    final feed = manager.createFeed([
      for (var i = 0; i < demoCatalog.length; i++)
        ReelFeedItem(demoCatalog[i].source, id: '$i'),
    ], config: demoFeedConfig);
    var withFrame = 0;
    var moving = 0;
    for (var i = 0; i < demoCatalog.length; i++) {
      final controller = feed.controllerAt(i);
      final prepared = controller.value.isInitialized;
      final watch = Stopwatch()..start();
      feed.setActiveIndex(i);
      int? frameAt;
      int? movingAt;
      while (watch.elapsed < dwell) {
        if (frameAt == null && controller.value.hasRenderedFirstFrame) {
          frameAt = watch.elapsedMilliseconds;
        }
        if (movingAt == null && controller.value.isPlaying) {
          final position = await controller.getPosition();
          if (position.position > Duration.zero) {
            movingAt = watch.elapsedMilliseconds;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (frameAt != null && frameAt < 150) withFrame++;
      if (movingAt != null) moving++;
      // ignore: avoid_print
      print(
        '#$i prepared=$prepared frame=${frameAt ?? '-'} '
        'moving=${movingAt ?? '-'} ${demoCatalog[i].title}',
      );
    }
    final n = demoCatalog.length;
    // ignore: avoid_print
    print(
      'SUMMARY ${dwell.inMilliseconds} ms per swipe: frame within 150 ms '
      '$withFrame/$n, moving within the swipe $moving/$n, ${feed.stats}',
    );
    await manager.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
