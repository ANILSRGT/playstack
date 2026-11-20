# playstack_test

Test helpers for apps that use [PlayStack](https://pub.dev/packages/playstack):
a fake video engine, so screens with `PlayStackFeedView` or
`PlayStackVideoView` run in `flutter test` without a device, and you can
check what they asked the engine to do.

## Install

```yaml
dev_dependencies:
  playstack_test: ^0.1.0-dev.10
```

## Use

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

- `FakePlayStackPlatform.install()` makes the fake the engine. Call it
  before the widget creates a `PlayStackManager`.
- `tester.pumpPlayStack()` lets PlayStack's asynchronous work finish
  between frames.
- `tester.disposePlayStack()` removes the widgets and lets players and
  timers shut down, so the test ends without pending timers.

Steer the fake: `positions[id]` moves playback, `emit(event)` sends any
engine event, `failingSources` fails a source, `setNetwork(...)` goes
offline, `liveEdges[id]` makes a live stream. `calls` lists every engine
call as text.

More: [Testing guide](https://github.com/ANILSRGT/playstack/blob/main/docs/guides/testing.md).
