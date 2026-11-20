import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';

import 'support/fake_playstack_platform.dart';

void main() {
  group('PlayStackCueController', () {
    late FakePlayStackPlatform platform;
    late PlayStackManager manager;
    const source = PlayStackSource.network('https://example.com/movie.mp4');

    setUp(() async {
      platform = FakePlayStackPlatform(
        videoInfo: const PlayStackVideoInfo(
          width: 1920,
          height: 1080,
          duration: Duration(seconds: 100),
        ),
      );
      manager = PlayStackManager(platform: platform);
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    Future<void> playTo(PlayStackPlayerController controller, int seconds) async {
      final id = controller.nativePlayerId!;
      final from = (platform.positions[id] ?? Duration.zero).inSeconds;
      for (var s = from + 1; s <= seconds; s++) {
        platform.positions[id] = Duration(seconds: s);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await flush();
    }

    test('fires when playback reaches a cue, pauses until handled', () async {
      final controller = manager.createController(source);
      final handled = Completer<void>();
      final fired = <String?>[];
      final cues = PlayStackCueController(
        controller: controller,
        cues: const [
          PlayStackCue(at: Duration(seconds: 3), id: 'poll', pause: true),
        ],
        onCue: (cue) {
          fired.add(cue.id);
          return handled.future;
        },
      );
      await controller.play();
      await flush();
      await playTo(controller, 2);
      expect(fired, isEmpty);
      await playTo(controller, 4);
      expect(fired, ['poll']);
      expect(cues.active?.id, 'poll');
      expect(controller.value.isPlaying, isFalse);

      handled.complete();
      await flush();
      await flush();
      expect(cues.active, isNull);
      expect(controller.value.isPlaying, isTrue);
      expect(cues.pending, isEmpty);
      cues.dispose();
    });

    test('seeking past a cue does not fire it', () async {
      final controller = manager.createController(source);
      final fired = <String?>[];
      final cues = PlayStackCueController(
        controller: controller,
        cues: const [PlayStackCue(at: Duration(seconds: 30), id: 'x')],
        onCue: (cue) => fired.add(cue.id),
      );
      await controller.play();
      await flush();
      await playTo(controller, 1);
      await controller.seekTo(const Duration(seconds: 50));
      await playTo(controller, 52);
      expect(fired, isEmpty);
      cues.dispose();
    });

    test('a cue from the end is placed by the length', () async {
      final controller = manager.createController(source);
      final fired = <String?>[];
      final cues = PlayStackCueController(
        controller: controller,
        cues: const [PlayStackCue.fromEnd(Duration(seconds: 10), id: 'rate')],
        onCue: (cue) => fired.add(cue.id),
      );
      expect(
        const PlayStackCue.fromEnd(
          Duration(seconds: 10),
        ).positionIn(const Duration(seconds: 100)),
        const Duration(seconds: 90),
      );
      await controller.play();
      await flush();
      await controller.seekTo(const Duration(seconds: 88));
      await playTo(controller, 91);
      expect(fired, ['rate']);
      cues.dispose();
    });
  });

  group('feed cues', () {
    late FakePlayStackPlatform platform;
    late PlayStackManager manager;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(flush);
        await tester.pump();
      }
    }

    testWidgets('the next item waits for onTransition', (tester) async {
      platform = FakePlayStackPlatform(
        videoInfo: const PlayStackVideoInfo(
          width: 1920,
          height: 1080,
          duration: Duration(seconds: 100),
        ),
      );
      manager = PlayStackManager(platform: platform);
      await tester.runAsync(manager.initialize);
      final view = PlayStackFeedViewController();
      final gate = Completer<void>();
      final moves = <PlayStackTransition<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 800,
            child: PlayStackFeedView<String>(
              items: const ['e1', 'e2', 'e3'],
              videoUrl: (id) => 'https://example.com/$id.mp4',
              manager: manager,
              controller: view,
              cues: PlayStackFeedCues<String>(
                onTransition: (context, move) {
                  moves.add(move);
                  return gate.future;
                },
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final first = view.feed!.controllerAt(0);
      expect(first.value.isPlaying, isTrue);

      unawaited(view.nextPage());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle(tester);
      expect(moves.single.from, 'e1');
      expect(moves.single.to, 'e2');
      expect(moves.single.count, 1);
      expect(moves.single.isForward, isTrue);
      final second = view.feed!.controllerAt(1);
      expect(second.value.isPlaying, isFalse);

      gate.complete();
      await settle(tester);
      expect(second.value.isPlaying, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(manager.dispose);
    });
  });
}
