import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

void main() {
  group('format detection', () {
    test('detects HLS and DASH by extension, ignoring query strings', () {
      expect(
        ReelSource.detectFormat('https://cdn.example.com/a/master.m3u8?t=1'),
        ReelVideoFormat.hls,
      );
      expect(
        ReelSource.detectFormat('https://cdn.example.com/manifest.MPD#x'),
        ReelVideoFormat.dash,
      );
      expect(
        ReelSource.detectFormat('https://cdn.example.com/a.mp4'),
        ReelVideoFormat.progressive,
      );
      expect(
        ReelSource.detectFormat('/storage/videos/clip.m3u8'),
        ReelVideoFormat.hls,
      );
    });

    test('an explicit format hint wins', () {
      const source = ReelSource.network(
        'https://example.com/stream',
        formatHint: ReelVideoFormat.hls,
      );
      expect(source.resolvedFormat, ReelVideoFormat.hls);
      expect(
        const ReelSource.asset('videos/intro.mp4').resolvedFormat,
        ReelVideoFormat.progressive,
      );
    });
  });

  test('network sources compare by value', () {
    const a = ReelSource.network(
      'https://example.com/a.mp4',
      headers: {'Authorization': 'Bearer x', 'X-A': '1'},
    );
    const b = ReelSource.network(
      'https://example.com/a.mp4',
      headers: {'X-A': '1', 'Authorization': 'Bearer x'},
    );
    const c = ReelSource.network('https://example.com/a.mp4');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('cache key defaults to the URL', () {
    const plain = ReelNetworkSource('https://example.com/a.mp4?sig=1');
    const keyed = ReelNetworkSource(
      'https://example.com/a.mp4?sig=2',
      cacheKey: 'video-a',
    );
    expect(plain.effectiveCacheKey, 'https://example.com/a.mp4?sig=1');
    expect(keyed.effectiveCacheKey, 'video-a');
  });

  test('memory sources compare by buffer identity', () {
    final bytes = Uint8List(4);
    expect(
      ReelSource.memory(bytes, mimeType: 'video/mp4'),
      ReelSource.memory(bytes, mimeType: 'video/mp4'),
    );
    expect(
      ReelSource.memory(bytes, mimeType: 'video/mp4'),
      isNot(ReelSource.memory(Uint8List(4), mimeType: 'video/mp4')),
    );
  });

  test('asset description includes the package', () {
    expect(
      const ReelSource.asset('a.mp4', package: 'pkg').description,
      'packages/pkg/a.mp4',
    );
  });
}
