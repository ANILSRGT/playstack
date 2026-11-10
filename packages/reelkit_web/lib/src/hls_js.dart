import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';
import 'package:web/web.dart' as web;

/// Minimal interop with [HLS.js](https://github.com/video-dev/hls.js), used
/// for HLS in browsers without native HLS (everything but Safari).
///
/// ReelKit does not bundle or download HLS.js. Applications that need HLS
/// on those browsers add it to `web/index.html`, for example
/// `<script src="https://cdn.jsdelivr.net/npm/hls.js@1"></script>`; ReelKit
/// uses it when `window.Hls` exists and reports `supportsHls` accordingly.
@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external factory _Hls();

  external static bool isSupported();

  external void loadSource(String url);

  external void attachMedia(web.HTMLMediaElement media);

  external void destroy();

  external void on(String event, JSFunction callback);
}

extension type _HlsErrorData._(JSObject _) implements JSObject {
  external bool get fatal;
  external String? get type;
  external String? get details;
}

/// One HLS.js instance attached to a `<video>` element.
class HlsJsSession {
  HlsJsSession._(this._hls);

  /// Whether HLS.js is loaded and Media Source Extensions are available.
  static bool get isAvailable {
    if (!globalContext.has('Hls')) return false;
    try {
      return _Hls.isSupported();
    } on Object {
      return false;
    }
  }

  /// Starts loading [url] into [video]. [onFatalError] receives errors HLS.js
  /// could not recover from.
  static HlsJsSession attach(
    web.HTMLVideoElement video,
    String url, {
    required void Function(ReelKitException error) onFatalError,
  }) {
    final hls = _Hls();
    hls.on(
      'hlsError',
      ((JSString _, _HlsErrorData data) {
        if (!data.fatal) return;
        final code = switch (data.type) {
          'networkError' => ReelKitErrorCode.network,
          'mediaError' => ReelKitErrorCode.decoder,
          _ => ReelKitErrorCode.unknown,
        };
        onFatalError(
          ReelKitException(
            code,
            'HLS.js: ${data.details ?? data.type ?? 'fatal error'}',
          ),
        );
      }).toJS,
    );
    hls
      ..loadSource(url)
      ..attachMedia(video);
    return HlsJsSession._(hls);
  }

  final _Hls _hls;

  void destroy() => _hls.destroy();
}
