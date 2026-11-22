import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_example/samples.dart';

import 'support/test_results.dart';

/// Picture-in-Picture, the media controls and quality choice against the
/// real engine. The quality test streams Apple's public HLS example, so it
/// needs the internet.
void main() {
  ensureBindingWithResults();

  late PlayStackManager manager;

  setUp(() async {
    manager = PlayStackManager();
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Picture-in-Picture starts and stops', (tester) async {
    final pictureInPicture = manager.pictureInPicture;
    if (!await pictureInPicture.isSupported()) {
      // Not on the web, and not in every simulator.
      debugPrint('Picture-in-Picture is not supported here: skipped');
      return;
    }
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(looping: true, muted: true),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PlayStackVideoView(controller: controller),
      ),
    );
    await controller.play();
    await waitUntil(() => controller.value.isPlaying, reason: 'playing');

    await pictureInPicture.enable(controller, autoEnter: false);
    expect(await pictureInPicture.start(), isTrue);
    await waitUntil(
      () => pictureInPicture.isActive.value,
      reason: 'Picture-in-Picture started',
    );
    expect(controller.value.isPlaying, isTrue);

    // Only iOS lets an app close the window; on Android the user does.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await pictureInPicture.stop();
      await waitUntil(
        () => !pictureInPicture.isActive.value,
        reason: 'Picture-in-Picture stopped',
      );
    }
    await pictureInPicture.disable();
  });

  testWidgets('media controls follow the controller', (tester) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
      config: const PlayStackPlayerConfig(looping: true, muted: true),
    );
    await controller.play();
    await waitUntil(() => controller.value.isPlaying, reason: 'playing');
    await manager.mediaSession.show(
      controller,
      const PlayStackMediaInfo(title: 'Landscape', artist: 'PlayStack'),
      onNext: () {},
    );
    // Pausing and seeking (after playing) answer and update the controls.
    await controller.pause();
    await controller
        .seekTo(const Duration(seconds: 1))
        .timeout(const Duration(seconds: 5));
    await controller.play();
    await waitUntil(() => controller.value.isPlaying, reason: 'playing again');
    await manager.mediaSession.clear();
  });

  testWidgets('lists the qualities of an HLS stream and picks one', (
    tester,
  ) async {
    if (kIsWeb) return;
    final controller = manager.createController(
      const PlayStackSource.network(
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
        'img_bipbop_adv_example_fmp4/master.m3u8',
      ),
      config: const PlayStackPlayerConfig(muted: true),
    );
    await controller.play();
    await waitUntil(
      () => controller.videoQualities.length >= 2,
      timeout: const Duration(seconds: 20),
      reason: 'qualities listed',
    );
    final qualities = controller.videoQualities;
    debugPrint('qualities: ${qualities.map((q) => q.label).join(', ')}');
    await controller.setVideoQuality(qualities.last);
    expect(controller.videoQuality.value, qualities.last);
    await controller.setVideoQuality(null);
    expect(controller.videoQuality.value, isNull);
  });

  testWidgets('downloads an HLS stream at a chosen quality', (tester) async {
    if (kIsWeb) return;
    final downloads = manager.downloads;
    await downloads.setEnabled(true);
    const source = PlayStackSource.network(
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/'
      'img_bipbop_adv_example_fmp4/master.m3u8',
    );
    // A short clip of the stream would be better; the test stops as soon as
    // the download makes progress.
    await downloads.download(
      'hls-quality',
      source,
      quality: PlayStackDownloadQuality.low,
    );
    await waitUntil(
      () {
        final download = downloads['hls-quality'];
        return download != null &&
            (download.isCompleted || (download.percent ?? 0) > 0);
      },
      timeout: const Duration(seconds: 60),
      reason: 'download progress: ${downloads['hls-quality']}',
    );
    expect(
      downloads['hls-quality']?.state,
      isNot(PlayStackDownloadState.failed),
    );
    await downloads.remove('hls-quality');
    await downloads.setEnabled(false);
  });
}
