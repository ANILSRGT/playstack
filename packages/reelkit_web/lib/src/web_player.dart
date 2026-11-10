import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';
import 'package:web/web.dart' as web;

/// One `HTMLVideoElement` and the media events it reports.
///
/// Listeners are attached once per element and tag events with the current
/// source generation; after [clear] nothing is reported until the next
/// [load].
class WebPlayer {
  WebPlayer(this.playerId, ReelNativePlayerOptions options, this._emit)
    : element = web.HTMLVideoElement() {
    element
      ..playsInline = true
      ..preload = 'auto'
      ..controls = false
      ..loop = options.looping
      ..playbackRate = options.playbackSpeed;
    setVolume(options.volume);
    element.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'fill'
      ..pointerEvents = 'none'
      ..backgroundColor = 'transparent';
    _listen('loadedmetadata', _onLoadedMetadata);
    _listen('loadeddata', _onLoadedData);
    _listen('waiting', () => _state(ReelNativePlaybackState.buffering));
    _listen('playing', () => _state(ReelNativePlaybackState.ready));
    _listen('canplay', () {
      if (_initializedSent) _state(ReelNativePlaybackState.ready);
    });
    _listen('play', () => _playing(true));
    _listen('pause', () => _playing(false));
    _listen('ended', () => _state(ReelNativePlaybackState.ended));
    _listen('resize', _onResize);
    _listen('error', _onError);
  }

  static const int _noSource = -1;

  final int playerId;
  final web.HTMLVideoElement element;
  final void Function(ReelPlatformEvent event) _emit;
  final List<(String, JSFunction)> _listeners = <(String, JSFunction)>[];

  int _generation = _noSource;
  bool _initializedSent = false;
  bool _firstFrameSent = false;
  String? _objectUrl;

  void load(String url, int generation, {bool ownsObjectUrl = false}) {
    clear();
    _generation = generation;
    if (ownsObjectUrl) _objectUrl = url;
    element
      ..src = url
      ..load();
  }

  void clear() {
    _generation = _noSource;
    _initializedSent = false;
    _firstFrameSent = false;
    element.pause();
    // Detaching the source and calling load() releases the decoder and any
    // media buffered for this element.
    element.removeAttribute('src');
    element.load();
    final objectUrl = _objectUrl;
    if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
    _objectUrl = null;
  }

  Future<void> play() async {
    try {
      await element.play().toDart;
    } catch (error) {
      switch (_domExceptionName(error)) {
        case 'NotAllowedError':
          throw const ReelKitException(
            ReelKitErrorCode.playbackNotAllowed,
            'The browser blocked playback with sound before a user gesture. '
            'Mute the controller or start playback from a user interaction.',
          );
        case 'AbortError':
          // Interrupted by pause() or a source change: not a failure.
          return;
        case 'NotSupportedError':
          throw const ReelKitException(
            ReelKitErrorCode.unsupportedFormat,
            'The browser cannot play this source.',
          );
        default:
          throw ReelKitException(ReelKitErrorCode.unknown, '$error');
      }
    }
  }

  /// Browsers only allow autoplay for muted elements; volume 0 alone does
  /// not count, so zero volume is applied as `muted`.
  void setVolume(double volume) {
    final clamped = volume.clamp(0.0, 1.0);
    element.muted = clamped == 0;
    if (clamped > 0) element.volume = clamped;
  }

  ReelPositionSnapshot position() {
    final current = element.currentTime;
    var bufferedEnd = current;
    final ranges = element.buffered;
    for (var i = 0; i < ranges.length; i++) {
      if (ranges.start(i) <= current + 0.001 && ranges.end(i) >= current) {
        bufferedEnd = ranges.end(i);
        break;
      }
    }
    return ReelPositionSnapshot(
      position: _duration(current),
      buffered: _duration(bufferedEnd),
    );
  }

  void dispose() {
    clear();
    for (final (type, listener) in _listeners) {
      element.removeEventListener(type, listener);
    }
    _listeners.clear();
    element.remove();
  }

  // ---------------------------------------------------------------------------

  void _listen(String type, void Function() handler) {
    final listener = ((web.Event _) => handler()).toJS;
    element.addEventListener(type, listener);
    _listeners.add((type, listener));
  }

  bool get _hasSource => _generation != _noSource;

  void _onLoadedMetadata() {
    if (!_hasSource || _initializedSent) return;
    _initializedSent = true;
    final duration = element.duration;
    _emit(
      ReelInitializedEvent(
        playerId: playerId,
        generation: _generation,
        // Browsers apply rotation metadata themselves, so the reported size
        // is upright and no rotation is left for Flutter.
        info: ReelVideoInfo(
          width: element.videoWidth,
          height: element.videoHeight,
          duration: duration.isFinite ? _duration(duration) : null,
        ),
      ),
    );
  }

  void _onLoadedData() {
    if (!_hasSource || _firstFrameSent) return;
    _firstFrameSent = true;
    _emit(ReelFirstFrameEvent(playerId: playerId, generation: _generation));
  }

  void _onResize() {
    if (!_hasSource || !_initializedSent) return;
    if (element.videoWidth == 0 || element.videoHeight == 0) return;
    _emit(
      ReelVideoSizeEvent(
        playerId: playerId,
        generation: _generation,
        width: element.videoWidth,
        height: element.videoHeight,
        rotationDegrees: 0,
        pixelAspectRatio: 1,
      ),
    );
  }

  void _state(ReelNativePlaybackState state) {
    if (!_hasSource) return;
    _emit(
      ReelNativeStateEvent(
        playerId: playerId,
        generation: _generation,
        state: state,
      ),
    );
  }

  void _playing(bool isPlaying) {
    if (!_hasSource) return;
    _emit(
      ReelIsPlayingEvent(
        playerId: playerId,
        generation: _generation,
        isPlaying: isPlaying,
      ),
    );
  }

  void _onError() {
    if (!_hasSource) return;
    final error = element.error;
    final code = switch (error?.code) {
      web.MediaError.MEDIA_ERR_ABORTED => ReelKitErrorCode.cancelled,
      web.MediaError.MEDIA_ERR_NETWORK => ReelKitErrorCode.network,
      web.MediaError.MEDIA_ERR_DECODE => ReelKitErrorCode.decoder,
      // Browsers use this code both for unsupported formats and for sources
      // that could not be fetched at all (for example HTTP 404).
      web.MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED =>
        ReelKitErrorCode.unsupportedFormat,
      _ => ReelKitErrorCode.unknown,
    };
    final message = error?.message ?? '';
    _emit(
      ReelErrorEvent(
        playerId: playerId,
        generation: _generation,
        error: ReelKitException(
          code,
          message.isEmpty ? 'Media error ${error?.code}.' : message,
          details: code == ReelKitErrorCode.unsupportedFormat
              ? 'The source was not found or its format is not supported.'
              : null,
        ),
      ),
    );
  }

  static Duration _duration(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  static String? _domExceptionName(Object error) {
    try {
      final name = (error as JSObject).getProperty<JSAny?>('name'.toJS);
      return name.isA<JSString>() ? (name as JSString).toDart : null;
    } on Object {
      return null;
    }
  }
}
