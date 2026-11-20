import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import 'support/fake_playstack_platform.dart';

void main() {
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;

  setUp(() async {
    platform = FakePlayStackPlatform();
    manager = PlayStackManager(platform: platform);
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  group('subtitle files', () {
    test('parses WebVTT and SubRip', () {
      final vtt = PlayStackSubtitleParser.parse('''WEBVTT

intro
00:01.000 --> 00:02.500 align:center
<b>Hello</b> &amp; welcome

00:00:03.000 --> 00:00:04.000
Line one
Line two
''');
      expect(vtt, [
        const PlayStackSubtitleCue(
          start: Duration(seconds: 1),
          end: Duration(milliseconds: 2500),
          text: 'Hello & welcome',
        ),
        const PlayStackSubtitleCue(
          start: Duration(seconds: 3),
          end: Duration(seconds: 4),
          text: 'Line one\nLine two',
        ),
      ]);
      final srt = PlayStackSubtitleParser.parse(
        '1\r\n00:00:01,000 --> 00:00:02,000\r\nMerhaba\r\n\r\n'
        '2\r\n00:01:00,500 --> 00:01:02,000\r\n<i>Nasılsın</i>\r\n',
        format: PlayStackSubtitleFormat.srt,
      );
      expect(srt.map((c) => c.text), ['Merhaba', 'Nasılsın']);
      expect(srt.last.start, const Duration(minutes: 1, milliseconds: 500));
    });

    test('are listed as tracks, chosen and shown by position', () async {
      const source = PlayStackSource.network(
        'https://example.com/a.mp4',
        subtitles: [
          PlayStackSubtitleSource.text(
            '00:00:01,000 --> 00:00:03,000\nMerhaba',
            language: 'tr',
            label: 'Türkçe',
          ),
        ],
      );
      final controller = manager.createController(source);
      await controller.initialize();
      final track = controller.tracks.value.singleWhere(
        (t) => t.id.startsWith('sidecar:'),
      );
      expect(track.label, 'Türkçe');
      expect(track.isSelected, isFalse);

      await controller.selectTrack(track);
      final id = platform.livePlayers.single;
      platform.positions[id] = const Duration(seconds: 2);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(controller.subtitles.value, ['Merhaba']);
      expect(
        controller.tracks.value.singleWhere((t) => t.id == track.id).isSelected,
        isTrue,
      );

      await controller.disableSubtitles();
      expect(controller.subtitles.value, isEmpty);
      await controller.dispose();
    });

    test('a default file is on from the start', () async {
      const source = PlayStackSource.network(
        'https://example.com/a.mp4',
        subtitles: [
          PlayStackSubtitleSource.text(
            '00:00:00,000 --> 00:00:05,000\nHi',
            isDefault: true,
          ),
        ],
      );
      final controller = manager.createController(source);
      await controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(controller.subtitles.value, ['Hi']);
      await controller.dispose();
    });
  });

  test('audio-only mode drops the picture on the player', () async {
    final controller = manager.createController(
      const PlayStackSource.network('https://example.com/a.mp4'),
    );
    await controller.setAudioOnly(true);
    expect(controller.audioOnly.value, isTrue);
    await controller.play();
    final id = platform.livePlayers.single;
    expect(platform.calls, contains('setVideoDisabled($id, true)'));
    await controller.setAudioOnly(false);
    expect(platform.calls, contains('setVideoDisabled($id, false)'));
    await controller.seekToLiveEdge();
    expect(platform.calls, contains('seekToLiveEdge($id)'));
  });

  group('sleep timer', () {
    test('pauses after the time and fades out', () async {
      final controller = manager.createController(
        const PlayStackSource.network('https://example.com/a.mp4'),
      );
      await controller.play();
      await flush();
      final finished = manager.sleepTimer.onFinished.first;
      manager.sleepTimer.start(
        const Duration(seconds: 2),
        fadeOut: const Duration(seconds: 2),
      );
      expect(manager.sleepTimer.isActive, isTrue);
      await finished.timeout(const Duration(seconds: 4));
      await flush();
      expect(controller.value.isPlaying, isFalse);
      expect(manager.sleepTimer.isActive, isFalse);
      expect(controller.value.volume, 1, reason: 'volume restored');
    });

    test('pauses at the end of the video and stops the feed', () async {
      final feed = manager.createFeed([
        for (var i = 0; i < 3; i++)
          PlayStackFeedItem(
            PlayStackSource.network('https://example.com/$i.mp4'),
            id: '$i',
          ),
      ], config: const PlayStackFeedConfig(activeHeadStart: Duration.zero));
      feed.setActiveIndex(0);
      await flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final controller = feed.activeController!;
      expect(controller.value.isPlaying, isTrue);
      manager.sleepTimer.startEndOfVideo();
      final id = controller.nativePlayerId!;
      platform.emit(
        PlayStackNativeStateEvent(
          playerId: id,
          generation: platform.generations[id]!,
          state: PlayStackNativePlaybackState.ended,
        ),
      );
      expect(feed.isPaused, isTrue);
      expect(manager.sleepTimer.isActive, isFalse);
      // The user plays again: the feed moves on as before.
      await controller.play();
      await flush();
      expect(feed.isPaused, isFalse);
    });
  });
}
