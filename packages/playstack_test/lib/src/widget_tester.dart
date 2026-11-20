import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_playstack_platform.dart';

/// PlayStack helpers for [WidgetTester].
extension PlayStackWidgetTester on WidgetTester {
  /// Lets PlayStack's asynchronous work (engine start, preparation, events)
  /// finish and pumps frames in between. Call it after `pumpWidget` and
  /// after interactions that start or change playback.
  Future<void> pumpPlayStack({int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await runAsync(flush);
      await pump();
    }
  }

  /// Removes the widgets under test and lets PlayStack shut down: players
  /// are released and its timers finish, so the test ends without pending
  /// timers. Call it at the end of a test that showed PlayStack widgets.
  Future<void> disposePlayStack() async {
    await pumpWidget(const SizedBox());
    await pumpPlayStack();
    // Idle players are destroyed after a delay.
    await pump(const Duration(minutes: 5));
    await pumpPlayStack();
  }
}
