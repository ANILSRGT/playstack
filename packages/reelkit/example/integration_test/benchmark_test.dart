import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit_example/benchmark/reel_benchmark.dart';

import 'support/test_results.dart';

/// Milestone 7: measures start latency, preloading, rapid scrolling and
/// memory on the device, prints the report and attaches it as report data.
///
/// For representative numbers run it in profile mode on a physical device:
///
/// ```sh
/// flutter drive --profile \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/benchmark_test.dart
/// ```
///
/// The assertions only catch regressions in behavior (pool bounds, preload
/// benefit, leaks); they do not enforce timing budgets, which depend on the
/// device.
void main() {
  final binding = ensureBindingWithResults();

  testWidgets('benchmark', (tester) async {
    final results = await ReelBenchmark(
      onProgress: (step) => debugPrint('[benchmark] $step'),
    ).run();

    for (final line in results.toLines()) {
      debugPrint('[benchmark] $line');
    }
    final json = results.toJson();
    debugPrint('[benchmark-json] ${jsonEncode(json)}');
    binding.reportData = <String, dynamic>{'benchmark': json};

    final scroll = results.rapidScroll;
    expect(scroll.peakAllocated, lessThanOrEqualTo(scroll.maxPlayers));
    expect(scroll.created, lessThanOrEqualTo(scroll.maxPlayers));

    // Preparing ahead must make starts faster than preparing on demand.
    expect(results.preloadedStart.median!, lessThan(results.coldStart.median!));
    expect(results.swipe.preloadHitRate, greaterThan(0.8));

    final memory = results.memory;
    expect(memory.playersCreated, memory.playersDisposed);
    final growth = memory.growth;
    if (growth != null) {
      // Each cycle creates and destroys a native player with a 1080p
      // decoder; a leak of either would add megabytes per cycle.
      expect(growth, lessThan(32 * 1024 * 1024));
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
