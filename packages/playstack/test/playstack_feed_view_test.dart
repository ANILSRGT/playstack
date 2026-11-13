import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import 'support/fake_playstack_platform.dart';

List<PlayStackFeedItem> _items(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    PlayStackFeedItem(
      PlayStackSource.network('https://example.com/$i.mp4'),
      id: '$i',
      data: 'post $i',
    ),
];

void main() {
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;

  Future<PlayStackFeedManager> start(
    WidgetTester tester, {
    int count = 5,
    PlayStackPlayerConfig player = const PlayStackPlayerConfig(looping: true),
  }) async {
    platform = FakePlayStackPlatform();
    manager = PlayStackManager(
      config: PlayStackConfig(player: player),
      platform: platform,
    );
    await tester.runAsync(manager.initialize);
    return manager.createFeed(
      _items(count),
      config: const PlayStackFeedConfig(activeHeadStart: Duration.zero),
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

  PlayStackFeedPageBuilder<Object?> label(
    List<PlayStackFeedPage<Object?>> seen,
  ) => (context, page) {
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
        PlayStackFeedView<Object?>.feed(
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
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          initialIndex: 3,
          controlsBuilder: null,
        ),
      ),
    );
    await settle(tester);
    expect(feed.activeIndex.value, 3);
    await finish(tester);
  });

  testWidgets('swipes horizontally when asked', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
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
    final view = PlayStackFeedViewController();
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controller: view,
          controlsBuilder: null,
        ),
      ),
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
    await tester.pumpWidget(host(PlayStackFeedView<Object?>.feed(feed: feed)));
    await settle(tester);
    expect(find.byType(PlayStackDefaultControls), findsOneWidget);
    expect(find.byType(PlayStackMuteButton), findsOneWidget);
    expect(find.byType(PlayStackVideoView), findsOneWidget);

    final seen = <PlayStackFeedPage<Object?>>[];
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: label(seen),
          videoBuilder: (context, page) => Text('video ${page.index}'),
        ),
      ),
    );
    expect(find.byType(PlayStackDefaultControls), findsNothing);
    expect(find.text('video 0'), findsOneWidget);
    final page = seen.last;
    expect(page.index, 0);
    expect(page.isActive, isTrue);
    expect(page.controller, same(feed.controllerAt(0)));
    expect(page.item.id, '0');

    await tester.pumpWidget(
      host(PlayStackFeedView<Object?>.feed(feed: feed, controlsBuilder: null)),
    );
    expect(find.byType(PlayStackDefaultControls), findsNothing);
    await finish(tester);
  });

  testWidgets('asks for more items near the end, once per length', (
    tester,
  ) async {
    final feed = await start(tester);
    var calls = 0;
    final view = PlayStackFeedViewController();
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controller: view,
          controlsBuilder: null,
          loadMoreThreshold: 2,
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
    final seen = <PlayStackFeedPage<Object?>>[];
    final view = PlayStackFeedViewController();
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
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
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: label([]),
          transition: PlayStackFeedTransition.custom((context, details, child) {
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
      PlayStackFeedTransition.parallax,
      PlayStackFeedTransition.stack,
      PlayStackFeedTransition.fade,
      PlayStackFeedTransition.zoom,
      PlayStackFeedTransition.cube,
    ]) {
      for (final reverse in [false, true]) {
        for (final axis in Axis.values) {
          final feed = await start(tester);
          await tester.pumpWidget(
            host(
              PlayStackFeedView<Object?>.feed(
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
    await tester.pumpWidget(host(PlayStackFeedView<Object?>.feed(feed: feed)));
    await settle(tester);
    expect(feed.controllerAt(0).value.isMuted, isFalse);

    await tester.tap(find.byType(PlayStackMuteButton));
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
    await tester.pumpWidget(host(PlayStackFeedView<Object?>.feed(feed: feed)));
    await settle(tester);
    final controller = feed.controllerAt(0);
    expect(controller.value.isPlaying, isTrue);

    await tester.tapAt(const Offset(400, 300));
    await settle(tester);
    expect(controller.value.status, PlayStackPlaybackStatus.paused);
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
      player: const PlayStackPlayerConfig(looping: false),
    );
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          autoAdvance: true,
          controlsBuilder: null,
        ),
      ),
    );
    await settle(tester);
    final controller = feed.controllerAt(0);
    expect(controller.value.isPlaying, isTrue);
    final id = platform.livePlayers.firstWhere(
      (id) => platform.calls.contains('play($id)'),
    );
    platform.emit(
      PlayStackNativeStateEvent(
        playerId: id,
        generation: platform.generations[id]!,
        state: PlayStackNativePlaybackState.ended,
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
        PlayStackBufferingIndicator(
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
        PlayStackBufferingIndicator(
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

  int playingPlayer() => platform.livePlayers.firstWhere(
    (id) => platform.calls.contains('play($id)'),
  );

  testWidgets('pauses under a pushed route and resumes after pop', (
    tester,
  ) async {
    final feed = await start(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: null,
        ),
      ),
    );
    await settle(tester);
    final controller = feed.controllerAt(0);
    expect(controller.value.isPlaying, isTrue);

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('profile')),
      ),
    );
    await tester.pumpAndSettle();
    await settle(tester);
    expect(feed.isPaused, isTrue);
    expect(controller.value.isPlaying, isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await settle(tester);
    expect(feed.isPaused, isFalse);
    expect(controller.value.isPlaying, isTrue);
    await finish(tester);
  });

  testWidgets('keeps playing when hidden with pauseWhenHidden off', (
    tester,
  ) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(
        TickerMode(
          enabled: false,
          child: PlayStackFeedView<Object?>.feed(
            feed: feed,
            pauseWhenHidden: false,
            controlsBuilder: null,
          ),
        ),
      ),
    );
    await settle(tester);
    expect(feed.isPaused, isFalse);
    expect(feed.controllerAt(0).value.isPlaying, isTrue);
    await finish(tester);
  });

  testWidgets('a hidden tab pauses, the shown tab plays', (tester) async {
    final feed = await start(tester);
    Widget build({required bool shown}) => host(
      TickerMode(
        enabled: shown,
        child: PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: null,
        ),
      ),
    );
    await tester.pumpWidget(build(shown: true));
    await settle(tester);
    expect(feed.controllerAt(0).value.isPlaying, isTrue);

    await tester.pumpWidget(build(shown: false));
    await settle(tester);
    expect(feed.isPaused, isTrue);

    await tester.pumpWidget(build(shown: true));
    await settle(tester);
    expect(feed.isPaused, isFalse);
    expect(feed.controllerAt(0).value.isPlaying, isTrue);
    await finish(tester);
  });

  testWidgets('the controller pauses and resumes the feed', (tester) async {
    final feed = await start(tester);
    final view = PlayStackFeedViewController();
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controller: view,
          controlsBuilder: null,
        ),
      ),
    );
    await settle(tester);
    view.pause();
    await settle(tester);
    expect(view.isPaused, isTrue);
    expect(feed.controllerAt(0).value.isPlaying, isFalse);

    view.resume();
    await settle(tester);
    expect(view.isPaused, isFalse);
    expect(feed.controllerAt(0).value.isPlaying, isTrue);
    await finish(tester);
    view.dispose();
  });

  testWidgets('does not resume a feed the app paused itself', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(PlayStackFeedView<Object?>.feed(feed: feed, controlsBuilder: null)),
    );
    await settle(tester);
    feed.pause();
    Widget hidden(bool value) => host(
      TickerMode(
        enabled: !value,
        child: PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: null,
        ),
      ),
    );
    await tester.pumpWidget(hidden(true));
    await settle(tester);
    await tester.pumpWidget(hidden(false));
    await settle(tester);
    expect(feed.isPaused, isTrue);
    await finish(tester);
  });

  testWidgets('reports how each item was watched', (tester) async {
    final feed = await start(
      tester,
      player: const PlayStackPlayerConfig(looping: false),
    );
    final views = <PlayStackItemView<Object?>>[];
    // The app rebuilds from its reports, even when the view is removed.
    final notifier = ValueNotifier(0);
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: null,
          onItemViewed: (view) {
            views.add(view);
            notifier.value++;
          },
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(views, isEmpty, reason: 'reported when the user leaves');

    await tester.fling(find.byType(PageView), const Offset(0, -400), 1500);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(views, hasLength(1));
    final first = views.single;
    expect(first.data, 'post 0');
    expect(first.index, 0);
    expect(first.item.id, '0');
    expect(first.watchTime, greaterThan(Duration.zero));
    expect(first.duration, const Duration(seconds: 30));
    expect(first.completed, isFalse);
    expect(first.watchedFraction, lessThan(0.5));

    // The second video plays to its end.
    final id = platform.livePlayers.lastWhere(
      (id) => platform.calls.contains('play($id)'),
    );
    platform.emit(
      PlayStackNativeStateEvent(
        playerId: id,
        generation: platform.generations[id]!,
        state: PlayStackNativePlaybackState.ended,
      ),
    );
    await settle(tester);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: notifier,
        builder: (_, _, _) => const SizedBox(),
      ),
    );
    expect(views, hasLength(2), reason: 'removing the view reports too');
    expect(views.last.data, 'post 1');
    expect(views.last.completed, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(manager.dispose);
  });

  testWidgets('buttons in the child are not delayed by double tap', (
    tester,
  ) async {
    final feed = await start(tester);
    var taps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: (context, page) => PlayStackDefaultControls(
            page: page,
            onDoubleTap: () => doubleTaps++,
            child: Align(
              alignment: Alignment.topLeft,
              child: GestureDetector(
                key: const ValueKey('button'),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.square(dimension: 48),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    final button = find.byKey(const ValueKey('button')).hitTestable();
    await tester.tap(button);
    await tester.pump();
    expect(taps, 1, reason: 'no wait for a second tap');

    // Empty parts still reach the double tap.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(doubleTaps, 1);
    await finish(tester);
  });

  testWidgets('holding pauses until release', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(host(PlayStackFeedView<Object?>.feed(feed: feed)));
    await settle(tester);
    final controller = feed.controllerAt(0);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await settle(tester);
    expect(controller.value.status, PlayStackPlaybackStatus.paused);
    expect(
      find.byIcon(Icons.play_arrow_rounded),
      findsNothing,
      reason: 'a hold is not a tap pause',
    );

    await gesture.up();
    await settle(tester);
    expect(controller.value.isPlaying, isTrue);
    await finish(tester);
  });

  testWidgets('holding with speedUp plays faster until release', (
    tester,
  ) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: (context, page) => PlayStackDefaultControls(
            page: page,
            holdAction: PlayStackHoldAction.speedUp,
          ),
        ),
      ),
    );
    await settle(tester);
    final controller = feed.controllerAt(0);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await settle(tester);
    expect(controller.value.playbackSpeed, 2.0);
    expect(controller.value.isPlaying, isTrue);
    expect(find.text('2x'), findsOneWidget);

    await gesture.up();
    await settle(tester);
    expect(controller.value.playbackSpeed, 1.0);
    expect(find.text('2x'), findsNothing);
    await finish(tester);
  });

  testWidgets('dragging the progress bar seeks', (tester) async {
    final feed = await start(tester);
    await tester.pumpWidget(host(PlayStackFeedView<Object?>.feed(feed: feed)));
    await settle(tester);
    final bar = find.byType(PlayStackProgressBar);
    expect(bar, findsOneWidget);
    final rect = tester.getRect(bar);
    expect(rect.height, 24, reason: 'a touch area, not a 2 px line');

    final gesture = await tester.startGesture(
      Offset(rect.left + 10, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.left + rect.width / 2, rect.center.dy));
    await tester.pump();
    await gesture.up();
    await settle(tester);
    final id = playingPlayer();
    expect(platform.calls, contains('seekTo($id, 15000)'));
    expect(feed.activeIndex.value, 0, reason: 'the feed did not move');
    await finish(tester);
  });

  testWidgets('a progress bar that is not seekable ignores the finger', (
    tester,
  ) async {
    final feed = await start(tester);
    await tester.pumpWidget(
      host(
        PlayStackFeedView<Object?>.feed(
          feed: feed,
          controlsBuilder: (context, page) =>
              PlayStackDefaultControls(page: page, seekable: false),
        ),
      ),
    );
    await settle(tester);
    final rect = tester.getRect(find.byType(PlayStackProgressBar));
    expect(rect.height, 2);
    await finish(tester);
  });

  group('items', () {
    late FakePlayStackPlatform engine;

    setUp(() {
      engine = FakePlayStackPlatform();
      PlayStackPlatform.instance = engine;
    });

    Future<void> run(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(flush);
        await tester.pump();
      }
    }

    testWidgets('a list of URLs is all it takes', (tester) async {
      await tester.pumpWidget(
        host(
          const PlayStackFeedView(
            items: ['https://example.com/a.m3u8', 'https://example.com/b.m3u8'],
          ),
        ),
      );
      await run(tester);
      expect(find.byType(PlayStackDefaultControls), findsOneWidget);
      expect(engine.calls.where((c) => c.startsWith('play(')), hasLength(1));
      expect(engine.livePlayers, isNotEmpty);

      await tester.fling(find.byType(PageView), const Offset(0, -400), 1500);
      await tester.pumpAndSettle();
      await run(tester);
      expect(engine.calls.where((c) => c.startsWith('play(')), hasLength(2));

      // The view created the players, so it releases them all.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      expect(engine.livePlayers, isEmpty);
    });

    testWidgets('builders get the app item, typed', (tester) async {
      final posts = [for (var i = 0; i < 3; i++) _Post('p$i')];
      final seen = <_Post>[];
      await tester.pumpWidget(
        host(
          PlayStackFeedView<_Post>(
            items: posts,
            videoUrl: (post) => post.url,
            posterUrl: (post) => '${post.url}.jpg',
            controlsBuilder: (context, page) {
              seen.add(page.data);
              return Text('${page.data.id} ${page.isActive}');
            },
          ),
        ),
      );
      await run(tester);
      expect(find.text('p0 true'), findsOneWidget);
      expect(seen.first, same(posts.first));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
    });

    testWidgets('says what is missing without videoUrl', (tester) async {
      await tester.pumpWidget(
        host(PlayStackFeedView<_Post>(items: [_Post('x')])),
      );
      final error = tester.takeException();
      expect(error, isArgumentError);
      expect('$error', contains('videoUrl'));
    });

    testWidgets('loads more until the source runs dry', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        host(
          PlayStackFeedView<String>(
            items: const ['https://example.com/0.m3u8'],
            controlsBuilder: null,
            onLoadMore: () async {
              calls++;
              return calls <= 2
                  ? [
                      'https://example.com/$calls-a.m3u8',
                      'https://example.com/$calls-b.m3u8',
                    ]
                  : const <String>[];
            },
          ),
        ),
      );
      await run(tester);
      // Near the end from the start: one page of two, then another
      // (still within three of the end), then the user is far enough.
      expect(calls, 2);
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.childrenDelegate.estimatedChildCount, 5);

      await tester.fling(find.byType(PageView), const Offset(0, -400), 1500);
      await tester.pumpAndSettle();
      await run(tester);
      expect(calls, 3, reason: 'the empty page ends it');
      await tester.fling(find.byType(PageView), const Offset(0, -400), 1500);
      await tester.pumpAndSettle();
      await run(tester);
      expect(calls, 3, reason: 'no more after an empty page');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
    });

    testWidgets('a longer items list appends, another one replaces', (
      tester,
    ) async {
      final view = PlayStackFeedViewController();
      Widget build(List<String> urls) => host(
        PlayStackFeedView<String>(
          items: urls,
          controller: view,
          controlsBuilder: (context, page) => Text(page.data),
        ),
      );
      const a = 'https://example.com/a.m3u8';
      const b = 'https://example.com/b.m3u8';
      const c = 'https://example.com/c.m3u8';
      await tester.pumpWidget(build(const [a]));
      await run(tester);
      final first = view.feed!.controllerAt(0);

      await tester.pumpWidget(build(const [a, b]));
      await run(tester);
      expect(view.feed!.length, 2);
      expect(view.feed!.controllerAt(0), same(first), reason: 'kept playing');

      await tester.pumpWidget(build(const [c]));
      await run(tester);
      expect(view.feed!.length, 1);
      expect(find.text(c), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
    });

    testWidgets('pull to refresh replaces the items', (tester) async {
      var refreshes = 0;
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView<String>(
            items: const [
              'https://example.com/a.m3u8',
              'https://example.com/b.m3u8',
            ],
            controller: view,
            controlsBuilder: (context, page) => Text(page.data),
            onRefresh: () async {
              refreshes++;
              return const ['https://example.com/new.m3u8'];
            },
          ),
        ),
      );
      await run(tester);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(0, 400), 1500);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(view.feed!.length, 1);
      expect(view.index, 0);
      expect(find.text('https://example.com/new.m3u8'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('pull to refresh works with iOS bouncing', (tester) async {
      var refreshes = 0;
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView<String>(
            items: const [
              'https://example.com/a.m3u8',
              'https://example.com/b.m3u8',
            ],
            controller: view,
            controlsBuilder: (context, page) => Text(page.data),
            onRefresh: () async {
              refreshes++;
              return const ['https://example.com/new.m3u8'];
            },
          ),
        ),
      );
      await run(tester);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(0, 400), 1500);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(view.feed!.length, 1);
      expect(view.index, 0);
      expect(find.text('https://example.com/new.m3u8'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('no pull to refresh without onRefresh', (tester) async {
      await tester.pumpWidget(
        host(const PlayStackFeedView(items: ['https://example.com/a.m3u8'])),
      );
      await run(tester);
      expect(find.byType(RefreshIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
    });

    testWidgets('pull to refresh works without MaterialApp', (tester) async {
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => PlayStackFeedView<String>(
            items: const ['https://example.com/a.m3u8'],
            controlsBuilder: null,
            onRefresh: () async => const [],
          ),
        ),
      );
      await run(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
    });

    testWidgets('autoAdvance turns looping off in the view\'s manager', (
      tester,
    ) async {
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView(
            items: const ['https://example.com/a.m3u8'],
            controller: view,
            autoAdvance: true,
          ),
        ),
      );
      await run(tester);
      expect(view.manager!.config.player.looping, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('startPosition prepares each video at its point', (
      tester,
    ) async {
      final views = <PlayStackItemView<_Post>>[];
      final posts = [_Post('a'), _Post('b'), _Post('c')];
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView<_Post>(
            items: posts,
            videoUrl: (post) => post.url,
            controller: view,
            controlsBuilder: null,
            startPosition: (post) => switch (post.id) {
              'a' => const Duration(seconds: 12),
              'b' => const Duration(seconds: 29, milliseconds: 500), // near end
              _ => null,
            },
            onItemViewed: views.add,
          ),
        ),
      );
      await run(tester);
      final first = view.feed!.controllerAt(0);
      expect(first.value.isPlaying, isTrue);
      expect(engine.calls.where((c) => c.startsWith('seekTo(')), [
        contains(', 12000)'),
      ], reason: 'only a; b is in its last second, c has none');
      // Seeked before playing.
      final seek = engine.calls.indexWhere((c) => c.endsWith(', 12000)'));
      final play = engine.calls.indexWhere((c) => c.startsWith('play('));
      expect(seek, lessThan(play));

      view.jumpTo(2);
      await run(tester);
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      expect(views, isNotEmpty);
      expect(views.first.data, posts.first);
      expect(views.first.position, const Duration(seconds: 12));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('jumps to an item by your object', (tester) async {
      final posts = [_Post('a'), _Post('b'), _Post('c'), _Post('d')];
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView<_Post>(
            items: posts,
            videoUrl: (post) => post.url,
            controller: view,
            controlsBuilder: (context, page) => Text(page.data.id),
          ),
        ),
      );
      await run(tester);
      expect(view.indexOfItem(posts[2]), 2);
      expect(view.indexOfItem(_Post('z')), -1);

      view.jumpToItem(posts[3]);
      await tester.pumpAndSettle();
      await run(tester);
      expect(view.index, 3);
      expect(find.text('d'), findsOneWidget);

      unawaited(view.animateToItem(posts[1]));
      await tester.pumpAndSettle();
      expect(view.index, 1);
      expect(() => view.jumpToItem(_Post('z')), throwsArgumentError);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('items without video are built by pageBuilder', (tester) async {
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView<String>(
            items: const [
              'https://example.com/a.m3u8',
              'ad',
              'https://example.com/b.m3u8',
            ],
            videoUrl: (item) => item == 'ad' ? null : item,
            controller: view,
            controlsBuilder: (context, page) => Text('video ${page.index}'),
            pageBuilder: (context, item, isActive) =>
                Text('page $item ${isActive ? 'active' : 'idle'}'),
          ),
        ),
      );
      await run(tester);
      expect(view.feed!.itemAt(1).isVideo, isFalse);
      view.jumpTo(1);
      await tester.pumpAndSettle();
      await run(tester);
      expect(find.text('page ad active'), findsOneWidget);
      expect(view.feed!.activeController, isNull);
      expect(
        view.feed!.controllerAt(2).value.isInitialized,
        isTrue,
        reason: 'the video after the ad is prepared',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets(
      'a list on a page scrolls first, then hands the swipe to the feed',
      (tester) async {
        final view = PlayStackFeedViewController();
        final list = ScrollController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: PlayStackFeedView<String>(
                  items: const [
                    'https://example.com/a.m3u8',
                    'card',
                    'https://example.com/b.m3u8',
                  ],
                  videoUrl: (item) => item == 'card' ? null : item,
                  controller: view,
                  initialIndex: 1,
                  controlsBuilder: null,
                  pageBuilder: (context, item, isActive) => ListView(
                    controller: list,
                    children: [
                      for (var i = 0; i < 30; i++)
                        SizedBox(height: 50, child: Text('row $i')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await run(tester);
        expect(view.index, 1);

        // Inside the list: the list scrolls, the feed stays.
        await tester.drag(find.text('row 2'), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(list.offset, greaterThan(0));
        expect(view.index, 1);

        // At the end of the list, pulling on moves to the next page.
        list.jumpTo(list.position.maxScrollExtent);
        await tester.pump();
        await tester.timedDrag(
          find.byType(ListView),
          const Offset(0, -200),
          const Duration(milliseconds: 300),
        );
        await tester.pumpAndSettle();
        await run(tester);
        expect(view.index, 2);

        // Back on the card, at the top, pulling down goes to the previous page.
        view.jumpTo(1);
        await tester.pumpAndSettle();
        list.jumpTo(0);
        await tester.pump();
        await tester.timedDrag(
          find.byType(ListView),
          const Offset(0, 200),
          const Duration(milliseconds: 300),
        );
        await tester.pumpAndSettle();
        await run(tester);
        expect(view.index, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await run(tester);
        view.dispose();
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('locked items show lockedBuilder until unlocked', (
      tester,
    ) async {
      final view = PlayStackFeedViewController();
      final unlocked = <String>{};
      Widget build() => host(
        PlayStackFeedView<String>(
          items: const [
            'https://example.com/1.m3u8',
            'https://example.com/2.m3u8',
          ],
          controller: view,
          isLocked: (url) => url.contains('2') && !unlocked.contains(url),
          lockedBuilder: (context, url, isActive) => const Text('paywall'),
          controlsBuilder: (context, page) => Text('playing ${page.index}'),
        ),
      );
      await tester.pumpWidget(build());
      await run(tester);
      view.jumpTo(1);
      await tester.pumpAndSettle();
      await run(tester);
      expect(find.text('paywall'), findsOneWidget);
      expect(view.feed!.activeController, isNull);

      unlocked.add('https://example.com/2.m3u8');
      await tester.pumpWidget(build());
      await run(tester);
      expect(find.text('paywall'), findsNothing);
      expect(view.feed!.activeController!.value.isPlaying, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('a preload prepares videos before the view opens', (
      tester,
    ) async {
      late PlayStackFeedPreload<String> preload;
      await tester.runAsync(() async {
        preload = PlayStackFeedPreload<String>(
          items: const [
            'https://example.com/p0.m3u8',
            'https://example.com/p1.m3u8',
            'https://example.com/p2.m3u8',
          ],
        );
        await preload.ready;
      });
      final prepared = engine.calls.where((c) => c.startsWith('setSource('));
      expect(prepared, hasLength(2), reason: 'count: 2 by default');
      expect(engine.calls.where((c) => c.startsWith('play(')), isEmpty);

      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(PlayStackFeedView<String>.preloaded(preload, controller: view)),
      );
      await run(tester);
      expect(view.index, 0);
      expect(view.feed!.activeController!.value.isPlaying, isTrue);
      expect(
        engine.calls.where((c) => c.startsWith('setSource(')),
        hasLength(greaterThanOrEqualTo(2)),
      );
      // Shown by a view: dispose is a no-op, the view owns the players.
      preload.dispose();
      expect(view.feed!.isDisposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('settings sheet changes speed and subtitles', (tester) async {
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView(
            items: const ['https://example.com/s.m3u8'],
            controller: view,
          ),
        ),
      );
      await run(tester);
      engine.trackList = const [
        PlayStackTrack(
          id: 'en',
          type: PlayStackTrackType.text,
          isSelected: false,
          label: 'English',
        ),
      ];
      final controller = view.feed!.activeController!;
      await tester.runAsync(
        () => controller.selectAutomaticTrack(PlayStackTrackType.audio),
      );
      await run(tester);

      await tester.tap(find.bySemanticsLabel('Playback settings'));
      await tester.pumpAndSettle();
      expect(find.text('Playback speed'), findsOneWidget);
      await tester.tap(find.text('1.5x'));
      await run(tester);
      expect(controller.value.playbackSpeed, 1.5);
      await tester.tap(find.text('English'));
      await run(tester);
      expect(
        engine.calls.any((c) => c.contains('text') && c.contains('en')),
        isTrue,
      );

      // Cues are drawn on the video.
      final id = engine.livePlayers.firstWhere(
        (id) => engine.calls.contains('play($id)'),
      );
      engine.emit(
        PlayStackCuesEvent(
          playerId: id,
          generation: engine.generations[id]!,
          texts: const ['Hello there'],
        ),
      );
      await run(tester);
      expect(find.text('Hello there'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('fullscreen covers the app and lifts the quality cap', (
      tester,
    ) async {
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayStackFeedView(
              items: const [
                'https://example.com/a.m3u8',
                'https://example.com/b.m3u8',
                'https://example.com/c.m3u8',
              ],
              controller: view,
              initialIndex: 1,
              // Pull to refresh used to rebuild the feed at its first page.
              onRefresh: () async => const <String>[],
              controlsBuilder: (context, page) => Text(
                '${page.data} ${page.isFullscreen ? 'fullscreen' : 'feed'}',
              ),
            ),
            bottomNavigationBar: const Text('bottom bar'),
          ),
        ),
      );
      await run(tester);
      expect(view.index, 1);
      final controller = view.feed!.activeController!;
      final cap = controller.videoQualityLimit;
      final url = 'https://example.com/b.m3u8';

      await tester.runAsync(view.enterFullscreen);
      await run(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(view.isFullscreen, isTrue);
      expect(engine.fullscreenRequests, hasLength(1));
      expect(controller.videoQualityLimit, PlayStackVideoQualityLimit.none);
      // The app's controls, built for fullscreen, above everything else.
      expect(find.text('$url fullscreen'), findsOneWidget);
      expect(find.text('bottom bar'), findsNothing);
      expect(find.byType(PageView), findsNothing);
      expect(view.index, 1);
      expect(view.feed!.isPaused, isFalse, reason: 'the video keeps playing');

      // Back leaves fullscreen, on the same video.
      await tester.runAsync(() => tester.binding.handlePopRoute());
      await run(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await run(tester);
      expect(view.isFullscreen, isFalse);
      expect(controller.videoQualityLimit, cap);
      expect(find.text('$url feed'), findsOneWidget);
      expect(find.text('bottom bar'), findsOneWidget);
      expect(view.index, 1);
      expect(view.feed!.isPaused, isFalse);

      // Again, leaving from the controller.
      await tester.runAsync(view.enterFullscreen);
      await run(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('$url fullscreen'), findsOneWidget);
      await tester.runAsync(view.exitFullscreen);
      await run(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(view.isFullscreen, isFalse);
      expect(find.text('$url feed'), findsOneWidget);
      expect(view.index, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('the motion sensors open fullscreen in a portrait app', (
      tester,
    ) async {
      engine = FakePlayStackPlatform(supportsDeviceOrientation: true)
        // The app locked itself with SystemChrome.
        ..appOrientations = [DeviceOrientation.portraitUp];
      PlayStackPlatform.instance = engine;
      // A phone held upright; the interface stays so.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final view = PlayStackFeedViewController();
      await tester.pumpWidget(
        host(
          PlayStackFeedView(
            items: const [
              'https://example.com/a.m3u8',
              'https://example.com/b.m3u8',
            ],
            controller: view,
          ),
        ),
      );
      await run(tester);
      void hold(DeviceOrientation orientation) =>
          engine.deviceOrientations.add(orientation);
      Future<void> settled() async {
        await run(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await run(tester);
      }

      // The sensors did not report yet: the interface tells where the
      // device is, so the first turn counts.
      hold(DeviceOrientation.landscapeLeft);
      await settled();
      expect(view.isFullscreen, isTrue);
      hold(DeviceOrientation.portraitUp);
      await settled();
      expect(view.isFullscreen, isFalse);

      // The interface does not turn, the sensors do.
      hold(DeviceOrientation.landscapeLeft);
      await settled();
      expect(view.isFullscreen, isTrue);
      expect(engine.fullscreenRequests.last.orientations, [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      hold(DeviceOrientation.portraitUp);
      await settled();
      expect(view.isFullscreen, isFalse);
      expect(engine.fullscreenRestores.last.orientations, [
        DeviceOrientation.portraitUp,
      ], reason: "the app's own lock comes back");

      // Left with the button while sideways: upright first.
      hold(DeviceOrientation.landscapeRight);
      await settled();
      expect(view.isFullscreen, isTrue);
      await tester.runAsync(view.exitFullscreen);
      await settled();
      expect(view.isFullscreen, isFalse);
      hold(DeviceOrientation.landscapeLeft);
      await settled();
      expect(view.isFullscreen, isFalse);
      hold(DeviceOrientation.portraitUp);
      await settled();
      hold(DeviceOrientation.landscapeLeft);
      await settled();
      expect(view.isFullscreen, isTrue);
      hold(DeviceOrientation.portraitUp);
      await settled();
      expect(view.isFullscreen, isFalse);

      // The button, then held sideways and upright again: closes too.
      await tester.runAsync(view.enterFullscreen);
      await settled();
      expect(view.isFullscreen, isTrue);
      hold(DeviceOrientation.landscapeLeft);
      await settled();
      expect(view.isFullscreen, isTrue);
      hold(DeviceOrientation.portraitUp);
      await settled();
      // The fake video is portrait: the interface never turned sideways,
      // so holding the device sideways does not count.
      expect(view.isFullscreen, isTrue);
      await tester.runAsync(view.exitFullscreen);
      await settled();

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });

    testWidgets('turning the device sideways opens fullscreen', (tester) async {
      addTearDown(tester.view.reset);
      Future<void> turn(Size size) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pump();
        await run(tester);
        await tester.pump();
      }

      const upright = Size(400, 800);
      const sideways = Size(800, 400);
      await turn(upright);
      final view = PlayStackFeedViewController();
      Widget app({bool fullscreenOnRotate = true}) => MaterialApp(
        home: PlayStackFeedView(
          items: const [
            'https://example.com/a.m3u8',
            'https://example.com/b.m3u8',
          ],
          controller: view,
          fullscreenOnRotate: fullscreenOnRotate,
        ),
      );
      await tester.pumpWidget(app());
      await run(tester);

      await turn(sideways);
      expect(view.isFullscreen, isTrue);
      expect(
        engine.fullscreenRequests.single.orientations,
        isNull,
        reason: 'the orientation stays free',
      );
      await turn(upright);
      expect(view.isFullscreen, isFalse);

      // Left with the button while sideways: no fullscreen until the device
      // was upright again.
      await turn(sideways);
      expect(view.isFullscreen, isTrue);
      await tester.runAsync(view.exitFullscreen);
      await run(tester);
      expect(view.isFullscreen, isFalse);
      // A turn right after leaving comes from the unlocked orientation.
      await turn(upright);
      await turn(sideways);
      expect(view.isFullscreen, isFalse);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await turn(sideways);
      expect(view.isFullscreen, isFalse, reason: 'still waits for upright');
      await turn(upright);
      await turn(sideways);
      expect(view.isFullscreen, isTrue);
      await turn(upright);
      expect(view.isFullscreen, isFalse);

      // Turned off.
      await tester.pumpWidget(app(fullscreenOnRotate: false));
      await run(tester);
      await turn(sideways);
      expect(view.isFullscreen, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await run(tester);
      view.dispose();
    });
  });
}

class _Post {
  _Post(this.id);

  final String id;
  String get url => 'https://example.com/$id.m3u8';
}
