import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';

import 'support/fake_playstack_platform.dart';

void main() {
  group('PlayStackWatchProgress', () {
    test('saves, resumes, finishes and persists through storage', () async {
      String? saved;
      final storage = PlayStackProgressStorage.keyValue(
        read: () => saved,
        write: (json) => saved = json,
      );
      final progress = PlayStackWatchProgress(storage: storage);
      await progress.load();
      expect(progress.resumePosition('a'), isNull);

      progress.update(
        'a',
        const Duration(seconds: 40),
        duration: const Duration(seconds: 100),
      );
      progress.update('b', const Duration(seconds: 2));
      expect(progress.resumePosition('a'), const Duration(seconds: 40));
      expect(progress['a']!.fraction, closeTo(0.4, 1e-9));
      expect(progress.resumePosition('b'), isNull, reason: 'barely started');
      expect(progress.unfinished.map((e) => e.id), ['a']);

      progress.update(
        'c',
        const Duration(seconds: 97),
        duration: const Duration(seconds: 100),
      );
      expect(progress['c']!.finished, isTrue);
      expect(progress.resumePosition('c'), isNull);
      await progress.flush();

      final reloaded = PlayStackWatchProgress(storage: storage);
      await reloaded.load();
      expect(reloaded.resumePosition('a'), const Duration(seconds: 40));
      expect(reloaded['c']!.finished, isTrue);
      await reloaded.remove('a');
      final again = PlayStackWatchProgress(storage: storage);
      await again.load();
      expect(again['a'], isNull);
    });

    test('tracks a controller and resumes it', () async {
      final platform = FakePlayStackPlatform(
        videoInfo: const PlayStackVideoInfo(
          width: 1920,
          height: 1080,
          duration: Duration(seconds: 100),
        ),
      );
      final manager = PlayStackManager(platform: platform);
      await manager.initialize();
      final progress = PlayStackWatchProgress();
      const source = PlayStackSource.network('https://example.com/e1.mp4');
      final controller = manager.createController(source);
      final tracking = progress.track(controller, 'e1');
      await controller.play();
      await flush();
      platform.positions[platform.livePlayers.single] = const Duration(
        seconds: 30,
      );
      await controller.pause();
      await flush();
      await Future<void>.delayed(Duration.zero);
      expect(progress.resumePosition('e1'), const Duration(seconds: 30));
      await tracking.stop();

      final next = manager.createController(
        source,
        startPosition: progress.resumePosition('e1'),
      );
      await next.initialize();
      expect(platform.calls, contains(endsWith(', 30000)')));
      await manager.dispose();
    });
  });

  group('feed series', () {
    late FakePlayStackPlatform platform;
    late PlayStackManager manager;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(flush);
        await tester.pump();
      }
    }

    Future<PlayStackFeedViewController> open(
      WidgetTester tester,
      PlayStackSeries<String> series,
    ) async {
      platform = FakePlayStackPlatform(
        videoInfo: const PlayStackVideoInfo(
          width: 1920,
          height: 1080,
          duration: Duration(seconds: 100),
        ),
      );
      manager = PlayStackManager(
        config: const PlayStackConfig(
          player: PlayStackPlayerConfig(looping: false),
        ),
        platform: platform,
      );
      await tester.runAsync(manager.initialize);
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 800,
            child: PlayStackFeedView<String>(
              items: const ['e1', 'e2', 'e3'],
              videoUrl: (id) => 'https://example.com/$id.mp4',
              itemId: (id) => id,
              manager: manager,
              controller: view,
              series: series,
            ),
          ),
        ),
      );
      await settle(tester);
      return view;
    }

    Future<void> moveTo(WidgetTester tester, Duration position) async {
      for (final id in platform.livePlayers) {
        platform.positions[id] = position;
      }
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(flush);
      }
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(manager.dispose);
    }

    testWidgets('shows a skip button inside a marker and skips it', (
      tester,
    ) async {
      final view = await open(
        tester,
        PlayStackSeries<String>(
          nextUp: null,
          skipMarkers: (_) => const [
            PlayStackSkipMarker.intro(
              start: Duration(seconds: 5),
              end: Duration(seconds: 20),
            ),
          ],
        ),
      );
      expect(find.text('Skip intro'), findsNothing);
      await moveTo(tester, const Duration(seconds: 6));
      expect(find.text('Skip intro'), findsOneWidget);
      await tester.tap(find.text('Skip intro'));
      await settle(tester);
      expect(
        platform.calls.where((c) => c.startsWith('seekTo')).last,
        endsWith('20000)'),
      );
      expect(view.index, 0);
      await finish(tester);
    });

    testWidgets('offers the next episode and moves after the countdown', (
      tester,
    ) async {
      final view = await open(
        tester,
        PlayStackSeries<String>(
          nextUp: const PlayStackNextUp(countdown: Duration(seconds: 2)),
          nextUpLabel: (next) => 'Episode $next',
        ),
      );
      await moveTo(tester, const Duration(seconds: 50));
      expect(find.text('Episode e2'), findsNothing);
      await moveTo(tester, const Duration(seconds: 91));
      expect(find.text('Episode e2'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pump();
      expect(find.text('Episode e2'), findsNothing);

      // Seeking back and reaching the end again offers it again.
      await moveTo(tester, const Duration(seconds: 10));
      await moveTo(tester, const Duration(seconds: 92));
      expect(find.text('Episode e2'), findsOneWidget);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(flush);
      }
      await tester.pumpAndSettle();
      expect(view.index, 1);
      await finish(tester);
    });
  });
}
