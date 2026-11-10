import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../config/reel_kit_config.dart';
import '../pool/reel_player_pool.dart';
import '../util/async_lock.dart';
import 'reel_playback_state.dart';

/// Services a controller needs from its manager.
@internal
abstract interface class ReelControllerHost {
  ReelKitPlatform get platform;
  ReelPlayerPool get pool;
  void controllerDisposed(ReelPlayerController controller);
}

/// Controls playback of one video.
///
/// A controller is a lightweight handle: it does not own a native player by
/// itself. It leases one from the manager's pool when it is initialized or
/// played and gives it back when it is disposed. If a controller with a
/// higher [priority] needs a player while the pool is full, this controller
/// can lose its player; its state then returns to [ReelPlaybackStatus.idle]
/// and the next [initialize] or [play] prepares the video again.
///
/// Commands are executed one at a time, in call order. Commands that were
/// still queued when [dispose] was called complete without effect; commands
/// issued after [dispose] throw a [ReelKitException] with
/// [ReelKitErrorCode.disposed].
///
/// Create controllers with `ReelKitManager.createController`.
class ReelPlayerController extends ChangeNotifier
    implements ValueListenable<ReelPlaybackState>, ReelPoolClient {
  /// Use `ReelKitManager.createController` instead.
  @internal
  ReelPlayerController.internal({
    required this._host,
    required this._source,
    required ReelPlayerConfig config,
  }) : _initializeTimeout = config.initializeTimeout,
       _value = ReelPlaybackState(
         isLooping: config.looping,
         volume: config.volume,
         isMuted: config.muted,
         playbackSpeed: config.playbackSpeed,
       );

  final ReelControllerHost _host;
  final Duration _initializeTimeout;
  final AsyncLock _commands = AsyncLock();

  final ReelSource _source;
  ReelPlaybackState _value;
  ReelPlayerPriority _priority = ReelPlayerPriority.visible;
  PooledPlayer? _lease;
  Completer<ReelVideoInfo>? _preparation;
  Future<void>? _pendingInitialize;
  bool _disposed = false;

  /// The video this controller plays.
  ReelSource get source => _source;

  @override
  ReelPlaybackState get value => _value;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// Claim strength on a native player. Raised to
  /// [ReelPlayerPriority.active] by [play] and lowered to
  /// [ReelPlayerPriority.visible] by [pause].
  ReelPlayerPriority get priority => _priority;

  set priority(ReelPlayerPriority value) {
    _throwIfDisposed();
    _priority = value;
  }

  @override
  @internal
  ReelPlayerPriority get poolPriority => _priority;

  /// Prepares the video so that [play] can start without delay.
  ///
  /// Concurrent calls share one preparation. Completes immediately when the
  /// video is already prepared. Throws a [ReelKitException] when preparation
  /// fails; the error is also reflected in [value].
  Future<void> initialize() {
    if (_disposed) return Future<void>.error(_disposedError());
    if (_value.isInitialized && _lease != null) return Future<void>.value();
    return _pendingInitialize ??= _commands
        .synchronized(_prepareIfNeeded)
        .whenComplete(() => _pendingInitialize = null);
  }

  /// Starts or resumes playback, preparing the video first if needed.
  ///
  /// Restarts from the beginning when the video had completed.
  Future<void> play() => _command(() async {
    _priority = ReelPlayerPriority.active;
    await _prepareIfNeeded();
    final lease = _lease;
    if (_disposed || lease == null) return;
    if (_value.status == ReelPlaybackStatus.completed) {
      await _host.platform.seekTo(lease.playerId, Duration.zero);
    }
    await _host.platform.play(lease.playerId);
  });

  /// Pauses playback. Keeps the native player and its buffers.
  Future<void> pause() => _command(() async {
    if (_priority == ReelPlayerPriority.active) {
      _priority = ReelPlayerPriority.visible;
    }
    final lease = _lease;
    if (lease == null || !_value.isInitialized) return;
    await _host.platform.pause(lease.playerId);
  });

  /// Seeks to [position], clamped to the video duration when it is known.
  ///
  /// Throws [ReelKitErrorCode.notInitialized] before the video is prepared.
  Future<void> seekTo(Duration position) => _command(() async {
    final lease = _requirePrepared('seekTo');
    await _host.platform.seekTo(lease.playerId, _clampToDuration(position));
  });

  /// Seeks [offset] relative to the current position. Negative offsets seek
  /// backwards.
  Future<void> seekBy(Duration offset) => _command(() async {
    final lease = _requirePrepared('seekBy');
    final current = await _host.platform.getPosition(lease.playerId);
    await _host.platform.seekTo(
      lease.playerId,
      _clampToDuration(current.position + offset),
    );
  });

  /// Seeks forward by [step].
  Future<void> fastForward([Duration step = const Duration(seconds: 10)]) =>
      seekBy(step);

  /// Seeks backward by [step].
  Future<void> rewind([Duration step = const Duration(seconds: 10)]) =>
      seekBy(-step);

  /// Enables or disables looping.
  Future<void> setLooping(bool looping) => _command(() async {
    _update(_value.copyWith(isLooping: looping));
    await _applySettings();
  });

  /// Sets the volume from 0.0 to 1.0. Does not change [ReelPlaybackState.isMuted].
  Future<void> setVolume(double volume) => _command(() async {
    if (volume.isNaN || volume < 0 || volume > 1) {
      throw ReelKitException(
        ReelKitErrorCode.invalidArgument,
        'Volume must be between 0.0 and 1.0, got $volume.',
      );
    }
    _update(_value.copyWith(volume: volume));
    await _applySettings();
  });

  /// Mutes or unmutes without losing the configured volume.
  Future<void> setMuted(bool muted) => _command(() async {
    _update(_value.copyWith(isMuted: muted));
    await _applySettings();
  });

  /// Sets the playback speed. Must be finite and greater than zero; engines
  /// may support a narrower range and report an error otherwise.
  Future<void> setPlaybackSpeed(double speed) => _command(() async {
    if (!speed.isFinite || speed <= 0) {
      throw ReelKitException(
        ReelKitErrorCode.invalidArgument,
        'Playback speed must be finite and greater than 0, got $speed.',
      );
    }
    _update(_value.copyWith(playbackSpeed: speed));
    await _applySettings();
  });

  /// Reads the current playback and buffer position from the engine.
  ///
  /// Returns zero positions while the controller holds no native player.
  Future<ReelPositionSnapshot> getPosition() async {
    _throwIfDisposed();
    final lease = _lease;
    if (lease == null || !_value.isInitialized) {
      return const ReelPositionSnapshot(
        position: Duration.zero,
        buffered: Duration.zero,
      );
    }
    return _host.platform.getPosition(lease.playerId);
  }

  /// Time left until the end, or null when the duration is unknown.
  Future<Duration?> getRemaining() async {
    final duration = _value.duration;
    if (duration == null) return null;
    final snapshot = await getPosition();
    final remaining = duration - snapshot.position;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Releases the native player back to the pool and disposes the
  /// controller. Safe to call more than once.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failPreparation(
      const ReelKitException(
        ReelKitErrorCode.cancelled,
        'The controller was disposed while preparing.',
      ),
    );
    _update(
      _value.copyWith(
        status: ReelPlaybackStatus.disposed,
        isAttached: false,
        isBuffering: false,
      ),
    );
    await _commands.synchronized(() async {
      if (_lease != null) {
        _lease = null;
        await _host.pool.release(this);
      }
    });
    _host.controllerDisposed(this);
    _disposedNotifier = true;
    super.dispose();
  }

  /// Builds the engine's render widget, or null while no native player is
  /// attached. Used by `ReelVideoView`.
  @internal
  Widget? buildNativeView() {
    final lease = _lease;
    if (lease == null || _disposed) return null;
    return _host.platform.buildView(lease.playerId);
  }

  /// Routes an engine event to this controller. Events that belong to an
  /// earlier lease or source generation are ignored.
  @internal
  void handlePlatformEvent(ReelPlatformEvent event) {
    final lease = _lease;
    if (_disposed ||
        lease == null ||
        event.playerId != lease.playerId ||
        event.generation != lease.generation) {
      return;
    }
    switch (event) {
      case ReelInitializedEvent(:final info):
        final preparation = _preparation;
        if (preparation != null && !preparation.isCompleted) {
          preparation.complete(info);
        } else {
          _update(_value.copyWith(videoInfo: info));
        }
      case ReelNativeStateEvent(:final state):
        _onNativeState(state);
      case ReelIsPlayingEvent(:final isPlaying):
        _onIsPlaying(isPlaying);
      case ReelVideoSizeEvent():
        final current =
            _value.videoInfo ?? const ReelVideoInfo(width: 0, height: 0);
        _update(
          _value.copyWith(
            videoInfo: current.copyWith(
              width: event.width,
              height: event.height,
              rotationDegrees: event.rotationDegrees,
              pixelAspectRatio: event.pixelAspectRatio,
            ),
          ),
        );
      case ReelFirstFrameEvent():
        _update(_value.copyWith(hasRenderedFirstFrame: true));
      case ReelErrorEvent(:final error):
        final preparation = _preparation;
        if (preparation != null && !preparation.isCompleted) {
          preparation.completeError(error);
        } else {
          _update(
            _value.copyWith(
              status: ReelPlaybackStatus.error,
              error: error,
              isBuffering: false,
            ),
          );
        }
    }
  }

  @override
  @internal
  void onPoolLeaseRevoked() {
    if (_lease == null) return;
    _lease = null;
    _failPreparation(
      const ReelKitException(
        ReelKitErrorCode.cancelled,
        'The native player was reassigned to a higher-priority controller.',
      ),
    );
    if (_disposed) return;
    _update(
      _value.copyWith(
        status: ReelPlaybackStatus.idle,
        isAttached: false,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _command(Future<void> Function() action) {
    if (_disposed) return Future<void>.error(_disposedError());
    return _commands.synchronized(() async {
      if (_disposed) return;
      await action();
    });
  }

  /// Leases a native player, applies settings, sets the source and waits for
  /// the engine to report the prepared video. Runs inside [_commands].
  Future<void> _prepareIfNeeded() async {
    if (_disposed) return;
    if (_value.isInitialized && _lease != null) return;

    _update(
      _value.copyWith(
        status: ReelPlaybackStatus.initializing,
        clearError: true,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
    final preparation = Completer<ReelVideoInfo>();
    // The completer can fail (revocation, dispose) before it is awaited.
    preparation.future.ignore();
    _preparation = preparation;
    try {
      if (_lease != null) {
        // A previous preparation failed on this lease. Return the player so
        // the retry runs under a fresh generation and late events of the
        // failed attempt are discarded.
        _lease = null;
        await _host.pool.release(this);
        if (_disposed) return;
      }
      final lease = await _host.pool.acquire(this);
      if (_disposed) return;
      _lease = lease;
      _update(_value.copyWith(isAttached: true));
      await _applySettings();
      await _host.platform.setSource(lease.playerId, _source, lease.generation);
      final info = await preparation.future.timeout(
        _initializeTimeout,
        onTimeout: () => throw ReelKitException(
          ReelKitErrorCode.timeout,
          'Preparing ${_source.description} did not complete within '
          '$_initializeTimeout.',
        ),
      );
      if (_disposed || !identical(_lease, lease)) return;
      _update(
        _value.copyWith(status: ReelPlaybackStatus.ready, videoInfo: info),
      );
    } on ReelKitException catch (error) {
      if (_disposed) return;
      if (error.code == ReelKitErrorCode.cancelled && _lease == null) {
        // Lost the player to a higher-priority controller; the state is
        // already idle and the next initialize() or play() starts over.
        rethrow;
      }
      _update(
        _value.copyWith(
          status: ReelPlaybackStatus.error,
          error: error,
          isBuffering: false,
        ),
      );
      rethrow;
    } finally {
      if (identical(_preparation, preparation)) _preparation = null;
    }
  }

  /// Sends only the settings that differ from what the native player
  /// already has, to avoid redundant channel traffic on player reuse.
  Future<void> _applySettings() async {
    final lease = _lease;
    if (lease == null || _disposed) return;
    final platform = _host.platform;
    final applied = lease.applied;
    final volume = _value.isMuted ? 0.0 : _value.volume;
    if (applied.looping != _value.isLooping) {
      await platform.setLooping(lease.playerId, _value.isLooping);
      applied.looping = _value.isLooping;
    }
    if (applied.volume != volume) {
      await platform.setVolume(lease.playerId, volume);
      applied.volume = volume;
    }
    if (applied.playbackSpeed != _value.playbackSpeed) {
      await platform.setPlaybackSpeed(lease.playerId, _value.playbackSpeed);
      applied.playbackSpeed = _value.playbackSpeed;
    }
  }

  void _onNativeState(ReelNativePlaybackState state) {
    switch (state) {
      case ReelNativePlaybackState.buffering:
        _update(_value.copyWith(isBuffering: true));
      case ReelNativePlaybackState.ready:
        _update(_value.copyWith(isBuffering: false));
      case ReelNativePlaybackState.ended:
        if (_value.isLooping || !_value.isInitialized) return;
        _update(
          _value.copyWith(
            status: ReelPlaybackStatus.completed,
            isBuffering: false,
          ),
        );
      case ReelNativePlaybackState.idle:
        break;
    }
  }

  void _onIsPlaying(bool isPlaying) {
    if (!_value.isInitialized) return;
    if (isPlaying) {
      _update(_value.copyWith(status: ReelPlaybackStatus.playing));
    } else if (_value.status == ReelPlaybackStatus.playing) {
      _update(_value.copyWith(status: ReelPlaybackStatus.paused));
    }
  }

  PooledPlayer _requirePrepared(String operation) {
    final lease = _lease;
    if (lease == null || !_value.isInitialized) {
      throw ReelKitException(
        ReelKitErrorCode.notInitialized,
        '$operation requires a prepared video. Call initialize() or play() '
        'first.',
      );
    }
    return lease;
  }

  Duration _clampToDuration(Duration position) {
    if (position.isNegative) return Duration.zero;
    final duration = _value.duration;
    if (duration != null && position > duration) return duration;
    return position;
  }

  void _failPreparation(ReelKitException error) {
    final preparation = _preparation;
    if (preparation != null && !preparation.isCompleted) {
      preparation.completeError(error);
    }
  }

  void _update(ReelPlaybackState next) {
    if (next == _value) return;
    _value = next;
    if (!_disposedNotifier) notifyListeners();
  }

  /// True once [ChangeNotifier.dispose] ran; notifying afterwards would
  /// assert in debug builds.
  bool _disposedNotifier = false;

  void _throwIfDisposed() {
    if (_disposed) throw _disposedError();
  }

  ReelKitException _disposedError() => const ReelKitException(
    ReelKitErrorCode.disposed,
    'This ReelPlayerController was disposed.',
  );
}
