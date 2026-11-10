import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'hls_js.dart';
import 'web_player.dart';

/// Web implementation of [ReelKitPlatform].
///
/// Each native player is an `HTMLVideoElement` shown through a Flutter
/// platform view. Browser limitations are reported, not hidden:
///
/// * `<video>` requests cannot carry custom HTTP headers; network sources
///   with headers fail with [ReelKitErrorCode.invalidSource].
/// * HLS plays natively in Safari and through HLS.js elsewhere when the app
///   loads HLS.js (`window.Hls`); MPEG-DASH is not supported. Unplayable
///   formats fail with [ReelKitErrorCode.unsupportedFormat].
/// * No ReelKit disk cache: the browser's HTTP cache applies, which ReelKit
///   can neither size, inspect nor clear.
/// * Fullscreen uses the Fullscreen API and needs a user gesture; orientation
///   locking works only where the browser allows it (Chrome on Android) and
///   is ignored elsewhere.
/// * File paths do not exist in browsers; use network, asset or memory
///   sources.
/// * Browsers block autoplay with sound until the user interacts with the
///   page; `play` then fails with [ReelKitErrorCode.playbackNotAllowed].
///   Muted playback (volume 0) is allowed.
/// * Browsers expose no decoder limits; the recommended pool size is derived
///   from `navigator.deviceMemory` where available.
/// * Forward buffering of paused videos cannot be bounded; browsers decide
///   how much of a `preload="auto"` video they download.
/// * Network status: `navigator.onLine` everywhere; metering and data saver
///   only where `navigator.connection` exists (Chromium).
class ReelKitWeb extends ReelKitPlatform {
  /// Registers this class as the default [ReelKitPlatform] implementation.
  static void registerWith(Registrar registrar) {
    ReelKitPlatform.instance = ReelKitWeb();
  }

  final Map<int, WebPlayer> _players = <int, WebPlayer>{};

  // Lives as long as the registered engine, which lives as long as the app.
  // ignore: close_sinks
  final StreamController<ReelPlatformEvent> _events =
      StreamController<ReelPlatformEvent>.broadcast();
  int _nextPlayerId = 1;
  ReelPlatformCapabilities? _capabilities;
  bool? _nativeHls;

  static String _viewType(int playerId) => 'dev.reelkit.web.player.$playerId';

  bool get _supportsNativeHls => _nativeHls ??= web.HTMLVideoElement()
      .canPlayType('application/vnd.apple.mpegurl')
      .isNotEmpty;

  @override
  Future<ReelPlatformCapabilities> initialize([
    ReelEngineConfig config = const ReelEngineConfig(),
  ]) async {
    return _capabilities ??= _readCapabilities();
  }

  ReelPlatformCapabilities _readCapabilities() {
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
      supportsHls: _supportsNativeHls || HlsJsSession.isAvailable,
      supportsDash: false,
      supportsDiskCache: false,
      supportsMemorySource: true,
      // Subtitle tracks exposed by the browser (for example HLS subtitles in
      // Safari) and, where the browser exposes them, audio tracks.
      supportsTrackSelection: true,
      supportsNetworkStatus: true,
    );
  }

  @override
  Future<ReelNativePlayerHandle> createPlayer(
    ReelNativePlayerOptions options,
  ) async {
    final playerId = _nextPlayerId++;
    final player = WebPlayer(playerId, options, _events.add);
    _players[playerId] = player;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType(playerId),
      (int viewId) => player.element,
    );
    return ReelNativePlayerHandle(playerId: playerId, textureId: -1);
  }

  @override
  Future<void> disposePlayer(int playerId) async {
    _players.remove(playerId)?.dispose();
  }

  WebPlayer _require(int playerId) {
    final player = _players[playerId];
    if (player == null) {
      throw ReelKitException(
        ReelKitErrorCode.playerNotFound,
        'No web player with id $playerId.',
      );
    }
    return player;
  }

  @override
  Future<void> setSource(
    int playerId,
    ReelSource source,
    int generation,
  ) async {
    final player = _require(playerId);
    final format = source.resolvedFormat;
    if (format == ReelVideoFormat.dash) {
      throw const ReelKitException(
        ReelKitErrorCode.unsupportedFormat,
        'MPEG-DASH is not supported by the web engine.',
      );
    }
    final useHlsJs = format == ReelVideoFormat.hls && !_supportsNativeHls;
    if (useHlsJs && !HlsJsSession.isAvailable) {
      throw const ReelKitException(
        ReelKitErrorCode.unsupportedFormat,
        'This browser cannot play HLS natively. Add HLS.js to web/index.html '
        'to play HLS outside Safari.',
      );
    }
    switch (source) {
      case ReelNetworkSource(:final url, :final headers):
        if (headers.isNotEmpty) {
          throw const ReelKitException(
            ReelKitErrorCode.invalidSource,
            'Browsers cannot attach custom HTTP headers to <video> requests. '
            'Use signed URLs or cookies for authorization on the web.',
          );
        }
        if (useHlsJs) {
          player.loadHls(url, generation);
        } else {
          player.load(url, generation);
        }
      case ReelAssetSource(:final assetName, :final package):
        final key = package == null
            ? assetName
            : 'packages/$package/$assetName';
        player.load(ui_web.assetManager.getAssetUrl(key), generation);
      case ReelMemorySource(:final bytes, :final mimeType):
        final blob = web.Blob(
          <JSUint8Array>[bytes.toJS].toJS,
          web.BlobPropertyBag(type: mimeType),
        );
        player.load(
          web.URL.createObjectURL(blob),
          generation,
          ownsObjectUrl: true,
        );
      case ReelFileSource(:final path):
        throw ReelKitException(
          ReelKitErrorCode.invalidSource,
          'File paths are not available in browsers: $path',
        );
    }
  }

  @override
  Future<void> clearSource(int playerId) async => _require(playerId).clear();

  @override
  Future<void> play(int playerId) => _require(playerId).play();

  @override
  Future<void> pause(int playerId) async => _require(playerId).element.pause();

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    _require(playerId).element.currentTime =
        position.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    _require(playerId).element.loop = looping;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    _require(playerId).setVolume(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    if (!speed.isFinite || speed <= 0) {
      throw ReelKitException(
        ReelKitErrorCode.invalidArgument,
        'Playback speed must be > 0, got $speed.',
      );
    }
    _require(playerId).element.playbackRate = speed;
  }

  @override
  Future<ReelPositionSnapshot> getPosition(int playerId) async =>
      _require(playerId).position();

  @override
  Future<List<ReelTrack>> getTracks(int playerId) async =>
      _require(playerId).tracks();

  @override
  Future<void> selectTrack(
    int playerId,
    ReelTrackType type,
    String? trackId,
  ) async => _require(playerId).selectTrack(type, trackId);

  @override
  Future<void> setVideoQualityLimit(
    int playerId,
    ReelVideoQualityLimit limit,
  ) async {
    _require(playerId);
    if (limit.isUnbounded) return;
    throw const ReelKitException(
      ReelKitErrorCode.notImplemented,
      'Browsers choose <video> renditions themselves; a quality limit '
      'cannot be applied.',
    );
  }

  @override
  Future<void> setPreloadBufferLimit(int playerId, Duration? limit) async {
    _require(playerId);
    if (limit == null) return;
    throw const ReelKitException(
      ReelKitErrorCode.notImplemented,
      'Browsers decide how much of a <video> they buffer; a preload buffer '
      'limit cannot be applied.',
    );
  }

  @override
  Future<ReelNetworkStatus> getNetworkStatus() async => _readNetwork();

  static const _noCache = ReelKitException(
    ReelKitErrorCode.notImplemented,
    'The web engine has no disk cache; the browser HTTP cache applies.',
  );

  @override
  Future<ReelCacheInfo> getCacheInfo() async => ReelCacheInfo.disabled;

  @override
  Future<void> clearCache() async => throw _noCache;

  @override
  Future<void> removeCached(String cacheKey) async => throw _noCache;

  @override
  Future<int> getCachedBytes(String cacheKey) async => throw _noCache;

  @override
  Future<void> enterFullscreen(ReelFullscreenRequest request) async {
    final document = web.document;
    if (document.fullscreenElement == null) {
      final root = document.documentElement;
      if (root == null) return;
      try {
        await root.requestFullscreen().toDart;
      } catch (error) {
        throw ReelKitException(
          ReelKitErrorCode.notAllowed,
          'The browser refused fullscreen. Call it from a user gesture '
          '(tap or click).',
          details: '$error',
        );
      }
    }
    final type = _orientationLockType(request.orientations);
    if (type == null) return;
    try {
      await web.window.screen.orientation.lock(type).toDart;
    } catch (_) {
      // Most desktop and iOS browsers cannot lock the orientation; the
      // request is a preference there, not an error.
    }
  }

  @override
  Future<void> exitFullscreen(ReelFullscreenRestore restore) async {
    try {
      web.window.screen.orientation.unlock();
    } catch (_) {
      // Not locked or not supported.
    }
    final document = web.document;
    if (document.fullscreenElement == null) return;
    try {
      await document.exitFullscreen().toDart;
    } catch (_) {
      // Already left (for example with Escape).
    }
  }

  @override
  Stream<bool> get fullscreenChanges => _fullscreen.stream;

  // Lives as long as the registered engine; the document listener is
  // attached only while the stream has a listener.
  // ignore: close_sinks
  late final StreamController<bool> _fullscreen =
      StreamController<bool>.broadcast(
        onListen: () => web.document.addEventListener(
          'fullscreenchange',
          _fullscreenListener,
        ),
        onCancel: () => web.document.removeEventListener(
          'fullscreenchange',
          _fullscreenListener,
        ),
      );
  late final JSFunction _fullscreenListener = ((web.Event _) => _fullscreen.add(
    web.document.fullscreenElement != null,
  )).toJS;

  static String? _orientationLockType(List<DeviceOrientation>? orientations) {
    if (orientations == null || orientations.isEmpty) return null;
    bool isLandscape(DeviceOrientation o) =>
        o == DeviceOrientation.landscapeLeft ||
        o == DeviceOrientation.landscapeRight;
    if (orientations.every(isLandscape)) return 'landscape';
    if (orientations.every((o) => !isLandscape(o))) return 'portrait';
    return null;
  }

  @override
  Stream<ReelNetworkStatus> get networkStatusChanges => _network.stream;

  // Lives as long as the registered engine. Browser listeners are attached
  // only while the stream has a listener.
  // ignore: close_sinks
  late final StreamController<ReelNetworkStatus> _network =
      StreamController<ReelNetworkStatus>.broadcast(
        onListen: _startNetworkEvents,
        onCancel: _stopNetworkEvents,
      );
  late final JSFunction _networkListener = ((
    web.Event _,
  ) => _emitNetwork()).toJS;
  web.NetworkInformation? _observedConnection;
  ReelNetworkStatus? _lastNetwork;

  void _startNetworkEvents() {
    web.window.addEventListener('online', _networkListener);
    web.window.addEventListener('offline', _networkListener);
    _observedConnection = _connection()
      ?..addEventListener('change', _networkListener);
    _lastNetwork = null;
    _emitNetwork();
  }

  void _stopNetworkEvents() {
    web.window.removeEventListener('online', _networkListener);
    web.window.removeEventListener('offline', _networkListener);
    _observedConnection?.removeEventListener('change', _networkListener);
    _observedConnection = null;
  }

  void _emitNetwork() {
    final status = _readNetwork();
    if (status == _lastNetwork) return;
    _lastNetwork = status;
    _network.add(status);
  }

  static web.NetworkInformation? _connection() {
    final navigator = web.window.navigator;
    if (!(navigator as JSObject).has('connection')) return null;
    return navigator.connection;
  }

  static ReelNetworkStatus _readNetwork() {
    final online = web.window.navigator.onLine;
    final connection = _connection();
    if (!online) {
      return ReelNetworkStatus(
        isConnected: false,
        isConstrained: connection?.saveData ?? false,
        type: ReelNetworkType.none,
      );
    }
    if (connection == null) return ReelNetworkStatus.unknown;
    final rawType = (connection as JSObject)
        .getProperty<JSString?>('type'.toJS)
        ?.toDart;
    final type = switch (rawType) {
      'wifi' => ReelNetworkType.wifi,
      'cellular' => ReelNetworkType.cellular,
      'ethernet' => ReelNetworkType.ethernet,
      'none' => ReelNetworkType.none,
      null || 'unknown' => ReelNetworkType.unknown,
      _ => ReelNetworkType.other,
    };
    final effectiveType = connection.has('effectiveType')
        ? connection.effectiveType
        : null;
    final saveData = connection.has('saveData') && connection.saveData;
    return ReelNetworkStatus(
      isConnected: true,
      isMetered: type == ReelNetworkType.cellular,
      isConstrained:
          saveData || effectiveType == 'slow-2g' || effectiveType == '2g',
      type: type,
    );
  }

  @override
  Stream<ReelPlatformEvent> get events => _events.stream;

  @override
  Widget buildView(int playerId) {
    if (!_players.containsKey(playerId)) return const SizedBox.shrink();
    return HtmlElementView(viewType: _viewType(playerId));
  }
}
