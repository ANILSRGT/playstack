// Walks through the demo app at a viewer's pace, for the recording in the
// README (packages/playstack/doc/demo.webp). See ../README.md.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/record_demo_test.dart -d <simulator>
//
// while `xcrun simctl io <simulator> recordVideo` records the screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:playstack_demo/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo tour', (tester) async {
    Future<void> wait(double seconds) =>
        tester.pump(Duration(milliseconds: (seconds * 1000).round()));
    Size screen() => tester.view.physicalSize / tester.view.devicePixelRatio;
    Future<void> swipeUp() async {
      final size = screen();
      await tester.timedDragFrom(
        Offset(size.width / 2, size.height * 0.75),
        Offset(0, -size.height * 0.5),
        const Duration(milliseconds: 280),
      );
    }

    /// Waits until [finder] shows, up to [timeout] seconds.
    Future<bool> waitFor(Finder finder, {double timeout = 12}) async {
      for (var i = 0; i < timeout * 10; i++) {
        if (finder.evaluate().isNotEmpty) return true;
        await wait(0.1);
      }
      return false;
    }

    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await wait(1.2);
    }

    unawaited(app.main());
    await wait(4);
    debugPrint('[tour] start');

    // Reels.
    await tester.tap(find.text('Reels'));
    await wait(4);
    final size = screen();
    final center = Offset(size.width / 2, size.height * 0.45);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center); // a double tap: like
    await wait(2);
    await swipeUp();
    await wait(3);
    // Drag sideways to seek, with the preview above the bar.
    final drag = await tester.startGesture(
      Offset(size.width * 0.2, size.height * 0.5),
    );
    for (var step = 0; step < 50; step++) {
      await drag.moveBy(Offset(size.width * 0.011, 0));
      await wait(step % 10 == 9 ? 0.5 : 0.04); // pauses to show the preview
    }
    await wait(0.6);
    await drag.up();
    await wait(2.5);
    await swipeUp();
    await wait(3);
    await back();

    // Drama.
    await tester.tap(find.text('Drama'));
    await wait(2.5);
    await tester.tap(find.textContaining('episode 1').first);
    final skip = find.textContaining('Skip intro');
    if (await waitFor(skip)) {
      await wait(1.2);
      await tester.tap(skip.first);
    }
    final yes = find.text('Yes'); // the poll, at 0:06
    if (await waitFor(yes)) {
      await wait(2);
      await tester.tap(yes.first);
    }
    await wait(2.5);
    await swipeUp(); // episode 2, with a pre-roll ad
    await wait(4.5);
    await swipeUp(); // episode 3
    await wait(3);
    await swipeUp(); // episode 4: an interstitial first
    await wait(4.5);
    final close = find.byIcon(Icons.close_rounded);
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close.last);
    }
    await wait(1.5);
    await back();
    await back();

    // Live.
    await tester.tap(find.text('Live'));
    await wait(6);
    debugPrint('[tour] end');
    await back();
    await wait(1);
  });
}
