import 'dart:async';

import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import '../controller/reel_player_controller.dart';
import '../util/async_lock.dart';

/// Orientation while fullscreen.
enum ReelFullscreenOrientation {
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
/// ReelKit restores what it is told here. Keep it in sync with
/// [ReelFullscreenManager.setAppPolicy] if the app changes its policy at run
/// time (for example per route).
@immutable
class ReelFullscreenConfig {
  /// Creates a fullscreen configuration.
  const ReelFullscreenConfig({
    this.appOrientations = const <DeviceOrientation>[],
    this.appSystemUiMode = SystemUiMode.edgeToEdge,
    this.appOverlays,
    this.fullscreenSystemUiMode = SystemUiMode.immersiveSticky,
  });

  /// The orientations your app allows outside fullscreen; ReelKit restores
  /// them when fullscreen ends. Set the same list you pass to
  /// `SystemChrome.setPreferredOrientations`, for example
  /// `[DeviceOrientation.portraitUp]` for a portrait-only app.
  ///
  /// Empty (the default) means every orientation the app declares. Leaving a
  /// landscape fullscreen then unlocks rotation, and the screen follows the
  /// device: it stays sideways while the phone is held sideways.
  /// `ReelKitConfig.reels` sets `[DeviceOrientation.portraitUp]`.
  final List<DeviceOrientation> appOrientations;

  /// System UI mode outside fullscreen.
  final SystemUiMode appSystemUiMode;

  /// Overlays when [appSystemUiMode] is [SystemUiMode.manual].
  final List<SystemUiOverlay>? appOverlays;

  /// System UI mode while fullscreen (mobile).
  final SystemUiMode fullscreenSystemUiMode;

  @override
  bool operator ==(Object other) =>
      other is ReelFullscreenConfig &&
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
/// ReelKit does not build a fullscreen route: the app shows its own
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
class ReelFullscreenManager {
  /// Creates a fullscreen manager. Applications use
  /// `ReelKitManager.fullscreen` instead of constructing one.
  ReelFullscreenManager(this._platform, ReelFullscreenConfig config)
    : _policy = config {
    Stream<bool> changes;
    try {
      changes = _platform.fullscreenChanges;
    } on UnimplementedError {
      changes = const Stream<bool>.empty();
    }
    _external = changes.listen((fullscreen) {
      if (!fullscreen && _isFullscreen.value) {
        // Left outside ReelKit (Escape in a browser).
        _isFullscreen.value = false;
        _changedOrientations = false;
      }
    }, onError: (Object _) {});
  }

  final ReelKitPlatform _platform;
  ReelFullscreenConfig _policy;
  final ValueNotifier<bool> _isFullscreen = ValueNotifier<bool>(false);
  StreamSubscription<bool>? _external;
  List<DeviceOrientation>? _previousOrientations;
  bool _changedOrientations = false;
  final AsyncLock _lock = AsyncLock();

  /// Whether fullscreen is active.
  ValueListenable<bool> get isFullscreen => _isFullscreen;

  /// The policy restored on [exit].
  ReelFullscreenConfig get appPolicy => _policy;

  /// Registers the app's current orientation and system UI policy, restored
  /// on [exit]. Call it when the app changes its own policy.
  void setAppPolicy(ReelFullscreenConfig policy) => _policy = policy;

  /// Enters fullscreen. With [ReelFullscreenOrientation.keepCurrent] (the
  /// default) the orientation is not changed. Calls while fullscreen only
  /// change the orientation. Enter and exit calls run in order.
  Future<void> enter({
    ReelFullscreenOrientation orientation =
        ReelFullscreenOrientation.keepCurrent,
    ReelPlayerController? controller,
  }) => _serial(() async {
    final orientations = _orientationsFor(orientation, controller);
    if (!_isFullscreen.value) _previousOrientations = _currentOrientations();
    await _platform.enterFullscreen(
      ReelFullscreenRequest(
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
      ReelFullscreenRestore(
        orientations: policy.appOrientations,
        systemUiMode: policy.appSystemUiMode,
        overlays: policy.appOverlays,
        previousOrientations: _previousOrientations,
        changedOrientations: _changedOrientations,
      ),
    );
    _changedOrientations = false;
    _previousOrientations = null;
    _isFullscreen.value = false;
  });

  /// Leaves fullscreen if needed and stops listening.
  Future<void> dispose() async {
    await exit();
    // Not awaited: cancelling may complete with a root-zone future.
    unawaited(_external?.cancel());
    _external = null;
    _isFullscreen.dispose();
  }

  Future<void> _serial(Future<void> Function() action) =>
      _lock.synchronized(action);

  List<DeviceOrientation>? _orientationsFor(
    ReelFullscreenOrientation orientation,
    ReelPlayerController? controller,
  ) {
    switch (orientation) {
      case ReelFullscreenOrientation.keepCurrent:
        return null;
      case ReelFullscreenOrientation.landscape:
        return const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case ReelFullscreenOrientation.portrait:
        return const [DeviceOrientation.portraitUp];
      case ReelFullscreenOrientation.matchVideo:
        final ratio = controller?.value.aspectRatio;
        if (ratio == null || (ratio - 1).abs() < 0.01) return null;
        return _orientationsFor(
          ratio > 1
              ? ReelFullscreenOrientation.landscape
              : ReelFullscreenOrientation.portrait,
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
