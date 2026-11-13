import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../cache/playstack_cache_manager.dart';
import '../config/playstack_config.dart';
import '../controller/playstack_player_controller.dart';
import '../feed/playstack_feed_config.dart';
import '../feed/playstack_feed_item.dart';
import '../feed/playstack_feed_manager.dart';
import '../fullscreen/playstack_fullscreen_manager.dart';
import '../pool/playstack_player_pool.dart';
import '../system/playstack_media_session.dart';
import 'playstack_playback_coordinator.dart';

/// The entry point of PlayStack: starts the native video engine, keeps a
/// limited set of native players and creates the controllers that use them.
///
/// You need one only outside `PlayStackFeedView(items: ...)`, which creates its
/// own. For a single player or your own layout:
///
/// ```dart
/// final manager = PlayStackManager();
/// await manager.initialize();
/// final controller = manager.createController(
///   PlayStackSource.network('https://example.com/video.mp4'),
/// );
/// await controller.play();
/// // when the screen closes:
/// await manager.dispose(); // disposes all controllers and native players
/// ```
///
/// Native players are expensive (each holds a decoder and buffers), so the
/// manager keeps a bounded pool and lends players to controllers as needed;
/// see [PlayStackPoolConfig]. Use one manager per independent screen or feed;
/// each has its own pool.
class PlayStackManager implements PlayStackControllerHost, PlayStackFeedHost {
  /// Creates a manager with [config]. Nothing starts until [initialize]; call
  /// it before creating controllers or feeds.
  PlayStackManager({
    this.config = const PlayStackConfig(),
    @visibleForTesting PlayStackPlatform? platform,
  }) : _platformOverride = platform,
       _coordinator = PlayStackPlaybackCoordinator(
         exclusive: config.exclusivePlayback,
       );

  /// The settings this manager was created with: pool, player defaults, cache, audio, lifecycle, fullscreen.
  final PlayStackConfig config;
  final PlayStackPlatform? _platformOverride;
  final Set<PlayStackPlayerController> _controllers =
      <PlayStackPlayerController>{};
  final PlayStackPlaybackCoordinator _coordinator;
  final Set<PlayStackFeedManager> _feeds = <PlayStackFeedManager>{};
  final ValueNotifier<PlayStackNetworkStatus> _network =
      ValueNotifier<PlayStackNetworkStatus>(PlayStackNetworkStatus.unknown);
  StreamSubscription<PlayStackNetworkStatus>? _networkEvents;
  PlayStackCacheManager? _cache;
  PlayStackFullscreenManager? _fullscreen;
  PlayStackMediaSession? _mediaSession;
  PlayStackPictureInPicture? _pictureInPicture;
  StreamSubscription<PlayStackSystemEvent>? _systemEvents;

  Future<void>? _initialization;
  PlayStackPlatformCapabilities? _capabilities;
  PlayStackPlayerPool? _pool;
  StreamSubscription<PlayStackPlatformEvent>? _events;
  _BindingObserver? _bindingObserver;
  final Set<PlayStackPlayerController> _pausedByLifecycle =
      <PlayStackPlayerController>{};
  bool _disposed = false;

  @override
  @internal
  PlayStackPlatform get platform =>
      _platformOverride ?? PlayStackPlatform.instance;

  @override
  @internal
  PlayStackPlayerPool get pool {
    final pool = _pool;
    if (pool == null) throw _notInitialized();
    return pool;
  }

  /// Whether [initialize] finished successfully and the manager is not disposed.
  bool get isInitialized => _pool != null && !_disposed;

  /// Whether [dispose] was called. A disposed manager cannot be used again.
  bool get isDisposed => _disposed;

  /// What the engine on this device supports: formats, track selection,
  /// quality caps, recommended player count. Throws before [initialize].
  @override
  PlayStackPlatformCapabilities get capabilities =>
      _capabilities ?? (throw _notInitialized());

  /// How many native players exist and how many are in use, by priority.
  /// Useful for diagnostics. Throws before [initialize].
  PlayStackPoolStats get poolStats => pool.stats;

  /// All controllers created by this manager that are not disposed yet.
  List<PlayStackPlayerController> get controllers =>
      List<PlayStackPlayerController>.unmodifiable(_controllers);

  /// The disk cache of network videos: its size and a way to clear it. Throws before [initialize].
  PlayStackCacheManager get cache => _cache ?? (throw _notInitialized());

  /// Enters and leaves fullscreen and restores orientation afterwards.
  /// `PlayStackFeedView` uses it for you. Throws before [initialize].
  PlayStackFullscreenManager get fullscreen =>
      _fullscreen ?? (throw _notInitialized());

  /// Shows a video in the system's media controls (lock screen,
  /// notification, headphones) and keeps it playing in the background.
  /// `PlayStackFeedView.mediaInfo` uses it for you. Throws before
  /// [initialize].
  PlayStackMediaSession get mediaSession =>
      _mediaSession ?? (throw _notInitialized());

  /// Plays a video in a floating window outside the app.
  /// `PlayStackFeedView.pictureInPicture` uses it for you. Throws before
  /// [initialize].
  PlayStackPictureInPicture get pictureInPicture =>
      _pictureInPicture ?? (throw _notInitialized());

  /// The device's connection: offline, Wi-Fi, mobile data, metered, data
  /// saver. Feeds use it to preload less on mobile data; show it to the user
  /// if you like. [PlayStackNetworkStatus.unknown] before [initialize] and on
  /// engines that cannot tell (see
  /// [PlayStackPlatformCapabilities.supportsNetworkStatus]).
  @override
  ValueListenable<PlayStackNetworkStatus> get networkStatus => _network;

  /// The controller that is playing (the one that started most recently when
  /// several play), or null when nothing plays. Listen to it to show a mini
  /// player or to react to the playing video changing.
  ValueListenable<PlayStackPlayerController?> get activeController =>
      _coordinator.active;

  /// Starts the engine and sizes the player pool. Idempotent; concurrent
  /// calls share one initialization. A failed initialization can be retried.
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(
        const PlayStackException(
          PlayStackErrorCode.disposed,
          'This PlayStackManager was disposed.',
        ),
      );
    }
    return _initialization ??= _initialize().catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    final cache = config.cache;
    final audio = config.audio;
    final capabilities = await platform.initialize(
      PlayStackEngineConfig(
        cacheEnabled: cache.enabled,
        cacheMaxBytes: cache.maxBytes,
        handleAudioFocus: audio.handleAudioFocus,
        pauseOnAudioRouteLoss: audio.pauseOnAudioRouteLoss,
        audioSessionCategory: audio.iosAudioSessionCategory,
        mixWithOthers: audio.mixWithOthers,
        resumeAfterInterruption: audio.resumeAfterInterruption,
      ),
    );
    if (_disposed) return;
    _capabilities = capabilities;
    _cache = PlayStackCacheManager(platform, capabilities);
    _fullscreen = PlayStackFullscreenManager(platform, config.fullscreen);
    final mediaSession = _mediaSession = PlayStackMediaSession(platform);
    final pictureInPicture = _pictureInPicture = PlayStackPictureInPicture(
      platform,
    );
    _systemEvents = platform.systemEvents.listen((event) {
      mediaSession.handle(event);
      pictureInPicture.handle(event);
    }, onError: (Object _) {});
    final playerConfig = config.player;
    _pool = PlayStackPlayerPool(
      platform: platform,
      maxPlayers: config.pool.resolveMaxPlayers(capabilities),
      idleTimeout: config.pool.idleTimeout,
      adaptToDecoderFailures: config.pool.adaptToDecoderFailures,
      playerOptions: PlayStackNativePlayerOptions(
        looping: playerConfig.looping,
        volume: playerConfig.muted ? 0 : playerConfig.volume,
        playbackSpeed: playerConfig.playbackSpeed,
      ),
    );
    _events = platform.events.listen(
      _routeEvent,
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'playstack',
            context: ErrorDescription('while receiving player events'),
          ),
        );
      },
    );
    if (capabilities.supportsNetworkStatus) await _startNetworkStatus();
    _bindingObserver = _BindingObserver(
      onMemoryPressure: _onMemoryPressure,
      onLifecycle: _onLifecycle,
    )..attach();
  }

  /// Creates a controller for [source].
  ///
  /// Creating a controller is cheap and allocates no native resources; a
  /// native player is leased when the controller is initialized or played.
  /// [config] overrides [PlayStackConfig.player] for this controller.
  /// [startPosition] starts the video there instead of at the beginning (see
  /// [PlayStackPlayerController.startPosition]).
  PlayStackPlayerController createController(
    PlayStackSource source, {
    PlayStackPlayerConfig? config,
    Duration? startPosition,
  }) {
    if (_disposed) {
      throw const PlayStackException(
        PlayStackErrorCode.disposed,
        'This PlayStackManager was disposed.',
      );
    }
    if (_pool == null) throw _notInitialized();
    final controller = PlayStackPlayerController.internal(
      host: this,
      source: source,
      config: config ?? this.config.player,
    )..startPosition = startPosition;
    _controllers.add(controller);
    return controller;
  }

  /// Creates a feed of [items] whose controllers share this manager's pool.
  ///
  /// See [PlayStackFeedManager]. Call `setActiveIndex` once the first item is in
  /// view.
  PlayStackFeedManager createFeed(
    Iterable<PlayStackFeedItem> items, {
    PlayStackFeedConfig config = const PlayStackFeedConfig(),
  }) {
    if (_disposed) {
      throw const PlayStackException(
        PlayStackErrorCode.disposed,
        'This PlayStackManager was disposed.',
      );
    }
    if (_pool == null) throw _notInitialized();
    final feed = PlayStackFeedManager.internal(
      host: this,
      items: items.toList(),
      config: config,
    );
    _feeds.add(feed);
    return feed;
  }

  /// Pauses every playing controller of this manager, for example when a dialog opens.
  Future<void> pauseAll() async {
    await Future.wait([
      for (final controller in List<PlayStackPlayerController>.of(_controllers))
        if (controller.value.isPlaying) controller.pause(),
    ]);
  }

  /// Destroys native players that no controller uses right now, to free
  /// memory at once instead of waiting for [PlayStackPoolConfig.idleTimeout].
  Future<void> trimIdlePlayers() => _pool?.trimIdle() ?? Future<void>.value();

  /// Disposes every controller and native player. Safe to call more than
  /// once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindingObserver?.detach();
    _bindingObserver = null;
    _pausedByLifecycle.clear();
    unawaited(_systemEvents?.cancel());
    _systemEvents = null;
    try {
      await _mediaSession?.clear();
      await _pictureInPicture?.disable();
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while removing the media controls');
    }
    _mediaSession?.dispose();
    _pictureInPicture?.dispose();
    try {
      await _fullscreen?.dispose();
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while leaving fullscreen');
    }
    for (final feed in List<PlayStackFeedManager>.of(_feeds)) {
      feed.dispose();
    }
    // Not awaited: a cancelled broadcast subscription completes with a
    // root-zone future, and nothing depends on it.
    unawaited(_networkEvents?.cancel());
    _networkEvents = null;
    await Future.wait(
      List<PlayStackPlayerController>.of(_controllers).map((c) => c.dispose()),
    );
    await _pool?.dispose();
    unawaited(_events?.cancel());
    _events = null;
    _coordinator.dispose();
    _network.dispose();
  }

  Future<void> _startNetworkStatus() async {
    try {
      _network.value = await platform.getNetworkStatus();
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while reading the network status');
    }
    _networkEvents = platform.networkStatusChanges.listen(
      (status) {
        if (_disposed) return;
        final reconnected = status.isConnected && !_network.value.isConnected;
        _network.value = status;
        if (reconnected) _retryAfterReconnection();
      },
      onError: (Object error, StackTrace stack) =>
          _reportError(error, stack, 'while monitoring the network'),
    );
  }

  /// Controllers that failed for lack of network prepare again (and resume
  /// where they failed) once the network is back.
  void _retryAfterReconnection() {
    for (final controller in List<PlayStackPlayerController>.of(_controllers)) {
      final error = controller.value.error;
      if (!controller.value.hasError || error == null) continue;
      if (error.code != PlayStackErrorCode.network &&
          error.code != PlayStackErrorCode.timeout) {
        continue;
      }
      unawaited(controller.retry().catchError((Object _) {}));
    }
  }

  void _reportError(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'playstack',
        context: ErrorDescription(context),
      ),
    );
  }

  @override
  @internal
  PlayStackPlayerController createFeedController(
    PlayStackSource source,
    PlayStackPlayerConfig? config,
  ) => createController(source, config: config);

  @override
  @internal
  int get maxPlayers => pool.maxPlayers;

  @override
  @internal
  bool get exclusivePlayback => config.exclusivePlayback;

  @override
  @internal
  void feedDisposed(PlayStackFeedManager feed) => _feeds.remove(feed);

  @override
  @internal
  void controllerDisposed(PlayStackPlayerController controller) {
    _controllers.remove(controller);
    _pausedByLifecycle.remove(controller);
    if (!_disposed) _coordinator.controllerDisposed(controller);
  }

  @override
  @internal
  void playRequested(PlayStackPlayerController controller) {
    // A play request supersedes resuming after the app returns.
    _pausedByLifecycle.remove(controller);
    _coordinator.playRequested(controller, _controllers);
  }

  @override
  @internal
  bool mayStartPlayback(PlayStackPlayerController controller) =>
      _coordinator.mayStartPlayback(controller);

  @override
  @internal
  void playingChanged(PlayStackPlayerController controller, bool isPlaying) {
    if (!_disposed) _coordinator.playingChanged(controller, isPlaying);
  }

  void _routeEvent(PlayStackPlatformEvent event) {
    final owner = _pool?.ownerOf(event.playerId);
    if (owner is PlayStackPlayerController) owner.handlePlatformEvent(event);
  }

  /// Destroys idle native players and takes the players of
  /// [PlayStackPlayerPriority.background] controllers, which by definition are
  /// kept only while nothing else needs them.
  void _onMemoryPressure() {
    for (final feed in List<PlayStackFeedManager>.of(_feeds)) {
      feed.handleMemoryPressure();
    }
    unawaited(_releaseForMemory().catchError(_reportMemoryError));
  }

  Future<void> _releaseForMemory() async {
    await Future.wait([
      for (final controller in List<PlayStackPlayerController>.of(_controllers))
        if (controller.priority == PlayStackPlayerPriority.background &&
            controller.value.isAttached)
          controller.release(),
    ]);
    // After the releases, so their players are destroyed too.
    await trimIdlePlayers();
  }

  void _reportMemoryError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'playstack',
        context: ErrorDescription('while reacting to memory pressure'),
      ),
    );
  }

  void _onLifecycle(AppLifecycleState state) {
    final lifecycle = config.lifecycle;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!lifecycle.pauseOnBackground) return;
        for (final controller in List<PlayStackPlayerController>.of(
          _controllers,
        )) {
          if (!controller.value.isPlaying) continue;
          // Background audio and the floating window keep playing.
          if ((_mediaSession?.keepsPlaying(controller) ?? false) ||
              (_pictureInPicture?.keepsPlaying(controller) ?? false)) {
            continue;
          }
          _pausedByLifecycle.add(controller);
          unawaited(controller.pause().catchError(_reportLifecycleError));
        }
      case AppLifecycleState.resumed:
        final toResume = List<PlayStackPlayerController>.of(_pausedByLifecycle);
        _pausedByLifecycle.clear();
        if (!lifecycle.resumeOnForeground) return;
        for (final controller in toResume) {
          if (controller.isDisposed) continue;
          unawaited(controller.play().catchError(_reportLifecycleError));
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _reportLifecycleError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'playstack',
        context: ErrorDescription('while applying the app lifecycle'),
      ),
    );
  }

  PlayStackException _notInitialized() => const PlayStackException(
    PlayStackErrorCode.notInitialized,
    'Call and await PlayStackManager.initialize() first.',
  );
}

/// Forwards memory pressure and app lifecycle changes to the manager.
class _BindingObserver with WidgetsBindingObserver {
  _BindingObserver({required this.onMemoryPressure, required this.onLifecycle});

  final VoidCallback onMemoryPressure;
  final void Function(AppLifecycleState state) onLifecycle;
  bool _attached = false;

  void attach() {
    // The binding may be absent in pure Dart contexts such as isolates.
    final binding = _bindingOrNull();
    if (binding == null) return;
    binding.addObserver(this);
    _attached = true;
  }

  void detach() {
    if (!_attached) return;
    _bindingOrNull()?.removeObserver(this);
    _attached = false;
  }

  static WidgetsBinding? _bindingOrNull() {
    try {
      return WidgetsBinding.instance;
    } on Object {
      return null;
    }
  }

  @override
  void didHaveMemoryPressure() => onMemoryPressure();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      onLifecycle(state);
}
