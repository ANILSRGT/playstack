import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';

import 'support/fake_playstack_platform.dart';

void main() {
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;
  const source = PlayStackSource.network(
    'https://example.com/episode-1.m3u8',
    cacheKey: 'episode-1',
  );

  setUp(() async {
    platform = FakePlayStackPlatform();
    manager = PlayStackManager(platform: platform);
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  test('downloads stay off until the app turns them on', () async {
    final downloads = manager.downloads;
    expect(downloads.isEnabled.value, isFalse);
    await expectLater(
      downloads.download('e1', source),
      throwsA(
        isA<PlayStackException>().having(
          (e) => e.code,
          'code',
          PlayStackErrorCode.notAllowed,
        ),
      ),
    );
    expect(platform.downloadRequests, isEmpty);
  });

  test('a completed download plays offline only while enabled', () async {
    final downloads = manager.downloads;
    await downloads.setEnabled(true);
    expect(platform.downloadsEnabled, isTrue);

    await downloads.download(
      'e1',
      source,
      title: 'Episode 1',
      maxVideoHeight: 720,
      metadata: const {'series': 'Coastline'},
    );
    final request = platform.downloadRequests.single;
    expect(request.maxVideoHeight, 720);
    expect(request.metadata, {'series': 'Coastline'});
    expect(downloads['e1']?.state, PlayStackDownloadState.queued);
    expect(downloads.isAvailableOffline(source), isFalse);

    platform.updateDownload(
      const PlayStackDownload(
        id: 'e1',
        key: 'episode-1',
        state: PlayStackDownloadState.completed,
        percent: 100,
      ),
    );
    expect(downloads.downloads.value.single.isCompleted, isTrue);
    expect(downloads.forSource(source)?.id, 'e1');
    expect(downloads.isAvailableOffline(source), isTrue);
    expect(manager.isAvailableOffline(source), isTrue);

    // The subscription ended: saved videos stream again.
    await downloads.setEnabled(false);
    expect(platform.downloadsEnabled, isFalse);
    expect(downloads.isAvailableOffline(source), isFalse);
    expect(downloads['e1'], isNotNull, reason: 'the files are kept');
  });

  test('a quality caps the renditions of the download', () async {
    await manager.downloads.setEnabled(true);
    await manager.downloads.download(
      'low',
      source,
      quality: PlayStackDownloadQuality.low,
    );
    await manager.downloads.download('best', source);
    expect(platform.downloadRequests.map((r) => r.maxVideoHeight), [360, null]);
    expect(PlayStackDownloadQuality.medium.label, '720p');
    expect(PlayStackDownloadQuality.best.label, 'Best');
  });

  test('removing deletes the download', () async {
    final downloads = manager.downloads;
    await downloads.setEnabled(true);
    await downloads.download('e1', source);
    await downloads.download(
      'e2',
      const PlayStackSource.network('https://example.com/e2.mp4'),
    );
    await downloads.remove('e1');
    expect(downloads.downloads.value.map((d) => d.id), ['e2']);
    await downloads.removeAll();
    expect(downloads.downloads.value, isEmpty);
    expect(platform.savedDownloads, isEmpty);
  });

  test('only network sources can be downloaded', () async {
    await manager.downloads.setEnabled(true);
    await expectLater(
      manager.downloads.download('a', const PlayStackSource.file('/a.mp4')),
      throwsA(
        isA<PlayStackException>().having(
          (e) => e.code,
          'code',
          PlayStackErrorCode.invalidSource,
        ),
      ),
    );
  });

  test('downloads saved earlier are listed once enabled', () async {
    platform.savedDownloads['old'] = const PlayStackDownload(
      id: 'old',
      key: 'episode-1',
      state: PlayStackDownloadState.completed,
    );
    await manager.downloads.setEnabled(true);
    expect(manager.downloads['old']?.isCompleted, isTrue);
    expect(manager.downloads.isAvailableOffline(source), isTrue);
  });

  test('platforms without downloads stay off', () async {
    final web = FakePlayStackPlatform()..supportsDownloads = false;
    final other = PlayStackManager(platform: web);
    await other.initialize();
    await other.downloads.setEnabled(true);
    expect(other.downloads.isEnabled.value, isFalse);
    await other.dispose();
  });

  test('every manager of the app sees the same downloads', () async {
    await manager.downloads.setEnabled(true);
    await manager.downloads.download('e1', source);
    final feedManager = PlayStackManager(platform: platform);
    await feedManager.initialize();
    expect(feedManager.downloads.isEnabled.value, isTrue);
    expect(feedManager.downloads['e1'], isNotNull);
    await feedManager.dispose();
    expect(manager.downloads['e1'], isNotNull, reason: 'still followed');
  });
}
