import 'package:flutter/services.dart';

/// Typed error categories reported by ReelKit.
enum ReelKitErrorCode {
  /// No ReelKit implementation is registered for the current platform.
  unsupportedPlatform,

  /// The operation exists in the API but the current engine does not
  /// implement it yet, or the platform cannot support it.
  notImplemented,

  /// `ReelKitManager.initialize` has not completed.
  notInitialized,

  /// The controller or manager was disposed.
  disposed,

  /// The native player no longer exists.
  playerNotFound,

  /// The native engine failed to allocate a player.
  playerCreationFailed,

  /// Every pooled player is in use by a controller with equal or higher
  /// priority.
  poolExhausted,

  /// The operation was superseded, for example because the controller lost
  /// its native player to a higher-priority controller.
  cancelled,

  /// The source is malformed or not usable on this platform.
  invalidSource,

  /// The media could not be found (HTTP 404, missing file or asset).
  sourceNotFound,

  /// The container or codec is not supported by the engine.
  unsupportedFormat,

  /// A network error occurred while loading media.
  network,

  /// The decoder failed while decoding, or no decoder exists for the media.
  decoder,

  /// A decoder exists for the media but could not be allocated, typically
  /// because other players (in this or another app) hold every available
  /// hardware decoder instance. ReelKit reacts by lowering the pool limit
  /// and retrying once (see `ReelPoolConfig.adaptToDecoderFailures`).
  ///
  /// Reported by Android (`ERROR_CODE_DECODER_INIT_FAILED`) and iOS
  /// (`AVError.decoderTemporarilyUnavailable`). Browsers do not distinguish
  /// this case.
  decoderUnavailable,

  /// The platform refused to start playback, for example a browser blocking
  /// autoplay with sound before the user interacted with the page.
  playbackNotAllowed,

  /// The platform refused a request that needs user activation or a
  /// permission, for example browser fullscreen outside a user gesture.
  notAllowed,

  /// The operation did not complete within its time limit.
  timeout,

  /// An argument was outside its valid range.
  invalidArgument,

  /// Any other error.
  unknown,
}

/// An error raised by ReelKit or by one of its native engines.
class ReelKitException implements Exception {
  const ReelKitException(this.code, this.message, {this.details});

  /// Maps a [PlatformException] from a native engine. Native engines use
  /// [ReelKitErrorCode] names as error codes.
  factory ReelKitException.fromPlatformException(PlatformException error) {
    return ReelKitException(
      codeFromName(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// Parses an error code name, falling back to [ReelKitErrorCode.unknown].
  static ReelKitErrorCode codeFromName(String name) {
    for (final code in ReelKitErrorCode.values) {
      if (code.name == name) return code;
    }
    return ReelKitErrorCode.unknown;
  }

  final ReelKitErrorCode code;
  final String message;
  final String? details;

  @override
  bool operator ==(Object other) =>
      other is ReelKitException &&
      other.code == code &&
      other.message == message &&
      other.details == details;

  @override
  int get hashCode => Object.hash(code, message, details);

  @override
  String toString() =>
      'ReelKitException(${code.name}): $message'
      '${details == null ? '' : ' [$details]'}';
}
