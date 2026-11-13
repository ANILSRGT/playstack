import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_example/samples.dart';

import 'support/test_results.dart';

/// Playback against the real engine, using the bundled 2 s 320x180 clips.
void main() {
  ensureBindingWithResults();

  late PlayStackManager manager;

  setUp(() async {
    manager = PlayStackManager(
      config: const PlayStackConfig(
        pool: PlayStackPoolConfig(maxPlayers: 2),
        // Browsers block autoplay with sound until the user interacts with
        // the page; see the dedicated test below.
        player: PlayStackPlayerConfig(muted: kIsWeb),
      ),
    );
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  Future<void> waitFor(
    PlayStackPlayerController controller,
    bool Function(PlayStackPlaybackState state) condition, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition(controller.value)) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out; last state: ${controller.value}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  testWidgets('prepares an asset and renders the first frame while paused', (
    tester,
  ) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.initialize();
    final info = controller.value.videoInfo!;
    expect(controller.value.status, PlayStackPlaybackStatus.ready);
    expect(info.displaySize.width, 320);
    expect(info.displaySize.height, 180);
    expect(info.duration!.inMilliseconds, closeTo(2000, 100));
    await waitFor(controller, (s) => s.hasRenderedFirstFrame);
  });

  testWidgets('reports rotation so the video is shown upright', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(rotatedAsset),
    );
    await controller.initialize();
    final info = controller.value.videoInfo!;
    expect(info.displaySize.width, 180);
    expect(info.displaySize.height, 320);
    expect(controller.value.aspectRatio, closeTo(180 / 320, 0.01));
  });

  testWidgets('web blocks autoplay with sound without a user gesture', (
    tester,
  ) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(),
    );
    await controller.initialize();
    try {
      await controller.play();
      // A browser that allows it (user engagement, policy flags) plays.
      await waitFor(controller, (s) => s.isPlaying);
    } on PlayStackException catch (error) {
      expect(error.code, PlayStackErrorCode.playbackNotAllowed);
      expect(controller.value.isPlaying, isFalse);
      // Muted playback is always allowed.
      await controller.setMuted(true);
      await controller.play();
      await waitFor(controller, (s) => s.isPlaying);
    }
  }, skip: !kIsWeb);

  testWidgets('plays to completion and restarts', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.play();
    await waitFor(
      controller,
      (s) => s.status == PlayStackPlaybackStatus.playing,
    );
    await waitFor(
      controller,
      (s) => s.status == PlayStackPlaybackStatus.completed,
    );
    final end = await controller.getPosition();
    expect(end.position.inMilliseconds, greaterThan(1800));

    await controller.play();
    await waitFor(
      controller,
      (s) => s.status == PlayStackPlaybackStatus.playing,
    );
    final restarted = await controller.getPosition();
    expect(restarted.position.inMilliseconds, lessThan(1000));
  });

  testWidgets('pause stops the position advancing', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.play();
    await waitFor(
      controller,
      (s) => s.status == PlayStackPlaybackStatus.playing,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await controller.pause();
    await waitFor(
      controller,
      (s) => s.status == PlayStackPlaybackStatus.paused,
    );
    final first = await controller.getPosition();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final second = await controller.getPosition();
    // Engines may settle the final position by a frame after pausing.
    expect(
      (second.position - first.position).inMilliseconds.abs(),
      lessThanOrEqualTo(40),
    );
    expect(first.position.inMilliseconds, greaterThan(0));
  });

  testWidgets('loops without completing', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(looping: true, muted: true),
    );
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    expect(controller.value.status, PlayStackPlaybackStatus.playing);
    expect(controller.value.isLooping, isTrue);
  });

  testWidgets('seeks precisely', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.initialize();
    await controller.seekTo(const Duration(milliseconds: 1000));
    final position = await controller.getPosition();
    expect(position.position.inMilliseconds, closeTo(1000, 50));
  });

  testWidgets('applies volume, mute and speed', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.initialize();
    await controller.setVolume(0.3);
    await controller.setMuted(true);
    await controller.setPlaybackSpeed(2);
    await controller.play();
    await waitFor(
      controller,
      (s) => s.status == PlayStackPlaybackStatus.completed,
      timeout: const Duration(seconds: 3),
    );
  });

  testWidgets('plays a memory source when supported', (tester) async {
    if (!manager.capabilities.supportsMemorySource) return;
    final data = await rootBundle.load(landscapeAsset);
    final controller = manager.createController(
      PlayStackSource.memory(data.buffer.asUint8List(), mimeType: 'video/mp4'),
    );
    await controller.initialize();
    expect(controller.value.videoInfo!.width, 320);
  });

  testWidgets('reports a missing asset as sourceNotFound', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset('assets/videos/does_not_exist.mp4'),
    );
    await expectLater(
      controller.initialize(),
      throwsA(
        isA<PlayStackException>().having(
          (e) => e.code,
          'code',
          anyOf(
            PlayStackErrorCode.sourceNotFound,
            PlayStackErrorCode.unsupportedFormat,
          ),
        ),
      ),
    );
    expect(controller.value.status, PlayStackPlaybackStatus.error);
  });

  testWidgets('a pooled player switches sources without stale state', (
    tester,
  ) async {
    final rotated = manager.createController(
      const PlayStackSource.asset(rotatedAsset),
    );
    await rotated.initialize();
    await rotated.dispose();
    final landscape = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await landscape.initialize();
    expect(landscape.value.videoInfo!.displaySize.width, 320);
    await waitFor(landscape, (s) => s.hasRenderedFirstFrame);
    expect(manager.poolStats.created, 1);
  });

  testWidgets('rapid switching across 100 sources stays within the pool', (
    tester,
  ) async {
    final controllers = <PlayStackPlayerController>[];
    for (var i = 0; i < 100; i++) {
      final controller = manager.createController(
        PlayStackSource.asset(i.isEven ? landscapeAsset : rotatedAsset),
      );
      // Like a fast scroll: the previous item loses priority and the new one
      // starts without waiting; most preparations are superseded.
      for (final previous in controllers) {
        previous.priority = PlayStackPlayerPriority.background;
      }
      controllers.add(controller);
      controller.play().ignore();
      if (controllers.length > 2) {
        await controllers.removeAt(0).dispose();
      }
      expect(manager.poolStats.allocated, lessThanOrEqualTo(2));
    }
    final last = controllers.last;
    await waitFor(last, (s) => s.status == PlayStackPlaybackStatus.playing);
    expect(manager.poolStats.created, lessThanOrEqualTo(2));
  });
}
