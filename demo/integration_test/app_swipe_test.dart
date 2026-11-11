import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_demo/main.dart';

/// Drives the real demo UI: swipes, then logs when the loading spinner is
/// on screen and what the active player reports meanwhile.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('spinner during playback', (tester) async {
    await tester.pumpWidget(const DemoApp());

    ReelPlayerController? active() {
      for (final element in find.byType(ReelVideoView).evaluate()) {
        final view = element.widget as ReelVideoView;
        if (view.controller.priority == ReelPlayerPriority.active) {
          return view.controller;
        }
      }
      return null;
    }

    for (var swipe = 0; swipe < 8; swipe++) {
      final watch = Stopwatch()..start();
      var spinner = false;
      String? last;
      final log = <String>[];
      while (watch.elapsed < const Duration(seconds: 6)) {
        await tester.pump(const Duration(milliseconds: 50));
        final shown = find
            .byType(CircularProgressIndicator)
            .evaluate()
            .isNotEmpty;
        final c = active();
        final s = c?.value;
        final line =
            '${s?.status.name} buf=${s?.isBuffering} '
            'w=${s?.videoInfo?.width} frame=${s?.hasRenderedFirstFrame}';
        if (shown != spinner || line != last) {
          log.add('${watch.elapsedMilliseconds}: spinner=$shown $line');
          spinner = shown;
          last = line;
        }
      }
      // ignore: avoid_print
      print('swipe $swipe\n  ${log.join('\n  ')}');
      await tester.fling(find.byType(PageView), const Offset(0, -500), 2000);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
