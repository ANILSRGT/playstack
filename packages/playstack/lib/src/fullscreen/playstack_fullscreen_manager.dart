import 'dart:async';

import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_player_controller.dart';
import '../util/async_lock.dart';

/// Orientation while fullscreen.
enum PlayStackFullscreenOrientation {
  /// Do not touch the orientation policy (default).
  keepCurrent,

  /// Allow both landscape orientations.
  landscape,

  /// Allow portrait up.
  portrait,

  /// Landscape for wide videos, portrait for tall ones, unchanged for square
  /// or unknown sizes. Needs a controller.
  matchVideo,
}

/// The application's own system UI policy, restored after fullscreen.
///
/// Flutter cannot read the orientations or system UI mode an app set, so
/// PlayStack restores what it is told here. Keep it in sync with
/// [PlayStackFullscreenManager.setAppPolicy] if the app changes its policy at run
/// time (for example per route).
@immutable
class PlayStackFullscreenConfig {
  /// Creates a fullscreen configuration.
  const PlayStackFullscreenConfig({
    this.appOrientations = const <DeviceOrientation>[],
    this.appSystemUiMode = SystemUiMode.edgeToEdge,
    this.appOverlays,
    this.fullscreenSystemUiMode = SystemUiMode.immersiveSticky,
  });

  /// The orientations your app allows outside fullscreen; PlayStack restores
  /// them when fullscreen ends. Set the same list you pass to
  /// `SystemChrome.setPreferredOrientations`, for example
  /// `[DeviceOrientation.portraitUp]` for a portrait-only app.
  ///
  /// Empty (the default) restores what the app allowed when fullscreen
  /// began. On Android and iOS PlayStack reads it from the platform, so a
  /// lock set with `SystemChrome.setPreferredOrientations` comes back
  /// without configuration; elsewhere empty means every orientation the app
  /// declares. `PlayStackConfig.reels` takes the list as `appOrientations`.
  final List<DeviceOrientation> appOrientations;

  /// System UI mode outside fullscreen.
  final SystemUiMode appSystemUiMode;

  /// Overlays when [appSystemUiMode] is [SystemUiMode.manual].
  final List<SystemUiOverlay>? appOverlays;

  /// System UI mode while fullscreen (mobile).
  final SystemUiMode fullscreenSystemUiMode;

  @override
  bool operator ==(Object other) =>
      other is PlayStackFullscreenConfig &&
      listEquals(other.appOrientations, appOrientations) &&
      other.appSystemUiMode == appSystemUiMode &&
      listEquals(other.appOverlays, appOverlays) &&
      other.fullscreenSystemUiMode == fullscreenSystemUiMode;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(appOrientations),
    appSystemUiMode,
    appOverlays == null ? null : Object.hashAll(appOverlays!),
    fullscreenSystemUiMode,
  );
}

/// Enters and leaves fullscreen without leaving the app's orientation or
/// system UI changed.
///
/// PlayStack does not build a fullscreen route: the app shows its own
/// fullscreen UI (a route, an overlay) and calls [enter] and [exit] around
/// it. On Android and iOS this hides the system bars and optionally locks
/// the orientation; on exit the bars come back, the interface is rotated
/// back to the orientation it had before, and the app's registered policy
/// is restored. On web it uses the browser Fullscreen API, which needs a
/// user gesture, and listens for the user leaving with Escape; orientation
/// locking works only where the browser allows it (mostly Chrome on
/// Android) and is otherwise ignored.
///
/// System UI is global, so use one fullscreen manager at a time.
class PlayStackFullscreenManager {
  /// Creates a fullscreen manager. Applications use
  /// `PlayStackManager.fullscreen` instead of constructing one.
  PlayStackFullscreenManager(this._platform, PlayStackFullscreenConfig config)
    : _policy = config {
    Stream<bool> changes;
    try {
      changes = _platform.fullscreenChanges;
    } on UnimplementedError {
      changes = const Stream<bool>.empty();
    }
    _external = changes.listen((fullscreen) {
      if (!fullscreen && _isFullscreen.value) {
        // Left outside PlayStack (Escape in a browser).
        _isFullscreen.value = false;
        _changedOrientations = false;
      }
    }, onError: (Object _) {});
    try {
      _sensor = _platform.deviceOrientationChanges;
    } on UnimplementedError {
      _sensor = null;
    }
  }

  final PlayStackPlatform _platform;
  PlayStackFullscreenConfig _policy;
  final ValueNotifier<bool> _isFullscreen = ValueNotifier<bool>(false);
  StreamSubscription<bool>? _external;
  List<DeviceOrientation>? _previousOrientations;
  bool _changedOrientations = false;
  final AsyncLock _lock = AsyncLock();
  List<DeviceOrientation>? _appOrientationsBefore;

  // Device orientation from the sensors, read only while listened to and
  // while the app is in the foreground.
  Stream<DeviceOrientation>? _sensor;
  StreamSubscription<DeviceOrientation>? _sensorSubscription;
  AppLifecycleListener? _lifecycle;
  DeviceOrientation? _deviceOrientation;
  late final StreamController<DeviceOrientation> _deviceOrientations =
      StreamController<DeviceOrientation>.broadcast(
        onListen: _startSensor,
        onCancel: _stopSensor,
      );

  /// How the user holds the device, from its motion sensors, also while the
  /// app is locked to one orientation. Null where the platform has no such
  /// sensor (web): follow the interface's orientation there.
  ///
  /// The sensors run only while this stream has a listener and the app is
  /// in the foreground. Nothing is reported while the user locked rotation
  /// in the system settings.
  Stream<DeviceOrientation>? get deviceOrientationChanges =>
      _sensor == null ? null : _deviceOrientations.stream;

  /// The last orientation [deviceOrientationChanges] reported, or null
  /// before it reported one.
  DeviceOrientation? get deviceOrientation => _deviceOrientation;

  void _startSensor() {
    try {
      _lifecycle ??= AppLifecycleListener(onStateChange: _onLifecycle);
    } on Object {
      // No binding, for example in pure Dart tests.
    }
    _subscribeSensor();
  }

  void _subscribeSensor() {
    final sensor = _sensor;
    if (sensor == null || _sensorSubscription != null) return;
    _sensorSubscription = sensor.listen((orientation) {
      if (orientation == _deviceOrientation) return;
      _deviceOrientation = orientation;
      _deviceOrientations.add(orientation);
    }, onError: (Object _) {});
  }

  void _stopSensor() {
    unawaited(_sensorSubscription?.cancel());
    _sensorSubscription = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _onLifecycle(AppLifecycleState state) {
    if (!_deviceOrientations.hasListener) return;
    if (state == AppLifecycleState.resumed) {
      _subscribeSensor();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_sensorSubscription?.cancel());
      _sensorSubscription = null;
    }
  }

  /// Whether fullscreen is active.
  ValueListenable<bool> get isFullscreen => _isFullscreen;

  /// The policy restored on [exit].
  PlayStackFullscreenConfig get appPolicy => _policy;

  /// Registers the app's current orientation and system UI policy, restored
  /// on [exit]. Call it when the app changes its own policy.
  void setAppPolicy(PlayStackFullscreenConfig policy) => _policy = policy;

  /// Enters fullscreen. With [PlayStackFullscreenOrientation.keepCurrent] (the
  /// default) the orientation is not changed. Calls while fullscreen only
  /// change the orientation. Enter and exit calls run in order.
  Future<void> enter({
    PlayStackFullscreenOrientation orientation =
        PlayStackFullscreenOrientation.keepCurrent,
    PlayStackPlayerController? controller,
  }) => _serial(() async {
    final orientations = _orientationsFor(orientation, controller);
    if (!_isFullscreen.value) {
      _previousOrientations = _currentOrientations();
      try {
        _appOrientationsBefore = await _platform.getAppOrientations();
      } on Object {
        _appOrientationsBefore = null;
      }
    }
    await _platform.enterFullscreen(
      PlayStackFullscreenRequest(
        orientations: orientations,
        systemUiMode: _policy.fullscreenSystemUiMode,
      ),
    );
    if (orientations != null) _changedOrientations = true;
    _isFullscreen.value = true;
  });

  /// Leaves fullscreen and restores the app policy. Does nothing when not
  /// fullscreen.
  Future<void> exit() => _serial(() async {
    if (!_isFullscreen.value) return;
    final policy = _policy;
    await _platform.exitFullscreen(
      PlayStackFullscreenRestore(
        orientations: policy.appOrientations.isNotEmpty
            ? policy.appOrientations
            : _appOrientationsBefore ?? const [],
        systemUiMode: policy.appSystemUiMode,
        overlays: policy.appOverlays,
        previousOrientations: _previousOrientations,
        changedOrientations: _changedOrientations,
      ),
    );
    _changedOrientations = false;
    _previousOrientations = null;
    _appOrientationsBefore = null;
    _isFullscreen.value = false;
  });

  /// Leaves fullscreen if needed and stops listening.
  Future<void> dispose() async {
    await exit();
    // Not awaited: cancelling may complete with a root-zone future.
    unawaited(_external?.cancel());
    _external = null;
    _stopSensor();
    unawaited(_deviceOrientations.close());
    _isFullscreen.dispose();
  }

  Future<void> _serial(Future<void> Function() action) =>
      _lock.synchronized(action);

  List<DeviceOrientation>? _orientationsFor(
    PlayStackFullscreenOrientation orientation,
    PlayStackPlayerController? controller,
  ) {
    switch (orientation) {
      case PlayStackFullscreenOrientation.keepCurrent:
        return null;
      case PlayStackFullscreenOrientation.landscape:
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case PlayStackFullscreenOrientation.portrait:
        return const [DeviceOrientation.portraitUp];
      case PlayStackFullscreenOrientation.matchVideo:
        final ratio = controller?.value.aspectRatio;
        if (ratio == null || (ratio - 1).abs() < 0.01) return null;
        return _orientationsFor(
          ratio > 1
              ? PlayStackFullscreenOrientation.landscape
              : PlayStackFullscreenOrientation.portrait,
          null,
        );
    }
  }

  /// The orientation of the app's view right now, as far as Flutter can
  /// tell (portrait vs landscape; the exact side is left to the system).
  static List<DeviceOrientation>? _currentOrientations() {
    final Iterable<FlutterView> views;
    try {
      views = WidgetsBinding.instance.platformDispatcher.views;
    } on Object {
      return null; // No binding, for example in pure Dart tests.
    }
    if (views.isEmpty) return null;
    final size = views.first.physicalSize;
    if (size.isEmpty) return null;
    return size.height >= size.width
        ? const [DeviceOrientation.portraitUp]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ];
  }
}
