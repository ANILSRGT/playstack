import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import 'support/fake_reelkit_platform.dart';

List<ReelFeedItem> _items(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    ReelFeedItem(
      ReelSource.network('https://example.com/$i.mp4'),
      id: '$i',
      data: 'post $i',
    ),
];

void main() {
  late FakeReelKitPlatform platform;
  late ReelKitManager manager;

  Future<ReelFeedManager> start(
    WidgetTester tester, {
    int count = 5,
    ReelPlayerConfig player = const ReelPlayerConfig(looping: true),
  }) async {
    platform = FakeReelKitPlatform();
    manager = ReelKitManager(
      config: ReelKitConfig(player: player),
      platform: platform,
    );
    await tester.runAsync(manager.initialize);
    return manager.createFeed(
      _items(count),
      config: const ReelFeedConfig(activeHeadStart: Duration.zero),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(flush);
      await tester.pump();
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(manager.dispose);
  }

  Widget host(Widget child) => MaterialApp(
    home: Center(child: SizedBox(width: 300, height: 600, child: child)),
  );

  ReelFeedPageBuilder label(List<ReelFeedPage> seen) => (context, page) {
    seen.add(page);
    return Center(
      child: Text('${page.data} ${page.isActive ? 'active' : 'idle'}'),
    );
  };

  testWidgets('activates the first item and follows swipes', (tester) async {
    final feed = await start(tester);
    final changes = <int>[];
    await tester.pumpWidget(
      host(
        ReelFeedView(
          feed: feed,
          controlsBuilder: label([]),
          onPageChanged: changes.add,
        ),
      ),
    );
    await settle(tester);
    expect(feed.activeIndex.value, 0);
    expect(find.text('post 0 active'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(0, -400), 1500);
    await tester.pumpAndSettle();
    expect(feed.activeIndex.value, 1);
    expect(changes, [1]);
    expect(find.text('post 1 active'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('starts at initialIndex', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(ReelFeedView(feed: feed, initialIndex: 3, controlsBuilder: null)),
    );
    await settle(tester);
    expect(feed.activeIndex.value, 3);
    await finish(tester);
  });

  testWidgets('swipes horizontally when asked', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(
        ReelFeedView(
          feed: feed,
          scrollDirection: Axis.horizontal,
          controlsBuilder: null,
        ),
      ),
    );
    await settle(tester);
    await tester.fling(find.byType(PageView), const Offset(0, -400), 1500);
    await tester.pumpAndSettle();
    expect(feed.activeIndex.value, 0, reason: 'vertical swipes are ignored');

    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1500);
    await tester.pumpAndSettle();
    expect(feed.activeIndex.value, 1);
    await finish(tester);
  });

  testWidgets('the controller animates and jumps', (tester) async {
    final feed = await start(tester);
    final view = ReelFeedViewController();
    await tester.pumpWidget(
      host(ReelFeedView(feed: feed, controller: view, controlsBuilder: null)),
    );
    await settle(tester);
    expect(view.isAttached, isTrue);

    final moved = view.nextPage();
    await tester.pumpAndSettle();
    await moved;
    expect(feed.activeIndex.value, 1);

    view.jumpTo(4);
    await tester.pump();
    expect(feed.activeIndex.value, 4);
    await view.nextPage(); // last page: nothing happens
    expect(feed.activeIndex.value, 4);

    final back = view.previousPage();
    await tester.pumpAndSettle();
    await back;
    expect(feed.activeIndex.value, 3);
    expect(() => view.jumpTo(9), throwsRangeError);

    await finish(tester);
    expect(view.isAttached, isFalse);
  });

  testWidgets('builders get the page; default controls by default', (
    tester,
  ) async {
    final feed = await start(tester);
    await tester.pumpWidget(host(ReelFeedView(feed: feed)));
    await settle(tester);
    expect(find.byType(ReelDefaultControls), findsOneWidget);
    expect(find.byType(ReelMuteButton), findsOneWidget);
    expect(find.byType(ReelVideoView), findsOneWidget);

    final seen = <ReelFeedPage>[];
    await tester.pumpWidget(
      host(
        ReelFeedView(
          feed: feed,
          controlsBuilder: label(seen),
          videoBuilder: (context, page) => Text('video ${page.index}'),
        ),
      ),
    );
    expect(find.byType(ReelDefaultControls), findsNothing);
    expect(find.text('video 0'), findsOneWidget);
    final page = seen.last;
    expect(page.index, 0);
    expect(page.isActive, isTrue);
    expect(page.controller, same(feed.controllerAt(0)));
    expect(page.item.id, '0');

    await tester.pumpWidget(
      host(ReelFeedView(feed: feed, controlsBuilder: null)),
    );
    expect(find.byType(ReelDefaultControls), findsNothing);
    await finish(tester);
  });

  testWidgets('asks for more items near the end, once per length', (
    tester,
  ) async {
    final feed = await start(tester);
    var calls = 0;
    final view = ReelFeedViewController();
    await tester.pumpWidget(
      host(
        ReelFeedView(
          feed: feed,
          controller: view,
          controlsBuilder: null,
          endReachedThreshold: 2,
          onEndReached: () {
            calls++;
            feed.addAll(_items(5, from: feed.length));
          },
        ),
      ),
    );
    await settle(tester);
    expect(calls, 0);
    view.jumpTo(1);
    await settle(tester);
    expect(calls, 0);
    view.jumpTo(2);
    await settle(tester);
    expect(calls, 1);
    expect(feed.length, 10);
    view.jumpTo(3);
    await settle(tester);
    expect(calls, 1);
    view.jumpTo(9);
    await settle(tester);
    expect(calls, 2);
    await finish(tester);
  });

  testWidgets('keeps the active item in view when items are inserted above', (
    tester,
  ) async {
    final feed = await start(tester);
    final seen = <ReelFeedPage>[];
    final view = ReelFeedViewController();
    await tester.pumpWidget(
      host(
        ReelFeedView(
          feed: feed,
          controller: view,
          controlsBuilder: label(seen),
        ),
      ),
    );
    await settle(tester);
    view.jumpTo(2);
    await settle(tester);
    expect(find.text('post 2 active'), findsOneWidget);

    feed.insertAll(0, _items(2, from: 100));
    await settle(tester);
    expect(feed.activeIndex.value, 4);
    expect(view.page, 4);
    expect(find.text('post 2 active'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('runs the transition with each page offset', (tester) async {
    final feed = await start(tester);
    final offsets = <double>[];
    await tester.pumpWidget(
      host(
        ReelFeedView(
          feed: feed,
          controlsBuilder: label([]),
          transition: ReelFeedTransition.custom((context, details, child) {
            offsets.add(details.offset);
            return child;
          }),
        ),
      ),
    );
    await settle(tester);
    expect(offsets.toSet(), {0});

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -150));
    offsets.clear();
    await tester.pump();
    expect(offsets, hasLength(2));
    expect(offsets[0], closeTo(-170 / 600, 0.01));
    expect(offsets[1], closeTo(1 - 170 / 600, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('built-in transitions build while dragging', (tester) async {
    for (final transition in [
      ReelFeedTransition.parallax,
      ReelFeedTransition.stack,
      ReelFeedTransition.fade,
      ReelFeedTransition.zoom,
      ReelFeedTransition.cube,
    ]) {
      for (final reverse in [false, true]) {
        for (final axis in Axis.values) {
          final feed = await start(tester);
          await tester.pumpWidget(
            host(
              ReelFeedView(
                key: UniqueKey(),
                feed: feed,
                transition: transition,
                scrollDirection: axis,
                reverse: reverse,
                controlsBuilder: label([]),
              ),
            ),
          );
          await settle(tester);
          final delta = axis == Axis.vertical
              ? Offset(0, reverse ? 200 : -200)
              : Offset(reverse ? 120 : -120, 0);
          await tester.fling(find.byType(PageView), delta, 1500);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 30));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle();
          expect(feed.activeIndex.value, 1, reason: '$transition $axis');
          await finish(tester);
        }
      }
    }
  });

  testWidgets('the sound switch mutes the whole feed', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(host(ReelFeedView(feed: feed)));
    await settle(tester);
    expect(feed.controllerAt(0).value.isMuted, isFalse);

    await tester.tap(find.byType(ReelMuteButton));
    await settle(tester);
    expect(feed.muted, isTrue);
    expect(feed.controllerAt(0).value.isMuted, isTrue);
    expect(feed.controllerAt(1).value.isMuted, isTrue);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    feed.addAll(_items(1, from: 50));
    expect(feed.controllerAt(5).value.isMuted, isTrue);
    await finish(tester);
  });

  testWidgets('a tap pauses and resumes', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(host(ReelFeedView(feed: feed)));
    await settle(tester);
    final controller = feed.controllerAt(0);
    expect(controller.value.isPlaying, isTrue);

    await tester.tapAt(const Offset(400, 300));
    await settle(tester);
    expect(controller.value.status, ReelPlaybackStatus.paused);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    await settle(tester);
    expect(controller.value.isPlaying, isTrue);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    await finish(tester);
  });

  testWidgets('moves on when a video ends with autoAdvance', (tester) async {
    final feed = await start(
      tester,
      player: const ReelPlayerConfig(looping: false),
    );
    await tester.pumpWidget(
      host(ReelFeedView(feed: feed, autoAdvance: true, controlsBuilder: null)),
    );
    await settle(tester);
    final controller = feed.controllerAt(0);
    expect(controller.value.isPlaying, isTrue);
    final id = platform.livePlayers.firstWhere(
      (id) => platform.calls.contains('play($id)'),
    );
    platform.emit(
      ReelNativeStateEvent(
        playerId: id,
        generation: platform.generations[id]!,
        state: ReelNativePlaybackState.ended,
      ),
    );
    await tester.pumpAndSettle();
    expect(feed.activeIndex.value, 1);
    await finish(tester);
  });

  testWidgets('the buffering indicator waits before showing', (tester) async {
    final feed = await start(tester);
    final controller = feed.controllerAt(0);
    await tester.pumpWidget(
      host(
        ReelBufferingIndicator(
          controller: controller,
          delay: const Duration(seconds: 2),
          blackScreenDelay: const Duration(milliseconds: 800),
        ),
      ),
    );
    // Idle and black: the shorter delay applies.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      host(
        ReelBufferingIndicator(
          key: UniqueKey(),
          controller: controller,
          active: false,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    feed.dispose();
    await finish(tester);
  });
}
