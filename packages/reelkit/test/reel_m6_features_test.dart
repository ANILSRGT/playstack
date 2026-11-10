import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import 'support/fake_reelkit_platform.dart';

const _source = ReelSource.network('https://example.com/a.mp4');
const _fastRetry = ReelRetryConfig(
  initialDelay: Duration(milliseconds: 5),
  maxDelay: Duration(milliseconds: 20),
);
const _networkError = ReelKitException(ReelKitErrorCode.network, 'offline');

Future<void> settle([int turns = 40]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeReelKitPlatform platform;
  late ReelKitManager manager;
  ReelKitManager? started;

  Future<void> start({
    ReelKitConfig config = const ReelKitConfig(
      player: ReelPlayerConfig(retry: _fastRetry),
    ),
    bool diskCache = false,
  }) async {
    platform = FakeReelKitPlatform(supportsDiskCache: diskCache);
    manager = ReelKitManager(config: config, platform: platform);
    await manager.initialize();
    started = manager;
  }

  tearDown(() async {
    await started?.dispose();
    started = null;
  });

  group('retry', () {
    test('delays grow and are capped', () {
      const retry = ReelRetryConfig(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
      );
      expect(retry.delayFor(1), const Duration(seconds: 1));
      expect(retry.delayFor(2), const Duration(seconds: 2));
      expect(retry.delayFor(3), const Duration(seconds: 4));
      expect(retry.delayFor(4), const Duration(seconds: 5));
      expect(retry.isRetryable(ReelKitErrorCode.network), isTrue);
      expect(retry.isRetryable(ReelKitErrorCode.sourceNotFound), isFalse);
    });

    test('a failed preparation is retried within initialize', () async {
      await start();
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      await controller.initialize();
      expect(controller.value.status, ReelPlaybackStatus.ready);
      expect(platform.callCount('setSource'), 2);
    });

    test('non-transient errors are not retried', () async {
      await start();
      platform.failingOnce[_source] = const ReelKitException(
        ReelKitErrorCode.sourceNotFound,
        '404',
      );
      final controller = manager.createController(_source);
      await expectLater(
        controller.initialize(),
        throwsA(isA<ReelKitException>()),
      );
      expect(platform.callCount('setSource'), 1);
    });

    test('playback errors recover at the failed position', () async {
      await start();
      final controller = manager.createController(_source);
      await controller.play();
      await settle();
      final playerId = platform.livePlayers.single;
      platform.positions[playerId] = const Duration(seconds: 12);
      platform.emit(
        ReelErrorEvent(
          playerId: playerId,
          generation: platform.generations[playerId]!,
          error: _networkError,
        ),
      );
      expect(controller.value.hasError, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();

      expect(controller.value.isPlaying, isTrue);
      expect(platform.calls, contains('seekTo($playerId, 12000)'));
      expect(platform.callCount('setSource'), 2);
    });

    test('retry and reinitialize work on demand', () async {
      await start(
        config: const ReelKitConfig(
          player: ReelPlayerConfig(retry: ReelRetryConfig.none),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      await expectLater(
        controller.initialize(),
        throwsA(isA<ReelKitException>()),
      );
      expect(controller.value.hasError, isTrue);

      await controller.retry();
      expect(controller.value.status, ReelPlaybackStatus.ready);

      await controller.reinitialize();
      expect(controller.value.status, ReelPlaybackStatus.ready);
      expect(platform.callCount('setSource'), 3);
    });

    test('release cancels a pending automatic retry', () async {
      await start(
        config: const ReelKitConfig(
          player: ReelPlayerConfig(
            retry: ReelRetryConfig(initialDelay: Duration(seconds: 10)),
          ),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      final preparing = controller.initialize();
      final cancelled = expectLater(
        preparing,
        throwsA(
          isA<ReelKitException>().having(
            (e) => e.code,
            'code',
            ReelKitErrorCode.cancelled,
          ),
        ),
      );
      await settle();
      await controller.release();
      await cancelled;
      expect(controller.value.status, ReelPlaybackStatus.idle);
    });

    test('reconnection retries controllers that failed offline', () async {
      await start(
        config: const ReelKitConfig(
          player: ReelPlayerConfig(retry: ReelRetryConfig.none),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      await controller.initialize().catchError((Object _) {});
      expect(controller.value.hasError, isTrue);

      platform.setNetwork(const ReelNetworkStatus(isConnected: false));
      platform.setNetwork(const ReelNetworkStatus(isConnected: true));
      await settle();
      expect(controller.value.status, ReelPlaybackStatus.ready);
    });
  });

  test('interruptions are forwarded', () async {
    await start();
    final controller = manager.createController(_source);
    await controller.play();
    await settle();
    final playerId = platform.livePlayers.single;
    final received = <ReelInterruption>[];
    controller.interruptions.listen(received.add);
    platform.emit(
      ReelInterruptionEvent(
        playerId: playerId,
        generation: platform.generations[playerId]!,
        type: ReelInterruptionType.audioRouteLost,
        ended: false,
      ),
    );
    await settle(2);
    expect(received, [
      const ReelInterruption(
        type: ReelInterruptionType.audioRouteLost,
        ended: false,
      ),
    ]);
  });

  test('engine configuration carries cache and audio settings', () async {
    await start(
      config: const ReelKitConfig(
        cache: ReelCacheConfig(maxBytes: 1000),
        audio: ReelAudioConfig(
          handleAudioFocus: false,
          iosAudioSessionCategory: ReelAudioSessionCategory.playback,
          mixWithOthers: true,
        ),
      ),
    );
    final config = platform.engineConfig!;
    expect(config.cacheEnabled, isTrue);
    expect(config.cacheMaxBytes, 1000);
    expect(config.handleAudioFocus, isFalse);
    expect(config.audioSessionCategory, ReelAudioSessionCategory.playback);
    expect(config.mixWithOthers, isTrue);
  });

  group('cache', () {
    test('inspects and clears through the engine', () async {
      await start(diskCache: true);
      const keyed = ReelNetworkSource(
        'https://cdn.example.com/a.mp4?sig=1',
        cacheKey: 'video-a',
      );
      platform.cache['video-a'] = 500;
      platform.cache['https://example.com/a.mp4'] = 300;

      expect((await manager.cache.info()).usedBytes, 800);
      expect(await manager.cache.cachedBytes(keyed), 500);
      await manager.cache.remove(keyed);
      expect(await manager.cache.cachedBytes(keyed), 0);
      await manager.cache.clear();
      expect((await manager.cache.info()).usedBytes, 0);
    });

    test('engines without a cache report it disabled', () async {
      await start();
      expect(manager.cache.isSupported, isFalse);
      expect(await manager.cache.info(), ReelCacheInfo.disabled);
      expect(await manager.cache.cachedBytes(_source as ReelNetworkSource), 0);
    });

    test('sources can bypass the cache', () {
      const bypass = ReelSource.network(
        'https://example.com/private.mp4',
        cachePolicy: ReelCachePolicy.bypass,
      );
      expect((bypass as ReelNetworkSource).cachePolicy, ReelCachePolicy.bypass);
      expect(
        bypass,
        isNot(const ReelSource.network('https://example.com/private.mp4')),
      );
    });
  });

  group('fullscreen', () {
    test(
      'keeps the orientation unless asked and restores the app policy',
      () async {
        await start(
          config: const ReelKitConfig(
            fullscreen: ReelFullscreenConfig(
              appOrientations: [DeviceOrientation.portraitUp],
            ),
          ),
        );
        final fullscreen = manager.fullscreen;
        await fullscreen.enter();
        expect(fullscreen.isFullscreen.value, isTrue);
        expect(platform.fullscreenRequests.single.orientations, isNull);
        await fullscreen.exit();
        expect(fullscreen.isFullscreen.value, isFalse);
        final restore = platform.fullscreenRestores.single;
        expect(restore.changedOrientations, isFalse);
        expect(restore.orientations, [DeviceOrientation.portraitUp]);
        expect(restore.systemUiMode, SystemUiMode.edgeToEdge);
      },
    );

    test('landscape fullscreen restores the policy on exit', () async {
      await start();
      final fullscreen = manager.fullscreen;
      fullscreen.setAppPolicy(
        const ReelFullscreenConfig(
          appOrientations: [
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
          ],
          appSystemUiMode: SystemUiMode.manual,
          appOverlays: [SystemUiOverlay.top],
        ),
      );
      await fullscreen.enter(orientation: ReelFullscreenOrientation.landscape);
      expect(platform.fullscreenRequests.single.orientations, [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await fullscreen.exit();
      final restore = platform.fullscreenRestores.single;
      expect(restore.changedOrientations, isTrue);
      expect(restore.orientations, [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
      ]);
      expect(restore.systemUiMode, SystemUiMode.manual);
      expect(restore.overlays, [SystemUiOverlay.top]);
    });

    test('repeated enter and exit stay balanced', () async {
      await start();
      final fullscreen = manager.fullscreen;
      for (var i = 0; i < 20; i++) {
        unawaitedEnter(fullscreen);
        await fullscreen.exit();
        await fullscreen.exit();
      }
      expect(fullscreen.isFullscreen.value, isFalse);
      expect(platform.fullscreenRestores, hasLength(20));
      expect(
        platform.fullscreenRestores.every((r) => r.changedOrientations),
        isTrue,
      );
    });

    test('matchVideo picks the orientation from the video', () async {
      await start();
      final controller = manager.createController(_source);
      await controller.initialize(); // fake video is 1080x1920
      await manager.fullscreen.enter(
        orientation: ReelFullscreenOrientation.matchVideo,
        controller: controller,
      );
      expect(platform.fullscreenRequests.single.orientations, [
        DeviceOrientation.portraitUp,
      ]);
    });

    test('leaving outside ReelKit updates the state', () async {
      await start();
      await manager.fullscreen.enter();
      platform.fullscreenEvents.add(false);
      expect(manager.fullscreen.isFullscreen.value, isFalse);
    });

    test('manager dispose leaves fullscreen', () async {
      await start();
      await manager.fullscreen.enter(
        orientation: ReelFullscreenOrientation.landscape,
      );
      await manager.dispose();
      expect(platform.fullscreenRestores, hasLength(1));
    });
  });
}

void unawaitedEnter(ReelFullscreenManager fullscreen) {
  // Enter and exit are serialized, so a following exit sees the fullscreen.
  fullscreen.enter(orientation: ReelFullscreenOrientation.portrait).ignore();
}
