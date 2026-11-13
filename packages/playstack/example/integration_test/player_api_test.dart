import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_example/samples.dart';

import 'support/test_results.dart';

/// Milestone 3 API against the real engine: metadata, tracks, subtitles,
/// source replacement, stop, position stream and app lifecycle.
void main() {
  final binding = ensureBindingWithResults();

  late PlayStackManager manager;

  setUp(() async {
    manager = PlayStackManager(
      config: const PlayStackConfig(pool: PlayStackPoolConfig(maxPlayers: 2)),
    );
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 8),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  bool isLanguage(String? tag, String code) =>
      tag != null &&
      (tag == code ||
          tag.startsWith('$code-') ||
          (code == 'en' && tag == 'eng') ||
          (code == 'tr' && tag == 'tur'));

  testWidgets('reports video metadata', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.initialize();
    final info = controller.value.videoInfo!;
    expect(info.isLive, isFalse);
    expect(info.frameRate, anyOf(isNull, closeTo(30, 1)));
    expect(info.videoCodec, anyOf(isNull, contains('avc')));
  }, skip: false);

  testWidgets('lists and selects audio and subtitle tracks', (tester) async {
    if (!manager.capabilities.supportsTrackSelection) return;
    final controller = manager.createController(
      const PlayStackSource.asset(multitrackAsset),
    );
    await controller.initialize();
    if (kIsWeb) {
      // Browsers expose in-band MP4 tracks only partly (Safari: audio;
      // Chromium: none). Whatever is exposed must be consistent and
      // turning subtitles off must work.
      await Future<void>.delayed(const Duration(seconds: 1));
      final tracks = controller.tracks.value;
      expect(
        tracks.where((t) => t.type == PlayStackTrackType.audio).length,
        anyOf(0, 2),
        reason: '$tracks',
      );
      await controller.disableSubtitles();
      expect(controller.subtitles.value, isEmpty);
      return;
    }
    await waitUntil(() => controller.tracks.value.isNotEmpty, reason: 'tracks');
    final tracks = controller.tracks.value;
    final audio = tracks
        .where((t) => t.type == PlayStackTrackType.audio)
        .toList();
    final text = tracks
        .where((t) => t.type == PlayStackTrackType.text)
        .toList();
    expect(audio, hasLength(2), reason: '$tracks');
    expect(text, hasLength(2), reason: '$tracks');

    final turkishAudio = audio.firstWhere((t) => isLanguage(t.language, 'tr'));
    await controller.selectTrack(turkishAudio);
    await waitUntil(
      () => controller.tracks.value.any(
        (t) => t.id == turkishAudio.id && t.isSelected,
      ),
      reason: 'turkish audio selected',
    );

    final englishText = text.firstWhere((t) => isLanguage(t.language, 'en'));
    await controller.selectTrack(englishText);
    await controller.play();
    await waitUntil(
      () => controller.subtitles.value.contains('Hello subtitles'),
      reason: 'subtitle cue; got ${controller.subtitles.value}',
    );

    await controller.disableSubtitles();
    expect(controller.subtitles.value, isEmpty);
  });

  testWidgets('replaces the source on the same native player', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(looping: true, muted: true),
    );
    await controller.play();
    await waitUntil(() => controller.value.isPlaying, reason: 'playing');

    await controller.setSource(const PlayStackSource.asset(rotatedAsset));
    expect(controller.value.videoInfo!.displaySize.width, 180);
    await waitUntil(() => controller.value.isPlaying, reason: 'resumed');
    await waitUntil(
      () => controller.value.hasRenderedFirstFrame,
      reason: 'first frame of new source',
    );
    expect(manager.poolStats.created, 1);
  });

  testWidgets('stop pauses and rewinds', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(muted: true),
    );
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await controller.stop();
    await waitUntil(
      () => controller.value.status == PlayStackPlaybackStatus.paused,
      reason: 'paused',
    );
    final position = await controller.getPosition();
    expect(position.position.inMilliseconds, lessThan(50));
  });

  testWidgets('position stream advances while playing', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(muted: true),
    );
    await controller.initialize();
    final positions = <Duration>[];
    final sub = controller
        .positions(interval: const Duration(milliseconds: 100))
        .listen((p) => positions.add(p.position));
    await controller.play();
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    await sub.cancel();
    expect(positions.length, greaterThanOrEqualTo(4));
    for (var i = 1; i < positions.length; i++) {
      expect(positions[i], greaterThanOrEqualTo(positions[i - 1]));
    }
  });

  testWidgets('applies a video quality limit where supported', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.initialize();
    if (manager.capabilities.supportsVideoQualityLimit) {
      await controller.setVideoQualityLimit(
        const PlayStackVideoQualityLimit(maxHeight: 144, maxBitrate: 100000),
      );
      await controller.setVideoQualityLimit(PlayStackVideoQualityLimit.none);
    } else {
      await expectLater(
        controller.setVideoQualityLimit(
          const PlayStackVideoQualityLimit(maxHeight: 144),
        ),
        throwsA(isA<PlayStackException>()),
      );
    }
  });

  testWidgets('pauses when the app is hidden and resumes after', (
    tester,
  ) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(looping: true, muted: true),
    );
    await controller.play();
    await waitUntil(() => controller.value.isPlaying, reason: 'playing');

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await waitUntil(
      () => controller.value.status == PlayStackPlaybackStatus.paused,
      reason: 'paused by lifecycle',
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitUntil(() => controller.value.isPlaying, reason: 'resumed');
  });
}
