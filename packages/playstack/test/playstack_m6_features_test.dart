import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import 'support/fake_playstack_platform.dart';

const _source = PlayStackSource.network('https://example.com/a.mp4');
const _fastRetry = PlayStackRetryConfig(
  initialDelay: Duration(milliseconds: 5),
  maxDelay: Duration(milliseconds: 20),
);
const _networkError = PlayStackException(PlayStackErrorCode.network, 'offline');

Future<void> settle([int turns = 40]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlayStackPlatform platform;
  late PlayStackManager manager;
  PlayStackManager? started;

  Future<void> start({
    PlayStackConfig config = const PlayStackConfig(
      player: PlayStackPlayerConfig(retry: _fastRetry),
    ),
    bool diskCache = false,
  }) async {
    platform = FakePlayStackPlatform(supportsDiskCache: diskCache);
    manager = PlayStackManager(config: config, platform: platform);
    await manager.initialize();
    started = manager;
  }

  tearDown(() async {
    await started?.dispose();
    started = null;
  });

  group('retry', () {
    test('delays grow and are capped', () {
      const retry = PlayStackRetryConfig(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 5),
      );
      expect(retry.delayFor(1), const Duration(seconds: 1));
      expect(retry.delayFor(2), const Duration(seconds: 2));
      expect(retry.delayFor(3), const Duration(seconds: 4));
      expect(retry.delayFor(4), const Duration(seconds: 5));
      expect(retry.isRetryable(PlayStackErrorCode.network), isTrue);
      expect(retry.isRetryable(PlayStackErrorCode.sourceNotFound), isFalse);
    });

    test('a failed preparation is retried within initialize', () async {
      await start();
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      await controller.initialize();
      expect(controller.value.status, PlayStackPlaybackStatus.ready);
      expect(platform.callCount('setSource'), 2);
    });

    test('non-transient errors are not retried', () async {
      await start();
      platform.failingOnce[_source] = const PlayStackException(
        PlayStackErrorCode.sourceNotFound,
        '404',
      );
      final controller = manager.createController(_source);
      await expectLater(
        controller.initialize(),
        throwsA(isA<PlayStackException>()),
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
        PlayStackErrorEvent(
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
        config: const PlayStackConfig(
          player: PlayStackPlayerConfig(retry: PlayStackRetryConfig.none),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      await expectLater(
        controller.initialize(),
        throwsA(isA<PlayStackException>()),
      );
      expect(controller.value.hasError, isTrue);

      await controller.retry();
      expect(controller.value.status, PlayStackPlaybackStatus.ready);

      await controller.reinitialize();
      expect(controller.value.status, PlayStackPlaybackStatus.ready);
      expect(platform.callCount('setSource'), 3);
    });

    test('release cancels a pending automatic retry', () async {
      await start(
        config: const PlayStackConfig(
          player: PlayStackPlayerConfig(
            retry: PlayStackRetryConfig(initialDelay: Duration(seconds: 10)),
          ),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      final preparing = controller.initialize();
      final cancelled = expectLater(
        preparing,
        throwsA(
          isA<PlayStackException>().having(
            (e) => e.code,
            'code',
            PlayStackErrorCode.cancelled,
          ),
        ),
      );
      await settle();
      await controller.release();
      await cancelled;
      expect(controller.value.status, PlayStackPlaybackStatus.idle);
    });

    test('setSource cancels a pending automatic retry', () async {
      await start(
        config: const PlayStackConfig(
          player: PlayStackPlayerConfig(
            retry: PlayStackRetryConfig(initialDelay: Duration(seconds: 10)),
          ),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      final cancelled = expectLater(
        controller.initialize(),
        throwsA(
          isA<PlayStackException>().having(
            (e) => e.code,
            'code',
            PlayStackErrorCode.cancelled,
          ),
        ),
      );
      await settle();
      const other = PlayStackSource.network('https://example.com/b.mp4');
      final switching = controller.setSource(other);
      await cancelled;
      await switching;
      await controller.initialize();
      expect(controller.value.status, PlayStackPlaybackStatus.ready);
      expect(controller.source, other);
      // The old source was tried once and never retried.
      expect(platform.callCount('setSource'), 2);
    });

    test('reconnection retries controllers that failed offline', () async {
      await start(
        config: const PlayStackConfig(
          player: PlayStackPlayerConfig(retry: PlayStackRetryConfig.none),
        ),
      );
      platform.failingOnce[_source] = _networkError;
      final controller = manager.createController(_source);
      await controller.initialize().catchError((Object _) {});
      expect(controller.value.hasError, isTrue);

      platform.setNetwork(const PlayStackNetworkStatus(isConnected: false));
      platform.setNetwork(const PlayStackNetworkStatus(isConnected: true));
      await settle();
      expect(controller.value.status, PlayStackPlaybackStatus.ready);
    });
  });

  test('interruptions are forwarded', () async {
    await start();
    final controller = manager.createController(_source);
    await controller.play();
    await settle();
    final playerId = platform.livePlayers.single;
    final received = <PlayStackInterruption>[];
    controller.interruptions.listen(received.add);
    platform.emit(
      PlayStackInterruptionEvent(
        playerId: playerId,
        generation: platform.generations[playerId]!,
        type: PlayStackInterruptionType.audioRouteLost,
        ended: false,
      ),
    );
    await settle(2);
    expect(received, [
      const PlayStackInterruption(
        type: PlayStackInterruptionType.audioRouteLost,
        ended: false,
      ),
    ]);
  });

  test('engine configuration carries cache and audio settings', () async {
    await start(
      config: const PlayStackConfig(
        cache: PlayStackCacheConfig(maxBytes: 1000),
        audio: PlayStackAudioConfig(
          handleAudioFocus: false,
          iosAudioSessionCategory: PlayStackAudioSessionCategory.playback,
          mixWithOthers: true,
        ),
      ),
    );
    final config = platform.engineConfig!;
    expect(config.cacheEnabled, isTrue);
    expect(config.cacheMaxBytes, 1000);
    expect(config.handleAudioFocus, isFalse);
    expect(config.audioSessionCategory, PlayStackAudioSessionCategory.playback);
    expect(config.mixWithOthers, isTrue);
  });

  group('cache', () {
    test('inspects and clears through the engine', () async {
      await start(diskCache: true);
      const keyed = PlayStackNetworkSource(
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
      expect(await manager.cache.info(), PlayStackCacheInfo.disabled);
      expect(
        await manager.cache.cachedBytes(_source as PlayStackNetworkSource),
        0,
      );
    });

    test('sources can bypass the cache', () {
      const bypass = PlayStackSource.network(
        'https://example.com/private.mp4',
        cachePolicy: PlayStackCachePolicy.bypass,
      );
      expect(
        (bypass as PlayStackNetworkSource).cachePolicy,
        PlayStackCachePolicy.bypass,
      );
      expect(
        bypass,
        isNot(const PlayStackSource.network('https://example.com/private.mp4')),
      );
    });
  });

  group('fullscreen', () {
    test(
      'keeps the orientation unless asked and restores the app policy',
      () async {
        await start(
          config: const PlayStackConfig(
            fullscreen: PlayStackFullscreenConfig(
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
        const PlayStackFullscreenConfig(
          appOrientations: [
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
          ],
          appSystemUiMode: SystemUiMode.manual,
          appOverlays: [SystemUiOverlay.top],
        ),
      );
      await fullscreen.enter(
        orientation: PlayStackFullscreenOrientation.landscape,
      );
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
        orientation: PlayStackFullscreenOrientation.matchVideo,
        controller: controller,
      );
      expect(platform.fullscreenRequests.single.orientations, [
        DeviceOrientation.portraitUp,
      ]);
    });

    test('leaving outside PlayStack updates the state', () async {
      await start();
      await manager.fullscreen.enter();
      platform.fullscreenEvents.add(false);
      expect(manager.fullscreen.isFullscreen.value, isFalse);
    });

    test('manager dispose leaves fullscreen', () async {
      await start();
      await manager.fullscreen.enter(
        orientation: PlayStackFullscreenOrientation.landscape,
      );
      await manager.dispose();
      expect(platform.fullscreenRestores, hasLength(1));
    });
  });
}

void unawaitedEnter(PlayStackFullscreenManager fullscreen) {
  // Enter and exit are serialized, so a following exit sees the fullscreen.
  fullscreen
      .enter(orientation: PlayStackFullscreenOrientation.portrait)
      .ignore();
}
