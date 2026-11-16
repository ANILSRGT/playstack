import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_example/samples.dart';

import 'support/media_server.dart';
import 'support/test_results.dart';

/// Milestone 6 against the real engine: disk cache, retry, fullscreen and
/// orientation restoration. Media comes from a local HTTP server so the
/// tests do not depend on the internet. The server needs `dart:io`, so the
/// network tests do not run on the web, where browsers also offer no
/// PlayStack-managed cache; fullscreen has a web-specific test.
void main() {
  final binding = ensureBindingWithResults();

  late MediaServer server;
  final managers = <PlayStackManager>[];

  setUpAll(() async {
    if (kIsWeb) return;
    final data = await rootBundle.load(landscapeAsset);
    server = await MediaServer.start(data.buffer.asUint8List());
  });

  tearDownAll(() async {
    if (!kIsWeb) await server.close();
  });

  tearDown(() async {
    for (final manager in managers) {
      await manager.dispose();
    }
    managers.clear();
    if (kIsWeb) return;
    server
      ..offline = false
      ..failNextRequests = 0;
  });

  // The example app allows every orientation, so after unlocking, iOS turns
  // to the (simulated) device orientation. Apps register the policy they
  // want restored; these tests register portrait only.
  const portraitApp = PlayStackFullscreenConfig(
    appOrientations: [DeviceOrientation.portraitUp],
  );

  Future<PlayStackManager> createManager({
    PlayStackRetryConfig retry = const PlayStackRetryConfig(),
  }) async {
    final manager = PlayStackManager(
      config: PlayStackConfig(
        fullscreen: portraitApp,
        pool: const PlayStackPoolConfig(maxPlayers: 2),
        player: PlayStackPlayerConfig(muted: true, retry: retry),
      ),
    );
    managers.add(manager);
    await manager.initialize();
    return manager;
  }

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  testWidgets('caches a network video and plays it offline', (tester) async {
    final manager = await createManager();
    if (!manager.cache.isSupported) return;
    await manager.cache.clear();
    final source = PlayStackNetworkSource(server.url('cached.mp4').toString());

    final first = manager.createController(source);
    await first.play();
    await waitUntil(
      () => first.value.status == PlayStackPlaybackStatus.completed,
      reason: 'played to the end; ${first.value}',
    );
    await first.dispose(); // closes the cache entry (iOS writes its index)
    final cached = await manager.cache.cachedBytes(source);
    expect(cached, server.bytes.length, reason: 'whole file cached');
    expect(
      (await manager.cache.info()).usedBytes,
      greaterThanOrEqualTo(cached),
    );

    server.offline = true;
    final second = manager.createController(source);
    await second.play();
    await waitUntil(
      () => second.value.isPlaying,
      reason: 'plays from cache while offline; ${second.value}',
    );
    await second.dispose();

    await manager.cache.remove(source);
    expect(await manager.cache.cachedBytes(source), 0);
  }, skip: kIsWeb);

  testWidgets('a bypass source is not cached', (tester) async {
    final manager = await createManager();
    if (!manager.cache.isSupported) return;
    final source = PlayStackNetworkSource(
      server.url('private.mp4').toString(),
      cachePolicy: PlayStackCachePolicy.bypass,
    );
    final controller = manager.createController(source);
    await controller.initialize();
    await controller.dispose();
    expect(await manager.cache.cachedBytes(source), 0);
  }, skip: kIsWeb);

  testWidgets('a downloaded video plays without a network', (tester) async {
    if (kIsWeb) return;
    final manager = await createManager(retry: PlayStackRetryConfig.none);
    final downloads = manager.downloads;
    expect(await downloads.isSupported(), isTrue);
    await downloads.setEnabled(true);
    // Off the disk cache, so only the download can serve it offline.
    final source = PlayStackSource.network(
      server
          .url('download-${DateTime.now().microsecondsSinceEpoch}.mp4')
          .toString(),
      cachePolicy: PlayStackCachePolicy.bypass,
    );
    const id = 'integration-download';
    await downloads.download(id, source, title: 'Integration test');
    await waitUntil(
      () => downloads[id]?.isCompleted ?? false,
      timeout: const Duration(seconds: 30),
      reason: 'download completed: ${downloads[id]}',
    );
    expect(downloads.isAvailableOffline(source), isTrue);

    server.offline = true;
    final offline = manager.createController(source);
    await offline.initialize();
    expect(offline.value.status, PlayStackPlaybackStatus.ready);
    await offline.dispose();

    // Without permission the download is not used: offline it fails.
    await downloads.setEnabled(false);
    final gated = manager.createController(source);
    await expectLater(gated.initialize(), throwsA(isA<PlayStackException>()));
    await gated.dispose();

    await downloads.setEnabled(true);
    await downloads.remove(id);
    expect(downloads[id], isNull);
  });

  testWidgets('retries a failed preparation automatically', (tester) async {
    final manager = await createManager(
      retry: const PlayStackRetryConfig(
        initialDelay: Duration(milliseconds: 200),
      ),
    );
    server.failNextRequests = 1;
    final controller = manager.createController(
      PlayStackNetworkSource(
        server.url('flaky.mp4').toString(),
        cachePolicy: PlayStackCachePolicy.bypass,
      ),
    );
    await controller.initialize();
    expect(controller.value.status, PlayStackPlaybackStatus.ready);
    expect(controller.metrics.preparations, 1);
  }, skip: kIsWeb);

  testWidgets('fullscreen restores portrait after landscape', (tester) async {
    final manager = await createManager();
    final fullscreen = manager.fullscreen;
    final view = binding.platformDispatcher.views.first;
    bool isPortrait() => view.physicalSize.height > view.physicalSize.width;
    await SystemChrome.setPreferredOrientations(portraitApp.appOrientations);
    await waitUntil(isPortrait, reason: 'starts in portrait');

    for (var round = 0; round < 3; round++) {
      await fullscreen.enter(
        orientation: PlayStackFullscreenOrientation.landscape,
      );
      expect(fullscreen.isFullscreen.value, isTrue);
      await waitUntil(
        () => !isPortrait(),
        reason: 'rotated to landscape (round $round)',
      );
      await fullscreen.exit();
      expect(fullscreen.isFullscreen.value, isFalse);
      await waitUntil(isPortrait, reason: 'back to portrait (round $round)');
    }
  }, skip: kIsWeb);

  testWidgets('fullscreen without an orientation keeps portrait', (
    tester,
  ) async {
    final manager = await createManager();
    final view = binding.platformDispatcher.views.first;
    await SystemChrome.setPreferredOrientations(portraitApp.appOrientations);
    await waitUntil(
      () => view.physicalSize.height > view.physicalSize.width,
      reason: 'starts in portrait',
    );
    final before = view.physicalSize;
    await manager.fullscreen.enter();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(view.physicalSize.height > view.physicalSize.width, isTrue);
    await manager.fullscreen.exit();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(view.physicalSize.aspectRatio, closeTo(before.aspectRatio, 0.2));
    // Leave the app with its default policy for later tests.
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  }, skip: kIsWeb);

  testWidgets('web fullscreen needs a user gesture', (tester) async {
    final manager = await createManager();
    final fullscreen = manager.fullscreen;
    try {
      await fullscreen.enter();
      binding.reportData = {...?binding.reportData, 'fullscreen': 'allowed'};
      // Allowed (for example by a browser flag): it must be reversible.
      expect(fullscreen.isFullscreen.value, isTrue);
      await fullscreen.exit();
      expect(fullscreen.isFullscreen.value, isFalse);
    } on PlayStackException catch (error) {
      binding.reportData = {...?binding.reportData, 'fullscreen': 'refused'};
      expect(error.code, PlayStackErrorCode.notAllowed);
      expect(fullscreen.isFullscreen.value, isFalse);
    }
  }, skip: !kIsWeb);
}
