import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'web_player.dart';

/// Web implementation of [ReelKitPlatform].
///
/// Each native player is an `HTMLVideoElement` shown through a Flutter
/// platform view. Browser limitations are reported, not hidden:
///
/// * `<video>` requests cannot carry custom HTTP headers; network sources
///   with headers fail with [ReelKitErrorCode.invalidSource].
/// * HLS plays only where the browser supports it natively (Safari); MPEG-DASH
///   is not supported. Both fail with [ReelKitErrorCode.unsupportedFormat].
/// * File paths do not exist in browsers; use network, asset or memory
///   sources.
/// * Browsers block autoplay with sound until the user interacts with the
///   page; `play` then fails with [ReelKitErrorCode.playbackNotAllowed].
///   Muted playback (volume 0) is allowed.
/// * Browsers expose no decoder limits; the recommended pool size is derived
///   from `navigator.deviceMemory` where available.
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
  Future<ReelPlatformCapabilities> initialize() async {
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
      supportsHls: _supportsNativeHls,
      supportsDash: false,
      supportsDiskCache: false,
      supportsMemorySource: true,
      // Subtitle tracks exposed by the browser (for example HLS subtitles in
      // Safari) and, where the browser exposes them, audio tracks.
      supportsTrackSelection: true,
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
    if (format == ReelVideoFormat.hls && !_supportsNativeHls) {
      throw const ReelKitException(
        ReelKitErrorCode.unsupportedFormat,
        'This browser cannot play HLS natively. HLS on the web currently '
        'requires Safari.',
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
        player.load(url, generation);
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
  Stream<ReelPlatformEvent> get events => _events.stream;

  @override
  Widget buildView(int playerId) {
    if (!_players.containsKey(playerId)) return const SizedBox.shrink();
    return HtmlElementView(viewType: _viewType(playerId));
  }
}
