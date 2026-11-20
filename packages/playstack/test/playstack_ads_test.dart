import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart'
    show PlayStackNativePlaybackState, PlayStackNativeStateEvent;

import 'support/fake_playstack_platform.dart';

const _vast = '''<?xml version="1.0"?>
<VAST version="3.0">
  <Ad id="a1" sequence="2">
    <InLine>
      <AdTitle>Second</AdTitle>
      <Impression>https://t.example.com/imp2</Impression>
      <Creatives><Creative><Linear>
        <Duration>00:00:10</Duration>
        <MediaFiles>
          <MediaFile type="video/mp4" width="1920" height="1080">https://ads.example.com/2-1080.mp4</MediaFile>
          <MediaFile type="video/mp4" width="1280" height="720">https://ads.example.com/2-720.mp4</MediaFile>
        </MediaFiles>
      </Linear></Creative></Creatives>
    </InLine>
  </Ad>
  <Ad id="a0" sequence="1">
    <InLine>
      <AdTitle>First</AdTitle>
      <Impression><![CDATA[https://t.example.com/imp?cb=[CACHEBUSTING]]]></Impression>
      <Creatives><Creative><Linear skipoffset="00:00:05">
        <Duration>00:00:30.500</Duration>
        <TrackingEvents>
          <Tracking event="start">https://t.example.com/start</Tracking>
          <Tracking event="midpoint">https://t.example.com/mid</Tracking>
        </TrackingEvents>
        <VideoClicks>
          <ClickThrough>https://brand.example.com</ClickThrough>
          <ClickTracking>https://t.example.com/click</ClickTracking>
        </VideoClicks>
        <MediaFiles>
          <MediaFile type="video/webm" height="720">https://ads.example.com/1.webm</MediaFile>
          <MediaFile type="video/mp4" height="480">https://ads.example.com/1.mp4</MediaFile>
        </MediaFiles>
      </Linear></Creative></Creatives>
    </InLine>
  </Ad>
</VAST>''';

void main() {
  test('reads VAST inline ads in sequence', () {
    final ads = PlayStackVast.parse(_vast);
    expect(ads.map((a) => a.title), ['First', 'Second']);
    final first = ads.first;
    expect(
      (first.source as PlayStackNetworkSource).url,
      'https://ads.example.com/1.mp4',
    );
    expect(first.skipAfter, const Duration(seconds: 5));
    expect(first.duration, const Duration(seconds: 30, milliseconds: 500));
    expect(first.clickThroughUrl, 'https://brand.example.com');
    expect(first.tracking[PlayStackAdEvent.start], [
      'https://t.example.com/start',
    ]);
    expect(first.tracking[PlayStackAdEvent.click], [
      'https://t.example.com/click',
    ]);
    expect(
      first.tracking[PlayStackAdEvent.impression]!.single,
      contains('[CACHEBUSTING]'),
    );
    expect(
      (ads.last.source as PlayStackNetworkSource).url,
      'https://ads.example.com/2-720.mp4',
    );
    expect(ads.last.skipAfter, isNull);
    expect(
      PlayStackAds.expandMacros('x?cb=[CACHEBUSTING]'),
      matches(RegExp(r'^x\?cb=\d{8}$')),
    );
  });

  group('ad breaks', () {
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

    test('a pre-roll plays before the video, which then resumes', () async {
      final controller = manager.createController(content);
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [
          PlayStackAdBreak.preRoll(
            PlayStackAdSource.ads(const [
              PlayStackAd(source: adVideo, skipAfter: Duration(seconds: 5)),
            ]),
          ),
        ],
      );
      final events = <PlayStackAdEvent>[];
      ads.events.listen((e) => events.add(e.$2));
      await controller.play();
      await flush();
      await flush();
      expect(ads.isPlayingAd, isTrue);
      expect(controller.value.isPlaying, isFalse);
      final ad = ads.adPlayer!;
      expect(ad.source, adVideo);
      expect(ad.value.isPlaying, isTrue);
      expect(ads.skippableIn, const Duration(seconds: 5));
      ads.skip();
      expect(events, isNot(contains(PlayStackAdEvent.skip)));

      end(playerOf(ad));
      await flush();
      await flush();
      expect(ads.isPlayingAd, isFalse);
      expect(controller.value.isPlaying, isTrue);
      expect(events, containsAll([
        PlayStackAdEvent.impression,
        PlayStackAdEvent.start,
        PlayStackAdEvent.complete,
      ]));
      ads.dispose();
    });

    test('a skippable ad can be skipped after its offset', () async {
      final controller = manager.createController(content);
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [
          PlayStackAdBreak.preRoll(
            PlayStackAdSource.ads(const [
              PlayStackAd(source: adVideo, skipAfter: Duration(seconds: 5)),
            ]),
          ),
        ],
      );
      await controller.play();
      await flush();
      await flush();
      final ad = ads.adPlayer!;
      platform.positions[playerOf(ad)] = const Duration(seconds: 6);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(ads.skippableIn, Duration.zero);
      ads.skip();
      await flush();
      await flush();
      expect(ads.isPlayingAd, isFalse);
      expect(controller.value.isPlaying, isTrue);
      ads.dispose();
    });

    test('a mid-roll plays when playback passes it', () async {
      final controller = manager.createController(content);
      final ads = PlayStackAdController(
        manager: manager,
        content: controller,
        breaks: [
          PlayStackAdBreak.midRoll(
            at: const Duration(seconds: 50),
            source: PlayStackAdSource.ads(const [PlayStackAd(source: adVideo)]),
          ),
        ],
      );
      await controller.play();
      await flush();
      expect(ads.isPlayingAd, isFalse);
      platform.positions[playerOf(controller)] = const Duration(seconds: 51);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await flush();
      expect(ads.isPlayingAd, isTrue);
      expect(ads.skippableIn, isNull);
      end(playerOf(ads.adPlayer!));
      await flush();
      await flush();
      expect(controller.value.isPlaying, isTrue);
      ads.dispose();
    });
  });
}
