import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit_example/samples.dart';

/// Milestone 5 against the real engine: feed playback, preloading, rapid
/// index changes and structural changes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ReelKitManager manager;

  setUp(() async {
    manager = ReelKitManager(
      config: const ReelKitConfig(
        pool: ReelPoolConfig(maxPlayers: 3),
        player: ReelPlayerConfig(looping: true, muted: true),
      ),
    );
    await manager.initialize();
  });

  tearDown(() => manager.dispose());

  List<ReelFeedItem> items(int count) => [
    for (var i = 0; i < count; i++)
      ReelFeedItem(
        ReelSource.asset(i.isEven ? landscapeAsset : rotatedAsset),
        id: 'item-$i',
      ),
  ];

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

  testWidgets('plays the active item and prepares the next one', (
    tester,
  ) async {
    final feed = manager.createFeed(items(10));
    feed.setActiveIndex(0);
    final next = feed.controllerAt(1);
    await waitUntil(
      () => feed.controllerAt(0).value.isPlaying,
      reason: 'active plays',
    );
    await waitUntil(
      () => next.value.isInitialized && next.value.hasRenderedFirstFrame,
      reason: 'next item prepared with its first frame; ${next.value}',
    );
    expect(next.value.isPlaying, isFalse);

    feed.setActiveIndex(1);
    await waitUntil(() => next.value.isPlaying, reason: 'next plays');
    expect(feed.stats.preparedOnArrival, 1);
    // A prepared item starts much faster than a cold one; the bound is
    // generous for slow CI emulators.
    expect(next.metrics.lastStartLatency, lessThan(const Duration(seconds: 1)));
    expect(feed.controllerAt(0).value.isPlaying, isFalse);
  });

  testWidgets('rapid index changes stay within the pool', (tester) async {
    final feed = manager.createFeed(items(100));
    for (var i = 0; i < 100; i++) {
      feed.setActiveIndex(i);
      if (i % 3 == 0) await Future<void>.delayed(Duration.zero);
      expect(manager.poolStats.allocated, lessThanOrEqualTo(3));
    }
    final last = feed.controllerAt(99);
    await waitUntil(() => last.value.isPlaying, reason: 'last item plays');
    expect(manager.poolStats.created, lessThanOrEqualTo(3));
    expect(manager.poolStats.leased, lessThanOrEqualTo(3));
  });

  testWidgets('removing the active item plays the next one', (tester) async {
    final feed = manager.createFeed(items(5));
    feed.setActiveIndex(2);
    await waitUntil(
      () => feed.controllerAt(2).value.isPlaying,
      reason: 'active plays',
    );
    feed.removeAt(2);
    await waitUntil(
      () => feed.activeController!.value.isPlaying,
      reason: 'replacement plays',
    );
    expect(feed.activeController!.source, items(5)[3].source);
  });

  testWidgets('reports network status', (tester) async {
    if (!manager.capabilities.supportsNetworkStatus) return;
    // Emulators and simulators are online through the host.
    await waitUntil(
      () => manager.networkStatus.value.isConnected,
      reason: 'connected; ${manager.networkStatus.value}',
    );
  });
}
