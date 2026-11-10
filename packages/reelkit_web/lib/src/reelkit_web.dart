import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';
import 'package:web/web.dart' as web;

/// Web implementation of [ReelKitPlatform].
///
/// Each native player is an `HTMLVideoElement` shown through a Flutter
/// platform view. Browsers do not expose decoder limits, so the recommended
/// pool size is derived from `navigator.deviceMemory` where the browser
/// provides it (Chromium-based browsers) and is conservative elsewhere.
class ReelKitWeb extends ReelKitPlatform {
  /// Registers this class as the default [ReelKitPlatform] implementation.
  static void registerWith(Registrar registrar) {
    ReelKitPlatform.instance = ReelKitWeb();
  }

  final Map<int, web.HTMLVideoElement> _elements =
      <int, web.HTMLVideoElement>{};
  // Lives as long as the registered engine, which lives as long as the app.
  // ignore: close_sinks
  final StreamController<ReelPlatformEvent> _events =
      StreamController<ReelPlatformEvent>.broadcast();
  int _nextPlayerId = 1;
  ReelPlatformCapabilities? _capabilities;

  static String _viewType(int playerId) => 'dev.reelkit.web.player.$playerId';

  @override
  Future<ReelPlatformCapabilities> initialize() async {
    return _capabilities ??= _readCapabilities();
  }

  ReelPlatformCapabilities _readCapabilities() {
    final probe = web.HTMLVideoElement();
    final nativeHls = probe
        .canPlayType('application/vnd.apple.mpegurl')
        .isNotEmpty;
    final navigator = web.window.navigator;
    final hasDeviceMemory = (navigator as JSObject).has('deviceMemory');
    final deviceMemoryGib = hasDeviceMemory ? navigator.deviceMemory : null;
    final recommended = switch (deviceMemoryGib) {
      null => 2,
      < 4 => 2,
      < 8 => 3,
      _ => 4,
    };
    return ReelPlatformCapabilities(
      engineName: 'HTMLVideoElement',
      engineVersion: navigator.userAgent,
      recommendedMaxPlayers: recommended,
      totalMemoryBytes: deviceMemoryGib == null
          ? null
          : (deviceMemoryGib * 1024 * 1024 * 1024).round(),
      isLowRamDevice: deviceMemoryGib != null && deviceMemoryGib < 2,
      supportsHls: nativeHls,
      supportsDash: false,
      supportsDiskCache: false,
      supportsMemorySource: false,
      supportsTrackSelection: false,
    );
  }

  @override
  Future<ReelNativePlayerHandle> createPlayer(
    ReelNativePlayerOptions options,
  ) async {
    final playerId = _nextPlayerId++;
    final element = web.HTMLVideoElement()
      ..playsInline = true
      ..preload = 'auto'
      ..loop = options.looping
      ..volume = options.volume.clamp(0.0, 1.0)
      ..playbackRate = options.playbackSpeed
      ..controls = false;
    element.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'fill'
      ..pointerEvents = 'none'
      ..backgroundColor = 'transparent';
    _elements[playerId] = element;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType(playerId),
      (int viewId) => element,
    );
    return ReelNativePlayerHandle(playerId: playerId, textureId: -1);
  }

  @override
  Future<void> disposePlayer(int playerId) async {
    final element = _elements.remove(playerId);
    if (element == null) return;
    element.pause();
    // Detaching the source and calling load() releases the decoder and any
    // buffered media held by the browser for this element.
    element.removeAttribute('src');
    element.load();
    element.remove();
  }

  Never _notImplemented(String method) => throw ReelKitException(
    ReelKitErrorCode.notImplemented,
    '$method is not implemented yet by the ReelKit web engine '
    '(scheduled for milestone 2: single native player).',
  );

  web.HTMLVideoElement _require(int playerId) {
    final element = _elements[playerId];
    if (element == null) {
      throw ReelKitException(
        ReelKitErrorCode.playerNotFound,
        'No web player with id $playerId.',
      );
    }
    return element;
  }

  @override
  Future<void> setSource(int playerId, ReelSource source, int generation) {
    _require(playerId);
    _notImplemented('setSource');
  }

  @override
  Future<void> play(int playerId) {
    _require(playerId);
    _notImplemented('play');
  }

  @override
  Future<void> pause(int playerId) {
    _require(playerId);
    _notImplemented('pause');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) {
    _require(playerId);
    _notImplemented('seekTo');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) {
    _require(playerId);
    _notImplemented('setLooping');
  }

  @override
  Future<void> setVolume(int playerId, double volume) {
    _require(playerId);
    _notImplemented('setVolume');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    _require(playerId);
    _notImplemented('setPlaybackSpeed');
  }

  @override
  Future<ReelPositionSnapshot> getPosition(int playerId) {
    _require(playerId);
    _notImplemented('getPosition');
  }

  @override
  Stream<ReelPlatformEvent> get events => _events.stream;

  @override
  Widget buildView(int playerId) {
    if (!_elements.containsKey(playerId)) return const SizedBox.shrink();
    return HtmlElementView(viewType: _viewType(playerId));
  }
}
