import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_player_controller.dart';

/// Shows a video in the system's media controls: the lock screen, the
/// notification shade (Android), Control Center (iOS), headphone buttons
/// and cars. The video also keeps playing while the app is in the
/// background, so the user can listen to it.
///
/// One video at a time; showing another replaces it. Use it through
/// `PlayStackManager.mediaSession`, or let `PlayStackFeedView.mediaInfo` do
/// it for the video in view.
///
/// ```dart
/// await manager.mediaSession.show(
///   controller,
///   const PlayStackMediaInfo(title: 'Episode 3', artist: 'Coastline'),
/// );
/// ```
///
/// Play, pause and the position bar of the controls act on the controller;
/// the skip buttons appear when [show] gets `onNext` or `onPrevious`.
///
/// Background audio needs platform setup: on iOS the `audio` background
/// mode in `Info.plist`; on Android the media service declared in the app's
/// manifest (see the background playback guide). Without it the controls
/// still work while the app is open.
class PlayStackMediaSession {
  /// Creates the session of a manager. Apps use
  /// `PlayStackManager.mediaSession` instead of constructing one.
  @internal
  PlayStackMediaSession(this._platform);

  final PlayStackPlatform _platform;
  PlayStackPlayerController? _controller;
  PlayStackMediaInfo? _info;
  VoidCallback? _onNext;
  VoidCallback? _onPrevious;
  int? _sentPlayerId;
  bool _sent = false;

  /// The video shown in the media controls, or null.
  PlayStackPlayerController? get controller => _controller;

  /// What the controls show about [controller].
  PlayStackMediaInfo? get info => _info;

  /// Shows [controller] in the system's media controls with [info], and
  /// keeps it playing while the app is in the background. [onNext] and
  /// [onPrevious] add skip buttons, for example to move a feed.
  Future<void> show(
    PlayStackPlayerController controller,
    PlayStackMediaInfo info, {
    VoidCallback? onNext,
    VoidCallback? onPrevious,
  }) async {
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onControllerChanged);
      controller.addListener(_onControllerChanged);
      _sentPlayerId = null;
    }
    final changed =
        !identical(controller, _controller) ||
        info != _info ||
        (onNext == null) != (_onNext == null) ||
        (onPrevious == null) != (_onPrevious == null);
    _controller = controller;
    _info = info;
    _onNext = onNext;
    _onPrevious = onPrevious;
    if (changed || !_sent) await _send();
  }

  /// Removes the media controls; the video no longer plays in the
  /// background.
  Future<void> clear() async {
    _controller?.removeListener(_onControllerChanged);
    _controller = null;
    _info = null;
    _onNext = null;
    _onPrevious = null;
    _sentPlayerId = null;
    if (!_sent) return;
    _sent = false;
    await _platform.setMediaSession(null, null);
  }

  /// Whether [controller] keeps playing while the app is in the background.
  @internal
  bool keepsPlaying(PlayStackPlayerController controller) =>
      identical(controller, _controller);

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.isDisposed) {
      unawaited(clear().catchError(_report));
      return;
    }
    // The controller moved to another native player (pool reuse).
    if (controller.nativePlayerId != _sentPlayerId) {
      unawaited(_send().catchError(_report));
    }
  }

  Future<void> _send() async {
    final controller = _controller;
    final info = _info;
    if (controller == null || info == null) return;
    final playerId = controller.nativePlayerId;
    _sentPlayerId = playerId;
    // Sent once the controller has a native player.
    if (playerId == null) return;
    _sent = true;
    await _platform.setMediaSession(
      playerId,
      info,
      canSkipNext: _onNext != null,
      canSkipPrevious: _onPrevious != null,
    );
  }

  /// A command from the media controls.
  @internal
  void handle(PlayStackSystemEvent event) {
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    switch (event.type) {
      case PlayStackSystemEventType.play:
        unawaited(controller.play().catchError(_report));
      case PlayStackSystemEventType.pause:
        unawaited(controller.pause().catchError(_report));
      case PlayStackSystemEventType.seek:
        final position = event.position;
        if (position != null) {
          unawaited(controller.seekTo(position).catchError(_report));
        }
      case PlayStackSystemEventType.next:
        _onNext?.call();
      case PlayStackSystemEventType.previous:
        _onPrevious?.call();
      case PlayStackSystemEventType.pictureInPictureStarted:
      case PlayStackSystemEventType.pictureInPictureStopped:
        break;
    }
  }

  /// Stops following the controller; the manager calls it.
  @internal
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller = null;
  }

  static void _report(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'playstack',
        context: ErrorDescription('while handling the media controls'),
      ),
    );
  }
}

/// Plays a video in a small floating window when the user leaves the app,
/// and on request: Picture-in-Picture (`AVPictureInPictureController` on
/// iOS, the Picture-in-Picture mode of the activity on Android).
///
/// Use it through `PlayStackManager.pictureInPicture`, or let
/// `PlayStackFeedView.pictureInPicture` do it for the video in view.
///
/// ```dart
/// await manager.pictureInPicture.enable(controller);   // when leaving the app
/// await manager.pictureInPicture.start();              // from a button
/// ```
///
/// Needs platform setup: on iOS the `audio` background mode in
/// `Info.plist`; on Android `android:supportsPictureInPicture="true"` on
/// the activity. [isSupported] tells whether it can work.
class PlayStackPictureInPicture {
  /// Creates the Picture-in-Picture control of a manager. Apps use
  /// `PlayStackManager.pictureInPicture` instead of constructing one.
  @internal
  PlayStackPictureInPicture(this._platform);

  final PlayStackPlatform _platform;
  final ValueNotifier<bool> _active = ValueNotifier<bool>(false);
  PlayStackPlayerController? _controller;
  bool _autoEnter = true;
  int? _sentPlayerId;
  bool _sent = false;
  bool? _supported;

  /// Whether the video is in the floating window now.
  ValueListenable<bool> get isActive => _active;

  /// The video shown in Picture-in-Picture, set by [enable].
  PlayStackPlayerController? get controller => _controller;

  /// Whether the device and the app support Picture-in-Picture. False on
  /// web, on devices without it and when the app lacks the setup.
  Future<bool> isSupported() async {
    try {
      return _supported ??= await _platform.isPictureInPictureSupported();
    } on Object {
      return false;
    }
  }

  /// Makes [controller] the video of Picture-in-Picture. With [autoEnter]
  /// (the default) it moves to the floating window when the user leaves the
  /// app while it plays.
  Future<void> enable(
    PlayStackPlayerController controller, {
    bool autoEnter = true,
  }) async {
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onControllerChanged);
      controller.addListener(_onControllerChanged);
      _sentPlayerId = null;
    } else if (autoEnter == _autoEnter && _sent) {
      return;
    }
    _controller = controller;
    _autoEnter = autoEnter;
    await _send();
  }

  /// Turns Picture-in-Picture off.
  Future<void> disable() async {
    _controller?.removeListener(_onControllerChanged);
    _controller = null;
    _sentPlayerId = null;
    if (!_sent) return;
    _sent = false;
    await _platform.setPictureInPicture(null, autoEnter: false);
  }

  /// Moves the video of [enable] to the floating window now, for a
  /// Picture-in-Picture button. False when it could not start.
  Future<bool> start() async {
    if (_controller == null) return false;
    if (!_sent) await _send();
    try {
      return await _platform.startPictureInPicture();
    } on Object {
      return false;
    }
  }

  /// Closes the floating window, where the platform allows it (iOS).
  Future<void> stop() => _platform.stopPictureInPicture();

  /// Whether [controller] keeps playing while the app is in the background.
  @internal
  bool keepsPlaying(PlayStackPlayerController controller) =>
      identical(controller, _controller) && _active.value;

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.isDisposed) {
      unawaited(disable().catchError(_report));
      return;
    }
    if (controller.nativePlayerId != _sentPlayerId) {
      unawaited(_send().catchError(_report));
    }
  }

  Future<void> _send() async {
    final controller = _controller;
    if (controller == null) return;
    final playerId = controller.nativePlayerId;
    _sentPlayerId = playerId;
    if (playerId == null) return;
    _sent = true;
    await _platform.setPictureInPicture(playerId, autoEnter: _autoEnter);
  }

  /// A change reported by the engine.
  @internal
  void handle(PlayStackSystemEvent event) {
    switch (event.type) {
      case PlayStackSystemEventType.pictureInPictureStarted:
        _active.value = true;
      case PlayStackSystemEventType.pictureInPictureStopped:
        _active.value = false;
        // Closing the window while the app is in the background stops the
        // video, as video apps do.
        final state = WidgetsBinding.instance.lifecycleState;
        final controller = _controller;
        if (state != AppLifecycleState.resumed &&
            state != AppLifecycleState.inactive &&
            controller != null &&
            !controller.isDisposed) {
          unawaited(controller.pause().catchError(_report));
        }
      default:
        break;
    }
  }

  /// Stops following the controller; the manager calls it.
  @internal
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller = null;
    _active.dispose();
  }

  static void _report(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'playstack',
        context: ErrorDescription('while handling Picture-in-Picture'),
      ),
    );
  }
}
