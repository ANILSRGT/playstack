import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';

import 'support/fake_reelkit_platform.dart';

ReelSource _source(int i) => ReelSource.network('https://example.com/$i.mp4');

List<ReelFeedItem> _items(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++) ReelFeedItem(_source(i), id: '$i'),
];

/// Lets chained preparations and preloads run.
Future<void> settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeReelKitPlatform platform;
  late ReelKitManager manager;
  ReelKitManager? started;

  Future<void> start({
    int maxPlayers = 3,
    bool lowRam = false,
    bool networkStatus = true,
  }) async {
    platform = FakeReelKitPlatform(
      isLowRamDevice: lowRam,
      supportsNetworkStatus: networkStatus,
    );
    manager = ReelKitManager(
      config: ReelKitConfig(pool: ReelPoolConfig(maxPlayers: maxPlayers)),
      platform: platform,
    );
    await manager.initialize();
    started = manager;
  }

  tearDown(() async {
    await started?.dispose();
    started = null;
  });

  group('preload window', () {
    const config = ReelFeedConfig(preloadAhead: 3, preloadBehind: 2);
    const wifi = ReelNetworkStatus(isConnected: true);

    ReelPreloadWindow resolve({
      ReelNetworkStatus network = wifi,
      bool lowRam = false,
      bool pressure = false,
      int maxPlayers = 10,
    }) => ReelPreloadWindow.resolve(
      config: config,
      network: network,
      isLowRamDevice: lowRam,
      underMemoryPressure: pressure,
      maxPlayers: maxPlayers,
    );

    test('uses the configured window when resources allow', () {
      expect(resolve(), const ReelPreloadWindow(ahead: 3, behind: 2));
    });

    test('shrinks on metered and constrained networks', () {
      expect(
        resolve(
          network: const ReelNetworkStatus(isConnected: true, isMetered: true),
        ),
        const ReelPreloadWindow(ahead: 1, behind: 0),
      );
      expect(
        resolve(
          network: const ReelNetworkStatus(
            isConnected: true,
            isConstrained: true,
          ),
        ),
        ReelPreloadWindow.none,
      );
    });

    test('shrinks on low memory and under memory pressure', () {
      expect(
        resolve(lowRam: true),
        const ReelPreloadWindow(ahead: 1, behind: 0),
      );
      expect(
        resolve(pressure: true),
        const ReelPreloadWindow(ahead: 1, behind: 0),
      );
    });

    test('keeps one player for the active item, dropping behind first', () {
      expect(
        resolve(maxPlayers: 4),
        const ReelPreloadWindow(ahead: 3, behind: 0),
      );
      expect(
        resolve(maxPlayers: 3),
        const ReelPreloadWindow(ahead: 2, behind: 0),
      );
      expect(resolve(maxPlayers: 1), ReelPreloadWindow.none);
    });

    test('orders the next item first, then the previous one', () {
      const window = ReelPreloadWindow(ahead: 3, behind: 2);
      expect(window.order(5, 20), [6, 4, 7, 8, 3]);
      expect(window.order(0, 2), [1]);
    });
  });

  test('plays the active item and prepares the next ones', () async {
    await start();
    final feed = manager.createFeed(_items(10));
    feed.setActiveIndex(0);
    await settle();

    expect(feed.controllerAt(0).value.isPlaying, isTrue);
    expect(feed.controllerAt(1).value.status, ReelPlaybackStatus.ready);
    expect(feed.controllerAt(2).value.status, ReelPlaybackStatus.ready);
    expect(feed.controllerAt(1).priority, ReelPlayerPriority.preload);
    expect(feed.controllerAt(3).value.isAttached, isFalse);
    expect(
      feed.preloadWindow.value,
      const ReelPreloadWindow(ahead: 2, behind: 0),
    );
    expect(feed.stats.preloadsCompleted, 2);

    final preloadPlayer = platform.calls
        .where((c) => c.startsWith('setPreloadBufferLimit'))
        .toList();
    expect(preloadPlayer, isNotEmpty, reason: 'preloads are buffer-limited');
    expect(platform.bufferLimits.values, contains(const Duration(seconds: 5)));
  });

  test('moving forward plays a prepared item and shifts the window', () async {
    await start();
    final feed = manager.createFeed(_items(10));
    feed.setActiveIndex(0);
    await settle();
    final next = feed.controllerAt(1);

    feed.setActiveIndex(1);
    await settle();

    expect(next.value.isPlaying, isTrue);
    expect(feed.controllerAt(0).value.isPlaying, isFalse);
    expect(feed.controllerAt(3).value.status, ReelPlaybackStatus.ready);
    expect(feed.controllerAt(0).value.isAttached, isFalse, reason: 'left');
    expect(feed.stats.transitions, 2);
    expect(feed.stats.preparedOnArrival, 1);
    expect(feed.stats.measuredStarts, 2);
    expect(platform.maxLivePlayers, lessThanOrEqualTo(3));
    // The item that became active plays without a buffer limit.
    final player = manager.poolStats.leased;
    expect(player, 3);
    expect(next.metrics.preparations, 1);
  });

  test(
    'rapid index changes stay within the pool and cancel preloads',
    () async {
      await start();
      final feed = manager.createFeed(_items(200));
      for (var i = 0; i < 200; i++) {
        feed.setActiveIndex(i);
        if (i.isEven) await Future<void>.delayed(Duration.zero);
        expect(manager.poolStats.allocated, lessThanOrEqualTo(3));
      }
      await settle();
      expect(feed.controllerAt(199).value.isPlaying, isTrue);
      expect(platform.maxLivePlayers, lessThanOrEqualTo(3));
      final attached = [
        for (var i = 0; i < 200; i++)
          if (feed.indexOf('$i') >= 0 && i >= 170) feed.controllerAt(i),
      ].where((c) => c.value.isAttached).length;
      expect(attached, lessThanOrEqualTo(3));
    },
  );

  test('releasing an item cancels its preparation in flight', () async {
    await start();
    final feed = manager.createFeed(_items(10));
    platform.hangingSources.add(_source(1));
    feed.setActiveIndex(0);
    await settle();
    final hanging = feed.controllerAt(1);
    expect(hanging.value.status, ReelPlaybackStatus.initializing);

    feed.setActiveIndex(5);
    await settle();

    expect(hanging.value.status, ReelPlaybackStatus.idle);
    expect(hanging.value.isAttached, isFalse);
    expect(feed.stats.preloadsCancelled, greaterThanOrEqualTo(1));
  });

  test('network conditions limit preloading', () async {
    await start(maxPlayers: 4);
    final feed = manager.createFeed(_items(10));
    platform.setNetwork(
      const ReelNetworkStatus(
        isConnected: true,
        isMetered: true,
        type: ReelNetworkType.cellular,
      ),
    );
    feed.setActiveIndex(0);
    await settle();
    expect(
      feed.preloadWindow.value,
      const ReelPreloadWindow(ahead: 1, behind: 0),
    );
    expect(feed.controllerAt(1).value.isInitialized, isTrue);
    expect(feed.controllerAt(2).value.isAttached, isFalse);

    platform.setNetwork(
      const ReelNetworkStatus(isConnected: false, type: ReelNetworkType.none),
    );
    feed.setActiveIndex(1);
    await settle();
    expect(feed.controllerAt(2).value.isAttached, isFalse, reason: 'offline');

    platform.setNetwork(const ReelNetworkStatus(isConnected: true));
    await settle();
    expect(
      feed.preloadWindow.value,
      const ReelPreloadWindow(ahead: 2, behind: 1),
    );
    expect(feed.controllerAt(2).value.isInitialized, isTrue);
  });

  test('an active item that failed offline restarts on reconnection', () async {
    await start();
    final feed = manager.createFeed(_items(3));
    platform.failingOnce[_source(0)] = const ReelKitException(
      ReelKitErrorCode.network,
      'offline',
    );
    feed.setActiveIndex(0);
    await settle();
    expect(feed.controllerAt(0).value.hasError, isTrue);

    platform.setNetwork(const ReelNetworkStatus(isConnected: false));
    await settle();
    platform.setNetwork(const ReelNetworkStatus(isConnected: true));
    await settle();
    expect(feed.controllerAt(0).value.isPlaying, isTrue);
  });

  test('low-memory devices and memory warnings shrink the window', () async {
    await start(lowRam: true, maxPlayers: 4);
    final feed = manager.createFeed(
      _items(10),
      config: const ReelFeedConfig(preloadAhead: 3),
    );
    feed.setActiveIndex(0);
    await settle();
    expect(
      feed.preloadWindow.value,
      const ReelPreloadWindow(ahead: 1, behind: 0),
    );
  });

  testWidgets('memory warnings shrink the window for a while', (tester) async {
    await tester.runAsync(() async {
      await start(maxPlayers: 4);
      final feed = manager.createFeed(
        _items(10),
        config: const ReelFeedConfig(
          preloadAhead: 3,
          memoryPressureCooldown: Duration(milliseconds: 50),
        ),
      );
      feed.setActiveIndex(0);
      await settle();
      expect(feed.preloadWindow.value.ahead, 3);

      tester.binding.handleMemoryPressure();
      await settle();
      expect(
        feed.preloadWindow.value,
        const ReelPreloadWindow(ahead: 1, behind: 0),
      );
      expect(feed.controllerAt(3).value.isAttached, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await settle();
      expect(feed.preloadWindow.value.ahead, 3);
      await manager.dispose();
    });
  });

  test('the window follows a pool shrunk by decoder shortage', () async {
    await start();
    final feed = manager.createFeed(_items(10));
    // The second preload fails while the active item and the first preload
    // hold decoders.
    platform.failingOnce[_source(2)] = const ReelKitException(
      ReelKitErrorCode.decoderUnavailable,
      'no decoder',
    );
    feed.setActiveIndex(0);
    await settle();
    expect(manager.poolStats.maxPlayers, 2);
    expect(manager.poolStats.decoderLimitReductions, 1);

    feed.setActiveIndex(1);
    await settle();
    expect(feed.controllerAt(1).value.isPlaying, isTrue);
    expect(
      feed.preloadWindow.value,
      const ReelPreloadWindow(ahead: 1, behind: 0),
    );
    expect(platform.livePlayers.length, lessThanOrEqualTo(2));
  });

  group('items', () {
    test('insertion before the active item keeps it active', () async {
      await start();
      final feed = manager.createFeed(_items(5));
      feed.setActiveIndex(2);
      await settle();
      final active = feed.activeController;

      feed.insertAll(0, _items(2, from: 100));

      expect(feed.activeIndex.value, 4);
      expect(feed.activeController, same(active));
      expect(feed.length, 7);
    });

    test('removing the active item activates the next one', () async {
      await start();
      final feed = manager.createFeed(_items(5));
      feed.setActiveIndex(1);
      await settle();
      final removedController = feed.controllerAt(1);

      final removed = feed.removeAt(1);
      await settle();

      expect(removed.id, '1');
      expect(removedController.isDisposed, isTrue);
      expect(feed.activeIndex.value, 1);
      expect(feed.activeController!.source, _source(2));
      expect(feed.activeController!.value.isPlaying, isTrue);
    });

    test('replaceAll keeps controllers of retained ids', () async {
      await start();
      final feed = manager.createFeed(_items(5));
      feed.setActiveIndex(2);
      await settle();
      final kept = feed.controllerAt(2);
      final dropped = feed.controllerAt(3);

      feed.replaceAll([
        ReelFeedItem(_source(50), id: 'new'),
        ReelFeedItem(_source(2), id: '2'),
      ]);
      await settle();

      expect(feed.activeIndex.value, 1);
      expect(feed.controllerAt(1), same(kept));
      expect(dropped.isDisposed, isTrue);
      expect(kept.value.isPlaying, isTrue);
    });

    test('updateSource switches a prepared controller', () async {
      await start();
      final feed = manager.createFeed(_items(3));
      feed.setActiveIndex(0);
      await settle();
      feed.updateSource('0', _source(99));
      await settle();
      expect(feed.controllerAt(0).source, _source(99));
      expect(feed.controllerAt(0).value.isPlaying, isTrue);
      expect(feed.items.first.source, _source(99));
    });

    test('rejects duplicate ids', () async {
      await start();
      expect(
        () => manager.createFeed([
          ReelFeedItem(_source(0), id: 'a'),
          ReelFeedItem(_source(1), id: 'a'),
        ]),
        throwsArgumentError,
      );
      final feed = manager.createFeed(_items(2));
      expect(
        () => feed.add(ReelFeedItem(_source(5), id: '0')),
        throwsArgumentError,
      );
    });

    test('notifies listeners when items change', () async {
      await start();
      final feed = manager.createFeed(_items(2));
      var notifications = 0;
      feed.addListener(() => notifications++);
      feed.add(ReelFeedItem(_source(9), id: '9'));
      feed.removeAt(0);
      expect(notifications, 2);
    });
  });

  test('pause stops playback and preloading until resume', () async {
    await start();
    final feed = manager.createFeed(_items(10));
    feed.setActiveIndex(0);
    await settle();
    feed.pause();
    await settle();
    expect(feed.controllerAt(0).value.isPlaying, isFalse);

    feed.setActiveIndex(3);
    await settle();
    expect(feed.controllerAt(3).value.isPlaying, isFalse);
    expect(feed.controllerAt(4).value.isAttached, isFalse);

    feed.resume();
    await settle();
    expect(feed.controllerAt(3).value.isPlaying, isTrue);
    expect(feed.controllerAt(4).value.isInitialized, isTrue);
  });

  test('without autoplay the active item is only prepared', () async {
    await start();
    final feed = manager.createFeed(
      _items(4),
      config: const ReelFeedConfig(autoplay: false),
    );
    feed.setActiveIndex(0);
    await settle();
    expect(feed.controllerAt(0).value.status, ReelPlaybackStatus.ready);
    expect(feed.controllerAt(1).value.status, ReelPlaybackStatus.ready);
  });

  test('controllers far from the active item are disposed', () async {
    await start();
    final feed = manager.createFeed(
      _items(100),
      config: const ReelFeedConfig(controllerRetention: 3),
    );
    feed.setActiveIndex(0);
    await settle();
    final first = feed.controllerAt(0);
    feed.setActiveIndex(50);
    await settle();
    expect(first.isDisposed, isTrue);
    final again = feed.controllerAt(0);
    expect(again.isDisposed, isFalse);
    expect(manager.controllers.length, lessThanOrEqualTo(12));
  });

  test('manager dispose disposes its feeds', () async {
    await start();
    final feed = manager.createFeed(_items(3));
    feed.setActiveIndex(0);
    await settle();
    await manager.dispose();
    expect(feed.isDisposed, isTrue);
    expect(platform.livePlayers, isEmpty);
  });
}
