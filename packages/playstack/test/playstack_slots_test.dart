import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart'
    show PlayStackNativePlaybackState, PlayStackNativeStateEvent;

import 'support/fake_playstack_platform.dart';

void main() {
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;
  const content = PlayStackSource.network('https://example.com/movie.mp4');
  const adVideo = PlayStackSource.network('https://ads.example.com/1.mp4');

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

  int playerOf(PlayStackPlayerController controller) =>
      controller.nativePlayerId!;

  void end(int id) => platform.emit(
    PlayStackNativeStateEvent(
      playerId: id,
      generation: platform.generations[id]!,
      state: PlayStackNativePlaybackState.ended,
    ),
  );

  Future<void> playTo(PlayStackPlayerController controller, int seconds) async {
    final id = controller.nativePlayerId!;
    final from = (platform.positions[id] ?? Duration.zero).inSeconds;
    for (var s = from + 1; s <= seconds; s++) {
      platform.positions[id] = Duration(seconds: s);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await flush();
  }

  PlayStackAdSource oneAd() =>
      PlayStackAdSource.ads(const [PlayStackAd(source: adVideo)]);

  group('ad break rules', () {
    test('shouldShow false skips the break and reports declined', () async {
      final controller = manager.createController(content);
      final events = <PlayStackAdBreakEventType>[];
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [PlayStackAdBreak.preRoll(oneAd(), id: 'pre')],
        shouldShow: (adBreak) async => false,
        onEvent: (adBreak, event) => events.add(event.type),
      );
      await flush();
      await controller.play();
      await flush();
      await flush();
      expect(ads.isPlayingAd, isFalse);
      expect(controller.value.isPlaying, isTrue);
      expect(events, [PlayStackAdBreakEventType.declined]);
      ads.dispose();
    });

    test('a shown break reports started, the ad and ended', () async {
      final controller = manager.createController(content);
      final events = <(String?, PlayStackAdBreakEventType)>[];
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [PlayStackAdBreak.preRoll(oneAd(), id: 'pre')],
        shouldShow: (adBreak) => adBreak.id == 'pre',
        onEvent: (adBreak, event) => events.add((adBreak.id, event.type)),
      );
      await controller.play();
      await flush();
      await flush();
      expect(ads.isPlayingAd, isTrue);
      expect(ads.adBreak?.id, 'pre');
      end(playerOf(ads.adPlayer!));
      await flush();
      await flush();
      expect(events.map((e) => e.$2), [
        PlayStackAdBreakEventType.started,
        PlayStackAdBreakEventType.adStarted,
        PlayStackAdBreakEventType.adCompleted,
        PlayStackAdBreakEventType.ended,
      ]);
      expect(events.every((e) => e.$1 == 'pre'), isTrue);
      expect(controller.value.isPlaying, isTrue);
      ads.dispose();
    });

    test('a late answer is waited for, then the break is skipped', () async {
      final controller = manager.createController(content);
      final events = <PlayStackAdBreakEventType>[];
      final answer = Completer<bool>();
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [PlayStackAdBreak.preRoll(oneAd())],
        shouldShow: (_) => answer.future,
        decisionTimeout: const Duration(milliseconds: 200),
        onEvent: (_, event) => events.add(event.type),
      );
      await controller.play();
      await flush();
      expect(controller.value.isPlaying, isFalse); // waits for the answer
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await flush();
      expect(events, [PlayStackAdBreakEventType.declined]);
      expect(controller.value.isPlaying, isTrue);
      ads.dispose();
    });

    test('pauseContent false keeps the video playing, muted', () async {
      final controller = manager.createController(content);
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [
          PlayStackAdBreak.preRoll(
            oneAd(),
            pauseContent: false,
            muteContent: true,
            muteAd: true,
          ),
        ],
      );
      await controller.play();
      await flush();
      await flush();
      expect(ads.isPlayingAd, isTrue);
      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.isMuted, isTrue);
      expect(ads.adPlayer!.value.isMuted, isTrue);
      end(playerOf(ads.adPlayer!));
      await flush();
      await flush();
      expect(ads.isPlayingAd, isFalse);
      expect(controller.value.isMuted, isFalse);
      ads.dispose();
    });

    test('skippable and skipAfter override the ad', () async {
      final controller = manager.createController(content);
      const skippableAd = PlayStackAd(
        source: adVideo,
        skipAfter: Duration(seconds: 5),
      );
      final locked = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [
          PlayStackAdBreak.preRoll(
            PlayStackAdSource.ads(const [skippableAd]),
            skippable: false,
          ),
        ],
      );
      await controller.play();
      await flush();
      await flush();
      expect(locked.skippableIn, isNull);
      locked.dispose();

      final other = manager.createController(content);
      final earlier = PlayStackAdController(
        manager: manager,
        content: other,
        breaks: [
          PlayStackAdBreak.preRoll(
            PlayStackAdSource.ads(const [skippableAd]),
            skipAfter: const Duration(seconds: 2),
          ),
        ],
      );
      await other.play();
      await flush();
      await flush();
      expect(earlier.skippableIn, const Duration(seconds: 2));
      earlier.dispose();
    });

    test(
      'repeatOnSeekBack plays a mid-roll again after seeking back',
      () async {
        final controller = manager.createController(content);
        var started = 0;
        final ads = PlayStackAdController(
          manager: manager,
          content: controller,
          breaks: [
            PlayStackAdBreak.midRoll(
              at: const Duration(seconds: 10),
              source: oneAd(),
              repeatOnSeekBack: true,
            ),
          ],
          onEvent: (_, event) {
            if (event.type == PlayStackAdBreakEventType.started) started++;
          },
        );
        await controller.play();
        await flush();
        platform.positions[playerOf(controller)] = const Duration(seconds: 11);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await flush();
        expect(started, 1);
        end(playerOf(ads.adPlayer!));
        await flush();
        await flush();
        await controller.seekTo(const Duration(seconds: 2));
        platform.positions[playerOf(controller)] = const Duration(seconds: 2);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        platform.positions[playerOf(controller)] = const Duration(seconds: 11);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await flush();
        expect(started, 2);
        ads.dispose();
      },
    );
  });

  group('cue rules', () {
    test('shouldShow false skips a cue; events tell how it ended', () async {
      final controller = manager.createController(content);
      final events = <(String?, PlayStackCueEvent)>[];
      final cues = PlayStackCueController(
        controller: controller,
        cues: const [
          PlayStackCue(at: Duration(seconds: 2), id: 'no'),
          PlayStackCue(
            at: Duration(seconds: 4),
            id: 'timed',
            showFor: Duration(milliseconds: 100),
          ),
          PlayStackCue(at: Duration(seconds: 7), id: 'closed'),
        ],
        endWhenHandled: false,
        shouldShow: (cue) => cue.id != 'no',
        onEvent: (cue, event) => events.add((cue.id, event)),
      );
      await controller.play();
      await flush();
      await playTo(controller, 5);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await playTo(controller, 8);
      expect(cues.active?.id, 'closed');
      cues.dismiss();
      await flush();
      expect(events, [
        ('no', PlayStackCueEvent.declined),
        ('timed', PlayStackCueEvent.shown),
        ('timed', PlayStackCueEvent.expired),
        ('closed', PlayStackCueEvent.shown),
        ('closed', PlayStackCueEvent.dismissed),
      ]);
      cues.dispose();
    });

    test(
      'a handled cue reports handled; repeatOnSeekBack fires again',
      () async {
        final controller = manager.createController(content);
        final events = <PlayStackCueEvent>[];
        final cues = PlayStackCueController(
          controller: controller,
          cues: const [
            PlayStackCue(
              at: Duration(seconds: 3),
              id: 'ad',
              repeatOnSeekBack: true,
            ),
          ],
          onCue: (cue) async {},
          onEvent: (cue, event) => events.add(event),
        );
        await controller.play();
        await flush();
        await playTo(controller, 4);
        await flush();
        expect(events, [PlayStackCueEvent.shown, PlayStackCueEvent.handled]);
        await controller.seekTo(Duration.zero);
        platform.positions[playerOf(controller)] = Duration.zero;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await playTo(controller, 4);
        await flush();
        expect(events.where((e) => e == PlayStackCueEvent.shown).length, 2);
        cues.dispose();
      },
    );
  });

  group('PlayStackShowRules', () {
    test('always, once, every and atMost', () async {
      var now = DateTime(2026, 1, 1, 12);
      final rules = PlayStackShowRules(clock: () => now);
      expect(await rules.allows('a', PlayStackShowRule.always), isTrue);
      expect(await rules.allows('a', PlayStackShowRule.once), isTrue);
      await rules.record('a');
      expect(await rules.allows('a', PlayStackShowRule.once), isFalse);
      expect(await rules.allows('a', PlayStackShowRule.always), isTrue);

      const daily = PlayStackShowRule.every(Duration(days: 1));
      expect(await rules.allows('a', daily), isFalse);
      now = now.add(const Duration(days: 1, minutes: 1));
      expect(await rules.allows('a', daily), isTrue);

      const twiceAnHour = PlayStackShowRule.atMost(2, per: Duration(hours: 1));
      await rules.record('b');
      expect(await rules.allows('b', twiceAnHour), isTrue);
      await rules.record('b');
      expect(await rules.allows('b', twiceAnHour), isFalse);
      now = now.add(const Duration(hours: 2));
      expect(await rules.allows('b', twiceAnHour), isTrue);
      expect(await rules.allows('other', PlayStackShowRule.once), isTrue);
    });

    test('kept in a custom store across instances', () async {
      String? saved;
      PlayStackShowStore store() => PlayStackShowStore.custom(
        read: () async => saved,
        write: (data) async => saved = data,
      );
      final first = PlayStackShowRules(store: store());
      await first.record('ep1/mid');
      await Future<void>.delayed(Duration.zero);
      final second = PlayStackShowRules(store: store());
      expect(await second.allows('ep1/mid', PlayStackShowRule.once), isFalse);
      expect((await second.history('ep1/mid')).length, 1);
      await second.reset('ep1/mid');
      expect(await second.allows('ep1/mid', PlayStackShowRule.once), isTrue);
    });
  });

  group('PlayStackSlotFrame', () {
    setUp(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(1000, 1000);
      view.devicePixelRatio = 1;
    });
    tearDown(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    Widget frame(PlayStackSlotLayout layout, {bool show = true}) {
      return MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 800,
            child: PlayStackSlotFrame(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _Counter(key: ValueKey('video')),
                  if (show) _Shower(layout: layout),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a strip below shrinks the video, which keeps its state', (
      tester,
    ) async {
      await tester.pumpWidget(
        frame(const PlayStackSlotLayout.videoArea(), show: false),
      );
      await tester.tap(find.byKey(const ValueKey('video')));
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('video'))).height, 800);

      await tester.pumpWidget(
        frame(const PlayStackSlotLayout.below(height: 100, safeArea: false)),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('video'))).height, 700);
      expect(tester.getSize(find.byKey(const ValueKey('slot'))).height, 100);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('slot'))).dy,
        tester.getBottomLeft(find.byKey(const ValueKey('video'))).dy,
      );
      expect(find.text('1'), findsOneWidget); // not rebuilt from scratch

      await tester.pumpWidget(
        frame(const PlayStackSlotLayout.videoArea(), show: false),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('video'))).height, 800);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('above, overlay, video area and custom', (tester) async {
      await tester.pumpWidget(
        frame(const PlayStackSlotLayout.above(height: 80, safeArea: false)),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('video'))).height, 720);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('slot'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('video'))).dy,
      );

      await tester.pumpWidget(
        frame(
          const PlayStackSlotLayout.overlay(
            size: Size(120, 60),
            alignment: Alignment.topRight,
            margin: EdgeInsets.zero,
            safeArea: false,
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('video'))).height, 800);
      expect(
        tester.getSize(find.byKey(const ValueKey('slot'))),
        const Size(120, 60),
      );
      expect(
        tester.getTopRight(find.byKey(const ValueKey('slot'))),
        tester.getTopRight(find.byKey(const ValueKey('video'))),
      );

      await tester.pumpWidget(frame(const PlayStackSlotLayout.videoArea()));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('slot'))),
        tester.getSize(find.byKey(const ValueKey('video'))),
      );

      await tester.pumpWidget(
        frame(
          PlayStackSlotLayout.custom(
            (context, video, slot) => Row(
              children: [
                Expanded(child: video),
                SizedBox(width: 100, child: slot),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey('video'))).width, 300);
      expect(tester.getSize(find.byKey(const ValueKey('slot'))).width, 100);
    });

    testWidgets('full screen covers more than the video', (tester) async {
      await tester.pumpWidget(frame(const PlayStackSlotLayout.fullScreen()));
      await tester.pump();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(tester.getSize(find.byKey(const ValueKey('slot'))), screen);
      expect(tester.getSize(find.byKey(const ValueKey('video'))).height, 800);
    });
  });
}

/// Counts taps, to tell whether its state survived a layout change.
class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _count++),
    child: ColoredBox(
      color: Colors.blue,
      child: Center(child: Text('$_count')),
    ),
  );
}

/// Shows a slot with [layout] in the frame above it.
class _Shower extends StatefulWidget {
  const _Shower({required this.layout});

  final PlayStackSlotLayout layout;

  @override
  State<_Shower> createState() => _ShowerState();
}

class _ShowerState extends State<_Shower> {
  PlayStackSlotFrameState? _frame;

  static Widget _slot(BuildContext context) =>
      const ColoredBox(key: ValueKey('slot'), color: Colors.red);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frame = PlayStackSlotFrame.maybeOf(context);
    _frame?.show(this, widget.layout, _slot);
  }

  @override
  void didUpdateWidget(_Shower oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frame?.show(this, widget.layout, _slot);
  }

  @override
  void dispose() {
    _frame?.show(this, null, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
