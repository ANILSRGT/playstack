import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

void main() {
  group('format detection', () {
    test('detects HLS and DASH by extension, ignoring query strings', () {
      expect(
        PlayStackSource.detectFormat(
          'https://cdn.example.com/a/master.m3u8?t=1',
        ),
        PlayStackVideoFormat.hls,
      );
      expect(
        PlayStackSource.detectFormat('https://cdn.example.com/manifest.MPD#x'),
        PlayStackVideoFormat.dash,
      );
      expect(
        PlayStackSource.detectFormat('https://cdn.example.com/a.mp4'),
        PlayStackVideoFormat.progressive,
      );
      expect(
        PlayStackSource.detectFormat('/storage/videos/clip.m3u8'),
        PlayStackVideoFormat.hls,
      );
    });

    test('an explicit format hint wins', () {
      const source = PlayStackSource.network(
        'https://example.com/stream',
        formatHint: PlayStackVideoFormat.hls,
      );
      expect(source.resolvedFormat, PlayStackVideoFormat.hls);
      expect(
        const PlayStackSource.asset('videos/intro.mp4').resolvedFormat,
        PlayStackVideoFormat.progressive,
      );
    });
  });

  test('network sources compare by value', () {
    const a = PlayStackSource.network(
      'https://example.com/a.mp4',
      headers: {'Authorization': 'Bearer x', 'X-A': '1'},
    );
    const b = PlayStackSource.network(
      'https://example.com/a.mp4',
      headers: {'X-A': '1', 'Authorization': 'Bearer x'},
    );
    const c = PlayStackSource.network('https://example.com/a.mp4');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('cache key defaults to the URL', () {
    const plain = PlayStackNetworkSource('https://example.com/a.mp4?sig=1');
    const keyed = PlayStackNetworkSource(
      'https://example.com/a.mp4?sig=2',
      cacheKey: 'video-a',
    );
    expect(plain.effectiveCacheKey, 'https://example.com/a.mp4?sig=1');
    expect(keyed.effectiveCacheKey, 'video-a');
  });

  test('memory sources compare by buffer identity', () {
    final bytes = Uint8List(4);
    expect(
      PlayStackSource.memory(bytes, mimeType: 'video/mp4'),
      PlayStackSource.memory(bytes, mimeType: 'video/mp4'),
    );
    expect(
      PlayStackSource.memory(bytes, mimeType: 'video/mp4'),
      isNot(PlayStackSource.memory(Uint8List(4), mimeType: 'video/mp4')),
    );
  });

  test('asset description includes the package', () {
    expect(
      const PlayStackSource.asset('a.mp4', package: 'pkg').description,
      'packages/pkg/a.mp4',
    );
  });
}
