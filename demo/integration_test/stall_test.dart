import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_demo/catalog.dart';

/// Watches the item the user stops on, with the demo's settings: whether
/// playback ever stops (position not advancing) and when the rendition
/// changes. Runs at a normal pace and after bursts of fast swipes, when the
/// next items preload in parallel. A measurement; results depend on the
/// network.
///
///     flutter test integration_test/stall_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<int> watch(
    String label,
    ReelFeedManager feed,
    int index, {
    Duration duration = const Duration(seconds: 7),
  }) async {
    final controller = feed.controllerAt(index);
    feed.setActiveIndex(index);
    final clock = Stopwatch()..start();
    final events = <String>[];
    int? width;
    var buffering = false;
    var last = const Duration(milliseconds: -1);
    var started = false;
    var stoppedMs = 0;
    while (clock.elapsed < duration) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final state = controller.value;
      final position = (await controller.getPosition()).position;
      final t = clock.elapsedMilliseconds;
      if (position > Duration.zero) started = true;
      if (started && position == last) {
        stoppedMs += 100;
        events.add('$t:stopped');
      }
      last = position;
      if (state.videoInfo?.width != width) {
        width = state.videoInfo?.width;
        events.add('$t:width=$width');
      }
      if (state.isBuffering != buffering) {
        buffering = state.isBuffering;
        events.add('$t:buffering=$buffering');
      }
    }
    // ignore: avoid_print
    print(
      '$label #$index ${demoCatalog[index].title}: stopped ${stoppedMs}ms '
      '${events.join(' ')}',
    );
    return stoppedMs;
  }

  testWidgets('playback never stops', (tester) async {
    final manager = ReelKitManager(config: ReelKitConfig.reels());
    await manager.initialize();
    final feed = manager.createFeed([
      for (var i = 0; i < demoCatalog.length; i++)
        ReelFeedItem(demoCatalog[i].source, id: '$i'),
    ], config: ReelFeedConfig.reels);
    var stopped = 0;
    var watched = 0;
    for (var i = 0; i < 8; i++) {
      stopped += await watch(
        'pace',
        feed,
        i,
        duration: const Duration(seconds: 12),
      );
      watched++;
    }
    for (var start = 8; start + 5 < demoCatalog.length; start += 6) {
      for (var j = start; j < start + 5; j++) {
        feed.setActiveIndex(j);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      stopped += await watch('burst', feed, start + 5);
      watched++;
    }
    // ignore: avoid_print
    print('SUMMARY stopped ${stopped}ms over $watched items, ${feed.stats}');
    await manager.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
