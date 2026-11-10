// fake_async tests drive futures by elapsing time instead of awaiting them.
// ignore_for_file: discarded_futures

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';
import 'package:reelkit/src/pool/reel_player_pool.dart';

import 'support/fake_reelkit_platform.dart';

class TestClient implements ReelPoolClient {
  TestClient([this.poolPriority = ReelPlayerPriority.visible]);

  @override
  ReelPlayerPriority poolPriority;

  int revocations = 0;

  @override
  void onPoolLeaseRevoked() => revocations++;
}

void main() {
  late FakeReelKitPlatform platform;

  ReelPlayerPool createPool({
    int maxPlayers = 3,
    Duration idleTimeout = const Duration(seconds: 30),
  }) {
    return ReelPlayerPool(
      platform: platform,
      maxPlayers: maxPlayers,
      idleTimeout: idleTimeout,
    );
  }

  setUp(() => platform = FakeReelKitPlatform());

  test('returns the existing lease for the same client', () async {
    final pool = createPool();
    final client = TestClient();
    final first = await pool.acquire(client);
    final second = await pool.acquire(client);
    expect(identical(first, second), isTrue);
    expect(platform.createCalls, 1);
    await pool.dispose();
  });

  test('never exceeds the limit under concurrent acquisition', () async {
    final pool = createPool(maxPlayers: 3);
    final clients = List.generate(
      20,
      (_) => TestClient(ReelPlayerPriority.active),
    );
    final results = await Future.wait(
      clients.map(
        (c) => pool.acquire(c).then<Object>((p) => p, onError: (Object e) => e),
      ),
    );
    final leased = results.whereType<PooledPlayer>().toList();
    final failures = results.whereType<ReelKitException>().toList();
    expect(leased, hasLength(3));
    expect(failures, hasLength(17));
    expect(
      failures.every((e) => e.code == ReelKitErrorCode.poolExhausted),
      isTrue,
    );
    expect(platform.maxLivePlayers, 3);
    expect(pool.stats.allocated, 3);
    await pool.dispose();
  });

  test('reuses a released player under a new generation', () async {
    final pool = createPool();
    final a = TestClient();
    final b = TestClient();
    final first = await pool.acquire(a);
    final firstGeneration = first.generation;
    await pool.release(a);
    final second = await pool.acquire(b);
    expect(second.playerId, first.playerId);
    expect(second.generation, isNot(firstGeneration));
    expect(platform.createCalls, 1);
    expect(pool.stats.reused, 1);
    expect(pool.ownerOf(second.playerId), same(b));
    await pool.dispose();
  });

  test('revokes the lowest-priority, least recently used lease', () async {
    final pool = createPool(maxPlayers: 3);
    final oldPreload = TestClient(ReelPlayerPriority.preload);
    final newPreload = TestClient(ReelPlayerPriority.preload);
    final visible = TestClient(ReelPlayerPriority.visible);
    final victimPlayer = await pool.acquire(oldPreload);
    await pool.acquire(newPreload);
    await pool.acquire(visible);

    final active = TestClient(ReelPlayerPriority.active);
    final player = await pool.acquire(active);

    expect(player.playerId, victimPlayer.playerId);
    expect(oldPreload.revocations, 1);
    expect(newPreload.revocations, 0);
    expect(visible.revocations, 0);
    expect(pool.leaseOf(oldPreload), isNull);
    expect(pool.stats.revoked, 1);
    expect(platform.maxLivePlayers, 3);
    await pool.dispose();
  });

  test('does not revoke leases of equal priority', () async {
    final pool = createPool(maxPlayers: 1);
    await pool.acquire(TestClient(ReelPlayerPriority.visible));
    await expectLater(
      pool.acquire(TestClient(ReelPlayerPriority.visible)),
      throwsA(
        isA<ReelKitException>().having(
          (e) => e.code,
          'code',
          ReelKitErrorCode.poolExhausted,
        ),
      ),
    );
    await pool.dispose();
  });

  test('destroys idle players after the idle timeout', () {
    fakeAsync((async) {
      final pool = createPool(idleTimeout: const Duration(seconds: 5));
      final client = TestClient();
      pool.acquire(client);
      async.flushMicrotasks();
      pool.release(client);
      async.flushMicrotasks();
      expect(platform.livePlayers, hasLength(1));

      async.elapse(const Duration(seconds: 4));
      expect(platform.livePlayers, hasLength(1));
      async.elapse(const Duration(seconds: 2));
      expect(platform.livePlayers, isEmpty);
      expect(pool.stats.disposed, 1);
      pool.dispose();
      async.flushMicrotasks();
    });
  });

  test('reacquiring an idle player cancels its idle timer', () {
    fakeAsync((async) {
      final pool = createPool(idleTimeout: const Duration(seconds: 5));
      final a = TestClient();
      final b = TestClient();
      pool.acquire(a);
      async.flushMicrotasks();
      pool.release(a);
      async.flushMicrotasks();
      pool.acquire(b);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(platform.livePlayers, hasLength(1));
      expect(pool.leaseOf(b), isNotNull);
      pool.dispose();
      async.flushMicrotasks();
    });
  });

  test('release detaches the source of the idle player', () async {
    final pool = createPool();
    final client = TestClient();
    final player = await pool.acquire(client);
    await pool.release(client);
    expect(platform.calls, contains('clearSource(${player.playerId})'));
    expect(platform.livePlayers, hasLength(1));
    await pool.dispose();
  });

  test('a player that cannot be cleared is destroyed', () async {
    final pool = createPool();
    final client = TestClient();
    await pool.acquire(client);
    platform.throwOn['clearSource'] = const ReelKitException(
      ReelKitErrorCode.playerNotFound,
      'gone',
    );
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    await pool.release(client);
    FlutterError.onError = previous;
    expect(errors, hasLength(1));
    expect(platform.livePlayers, isEmpty);
    await pool.dispose();
  });

  test('zero idle timeout destroys players on release', () async {
    final pool = createPool(idleTimeout: Duration.zero);
    final client = TestClient();
    await pool.acquire(client);
    await pool.release(client);
    expect(platform.livePlayers, isEmpty);
    await pool.dispose();
  });

  test('trimIdle destroys only idle players', () async {
    final pool = createPool();
    final a = TestClient();
    final b = TestClient();
    await pool.acquire(a);
    await pool.acquire(b);
    await pool.release(a);
    await pool.trimIdle();
    expect(platform.livePlayers, hasLength(1));
    expect(pool.leaseOf(b), isNotNull);
    await pool.dispose();
  });

  test('resize lowers the limit without breaking active leases', () async {
    final pool = createPool(maxPlayers: 3);
    final clients = List.generate(3, (_) => TestClient());
    for (final c in clients) {
      await pool.acquire(c);
    }
    await pool.release(clients[0]);
    await pool.resize(1);
    // The idle player is destroyed at once, leased ones stay.
    expect(platform.livePlayers, hasLength(2));
    // A leased player above the limit is destroyed when released.
    await pool.release(clients[1]);
    expect(platform.livePlayers, hasLength(1));
    await pool.dispose();
  });

  test('dispose revokes leases and destroys every player', () async {
    final pool = createPool();
    final a = TestClient();
    final b = TestClient();
    await pool.acquire(a);
    await pool.acquire(b);
    await pool.dispose();
    expect(a.revocations, 1);
    expect(b.revocations, 1);
    expect(platform.livePlayers, isEmpty);
    await expectLater(
      pool.acquire(TestClient()),
      throwsA(
        isA<ReelKitException>().having(
          (e) => e.code,
          'code',
          ReelKitErrorCode.disposed,
        ),
      ),
    );
  });

  test('a failed native allocation does not consume a slot', () async {
    final pool = createPool(maxPlayers: 1);
    platform.throwOn['createPlayer'] = const ReelKitException(
      ReelKitErrorCode.playerCreationFailed,
      'boom',
    );
    await expectLater(
      pool.acquire(TestClient()),
      throwsA(isA<ReelKitException>()),
    );
    platform.throwOn.clear();
    await pool.acquire(TestClient());
    expect(pool.stats.allocated, 1);
    await pool.dispose();
  });

  test('churn through 500 sources keeps the pool bounded', () async {
    final pool = createPool(maxPlayers: 3);
    final window = <TestClient>[];
    for (var i = 0; i < 500; i++) {
      final client = TestClient(ReelPlayerPriority.active);
      await pool.acquire(client);
      window.add(client);
      for (final c in window) {
        if (!identical(c, client)) c.poolPriority = ReelPlayerPriority.preload;
      }
      if (window.length > 2) await pool.release(window.removeAt(0));
      expect(pool.stats.allocated, lessThanOrEqualTo(3));
    }
    expect(platform.maxLivePlayers, lessThanOrEqualTo(3));
    expect(platform.createCalls, lessThanOrEqualTo(3));
    await pool.dispose();
    expect(platform.livePlayers, isEmpty);
  });

  group('decoder failures', () {
    test(
      'lower the limit to the other leases and destroy idle players',
      () async {
        final pool = createPool(maxPlayers: 4);
        final a = TestClient(ReelPlayerPriority.visible);
        final b = TestClient(ReelPlayerPriority.preload);
        final idle = TestClient();
        final failing = TestClient(ReelPlayerPriority.active);
        await pool.acquire(a);
        await pool.acquire(b);
        await pool.acquire(idle);
        await pool.release(idle);
        await pool.acquire(failing);
        final idleCount = pool.stats.idle;

        expect(await pool.reportDecoderUnavailable(failing), isTrue);

        expect(pool.maxPlayers, 2);
        expect(pool.stats.decoderLimitReductions, 1);
        expect(idleCount, 0, reason: 'the idle player was reused');
        await pool.release(failing);
        expect(pool.stats.allocated, 2, reason: 'over the limit, destroyed');
        final retry = await pool.acquire(failing);
        expect(b.revocations, 1);
        expect(pool.ownerOf(retry.playerId), same(failing));
        await pool.dispose();
      },
    );

    test('are not attributed to the pool without other leases', () async {
      final pool = createPool();
      final client = TestClient(ReelPlayerPriority.active);
      await pool.acquire(client);
      expect(await pool.reportDecoderUnavailable(client), isFalse);
      expect(pool.maxPlayers, 3);
      await pool.dispose();
    });

    test('are ignored when adaptation is disabled', () async {
      final pool = ReelPlayerPool(
        platform: platform,
        maxPlayers: 3,
        idleTimeout: const Duration(seconds: 30),
        adaptToDecoderFailures: false,
      );
      final other = TestClient();
      final client = TestClient(ReelPlayerPriority.active);
      await pool.acquire(other);
      await pool.acquire(client);
      expect(await pool.reportDecoderUnavailable(client), isFalse);
      expect(pool.maxPlayers, 3);
      await pool.dispose();
    });

    test('concurrent failures lower the limit once', () async {
      final pool = createPool(maxPlayers: 3);
      final holder = TestClient(ReelPlayerPriority.visible);
      final first = TestClient(ReelPlayerPriority.active);
      final second = TestClient(ReelPlayerPriority.active);
      await pool.acquire(holder);
      await pool.acquire(first);
      await pool.acquire(second);

      expect(await pool.reportDecoderUnavailable(first), isTrue);
      expect(pool.maxPlayers, 2);
      expect(await pool.reportDecoderUnavailable(second), isTrue);
      expect(pool.maxPlayers, 2, reason: 'same shortage, reported twice');
      expect(pool.stats.decoderLimitReductions, 1);
      await pool.dispose();
    });
  });

  test('stats count leases per priority', () async {
    final pool = createPool();
    await pool.acquire(TestClient(ReelPlayerPriority.active));
    await pool.acquire(TestClient(ReelPlayerPriority.preload));
    await pool.acquire(TestClient(ReelPlayerPriority.preload));
    expect(pool.stats.leasedByPriority, {
      ReelPlayerPriority.active: 1,
      ReelPlayerPriority.preload: 2,
    });
    await pool.dispose();
  });
}
