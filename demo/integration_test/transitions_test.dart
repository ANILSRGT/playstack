import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_demo/catalog.dart';
import 'package:reelkit_demo/reels_page.dart';
import 'package:reelkit_demo/settings.dart';

/// Holds every transition halfway through a swipe for a few seconds and
/// prints `HOLD <name>` meanwhile, so a screenshot can be taken from
/// outside (`xcrun simctl io booted screenshot`). Then lets go and checks
/// the next item became active.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('transitions', (tester) async {
    final manager = ReelKitManager(config: demoKitConfig(muted: true));
    await manager.initialize();
    for (final MapEntry(key: name, value: transition)
        in demoTransitions.entries) {
      for (final axis in Axis.values) {
        final feed = manager.createFeed([
          for (var i = 0; i < 4; i++)
            ReelFeedItem(
              demoCatalog[i].source,
              id: '$name-$axis-$i',
              poster: switch (demoCatalog[i].poster) {
                final url? => NetworkImage(url),
                null => null,
              },
            ),
        ], config: demoFeedConfig);
        await tester.pumpWidget(
          MaterialApp(
            home: ReelFeedView(
              key: UniqueKey(),
              feed: feed,
              transition: transition,
              scrollDirection: axis,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 3));
        final size = tester.getSize(find.byType(PageView));
        final center = size.center(Offset.zero);
        final gesture = await tester.startGesture(center);
        final step = axis == Axis.vertical
            ? Offset(0, -size.height * 0.4 / 10)
            : Offset(-size.width * 0.4 / 10, 0);
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(step);
          await tester.pump(const Duration(milliseconds: 16));
        }
        // ignore: avoid_print
        print('HOLD $name-${axis.name}');
        await tester.pump(const Duration(seconds: 3));
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(step * 2.5);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pump(const Duration(seconds: 1));
        expect(feed.activeIndex.value, 1, reason: '$name ${axis.name}');
        await tester.pumpWidget(const SizedBox());
        feed.dispose();
      }
    }
    await manager.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
