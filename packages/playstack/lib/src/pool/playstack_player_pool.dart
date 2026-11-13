import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../util/async_lock.dart';

/// How important a controller's claim on a native player is.
///
/// When the pool is full, a controller can take the player of a controller
/// with strictly lower priority. Values are ordered from lowest to highest.
enum PlayStackPlayerPriority {
  /// Kept only while nothing else needs the player, for example a video
  /// behind the current feed position.
  background,

  /// Being prepared ahead of time, for example the next video in a feed.
  preload,

  /// On screen but not playing.
  visible,

  /// Currently playing.
  active,
}

/// A party that can hold a lease on a pooled native player.
@internal
abstract interface class PlayStackPoolClient {
  /// Current claim strength, read whenever the pool must choose a victim.
  PlayStackPlayerPriority get poolPriority;

  /// Called synchronously when the pool takes the player away from this
  /// client, either for a higher-priority client or because the pool is
  /// disposed. The client must stop using the player immediately.
  void onPoolLeaseRevoked();
}

/// Settings last sent to a native player, used to skip redundant channel
/// calls when a player is handed to a controller with identical settings.
@internal
class AppliedPlayerSettings {
  AppliedPlayerSettings.from(PlayStackNativePlayerOptions options)
    : looping = options.looping,
      volume = options.volume,
      playbackSpeed = options.playbackSpeed;

  bool looping;
  double volume;
  double playbackSpeed;

  /// Native players start without a preload buffer limit.
  Duration? preloadBufferLimit;

  /// Native players start without a quality limit; it applies to every
  /// source set afterwards.
  PlayStackVideoQualityLimit qualityLimit = PlayStackVideoQualityLimit.none;
}

/// A native player owned by a [PlayStackPlayerPool].
@internal
class PooledPlayer {
  PooledPlayer._(this.handle, PlayStackNativePlayerOptions options)
    : applied = AppliedPlayerSettings.from(options);

  final PlayStackNativePlayerHandle handle;
  final AppliedPlayerSettings applied;

  int get playerId => handle.playerId;

  /// Identifies the current lease. Every change of owner produces a new
  /// generation so late events from a previous source can be discarded.
  int get generation => _generation;
  int _generation = 0;

  PlayStackPoolClient? _owner;
  int _lastUsed = 0;

  /// The pool's limit epoch when the current lease or attempt started.
  int _limitEpoch = 0;
  Timer? _idleTimer;

  bool get isLeased => _owner != null;
}

/// Snapshot of pool usage, intended for diagnostics and benchmarks.
@immutable
class PlayStackPoolStats {
  /// Creates a statistics snapshot.
  const PlayStackPoolStats({
    required this.maxPlayers,
    required this.allocated,
    required this.leased,
    required this.created,
    required this.disposed,
    required this.reused,
    required this.revoked,
    this.leasedByPriority = const <PlayStackPlayerPriority, int>{},
    this.decoderLimitReductions = 0,
  });

  /// Current upper bound of native players.
  final int maxPlayers;

  /// Native players currently alive.
  final int allocated;

  /// Native players currently assigned to a controller.
  final int leased;

  /// Native players alive but unassigned, kept for reuse.
  int get idle => allocated - leased;

  /// Native players created since the pool started.
  final int created;

  /// Native players destroyed since the pool started.
  final int disposed;

  /// Leases served by reusing an idle native player instead of creating one.
  final int reused;

  /// Leases taken from a lower-priority controller.
  final int revoked;

  /// Leased players per priority of their controller. Priorities without a
  /// leased player are absent.
  final Map<PlayStackPlayerPriority, int> leasedByPriority;

  /// How often [maxPlayers] was lowered because a decoder could not be
  /// allocated (see `PlayStackPoolConfig.adaptToDecoderFailures`).
  final int decoderLimitReductions;

  @override
  bool operator ==(Object other) =>
      other is PlayStackPoolStats &&
      other.maxPlayers == maxPlayers &&
      other.allocated == allocated &&
      other.leased == leased &&
      other.created == created &&
      other.disposed == disposed &&
      other.reused == reused &&
      other.revoked == revoked &&
      mapEquals(other.leasedByPriority, leasedByPriority) &&
      other.decoderLimitReductions == decoderLimitReductions;

  @override
  int get hashCode => Object.hash(
    maxPlayers,
    allocated,
    leased,
    created,
    disposed,
    reused,
    revoked,
    Object.hashAllUnordered(
      leasedByPriority.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    decoderLimitReductions,
  );

  @override
  String toString() =>
      'PlayStackPoolStats(max: $maxPlayers, allocated: $allocated, '
      'leased: $leased, idle: $idle, created: $created, '
      'disposed: $disposed, reused: $reused, revoked: $revoked, '
      'decoderLimitReductions: $decoderLimitReductions)';
}

/// Allocates, reuses and destroys native players under a hard upper bound.
///
/// Invariants:
/// * The number of live native players never exceeds [maxPlayers]. All
///   mutations are serialized, so concurrent acquisitions cannot race past
///   the limit.
/// * A native player has at most one owner.
/// * Every change of owner increments the player's generation.
@internal
class PlayStackPlayerPool {
  PlayStackPlayerPool({
    required this._platform,
    required int maxPlayers,
    required this._idleTimeout,
    this._playerOptions = const PlayStackNativePlayerOptions(),
    this._adaptToDecoderFailures = true,
  }) : assert(maxPlayers > 0),
       _maxPlayers = maxPlayers;

  final PlayStackPlatform _platform;
  final Duration _idleTimeout;
  final PlayStackNativePlayerOptions _playerOptions;
  final bool _adaptToDecoderFailures;
  final AsyncLock _lock = AsyncLock();
  final List<PooledPlayer> _players = <PooledPlayer>[];

  int _maxPlayers;
  int _clock = 0;
  int _nextGeneration = 1;
  bool _disposed = false;

  int _created = 0;
  int _destroyed = 0;
  int _reused = 0;
  int _revoked = 0;
  int _limitEpoch = 0;
  int _decoderLimitReductions = 0;

  int get maxPlayers => _maxPlayers;

  bool get isDisposed => _disposed;

  PlayStackPoolStats get stats => PlayStackPoolStats(
    maxPlayers: _maxPlayers,
    allocated: _players.length,
    leased: _players.where((p) => p.isLeased).length,
    created: _created,
    disposed: _destroyed,
    reused: _reused,
    revoked: _revoked,
    leasedByPriority: Map<PlayStackPlayerPriority, int>.unmodifiable(
      _leasedByPriority(),
    ),
    decoderLimitReductions: _decoderLimitReductions,
  );

  Map<PlayStackPlayerPriority, int> _leasedByPriority() {
    final counts = <PlayStackPlayerPriority, int>{};
    for (final player in _players) {
      final owner = player._owner;
      if (owner == null) continue;
      counts.update(owner.poolPriority, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  /// The player currently leased by [client], if any.
  PooledPlayer? leaseOf(PlayStackPoolClient client) {
    for (final player in _players) {
      if (identical(player._owner, client)) return player;
    }
    return null;
  }

  /// The client currently holding [playerId], if any.
  PlayStackPoolClient? ownerOf(int playerId) {
    for (final player in _players) {
      if (player.playerId == playerId) return player._owner;
    }
    return null;
  }

  /// Leases a native player to [client].
  ///
  /// Returns the client's existing lease when it has one. Otherwise reuses an
  /// idle player, creates a new one while below [maxPlayers], or revokes the
  /// lease of the lowest-priority, least recently used client whose priority
  /// is strictly lower than [client]'s. Throws [PlayStackException] with
  /// [PlayStackErrorCode.poolExhausted] when none of these is possible.
  Future<PooledPlayer> acquire(PlayStackPoolClient client) {
    return _lock.synchronized(() async {
      _throwIfDisposed();
      final existing = leaseOf(client);
      if (existing != null) {
        existing._lastUsed = ++_clock;
        return existing;
      }

      var player = _takeIdle();
      if (player != null) {
        _reused++;
      } else if (_players.length < _maxPlayers) {
        player = await _create();
      } else {
        player = _revokeFor(client);
        if (player == null) {
          throw PlayStackException(
            PlayStackErrorCode.poolExhausted,
            'All $_maxPlayers native players are held by controllers with '
            'priority ${client.poolPriority.name} or higher. Lower the '
            'priority of, release or dispose another controller, or raise '
            'PlayStackPoolConfig.maxPlayers.',
          );
        }
        _revoked++;
      }
      _assign(player, client);
      return player;
    });
  }

  /// Gives [client]'s current lease a new generation without changing the
  /// native player, so events of the previous source are discarded. Returns
  /// null when the client holds no lease.
  Future<PooledPlayer?> renew(PlayStackPoolClient client) {
    return _lock.synchronized(() async {
      final player = leaseOf(client);
      if (player == null) return null;
      player
        .._generation = _nextGeneration++
        .._lastUsed = ++_clock
        .._limitEpoch = _limitEpoch;
      return player;
    });
  }

  /// Reacts to [client] failing to allocate a decoder
  /// ([PlayStackErrorCode.decoderUnavailable]) and returns whether retrying on
  /// a different player is worthwhile.
  ///
  /// The failure is attributed to this pool only when other clients hold
  /// leased (prepared or preparing) players. The limit then drops to the
  /// number of those players, so the retry has to take a player from a
  /// lower-priority client instead of adding one. Failures of attempts that
  /// started before an earlier reduction do not lower the limit again,
  /// because concurrent failures report the same shortage.
  Future<bool> reportDecoderUnavailable(PlayStackPoolClient client) {
    return _lock.synchronized(() async {
      if (_disposed || !_adaptToDecoderFailures) return false;
      var others = 0;
      for (final player in _players) {
        final owner = player._owner;
        if (owner != null && !identical(owner, client)) others++;
      }
      if (others == 0) return false;
      final lease = leaseOf(client);
      final stale = lease != null && lease._limitEpoch < _limitEpoch;
      if (!stale && others < _maxPlayers) {
        _maxPlayers = others;
        _limitEpoch++;
        _decoderLimitReductions++;
        await _destroyIdleAboveLimit();
      }
      return true;
    });
  }

  /// Returns [client]'s player to the pool. Its source is detached so it
  /// stops using decoder and network resources; the native player itself
  /// stays alive for reuse until the idle timeout, unless the pool is above
  /// its limit.
  Future<void> release(PlayStackPoolClient client) {
    return _lock.synchronized(() async {
      final player = leaseOf(client);
      if (player == null) return;
      player
        .._owner = null
        .._generation = _nextGeneration++
        .._lastUsed = ++_clock;
      if (_disposed) return;
      if (_players.length > _maxPlayers || _idleTimeout == Duration.zero) {
        await _destroy(player);
      } else if (await _clear(player)) {
        _scheduleIdleDisposal(player);
      } else {
        await _destroy(player);
      }
    });
  }

  /// Changes the player limit. Idle players above the new limit are
  /// destroyed immediately; leased players above it are destroyed when
  /// released.
  Future<void> resize(int maxPlayers) {
    assert(maxPlayers > 0);
    return _lock.synchronized(() async {
      _maxPlayers = maxPlayers;
      await _destroyIdleAboveLimit();
    });
  }

  Future<void> _destroyIdleAboveLimit() async {
    final excess = _players.length - _maxPlayers;
    if (excess <= 0) return;
    final idle = _players.where((p) => !p.isLeased).take(excess).toList();
    for (final player in idle) {
      await _destroy(player);
    }
  }

  /// Destroys every idle native player, for example under memory pressure.
  Future<void> trimIdle() {
    return _lock.synchronized(() async {
      final idle = _players.where((p) => !p.isLeased).toList();
      for (final player in idle) {
        await _destroy(player);
      }
    });
  }

  /// Revokes all leases and destroys every native player.
  Future<void> dispose() {
    if (_disposed) return Future<void>.value();
    _disposed = true;
    return _lock.synchronized(() async {
      final players = List<PooledPlayer>.of(_players);
      for (final player in players) {
        final owner = player._owner;
        player._owner = null;
        _notifyRevoked(owner);
      }
      await Future.wait(players.map(_destroy));
    });
  }

  Future<PooledPlayer> _create() async {
    final handle = await _platform.createPlayer(_playerOptions);
    _created++;
    final player = PooledPlayer._(handle, _playerOptions);
    _players.add(player);
    return player;
  }

  PooledPlayer? _takeIdle() {
    PooledPlayer? best;
    for (final player in _players) {
      if (player.isLeased) continue;
      if (best == null || player._lastUsed > best._lastUsed) best = player;
    }
    best?._idleTimer?.cancel();
    best?._idleTimer = null;
    return best;
  }

  PooledPlayer? _revokeFor(PlayStackPoolClient client) {
    final priority = client.poolPriority.index;
    PooledPlayer? victim;
    for (final player in _players) {
      final owner = player._owner;
      if (owner == null || owner.poolPriority.index >= priority) continue;
      if (victim == null) {
        victim = player;
        continue;
      }
      final victimPriority = victim._owner!.poolPriority.index;
      final ownerPriority = owner.poolPriority.index;
      if (ownerPriority < victimPriority ||
          (ownerPriority == victimPriority &&
              player._lastUsed < victim._lastUsed)) {
        victim = player;
      }
    }
    if (victim == null) return null;
    final previousOwner = victim._owner;
    victim._owner = null;
    _notifyRevoked(previousOwner);
    return victim;
  }

  void _assign(PooledPlayer player, PlayStackPoolClient client) {
    player
      .._owner = client
      .._generation = _nextGeneration++
      .._lastUsed = ++_clock
      .._limitEpoch = _limitEpoch;
  }

  void _scheduleIdleDisposal(PooledPlayer player) {
    player._idleTimer?.cancel();
    player._idleTimer = Timer(_idleTimeout, () {
      unawaited(
        _lock.synchronized(() async {
          if (player.isLeased || !_players.contains(player)) return;
          await _destroy(player);
        }),
      );
    });
  }

  /// Detaches the source of an idle player so it stops consuming decoder,
  /// network and memory. Returns false when the player is unusable.
  Future<bool> _clear(PooledPlayer player) async {
    try {
      await _platform.clearSource(player.playerId);
      return true;
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription(
            'while clearing native player ${player.playerId}',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _destroy(PooledPlayer player) async {
    player._idleTimer?.cancel();
    player._idleTimer = null;
    if (!_players.remove(player)) return;
    _destroyed++;
    try {
      await _platform.disposePlayer(player.playerId);
    } on Object catch (error, stack) {
      // The native side may already be gone (engine detached). The player is
      // unusable either way, so the failure is reported, not rethrown.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription(
            'while disposing native player ${player.playerId}',
          ),
        ),
      );
    }
  }

  void _notifyRevoked(PlayStackPoolClient? owner) {
    if (owner == null) return;
    try {
      owner.onPoolLeaseRevoked();
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription('while revoking a player lease'),
        ),
      );
    }
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw const PlayStackException(
        PlayStackErrorCode.disposed,
        'The player pool was disposed.',
      );
    }
  }
}
