import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';

import 'support/fake_playstack_platform.dart';

void main() {
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(flush);
      await tester.pump();
    }
  }

  Future<void> open(
    WidgetTester tester,
    PlayStackFeedPageBuilder<Object?> controls, {
    bool live = false,
  }) async {
    platform = FakePlayStackPlatform(
      videoInfo: PlayStackVideoInfo(
        width: 1080,
        height: 1920,
        duration: const Duration(seconds: 100),
        isLive: live,
      ),
    );
    manager = PlayStackManager(platform: platform);
    await tester.runAsync(manager.initialize);
    final feed = manager.createFeed([
      PlayStackFeedItem(
        const PlayStackSource.network('https://example.com/a.mp4'),
        id: 'a',
      ),
    ], config: const PlayStackFeedConfig(activeHeadStart: Duration.zero));
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 600,
            child: PlayStackFeedView<Object?>.feed(
              feed: feed,
              controlsBuilder: controls,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(manager.dispose);
  }

  testWidgets('double tap on a side seeks; more taps add up', (tester) async {
    await open(
      tester,
      (context, page) => PlayStackDefaultControls(
        page: page,
        doubleTapToSeek: const Duration(seconds: 10),
      ),
    );
    final id = platform.livePlayers.single;
    platform.positions[id] = const Duration(seconds: 30);
    await tester.tapAt(tester.getTopLeft(find.byType(PlayStackFeedView<Object?>)) + const Offset(280, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(tester.getTopLeft(find.byType(PlayStackFeedView<Object?>)) + const Offset(280, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(flush);
    expect(platform.calls, contains('seekTo($id, 40000)'));
    expect(find.text('+10 s'), findsOneWidget);

    // A third tap on the same side jumps again.
    await tester.tapAt(tester.getTopLeft(find.byType(PlayStackFeedView<Object?>)) + const Offset(280, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(flush);
    expect(find.text('+20 s'), findsOneWidget);
    expect(platform.calls, contains('seekTo($id, 50000)'));

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('+20 s'), findsNothing);
    await finish(tester);
  });

  testWidgets('dragging the progress bar shows the time under the finger', (
    tester,
  ) async {
    await open(
      tester,
      (context, page) => PlayStackDefaultControls(
        page: page,
        thumbnails: PlayStackThumbnails.builder((_) => null),
      ),
    );
    final bar = find.byType(PlayStackProgressBar);
    final bottom = tester.getBottomLeft(bar);
    final gesture = await tester.startGesture(bottom + const Offset(30, -8));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    // 150 of 300 pixels: half of 100 s.
    expect(find.text('0:50'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.text('0:50'), findsNothing);
    await finish(tester);
  });

  testWidgets('a live stream shows LIVE and returns to the edge', (
    tester,
  ) async {
    await open(tester, PlayStackDefaultControls.builder, live: true);
    final id = platform.livePlayers.single;
    platform.liveEdges[id] = const Duration(minutes: 5);
    platform.positions[id] = const Duration(minutes: 4, seconds: 30);
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(flush);
    await tester.pump();
    expect(find.text('LIVE  -0:30'), findsOneWidget);
    await tester.tap(find.text('LIVE  -0:30'));
    await tester.runAsync(flush);
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(flush);
    await tester.pump();
    expect(platform.calls, contains('seekToLiveEdge($id)'));
    expect(find.text('LIVE'), findsOneWidget);
    await finish(tester);
  });
}
