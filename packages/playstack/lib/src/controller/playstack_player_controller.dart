import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../config/playstack_config.dart';
import '../pool/playstack_player_pool.dart';
import '../util/async_lock.dart';
import 'playstack_playback_state.dart';
import 'playstack_player_metrics.dart';
import 'playstack_position_stream.dart';
import 'playstack_track_state.dart';

/// Why the system paused or resumed playback, emitted by
/// [PlayStackPlayerController.interruptions]: a phone call, another app taking
/// the audio, headphones unplugged.
///
/// Use it to explain a pause to the user; the playback state changes on its
/// own.
@immutable
class PlayStackInterruption {
  /// Creates an interruption notice. Controllers create these.
  const PlayStackInterruption({required this.type, required this.ended});

  /// What interrupted playback, for example a call or headphones being unplugged.
  final PlayStackInterruptionType type;

  /// False when the interruption began, true when it ended.
  final bool ended;

  @override
  bool operator ==(Object other) =>
      other is PlayStackInterruption &&
      other.type == type &&
      other.ended == ended;

  @override
  int get hashCode => Object.hash(type, ended);

  @override
  String toString() => 'PlayStackInterruption(${type.name}, ended: $ended)';
}

/// Services a controller needs from its manager.
@internal
abstract interface class PlayStackControllerHost {
  PlayStackPlatform get platform;
  PlayStackPlatformCapabilities get capabilities;
  PlayStackPlayerPool get pool;
  void controllerDisposed(PlayStackPlayerController controller);

  /// Called synchronously when `play` is called, before it is queued.
  void playRequested(PlayStackPlayerController controller);

  /// Whether the controller may start playback now (exclusive playback).
  bool mayStartPlayback(PlayStackPlayerController controller);

  /// Called when [PlayStackPlaybackState.isPlaying] changes.
  void playingChanged(PlayStackPlayerController controller, bool isPlaying);
}

/// Plays one video: play, pause, seek, volume, speed, tracks, and its
/// observable state.
///
/// Create one with `PlayStackManager.createController`, show it with
/// `PlayStackVideoView`, and dispose it when done:
///
/// ```dart
/// final controller = manager.createController(
///   PlayStackSource.network('https://example.com/video.m3u8'),
/// );
/// await controller.play();          // prepares the video first if needed
/// PlayStackVideoView(controller: controller);
/// // later
/// await controller.dispose();
/// ```
///
/// In a `PlayStackFeedView` you never create controllers: each page gets one as
/// `PlayStackFeedPage.controller`, and the feed plays and pauses it as the user
/// swipes.
///
/// Creating a controller is cheap: it holds no native player until it is
/// prepared ([initialize]) or played. Players come from the manager's pool
/// and go back on [dispose] or [release]. If a more important controller
/// (higher [priority]) needs a player while the pool is full, this one may
/// lose its player; its status returns to [PlayStackPlaybackStatus.idle] and the
/// next [play] prepares the video again.
///
/// By default, [play] pauses the manager's other controllers, so only one
/// video plays at a time (see `PlayStackConfig.exclusivePlayback`).
///
/// Commands run one at a time in call order, so you can call them without
/// awaiting. After [dispose], commands throw a [PlayStackException] with
/// [PlayStackErrorCode.disposed].
class PlayStackPlayerController extends ChangeNotifier
    implements ValueListenable<PlayStackPlaybackState>, PlayStackPoolClient {
  /// Use `PlayStackManager.createController` instead.
  @internal
  PlayStackPlayerController.internal({
    required this._host,
    required this._source,
    required PlayStackPlayerConfig config,
  }) : _initializeTimeout = config.initializeTimeout,
       _preloadBufferDuration = config.preloadBufferDuration,
       _startupQualityLimit = config.startupQualityLimit,
       _retry = config.retry,
       _value = PlayStackPlaybackState(
         isLooping: config.looping,
         volume: config.volume,
         isMuted: config.muted,
         playbackSpeed: config.playbackSpeed,
       ) {
    _tracks = PlayStackTrackState(() => _host.platform)
      ..storeQualityLimit(config.videoQualityLimit);
  }

  final PlayStackControllerHost _host;
  final Duration _initializeTimeout;
  final Duration? _preloadBufferDuration;
  final PlayStackVideoQualityLimit? _startupQualityLimit;
  final PlayStackRetryConfig _retry;

  /// Whether the current preparation has started playing, which lifts
  /// [_startupQualityLimit].
  bool _startedPlayback = false;
  final StreamController<PlayStackInterruption> _interruptions =
      StreamController<PlayStackInterruption>.broadcast();
  Completer<void>? _retryWait;
  Timer? _retryTimer;
  Timer? _recoveryTimer;
  int _playbackRetries = 0;
  bool _resumeAfterError = false;
  final AsyncLock _commands = AsyncLock();

  late final PlayStackTrackState _tracks;
  final ChangeNotifier _positionChanges = ChangeNotifier();
  final Set<StreamController<PlayStackPositionSnapshot>> _positionStreams =
      <StreamController<PlayStackPositionSnapshot>>{};

  PlayStackSource _source;
  PlayStackPlaybackState _value;
  PlayStackPlayerPriority _priority = PlayStackPlayerPriority.visible;
  PooledPlayer? _lease;
  Completer<PlayStackVideoInfo>? _preparation;
  Future<void>? _pendingInitialize;
  bool _disposed = false;

  PlayStackPlayerMetrics _metrics = const PlayStackPlayerMetrics();
  final Stopwatch _preparationClock = Stopwatch();
  bool _firstFrameMeasured = false;
  final Stopwatch _startClock = Stopwatch();

  /// Set by [play] and cleared by everything that ends the request (pause,
  /// stop, completion, errors, losing the player).
  bool _playbackRequested = false;

  /// The video this controller plays. Change it with [setSource].
  PlayStackSource get source => _source;

  /// Where the video starts, for example where the user stopped watching an
  /// episode. Null (the default) starts at the beginning.
  ///
  /// The video is prepared at this point, so playback starts there without
  /// first showing the beginning. It applies to every preparation that
  /// follows, including after a [setSource] or after the controller lost its
  /// native player; set it to null once it should no longer apply. A video
  /// already prepared is not moved: use [seekTo] for that.
  ///
  /// Ignored for live streams, and when it is in the last second of the
  /// video (an episode watched to the end starts over).
  Duration? startPosition;

  /// The current playback state: status, buffering, size, duration,
  /// volume, error. See [PlayStackPlaybackState].
  ///
  /// The controller is a `ValueListenable`, so rebuild widgets from it:
  ///
  /// ```dart
  /// ValueListenableBuilder<PlayStackPlaybackState>(
  ///   valueListenable: controller,
  ///   builder: (context, state, _) =>
  ///       Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
  /// )
  /// ```
  ///
  /// The position is not part of it, because it changes every frame; read
  /// it with [positions] or [getPosition].
  @override
  PlayStackPlaybackState get value => _value;

  /// Audio, video and text tracks of the prepared source. Updated by the
  /// engine; empty until the source is prepared and on engines without
  /// track support (see `PlayStackPlatformCapabilities.supportsTrackSelection`).
  ValueListenable<List<PlayStackTrack>> get tracks => _tracks.tracks;

  /// Subtitle text to display now, one entry per cue. Empty when no
  /// subtitle track is selected or nothing is to be shown. Render it with
  /// your own widgets.
  ValueListenable<List<String>> get subtitles => _tracks.subtitles;

  /// The current cap on the video quality of adaptive streams (HLS, DASH),
  /// set by `PlayStackPlayerConfig.videoQualityLimit` or
  /// [setVideoQualityLimit]. [PlayStackVideoQualityLimit.none] when uncapped.
  PlayStackVideoQualityLimit get videoQualityLimit => _tracks.qualityLimit;

  /// Whether [dispose] was called. A disposed controller cannot be used again.
  bool get isDisposed => _disposed;

  /// How strongly this controller holds on to its native player when the pool
  /// is full: [PlayStackPlayerPriority.active] (playing) beats
  /// [PlayStackPlayerPriority.visible] (on screen), which beats
  /// [PlayStackPlayerPriority.preload] and [PlayStackPlayerPriority.background].
  ///
  /// [play] raises it to active and [pause] lowers it to visible. Feeds manage
  /// it for their controllers; set it yourself only for custom layouts, for
  /// example `background` for a video scrolled out of view.
  PlayStackPlayerPriority get priority => _priority;

  set priority(PlayStackPlayerPriority value) {
    _throwIfDisposed();
    if (_priority == value) return;
    _priority = value;
    final lease = _lease;
    if (lease != null &&
        lease.applied.preloadBufferLimit != _desiredPreloadBufferLimit) {
      unawaited(_command(_applySettings).catchError(_reportBackgroundError));
    }
  }

  /// Tells why the system paused or resumed playback: another app took the
  /// audio, a phone call, headphones unplugged. The playback state changes on
  /// its own; listen here to tell the user why.
  Stream<PlayStackInterruption> get interruptions => _interruptions.stream;

  /// How long the latest preparation and playback start took. Useful for
  /// diagnostics and performance logging.
  PlayStackPlayerMetrics get metrics => _metrics;

  @override
  @internal
  PlayStackPlayerPriority get poolPriority => _priority;

  /// Prepares the video so that [play] can start without delay.
  ///
  /// Concurrent calls share one preparation. Completes immediately when the
  /// video is already prepared. Throws a [PlayStackException] when preparation
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
      _priority = PlayStackPlayerPriority.active;
      await _prepareIfNeeded();
      final lease = _lease;
      if (_disposed || lease == null) return;
      if (!_host.mayStartPlayback(this)) {
        _endPlaybackRequest();
        return;
      }
      if (_value.status == PlayStackPlaybackStatus.completed) {
        await _host.platform.seekTo(lease.playerId, Duration.zero);
      }
      _startedPlayback = true;
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
    if (_priority == PlayStackPlayerPriority.active) {
      _priority = PlayStackPlayerPriority.visible;
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
  /// Throws [PlayStackErrorCode.notInitialized] before the video is prepared.
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

  /// Seeks forward by [step], 10 seconds by default. Stops at the end.
  Future<void> fastForward([Duration step = const Duration(seconds: 10)]) =>
      seekBy(step);

  /// Seeks backward by [step], 10 seconds by default. Stops at the beginning.
  Future<void> rewind([Duration step = const Duration(seconds: 10)]) =>
      seekBy(-step);

  /// Whether the video starts over when it reaches the end. When false, the
  /// status becomes [PlayStackPlaybackStatus.completed] at the end and [play]
  /// restarts it.
  Future<void> setLooping(bool looping) => _command(() async {
    _update(_value.copyWith(isLooping: looping));
    await _applySettings();
  });

  /// Sets the volume from 0.0 to 1.0. Does not change [PlayStackPlaybackState.isMuted].
  Future<void> setVolume(double volume) => _command(() async {
    if (volume.isNaN || volume < 0 || volume > 1) {
      throw PlayStackException(
        PlayStackErrorCode.invalidArgument,
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
      throw PlayStackException(
        PlayStackErrorCode.invalidArgument,
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
  Future<void> setSource(PlayStackSource source) {
    // A pending automatic retry belongs to the old source: stop it now
    // instead of queueing the new source behind its delay.
    if (source != _source) _cancelRetries();
    return _command(() => _setSourceNow(source));
  }

  Future<void> _setSourceNow(PlayStackSource source) async {
    if (source == _source && _value.isInitialized) return;
    final resume = _value.isPlaying;
    _source = source;
    _tracks.resetForNewSource();
    _update(
      _value.copyWith(
        clearVideoInfo: true,
        clearError: true,
        status: PlayStackPlaybackStatus.idle,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
    if (_lease == null) return;
    await _prepareIfNeeded();
    final lease = _lease;
    if (resume && lease != null && !_disposed && _host.mayStartPlayback(this)) {
      _startedPlayback = true;
      await _applySettings();
      await _host.platform.play(lease.playerId);
    }
  }

  /// Selects [track] (from [tracks]).
  ///
  /// The choice is remembered for this source and re-applied if the
  /// controller has to prepare again.
  Future<void> selectTrack(PlayStackTrack track) => _command(() async {
    await _tracks.select(_preparedPlayerId, track.type, track.id);
    await _refreshTracks();
  });

  /// Returns [type] to automatic selection: adaptive bitrate for video, the
  /// engine's default for audio. For text this is the same as
  /// [disableSubtitles].
  Future<void> selectAutomaticTrack(PlayStackTrackType type) =>
      _command(() async {
        await _tracks.select(_preparedPlayerId, type, null);
        await _refreshTracks();
      });

  /// Turns subtitles off: [subtitles] becomes empty until a text track is selected again.
  Future<void> disableSubtitles() =>
      selectAutomaticTrack(PlayStackTrackType.text);

  /// Caps adaptive video quality, for example on metered networks. Pass
  /// [PlayStackVideoQualityLimit.none] to remove the cap.
  Future<void> setVideoQualityLimit(PlayStackVideoQualityLimit limit) =>
      _command(() async {
        if (!_managesQualityLimit) {
          await _tracks.setQualityLimit(_preparedPlayerId, limit);
          return;
        }
        _tracks.storeQualityLimit(limit);
        await _applySettings();
      });

  /// The playback position, for progress bars and time labels.
  ///
  /// Emits every [interval] while playing, and once after every state change
  /// or seek. It reads from the engine only while the stream has a listener
  /// and the video plays, so a paused video costs nothing.
  ///
  /// ```dart
  /// StreamBuilder<PlayStackPositionSnapshot>(
  ///   stream: controller.positions(),
  ///   builder: (context, snapshot) =>
  ///       Text('${snapshot.data?.position.inSeconds ?? 0} s'),
  /// )
  /// ```
  ///
  /// Create the stream once (for example in `initState`), not in every
  /// `build`.
  Stream<PlayStackPositionSnapshot> positions({
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
  /// state returns to [PlayStackPlaybackStatus.idle] (video info is kept for
  /// layout) and the next [initialize] or [play] prepares the video again.
  Future<void> release() {
    // Cancel an in-flight preparation now instead of after it completes, so
    // that a preload that is no longer wanted stops downloading at once.
    _failPreparation(
      const PlayStackException(
        PlayStackErrorCode.cancelled,
        'The controller was released while preparing.',
      ),
    );
    _cancelRetries();
    return _command(_releaseNow);
  }

  /// Prepares the video again after an error, seeks back to where it failed
  /// and resumes if it was playing. Does nothing unless the state is
  /// [PlayStackPlaybackStatus.error]. Automatic retries ([PlayStackRetryConfig]) use
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
        status: PlayStackPlaybackStatus.idle,
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
  Future<PlayStackPositionSnapshot> getPosition() async {
    _throwIfDisposed();
    final lease = _lease;
    if (lease == null || !_value.isInitialized) {
      return const PlayStackPositionSnapshot(
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
      const PlayStackException(
        PlayStackErrorCode.cancelled,
        'The controller was disposed while preparing.',
      ),
    );
    _update(
      _value.copyWith(
        status: PlayStackPlaybackStatus.disposed,
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
  /// attached. Used by `PlayStackVideoView`.
  @internal
  Widget? buildNativeView() {
    final lease = _lease;
    if (lease == null || _disposed) return null;
    return _host.platform.buildView(lease.playerId);
  }

  /// Routes an engine event to this controller. Events that belong to an
  /// earlier lease or source generation are ignored.
  @internal
  void handlePlatformEvent(PlayStackPlatformEvent event) {
    final lease = _lease;
    if (_disposed ||
        lease == null ||
        event.playerId != lease.playerId ||
        event.generation != lease.generation) {
      return;
    }
    switch (event) {
      case PlayStackInitializedEvent(:final info):
        final preparation = _preparation;
        if (preparation != null && !preparation.isCompleted) {
          preparation.complete(info);
        } else {
          _update(_value.copyWith(videoInfo: info));
        }
      case PlayStackNativeStateEvent(:final state):
        _onNativeState(state);
      case PlayStackIsPlayingEvent(:final isPlaying):
        _onIsPlaying(isPlaying);
      case PlayStackVideoSizeEvent():
        final current =
            _value.videoInfo ?? const PlayStackVideoInfo(width: 0, height: 0);
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
      case PlayStackFirstFrameEvent():
        // The first frame can arrive before or after the engine reports the
        // video ready, so the clock keeps running for the other measurement.
        if (_preparationClock.isRunning && !_firstFrameMeasured) {
          _firstFrameMeasured = true;
          _metrics = _metrics.copyWith(
            lastTimeToFirstFrame: _preparationClock.elapsed,
          );
        }
        _update(_value.copyWith(hasRenderedFirstFrame: true));
      case PlayStackTracksChangedEvent():
        unawaited(_refreshTracks().catchError(_reportBackgroundError));
      case PlayStackCuesEvent(:final texts):
        _tracks.onCues(texts);
      case PlayStackErrorEvent(:final error):
        final preparation = _preparation;
        if (preparation != null && !preparation.isCompleted) {
          preparation.completeError(error);
        } else {
          _resumeAfterError = _playbackRequested || _value.isPlaying;
          _endPlaybackRequest();
          _update(
            _value.copyWith(
              status: PlayStackPlaybackStatus.error,
              error: error,
              isBuffering: false,
            ),
          );
          _scheduleRecovery(error);
        }
      case PlayStackInterruptionEvent(:final type, :final ended):
        _interruptions.add(PlayStackInterruption(type: type, ended: ended));
    }
  }

  @override
  @internal
  void onPoolLeaseRevoked() {
    if (_lease == null) return;
    _lease = null;
    _playbackRequested = false;
    _failPreparation(
      const PlayStackException(
        PlayStackErrorCode.cancelled,
        'The native player was reassigned to a higher-priority controller.',
      ),
    );
    if (_disposed) return;
    _tracks.clear();
    _update(
      _value.copyWith(
        status: PlayStackPlaybackStatus.idle,
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
        status: PlayStackPlaybackStatus.initializing,
        clearError: true,
        isBuffering: false,
        hasRenderedFirstFrame: false,
      ),
    );
    _preparationClock
      ..reset()
      ..start();
    _firstFrameMeasured = false;
    _startedPlayback = false;
    _metrics = _metrics.copyWith(preparations: _metrics.preparations + 1);
    try {
      PlayStackVideoInfo? info;
      for (var attempt = 0; ; attempt++) {
        try {
          info = await _prepareOnce();
          break;
        } on PlayStackException catch (error) {
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
      await _tracks.applyPreferences(
        lease.playerId,
        includeQualityLimit: !_managesQualityLimit,
      );
      await _seekToStart(lease, info);
      if (_disposed || !identical(_lease, lease)) return;
      _update(
        _value.copyWith(status: PlayStackPlaybackStatus.ready, videoInfo: info),
      );
      unawaited(_refreshTracks().catchError(_reportBackgroundError));
    } on PlayStackException catch (error) {
      if (_disposed) return;
      _preparationClock.stop();
      _endPlaybackRequest();
      if (error.code == PlayStackErrorCode.cancelled) {
        // Lost the player to a higher-priority controller, or released while
        // preparing: not an error. The next initialize() or play() starts
        // over.
        _update(
          _value.copyWith(
            status: PlayStackPlaybackStatus.idle,
            isBuffering: false,
            hasRenderedFirstFrame: false,
          ),
        );
        rethrow;
      }
      _update(
        _value.copyWith(
          status: PlayStackPlaybackStatus.error,
          error: error,
          isBuffering: false,
        ),
      );
      rethrow;
    }
  }

  /// One preparation attempt, plus one more on a different player after a
  /// decoder shortage.
  Future<PlayStackVideoInfo?> _prepareOnce() async {
    try {
      return await _prepareAttempt(freshPlayer: false);
    } on PlayStackException catch (error) {
      if (!await _releaseForDecoderRetry(error)) rethrow;
      try {
        return await _prepareAttempt(freshPlayer: true);
      } on PlayStackException catch (retryError) {
        // No player could be taken for the retry; the decoder shortage is
        // the meaningful error.
        if (retryError.code == PlayStackErrorCode.poolExhausted) throw error;
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
        const PlayStackException(
          PlayStackErrorCode.cancelled,
          'The automatic retry was cancelled.',
        ),
      );
    }
  }

  /// Schedules an automatic recovery from a playback error.
  void _scheduleRecovery(PlayStackException error) {
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
    if (_disposed || _value.status != PlayStackPlaybackStatus.error) return;
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
      _priority = PlayStackPlayerPriority.active;
      _startedPlayback = true;
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
  Future<PlayStackVideoInfo?> _prepareAttempt({
    required bool freshPlayer,
  }) async {
    final preparation = Completer<PlayStackVideoInfo>();
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
        onTimeout: () => throw PlayStackException(
          PlayStackErrorCode.timeout,
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

  /// After [PlayStackErrorCode.decoderUnavailable], lets the pool lower its
  /// limit and gives this controller's player back, so the retry takes a
  /// player (and its decoder) from a lower-priority controller instead of
  /// adding one. Returns whether to retry.
  Future<bool> _releaseForDecoderRetry(PlayStackException error) async {
    if (error.code != PlayStackErrorCode.decoderUnavailable) return false;
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
    if (_managesQualityLimit) {
      final qualityLimit = _desiredQualityLimit;
      if (applied.qualityLimit != qualityLimit) {
        await platform.setVideoQualityLimit(lease.playerId, qualityLimit);
        applied.qualityLimit = qualityLimit;
      }
    }
  }

  /// Whether the quality limit is a player setting sent by [_applySettings]
  /// (before the source is set, so it already governs the first rendition).
  bool get _managesQualityLimit => _host.capabilities.supportsVideoQualityLimit;

  /// The app's limit, tightened by [_startupQualityLimit] until playback
  /// starts.
  PlayStackVideoQualityLimit get _desiredQualityLimit {
    final limit = _tracks.qualityLimit;
    final startup = _startupQualityLimit;
    if (startup == null || _startedPlayback) return limit;
    int? lower(int? a, int? b) => a == null
        ? b
        : b == null
        ? a
        : (a < b ? a : b);
    return PlayStackVideoQualityLimit(
      maxBitrate: lower(limit.maxBitrate, startup.maxBitrate),
      maxWidth: lower(limit.maxWidth, startup.maxWidth),
      maxHeight: lower(limit.maxHeight, startup.maxHeight),
    );
  }

  /// The forward-buffer cap this controller wants on its native player:
  /// only while it is a paused preload or background controller.
  Duration? get _desiredPreloadBufferLimit {
    if (!_host.capabilities.supportsPreloadBufferLimit) return null;
    if (_playbackRequested) return null;
    return switch (_priority) {
      PlayStackPlayerPriority.preload ||
      PlayStackPlayerPriority.background => _preloadBufferDuration,
      PlayStackPlayerPriority.visible || PlayStackPlayerPriority.active => null,
    };
  }

  void _onNativeState(PlayStackNativePlaybackState state) {
    switch (state) {
      case PlayStackNativePlaybackState.buffering:
        _update(_value.copyWith(isBuffering: true));
      case PlayStackNativePlaybackState.ready:
        _update(_value.copyWith(isBuffering: false));
      case PlayStackNativePlaybackState.ended:
        if (_value.isLooping || !_value.isInitialized) return;
        _endPlaybackRequest();
        _update(
          _value.copyWith(
            status: PlayStackPlaybackStatus.completed,
            isBuffering: false,
          ),
        );
      case PlayStackNativePlaybackState.idle:
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
      _update(_value.copyWith(status: PlayStackPlaybackStatus.playing));
    } else if (_value.status == PlayStackPlaybackStatus.playing) {
      _update(_value.copyWith(status: PlayStackPlaybackStatus.paused));
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
        library: 'playstack',
        context: ErrorDescription('while reading tracks'),
      ),
    );
  }

  PooledPlayer _requirePrepared(String operation) {
    final lease = _lease;
    if (lease == null || !_value.isInitialized) {
      throw PlayStackException(
        PlayStackErrorCode.notInitialized,
        '$operation requires a prepared video. Call initialize() or play() '
        'first.',
      );
    }
    return lease;
  }

  /// Moves a freshly prepared video to [startPosition].
  Future<void> _seekToStart(PooledPlayer lease, PlayStackVideoInfo info) async {
    final start = startPosition;
    if (start == null || start <= Duration.zero || info.isLive) return;
    final duration = info.duration;
    if (duration != null && start >= duration - const Duration(seconds: 1)) {
      return;
    }
    await _host.platform.seekTo(lease.playerId, start);
    _positionChanges.notifyListeners();
  }

  Duration _clampToDuration(Duration position) {
    if (position.isNegative) return Duration.zero;
    final duration = _value.duration;
    if (duration != null && position > duration) return duration;
    return position;
  }

  void _failPreparation(PlayStackException error) {
    final preparation = _preparation;
    if (preparation != null && !preparation.isCompleted) {
      preparation.completeError(error);
    }
  }

  void _update(PlayStackPlaybackState next) {
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

  PlayStackException _disposedError() => const PlayStackException(
    PlayStackErrorCode.disposed,
    'This PlayStackPlayerController was disposed.',
  );
}
