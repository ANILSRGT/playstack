import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart'
    hide PlayStackErrorEvent;
import 'package:playstack_platform_interface/playstack_platform_interface.dart'
    as platform_events
    show PlayStackErrorEvent;

import 'support/fake_playstack_platform.dart';

void main() {
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;
  late List<PlayStackAnalyticsEvent> events;
  const source = PlayStackSource.network('https://example.com/a.mp4');

  setUp(() async {
    platform = FakePlayStackPlatform(
      videoInfo: const PlayStackVideoInfo(
        width: 1080,
        height: 1920,
        duration: Duration(seconds: 100),
      ),
    );
    manager = PlayStackManager(
      config: const PlayStackConfig(
        analytics: PlayStackAnalyticsConfig(
          positionInterval: Duration(milliseconds: 10),
        ),
      ),
      platform: platform,
    );
    await manager.initialize();
    events = [];
    manager.analytics.events.listen(events.add);
  });

  tearDown(() => manager.dispose());

  List<String> names() => [for (final e in events) e.name];

  test('reports load, start, pause, resume and end', () async {
    final controller = manager.createController(source)..contentId = 'ep-1';
    await controller.play();
    await flush();
    await controller.pause();
    await flush();
    await controller.play();
    await flush();
    await controller.release();
    await flush();
    expect(names(), [
      'video_load',
      'video_start',
      'video_pause',
      'video_resume',
      'video_end',
    ]);
    expect(events.first.contentId, 'ep-1');
    expect(events.first.parameters['content_id'], 'ep-1');
    expect(events.first.parameters['source'], 'https://example.com/a.mp4');
    final start = events[1] as PlayStackStartEvent;
    expect(start.parameters['startup_ms'], isA<int>());
  });

  test('reports progress milestones once and the seek', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final id = platform.livePlayers.single;
    await controller.seekTo(const Duration(seconds: 60));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    platform.positions[id] = const Duration(seconds: 61);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final seek = events.whereType<PlayStackSeekEvent>().single;
    expect(seek.position, const Duration(seconds: 60));
    expect(seek.from, Duration.zero);
    final progress = events.whereType<PlayStackProgressEvent>().toList();
    expect([for (final p in progress) p.percent], [25, 50]);
  });

  test('reports completion, failures and rebuffering', () async {
    final controller = manager.createController(source);
    await controller.play();
    await flush();
    final id = platform.livePlayers.single;
    final generation = platform.generations[id]!;
    platform.emit(
      PlayStackNativeStateEvent(
        playerId: id,
        generation: generation,
        state: PlayStackNativePlaybackState.buffering,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    platform.emit(
      PlayStackNativeStateEvent(
        playerId: id,
        generation: generation,
        state: PlayStackNativePlaybackState.ready,
      ),
    );
    final stall = events.whereType<PlayStackRebufferEvent>().single;
    expect(stall.stall, greaterThan(Duration.zero));
    expect(stall.afterSeek, isFalse);

    platform.emit(
      PlayStackNativeStateEvent(
        playerId: id,
        generation: generation,
        state: PlayStackNativePlaybackState.ended,
      ),
    );
    expect(events.whereType<PlayStackCompleteEvent>(), hasLength(1));
    expect(
      [for (final p in events.whereType<PlayStackProgressEvent>()) p.percent],
      [25, 50, 75],
    );

    platform.emit(
      platform_events.PlayStackErrorEvent(
        playerId: id,
        generation: generation,
        error: const PlayStackException(PlayStackErrorCode.network, 'down'),
      ),
    );
    final failure = events.whereType<PlayStackFailureEvent>().single;
    expect(failure.parameters['error_code'], 'network');
    await controller.dispose();
    final end = events.whereType<PlayStackEndEvent>().single;
    expect(end.completed, isTrue);
    expect(end.stalls, 1);
  });

  test('the app-wide stream sees every manager; disabled reports nothing',
      () async {
    final all = <PlayStackAnalyticsEvent>[];
    final subscription = PlayStackAnalytics.all.listen(all.add);
    final quiet = PlayStackManager(
      config: const PlayStackConfig(
        analytics: PlayStackAnalyticsConfig.disabled,
      ),
      platform: platform,
    );
    await quiet.initialize();
    await quiet.createController(source).play();
    await flush();
    expect(all, isEmpty);
    await manager.createController(source).play();
    await flush();
    expect(all.map((e) => e.name), containsAll(['video_load', 'video_start']));
    await subscription.cancel();
    await quiet.dispose();
  });
}
