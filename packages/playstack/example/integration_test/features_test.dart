import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_example/samples.dart';

import 'support/test_results.dart';

/// The features added for app developers, against the real engine:
/// subtitle files, audio only, live streams, VAST ads, screen brightness.
void main() {
  ensureBindingWithResults();

  late PlayStackManager manager;

  setUp(() async {
    manager = PlayStackManager();
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  Future<void> waitFor(bool Function() condition, {int seconds = 20}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a subtitle file shows its lines while the video plays', (
    _,
  ) async {
    final controller = manager.createController(
      const PlayStackSource.asset(
        landscapeAsset,
        subtitles: [
          PlayStackSubtitleSource.text(
            '00:00:00,000 --> 00:00:30,000\nHello from a file',
            isDefault: true,
          ),
        ],
      ),
    );
    await controller.play();
    await waitFor(() => controller.subtitles.value.isNotEmpty);
    expect(controller.subtitles.value, ['Hello from a file']);
    expect(
      controller.tracks.value.where((t) => t.id.startsWith('sidecar:')),
      hasLength(1),
    );
  });

  testWidgets('audio only keeps the sound playing', (_) async {
    final controller = manager.createController(
      const PlayStackSource.asset(landscapeAsset),
    );
    await controller.play();
    await waitFor(() => controller.value.isPlaying);
    await controller.setAudioOnly(true);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(controller.value.hasError, isFalse);
    expect(controller.value.isPlaying, isTrue);
    await controller.setAudioOnly(false);
  });

  testWidgets('a live stream reports its live edge and returns to it', (
    _,
  ) async {
    final controller = manager.createController(
      const PlayStackSource.network(
        'https://demo.unified-streaming.com/k8s/live/stable/live.isml/.m3u8',
      ),
    );
    await controller.play();
    await waitFor(() => controller.value.isPlaying, seconds: 30);
    expect(controller.value.videoInfo?.isLive, isTrue);
    final snapshot = await controller.getPosition();
    expect(snapshot.liveEdge, isNotNull);
    await controller.pause();
    await Future<void>.delayed(const Duration(seconds: 3));
    await controller.seekToLiveEdge();
    final after = await controller.getPosition();
    expect(after.behindLive!, lessThan(const Duration(seconds: 30)));
  }, skip: kIsWeb);

  testWidgets('Google sample VAST tag loads a playable ad', (_) async {
    final ads = await PlayStackVast.load(
      'https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/'
      'single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs='
      '300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&'
      'env=vp&impl=s&correlator=[CACHEBUSTING]',
    );
    expect(ads, isNotEmpty);
    final ad = manager.createController(ads.first.source);
    await ad.play();
    await waitFor(() => ad.value.isPlaying, seconds: 30);
    expect(ads.first.tracking[PlayStackAdEvent.impression], isNotEmpty);
  });

  testWidgets('screen brightness can be read, set and restored', (_) async {
    final before = await manager.getScreenBrightness();
    expect(before, isNotNull);
    // Simulators keep their brightness; a device shows the change.
    await manager.setScreenBrightness(0.3);
    expect(await manager.getScreenBrightness(), inInclusiveRange(0.0, 1.0));
    await manager.setScreenBrightness(null);
  }, skip: kIsWeb);

  testWidgets('frames of a video are read for the scrub preview', (_) async {
    final frame = await manager.getVideoFrame(
      const PlayStackSource.asset(landscapeAsset),
      const Duration(seconds: 2),
    );
    expect(frame, isNotNull);
    // JPEG.
    expect(frame!.sublist(0, 2), [0xFF, 0xD8]);
  }, skip: kIsWeb);
}
