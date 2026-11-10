import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../config/reel_kit_config.dart';
import '../controller/reel_player_controller.dart';
import '../pool/reel_player_pool.dart';

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
class ReelKitManager implements ReelControllerHost {
  ReelKitManager({
    this.config = const ReelKitConfig(),
    @visibleForTesting ReelKitPlatform? platform,
  }) : _platformOverride = platform;

  final ReelKitConfig config;
  final ReelKitPlatform? _platformOverride;
  final Set<ReelPlayerController> _controllers = <ReelPlayerController>{};

  Future<void>? _initialization;
  ReelPlatformCapabilities? _capabilities;
  ReelPlayerPool? _pool;
  StreamSubscription<ReelPlatformEvent>? _events;
  _MemoryPressureObserver? _memoryObserver;
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

  bool get isDisposed => _disposed;

  /// Engine and device capabilities. Available after [initialize].
  ReelPlatformCapabilities get capabilities =>
      _capabilities ?? (throw _notInitialized());

  /// Pool usage snapshot. Available after [initialize].
  ReelPoolStats get poolStats => pool.stats;

  /// Controllers created by this manager that are not disposed.
  List<ReelPlayerController> get controllers =>
      List<ReelPlayerController>.unmodifiable(_controllers);

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
    final capabilities = await platform.initialize();
    if (_disposed) return;
    _capabilities = capabilities;
    final playerConfig = config.player;
    _pool = ReelPlayerPool(
      platform: platform,
      maxPlayers: config.pool.resolveMaxPlayers(capabilities),
      idleTimeout: config.pool.idleTimeout,
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
    _memoryObserver = _MemoryPressureObserver(_onMemoryPressure)..attach();
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

  /// Destroys native players that are not assigned to any controller.
  Future<void> trimIdlePlayers() => _pool?.trimIdle() ?? Future<void>.value();

  /// Disposes every controller and native player. Safe to call more than
  /// once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _memoryObserver?.detach();
    _memoryObserver = null;
    await Future.wait(
      List<ReelPlayerController>.of(_controllers).map((c) => c.dispose()),
    );
    await _pool?.dispose();
    await _events?.cancel();
    _events = null;
  }

  @override
  @internal
  void controllerDisposed(ReelPlayerController controller) {
    _controllers.remove(controller);
  }

  void _routeEvent(ReelPlatformEvent event) {
    final owner = _pool?.ownerOf(event.playerId);
    if (owner is ReelPlayerController) owner.handlePlatformEvent(event);
  }

  void _onMemoryPressure() {
    unawaited(trimIdlePlayers());
  }

  ReelKitException _notInitialized() => const ReelKitException(
    ReelKitErrorCode.notInitialized,
    'Call and await ReelKitManager.initialize() first.',
  );
}

/// Destroys idle native players when the OS reports memory pressure.
class _MemoryPressureObserver with WidgetsBindingObserver {
  _MemoryPressureObserver(this._onPressure);

  final VoidCallback _onPressure;
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
  void didHaveMemoryPressure() => _onPressure();
}
