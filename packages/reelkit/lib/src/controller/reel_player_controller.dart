import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../config/reel_kit_config.dart';
import '../pool/reel_player_pool.dart';
import '../util/async_lock.dart';
import 'reel_playback_state.dart';
import 'reel_player_metrics.dart';
import 'reel_position_stream.dart';
import 'reel_track_state.dart';

/// A system interruption of playback, see
/// [ReelPlayerController.interruptions].
@immutable
class ReelInterruption {
  /// Creates an interruption notice.
  const ReelInterruption({required this.type, required this.ended});

  /// What interrupted playback.
  final ReelInterruptionType type;

  /// False when the interruption began, true when it ended.
  final bool ended;

  @override
  bool operator ==(Object other) =>
      other is ReelInterruption && other.type == type && other.ended == ended;

  @override
  int get hashCode => Object.hash(type, ended);

  @override
  String toString() => 'ReelInterruption(${type.name}, ended: $ended)';
}

/// Services a controller needs from its manager.
@internal
abstract interface class ReelControllerHost {
  ReelKitPlatform get platform;
  ReelPlatformCapabilities get capabilities;
  ReelPlayerPool get pool;
  void controllerDisposed(ReelPlayerController controller);

  /// Called synchronously when `play` is called, before it is queued.
  void playRequested(ReelPlayerController controller);

  /// Whether the controller may start playback now (exclusive playback).
  bool mayStartPlayback(ReelPlayerController controller);

  /// Called when [ReelPlaybackState.isPlaying] changes.
  void playingChanged(ReelPlayerController controller, bool isPlaying);
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
/// When the manager uses exclusive playback (the default), [play] pauses the
/// manager's other controllers; see `ReelKitConfig.exclusivePlayback`.
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
       _preloadBufferDuration = config.preloadBufferDuration,
       _retry = config.retry,
       _value = ReelPlaybackState(
         isLooping: config.looping,
         volume: config.volume,
         isMuted: config.muted,
         playbackSpeed: config.playbackSpeed,
       ) {
    _tracks = ReelTrackState(() => _host.platform);
  }

  final ReelControllerHost _host;
  final Duration _initializeTimeout;
  final Duration? _preloadBufferDuration;
  final ReelRetryConfig _retry;
  final StreamController<ReelInterruption> _interruptions =
      StreamController<ReelInterruption>.broadcast();
  Completer<void>? _retryWait;
  Timer? _retryTimer;
  Timer? _recoveryTimer;
  int _playbackRetries = 0;
  bool _resumeAfterError = false;
  final AsyncLock _commands = AsyncLock();

  late final ReelTrackState _tracks;
  final ChangeNotifier _positionChanges = ChangeNotifier();
  final Set<StreamController<ReelPositionSnapshot>> _positionStreams =
      <StreamController<ReelPositionSnapshot>>{};

  ReelSource _source;
  ReelPlaybackState _value;
  ReelPlayerPriority _priority = ReelPlayerPriority.visible;
  PooledPlayer? _lease;
  Completer<ReelVideoInfo>? _preparation;
  Future<void>? _pendingInitialize;
  bool _disposed = false;

  ReelPlayerMetrics _metrics = const ReelPlayerMetrics();
  final Stopwatch _preparationClock = Stopwatch();
  bool _firstFrameMeasured = false;
  final Stopwatch _startClock = Stopwatch();

  /// Set by [play] and cleared by everything that ends the request (pause,
  /// stop, completion, errors, losing the player).
  bool _playbackRequested = false;

  /// The video this controller plays.
  ReelSource get source => _source;

  @override
  ReelPlaybackState get value => _value;

  /// Audio, video and text tracks of the prepared source. Updated by the
  /// engine; empty until the source is prepared and on engines without
  /// track support (see `ReelPlatformCapabilities.supportsTrackSelection`).
  ValueListenable<List<ReelTrack>> get tracks => _tracks.tracks;

  /// Subtitle text to display now, one entry per cue. Empty when no
  /// subtitle track is selected or nothing is to be shown. Render it with
  /// your own widgets.
  ValueListenable<List<String>> get subtitles => _tracks.subtitles;

  /// The current adaptive video cap.
  ReelVideoQualityLimit get videoQualityLimit => _tracks.qualityLimit;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// Claim strength on a native player. Raised to
  /// [ReelPlayerPriority.active] by [play] and lowered to
  /// [ReelPlayerPriority.visible] by [pause].
  ReelPlayerPriority get priority => _priority;

  set priority(ReelPlayerPriority value) {
    _throwIfDisposed();
    if (_priority == value) return;
    _priority = value;
    final lease = _lease;
    if (lease != null &&
        lease.applied.preloadBufferLimit != _desiredPreloadBufferLimit) {
      unawaited(_command(_applySettings).catchError(_reportBackgroundError));
    }
  }

  /// Playback paused or resumed by the system: audio focus taken by another
  /// app, a phone call, headphones unplugged. The playback state changes as
  /// usual; this stream says why.
  Stream<ReelInterruption> get interruptions => _interruptions.stream;

  /// Timing of the latest preparation and playback start.
  ReelPlayerMetrics get metrics => _metrics;

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
  /// Restarts from the beginning when the video had completed. With
  /// exclusive playback, other controllers of the manager are paused, and
  /// this call completes without starting playback when another
  /// controller's [play] was called after it but before playback started.
  Future<void> play() {
    if (_disposed) return Future<void>.error(_disposedError());
    _playbackRequested = true;
    _host.playRequested(this);
    return _command(() async {
      if (!_host.mayStartPlayback(this)) {
        _endPlaybackRequest();
        return;
      }
      _priority = ReelPlayerPriority.active;
      await _prepareIfNeeded();
      final lease = _lease;
      if (_disposed || lease == null) return;
      if (!_host.mayStartPlayback(this)) {
        _endPlaybackRequest();
        return;
      }
      if (_value.status == ReelPlaybackStatus.completed) {
        await _host.platform.seekTo(lease.playerId, Duration.zero);
      }
      await _applySettings();
      if (!_value.isPlaying) {
        _startClock
          ..reset()
          ..start();
      }
      await _host.platform.play(lease.playerId);
    });
  }

  /// Pauses playback. Keeps the native player and its buffers.
  Future<void> pause() => _command(_pauseNow);

  /// Whether this controller plays or has a pending [play]. Used by the
  /// manager's exclusive playback.
  @internal
  bool get wantsPlayback =>
      !_disposed && (_playbackRequested || _value.isPlaying);

  /// Pauses unless this controller has become the latest to request
  /// playback again. Queued like any command, so it runs after a pending
  /// [play] of this controller.
  @internal
  Future<void> yieldPlayback() => _command(() async {
    if (_host.mayStartPlayback(this)) return;
    await _pauseNow();
  });

  Future<void> _pauseNow() async {
    _endPlaybackRequest();
    final lease = _lease;
    if (lease == null || !_value.isInitialized) return;
    await _host.platform.pause(lease.playerId);
  }

  void _endPlaybackRequest() {
    _playbackRequested = false;
    if (_priority == ReelPlayerPriority.active) {
      _priority = ReelPlayerPriority.visible;
    }
  }

  /// Pauses and returns to the beginning. The video stays prepared.
  Future<void> stop() => _command(() async {
    _endPlaybackRequest();
    final lease = _lease;
    if (lease == null || !_value.isInitialized) return;
    await _host.platform.pause(lease.playerId);
    await _host.platform.seekTo(lease.playerId, Duration.zero);
    _positionChanges.notifyListeners();
  });

  /// Seeks to [position], clamped to the video duration when it is known.
  ///
  /// Throws [ReelKitErrorCode.notInitialized] before the video is prepared.
  Future<void> seekTo(Duration position) => _command(() async {
    final lease = _requirePrepared('seekTo');
    await _host.platform.seekTo(lease.playerId, _clampToDuration(position));
    _positionChanges.notifyListeners();
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
    _positionChanges.notifyListeners();
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

  /// Replaces the video while keeping this controller, its settings and, when
  /// attached, its native player.
  ///
  /// When the controller is prepared, the new source is prepared at once and
  /// playback resumes if it was playing. Otherwise the new source is used by
  /// the next [initialize] or [play]. Track selections are reset; the video
  /// quality limit is kept.
  Future<void> setSource(ReelSource source) {
    // A pending automatic retry belongs to the old source: stop it now
    // instead of queueing the new source behind its delay.
    if (source != _source) _cancelRetries();
    return _command(() => _setSourceNow(source));
  }

  Future<void> _setSourceNow(ReelSource source) async {
    if (source == _source && _value.isInitialized) return;
    final resume = _value.isPlaying;
    _source = source;
    _tracks.resetForNewSource();
    _update(
      _value.copyWith(
        clearVideoInfo: true,
        clearError: true,
        status: ReelPlaybackStatus.idle,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
    if (_lease == null) return;
    await _prepareIfNeeded();
    final lease = _lease;
    if (resume && lease != null && !_disposed && _host.mayStartPlayback(this)) {
      await _host.platform.play(lease.playerId);
    }
  }

  /// Selects [track] (from [tracks]).
  ///
  /// The choice is remembered for this source and re-applied if the
  /// controller has to prepare again.
  Future<void> selectTrack(ReelTrack track) => _command(() async {
    await _tracks.select(_preparedPlayerId, track.type, track.id);
    await _refreshTracks();
  });

  /// Returns [type] to automatic selection: adaptive bitrate for video, the
  /// engine's default for audio. For text this is the same as
  /// [disableSubtitles].
  Future<void> selectAutomaticTrack(ReelTrackType type) => _command(() async {
    await _tracks.select(_preparedPlayerId, type, null);
    await _refreshTracks();
  });

  /// Turns subtitles off.
  Future<void> disableSubtitles() => selectAutomaticTrack(ReelTrackType.text);

  /// Caps adaptive video quality, for example on metered networks. Pass
  /// [ReelVideoQualityLimit.none] to remove the cap.
  Future<void> setVideoQualityLimit(ReelVideoQualityLimit limit) =>
      _command(() => _tracks.setQualityLimit(_preparedPlayerId, limit));

  /// Emits the playback position every [interval] while playing, and once
  /// after every state change or seek.
  ///
  /// Polling runs only while the stream has a listener and the video is
  /// playing, so a paused video causes no channel traffic.
  Stream<ReelPositionSnapshot> positions({
    Duration interval = const Duration(milliseconds: 250),
  }) {
    _throwIfDisposed();
    return pollPositions(
      interval: interval,
      read: getPosition,
      isPlaying: () => _value.isPlaying,
      isClosed: () => _disposed,
      changes: Listenable.merge([this, _positionChanges]),
      register: _positionStreams.add,
      unregister: _positionStreams.remove,
    );
  }

  /// Gives the native player back to the pool without disposing the
  /// controller, for example when a feed item scrolls far out of view. The
  /// state returns to [ReelPlaybackStatus.idle] (video info is kept for
  /// layout) and the next [initialize] or [play] prepares the video again.
  Future<void> release() {
    // Cancel an in-flight preparation now instead of after it completes, so
    // that a preload that is no longer wanted stops downloading at once.
    _failPreparation(
      const ReelKitException(
        ReelKitErrorCode.cancelled,
        'The controller was released while preparing.',
      ),
    );
    _cancelRetries();
    return _command(_releaseNow);
  }

  /// Prepares the video again after an error, seeks back to where it failed
  /// and resumes if it was playing. Does nothing unless the state is
  /// [ReelPlaybackStatus.error]. Automatic retries ([ReelRetryConfig]) use
  /// the same path.
  Future<void> retry() => _command(() => _recover(_resumeAfterError));

  /// Gives the native player back and prepares the source from the
  /// beginning, for example after the app changed network settings.
  Future<void> reinitialize() {
    _cancelRetries();
    return _command(() async {
      await _releaseNow();
      await _prepareIfNeeded();
    });
  }

  Future<void> _releaseNow() async {
    if (_lease == null) return;
    _lease = null;
    _endPlaybackRequest();
    _tracks.clear();
    _update(
      _value.copyWith(
        status: ReelPlaybackStatus.idle,
        isAttached: false,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
    await _host.pool.release(this);
  }

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
    _playbackRequested = false;
    _cancelRetries();
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
    for (final stream in List.of(_positionStreams)) {
      await stream.close();
    }
    _positionStreams.clear();
    _tracks.dispose();
    _positionChanges.dispose();
    unawaited(_interruptions.close());
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
        // The first frame can arrive before or after the engine reports the
        // video ready, so the clock keeps running for the other measurement.
        if (_preparationClock.isRunning && !_firstFrameMeasured) {
          _firstFrameMeasured = true;
          _metrics = _metrics.copyWith(
            lastTimeToFirstFrame: _preparationClock.elapsed,
          );
        }
        _update(_value.copyWith(hasRenderedFirstFrame: true));
      case ReelTracksChangedEvent():
        unawaited(_refreshTracks().catchError(_reportBackgroundError));
      case ReelCuesEvent(:final texts):
        _tracks.onCues(texts);
      case ReelErrorEvent(:final error):
        final preparation = _preparation;
        if (preparation != null && !preparation.isCompleted) {
          preparation.completeError(error);
        } else {
          _resumeAfterError = _playbackRequested || _value.isPlaying;
          _endPlaybackRequest();
          _update(
            _value.copyWith(
              status: ReelPlaybackStatus.error,
              error: error,
              isBuffering: false,
            ),
          );
          _scheduleRecovery(error);
        }
      case ReelInterruptionEvent(:final type, :final ended):
        _interruptions.add(ReelInterruption(type: type, ended: ended));
    }
  }

  @override
  @internal
  void onPoolLeaseRevoked() {
    if (_lease == null) return;
    _lease = null;
    _playbackRequested = false;
    _failPreparation(
      const ReelKitException(
        ReelKitErrorCode.cancelled,
        'The native player was reassigned to a higher-priority controller.',
      ),
    );
    if (_disposed) return;
    _tracks.clear();
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
    _tracks.clear();

    _update(
      _value.copyWith(
        status: ReelPlaybackStatus.initializing,
        clearError: true,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
    _preparationClock
      ..reset()
      ..start();
    _firstFrameMeasured = false;
    _metrics = _metrics.copyWith(preparations: _metrics.preparations + 1);
    try {
      ReelVideoInfo? info;
      for (var attempt = 0; ; attempt++) {
        try {
          info = await _prepareOnce();
          break;
        } on ReelKitException catch (error) {
          if (_disposed ||
              attempt >= _retry.maxAttempts ||
              !_retry.isRetryable(error.code)) {
            rethrow;
          }
          await _waitForRetry(_retry.delayFor(attempt + 1));
        }
      }
      final lease = _lease;
      if (info == null || lease == null || _disposed) return;
      _metrics = _metrics.copyWith(
        lastPreparationTime: _preparationClock.elapsed,
      );
      await _tracks.applyPreferences(lease.playerId);
      _update(
        _value.copyWith(status: ReelPlaybackStatus.ready, videoInfo: info),
      );
      unawaited(_refreshTracks().catchError(_reportBackgroundError));
    } on ReelKitException catch (error) {
      if (_disposed) return;
      _preparationClock.stop();
      _endPlaybackRequest();
      if (error.code == ReelKitErrorCode.cancelled) {
        // Lost the player to a higher-priority controller, or released while
        // preparing: not an error. The next initialize() or play() starts
        // over.
        _update(
          _value.copyWith(
            status: ReelPlaybackStatus.idle,
            isBuffering: false,
            hasRenderedFirstFrame: false,
          ),
        );
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
    }
  }

  /// One preparation attempt, plus one more on a different player after a
  /// decoder shortage.
  Future<ReelVideoInfo?> _prepareOnce() async {
    try {
      return await _prepareAttempt(freshPlayer: false);
    } on ReelKitException catch (error) {
      if (!await _releaseForDecoderRetry(error)) rethrow;
      try {
        return await _prepareAttempt(freshPlayer: true);
      } on ReelKitException catch (retryError) {
        // No player could be taken for the retry; the decoder shortage is
        // the meaningful error.
        if (retryError.code == ReelKitErrorCode.poolExhausted) throw error;
        rethrow;
      }
    }
  }

  /// Waits before an automatic retry. Throws `cancelled` when the
  /// controller is released or disposed meanwhile.
  Future<void> _waitForRetry(Duration delay) async {
    final wait = Completer<void>();
    _retryWait = wait;
    _retryTimer = Timer(delay, () {
      if (!wait.isCompleted) wait.complete();
    });
    try {
      await wait.future;
    } finally {
      if (identical(_retryWait, wait)) {
        _retryWait = null;
        _retryTimer = null;
      }
    }
  }

  void _cancelRetries() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    final wait = _retryWait;
    _retryWait = null;
    if (wait != null && !wait.isCompleted) {
      wait.completeError(
        const ReelKitException(
          ReelKitErrorCode.cancelled,
          'The automatic retry was cancelled.',
        ),
      );
    }
  }

  /// Schedules an automatic recovery from a playback error.
  void _scheduleRecovery(ReelKitException error) {
    if (!_retry.isRetryable(error.code) ||
        _playbackRetries >= _retry.maxAttempts) {
      return;
    }
    _playbackRetries++;
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(_retry.delayFor(_playbackRetries), () {
      _recoveryTimer = null;
      unawaited(retry().catchError(_ignoreRecoveryError));
    });
  }

  static void _ignoreRecoveryError(Object _) {}

  /// Prepares again after an error and restores position and playback.
  Future<void> _recover(bool resume) async {
    if (_disposed || _value.status != ReelPlaybackStatus.error) return;
    var resumeAt = Duration.zero;
    final failed = _lease;
    if (failed != null && _value.videoInfo?.isLive != true) {
      try {
        resumeAt = (await _host.platform.getPosition(failed.playerId)).position;
      } on Object {
        // The engine may not know the position after the failure.
      }
    }
    await _prepareIfNeeded();
    final lease = _lease;
    if (_disposed || lease == null || !_value.isInitialized) return;
    if (resumeAt > Duration.zero) {
      await _host.platform.seekTo(lease.playerId, _clampToDuration(resumeAt));
    }
    if (resume && _host.mayStartPlayback(this)) {
      _playbackRequested = true;
      _priority = ReelPlayerPriority.active;
      await _applySettings();
      await _host.platform.play(lease.playerId);
    }
  }

  /// One preparation attempt. Returns null when the attempt was superseded
  /// (disposed, or the player was reassigned).
  ///
  /// Without [freshPlayer], a held lease (retry after an error, or a new
  /// source) keeps its native player but gets a fresh generation, so late
  /// events of the previous attempt are discarded.
  Future<ReelVideoInfo?> _prepareAttempt({required bool freshPlayer}) async {
    final preparation = Completer<ReelVideoInfo>();
    // The completer can fail (revocation, dispose) before it is awaited.
    preparation.future.ignore();
    _preparation = preparation;
    try {
      final pool = _host.pool;
      final lease = freshPlayer
          ? await pool.acquire(this)
          : await pool.renew(this) ?? await pool.acquire(this);
      // Assigned before the disposed check so that dispose() returns it.
      _lease = lease;
      if (_disposed) return null;
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
      if (_disposed || !identical(_lease, lease)) return null;
      return info;
    } finally {
      if (identical(_preparation, preparation)) _preparation = null;
    }
  }

  /// After [ReelKitErrorCode.decoderUnavailable], lets the pool lower its
  /// limit and gives this controller's player back, so the retry takes a
  /// player (and its decoder) from a lower-priority controller instead of
  /// adding one. Returns whether to retry.
  Future<bool> _releaseForDecoderRetry(ReelKitException error) async {
    if (error.code != ReelKitErrorCode.decoderUnavailable) return false;
    if (_disposed || _lease == null) return false;
    if (!await _host.pool.reportDecoderUnavailable(this)) return false;
    if (_disposed || _lease == null) return false;
    _lease = null;
    _update(_value.copyWith(isAttached: false));
    await _host.pool.release(this);
    return !_disposed;
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
    final bufferLimit = _desiredPreloadBufferLimit;
    if (applied.preloadBufferLimit != bufferLimit) {
      await platform.setPreloadBufferLimit(lease.playerId, bufferLimit);
      applied.preloadBufferLimit = bufferLimit;
    }
  }

  /// The forward-buffer cap this controller wants on its native player:
  /// only while it is a paused preload or background controller.
  Duration? get _desiredPreloadBufferLimit {
    if (!_host.capabilities.supportsPreloadBufferLimit) return null;
    if (_playbackRequested) return null;
    return switch (_priority) {
      ReelPlayerPriority.preload ||
      ReelPlayerPriority.background => _preloadBufferDuration,
      ReelPlayerPriority.visible || ReelPlayerPriority.active => null,
    };
  }

  void _onNativeState(ReelNativePlaybackState state) {
    switch (state) {
      case ReelNativePlaybackState.buffering:
        _update(_value.copyWith(isBuffering: true));
      case ReelNativePlaybackState.ready:
        _update(_value.copyWith(isBuffering: false));
      case ReelNativePlaybackState.ended:
        if (_value.isLooping || !_value.isInitialized) return;
        _endPlaybackRequest();
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
    if (isPlaying) _playbackRetries = 0;
    if (isPlaying && _startClock.isRunning) {
      _metrics = _metrics.copyWith(lastStartLatency: _startClock.elapsed);
      _startClock.stop();
    }
    if (isPlaying) {
      _update(_value.copyWith(status: ReelPlaybackStatus.playing));
    } else if (_value.status == ReelPlaybackStatus.playing) {
      _update(_value.copyWith(status: ReelPlaybackStatus.paused));
    }
  }

  int? get _preparedPlayerId => _value.isInitialized ? _lease?.playerId : null;

  Future<void> _refreshTracks() async {
    final lease = _lease;
    if (lease == null || _disposed || !_value.isInitialized) return;
    final generation = lease.generation;
    await _tracks.refresh(
      lease.playerId,
      () =>
          !_disposed &&
          identical(_lease, lease) &&
          lease.generation == generation,
    );
  }

  void _reportBackgroundError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'reelkit',
        context: ErrorDescription('while reading tracks'),
      ),
    );
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
    final wasPlaying = _value.isPlaying;
    _value = next;
    if (wasPlaying != next.isPlaying) {
      _host.playingChanged(this, next.isPlaying);
    }
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
