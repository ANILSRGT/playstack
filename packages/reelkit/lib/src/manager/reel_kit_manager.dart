import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../cache/reel_cache_manager.dart';
import '../config/reel_kit_config.dart';
import '../controller/reel_player_controller.dart';
import '../feed/reel_feed_config.dart';
import '../feed/reel_feed_item.dart';
import '../feed/reel_feed_manager.dart';
import '../fullscreen/reel_fullscreen_manager.dart';
import '../pool/reel_player_pool.dart';
import 'reel_playback_coordinator.dart';

/// Entry point of ReelKit: owns the playback engine, the native player pool
/// and every controller created through it.
///
/// ```dart
/// final manager = ReelKitManager();
/// await manager.initialize();
/// final controller = manager.createController(
///   ReelSource.network('https://example.com/video.mp4'),
/// );
/// await controller.play();
/// // ...
/// await manager.dispose(); // disposes all controllers and native players
/// ```
///
/// Use one manager per independent playback context (for example one per
/// feed). Each manager has its own pool limit.
class ReelKitManager implements ReelControllerHost, ReelFeedHost {
  /// Creates a manager. Call [initialize] before creating controllers.
  ReelKitManager({
    this.config = const ReelKitConfig(),
    @visibleForTesting ReelKitPlatform? platform,
  }) : _platformOverride = platform,
       _coordinator = ReelPlaybackCoordinator(
         exclusive: config.exclusivePlayback,
       );

  /// Configuration of this manager, its pool and its controllers.
  final ReelKitConfig config;
  final ReelKitPlatform? _platformOverride;
  final Set<ReelPlayerController> _controllers = <ReelPlayerController>{};
  final ReelPlaybackCoordinator _coordinator;
  final Set<ReelFeedManager> _feeds = <ReelFeedManager>{};
  final ValueNotifier<ReelNetworkStatus> _network =
      ValueNotifier<ReelNetworkStatus>(ReelNetworkStatus.unknown);
  StreamSubscription<ReelNetworkStatus>? _networkEvents;
  ReelCacheManager? _cache;
  ReelFullscreenManager? _fullscreen;

  Future<void>? _initialization;
  ReelPlatformCapabilities? _capabilities;
  ReelPlayerPool? _pool;
  StreamSubscription<ReelPlatformEvent>? _events;
  _BindingObserver? _bindingObserver;
  final Set<ReelPlayerController> _pausedByLifecycle = <ReelPlayerController>{};
  bool _disposed = false;

  @override
  @internal
  ReelKitPlatform get platform => _platformOverride ?? ReelKitPlatform.instance;

  @override
  @internal
  ReelPlayerPool get pool {
    final pool = _pool;
    if (pool == null) throw _notInitialized();
    return pool;
  }

  /// Whether [initialize] completed successfully.
  bool get isInitialized => _pool != null && !_disposed;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  /// Engine and device capabilities. Available after [initialize].
  @override
  ReelPlatformCapabilities get capabilities =>
      _capabilities ?? (throw _notInitialized());

  /// Pool usage snapshot. Available after [initialize].
  ReelPoolStats get poolStats => pool.stats;

  /// Controllers created by this manager that are not disposed.
  List<ReelPlayerController> get controllers =>
      List<ReelPlayerController>.unmodifiable(_controllers);

  /// The engine's disk cache. Available after [initialize].
  ReelCacheManager get cache => _cache ?? (throw _notInitialized());

  /// Fullscreen and orientation coordination. Available after [initialize].
  ReelFullscreenManager get fullscreen =>
      _fullscreen ?? (throw _notInitialized());

  /// Connectivity reported by the engine. [ReelNetworkStatus.unknown] on
  /// engines without network status (see
  /// [ReelPlatformCapabilities.supportsNetworkStatus]) and before
  /// [initialize].
  @override
  ValueListenable<ReelNetworkStatus> get networkStatus => _network;

  /// The playing controller that started most recently, or null when none
  /// plays. With exclusive playback this is the only playing controller.
  ValueListenable<ReelPlayerController?> get activeController =>
      _coordinator.active;

  /// Starts the engine and sizes the player pool. Idempotent; concurrent
  /// calls share one initialization. A failed initialization can be retried.
  Future<void> initialize() {
    if (_disposed) {
      return Future<void>.error(
        const ReelKitException(
          ReelKitErrorCode.disposed,
          'This ReelKitManager was disposed.',
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
      ReelEngineConfig(
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
    _cache = ReelCacheManager(platform, capabilities);
    _fullscreen = ReelFullscreenManager(platform, config.fullscreen);
    final playerConfig = config.player;
    _pool = ReelPlayerPool(
      platform: platform,
      maxPlayers: config.pool.resolveMaxPlayers(capabilities),
      idleTimeout: config.pool.idleTimeout,
      adaptToDecoderFailures: config.pool.adaptToDecoderFailures,
      playerOptions: ReelNativePlayerOptions(
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
            library: 'reelkit',
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
  /// [config] overrides [ReelKitConfig.player] for this controller.
  ReelPlayerController createController(
    ReelSource source, {
    ReelPlayerConfig? config,
  }) {
    if (_disposed) {
      throw const ReelKitException(
        ReelKitErrorCode.disposed,
        'This ReelKitManager was disposed.',
      );
    }
    if (_pool == null) throw _notInitialized();
    final controller = ReelPlayerController.internal(
      host: this,
      source: source,
      config: config ?? this.config.player,
    );
    _controllers.add(controller);
    return controller;
  }

  /// Creates a feed of [items] whose controllers share this manager's pool.
  ///
  /// See [ReelFeedManager]. Call `setActiveIndex` once the first item is in
  /// view.
  ReelFeedManager createFeed(
    Iterable<ReelFeedItem> items, {
    ReelFeedConfig config = const ReelFeedConfig(),
  }) {
    if (_disposed) {
      throw const ReelKitException(
        ReelKitErrorCode.disposed,
        'This ReelKitManager was disposed.',
      );
    }
    if (_pool == null) throw _notInitialized();
    final feed = ReelFeedManager.internal(
      host: this,
      items: items.toList(),
      config: config,
    );
    _feeds.add(feed);
    return feed;
  }

  /// Pauses every playing controller of this manager.
  Future<void> pauseAll() async {
    await Future.wait([
      for (final controller in List<ReelPlayerController>.of(_controllers))
        if (controller.value.isPlaying) controller.pause(),
    ]);
  }

  /// Destroys native players that are not assigned to any controller.
  Future<void> trimIdlePlayers() => _pool?.trimIdle() ?? Future<void>.value();

  /// Disposes every controller and native player. Safe to call more than
  /// once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bindingObserver?.detach();
    _bindingObserver = null;
    _pausedByLifecycle.clear();
    try {
      await _fullscreen?.dispose();
    } on Object catch (error, stack) {
      _reportError(error, stack, 'while leaving fullscreen');
    }
    for (final feed in List<ReelFeedManager>.of(_feeds)) {
      feed.dispose();
    }
    // Not awaited: a cancelled broadcast subscription completes with a
    // root-zone future, and nothing depends on it.
    unawaited(_networkEvents?.cancel());
    _networkEvents = null;
    await Future.wait(
      List<ReelPlayerController>.of(_controllers).map((c) => c.dispose()),
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
    for (final controller in List<ReelPlayerController>.of(_controllers)) {
      final error = controller.value.error;
      if (!controller.value.hasError || error == null) continue;
      if (error.code != ReelKitErrorCode.network &&
          error.code != ReelKitErrorCode.timeout) {
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
        library: 'reelkit',
        context: ErrorDescription(context),
      ),
    );
  }

  @override
  @internal
  ReelPlayerController createFeedController(
    ReelSource source,
    ReelPlayerConfig? config,
  ) => createController(source, config: config);

  @override
  @internal
  int get maxPlayers => pool.maxPlayers;

  @override
  @internal
  bool get exclusivePlayback => config.exclusivePlayback;

  @override
  @internal
  void feedDisposed(ReelFeedManager feed) => _feeds.remove(feed);

  @override
  @internal
  void controllerDisposed(ReelPlayerController controller) {
    _controllers.remove(controller);
    _pausedByLifecycle.remove(controller);
    if (!_disposed) _coordinator.controllerDisposed(controller);
  }

  @override
  @internal
  void playRequested(ReelPlayerController controller) {
    // A play request supersedes resuming after the app returns.
    _pausedByLifecycle.remove(controller);
    _coordinator.playRequested(controller, _controllers);
  }

  @override
  @internal
  bool mayStartPlayback(ReelPlayerController controller) =>
      _coordinator.mayStartPlayback(controller);

  @override
  @internal
  void playingChanged(ReelPlayerController controller, bool isPlaying) {
    if (!_disposed) _coordinator.playingChanged(controller, isPlaying);
  }

  void _routeEvent(ReelPlatformEvent event) {
    final owner = _pool?.ownerOf(event.playerId);
    if (owner is ReelPlayerController) owner.handlePlatformEvent(event);
  }

  /// Destroys idle native players and takes the players of
  /// [ReelPlayerPriority.background] controllers, which by definition are
  /// kept only while nothing else needs them.
  void _onMemoryPressure() {
    for (final feed in List<ReelFeedManager>.of(_feeds)) {
      feed.handleMemoryPressure();
    }
    unawaited(_releaseForMemory().catchError(_reportMemoryError));
  }

  Future<void> _releaseForMemory() async {
    await Future.wait([
      for (final controller in List<ReelPlayerController>.of(_controllers))
        if (controller.priority == ReelPlayerPriority.background &&
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
        library: 'reelkit',
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
        for (final controller in List<ReelPlayerController>.of(_controllers)) {
          if (!controller.value.isPlaying) continue;
          _pausedByLifecycle.add(controller);
          unawaited(controller.pause().catchError(_reportLifecycleError));
        }
      case AppLifecycleState.resumed:
        final toResume = List<ReelPlayerController>.of(_pausedByLifecycle);
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
        library: 'reelkit',
        context: ErrorDescription('while applying the app lifecycle'),
      ),
    );
  }

  ReelKitException _notInitialized() => const ReelKitException(
    ReelKitErrorCode.notInitialized,
    'Call and await ReelKitManager.initialize() first.',
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
