# Testing apps that use PlayStack

`playstack_test` is a fake video engine for widget and unit tests. Screens
with `PlayStackFeedView` or `PlayStackVideoView` run in `flutter test`
without a device, and you can check what they asked the engine to do.

```yaml
dev_dependencies:
  playstack_test: ^0.1.0-dev.10
```

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack_test/playstack_test.dart';

void main() {
  testWidgets('the feed plays the first video', (tester) async {
    final engine = FakePlayStackPlatform.install();
    await tester.pumpWidget(const MaterialApp(home: ReelsScreen()));
    await tester.pumpPlayStack();

    expect(engine.calls, contains('play(1)'));

    await tester.disposePlayStack();
  });
}
```

- `FakePlayStackPlatform.install()` makes the fake the engine; call it
  before the widget creates a `PlayStackManager`.
- `tester.pumpPlayStack()` lets PlayStack's asynchronous work (engine
  start, preparation, events) finish between frames.
- `tester.disposePlayStack()` removes the widgets and lets players and
  timers shut down, so the test does not end with pending timers.

## Steering the fake

| | |
| --- | --- |
| `calls` | Every engine call as text, such as `play(1)`, `seekTo(1, 30000)` |
| `livePlayers` | Ids of the players that exist |
| `positions[id] = Duration(...)` | Moves playback |
| `emit(event)` | Sends any engine event: ended, buffering, errors |
| `failingSources[source] = PlayStackException(...)` | A source that fails to prepare |
| `setNetwork(PlayStackNetworkStatus(...))` | Goes offline or on a metered network |
| `liveEdges[id]` | Makes a player a live stream with that edge |
| Constructor arguments | `videoInfo` (size, duration), `recommendedMaxPlayers` and more |

Use `FakePlayStackPlatform(...)..register()` instead of `install()` to
change constructor arguments.

## Tips

- Without `tester.runAsync`, PlayStack's timers run on the test's fake
  clock: `tester.pump(const Duration(seconds: 1))` moves them.
- To step playback through a position, set `positions` and pump in small
  steps; cues treat jumps of more than 2 s as seeks.
- Integration tests on a device or simulator use the real engine; do not
  install the fake there.
