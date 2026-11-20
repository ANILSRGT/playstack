import 'package:flutter/foundation.dart';

/// A content protection system.
enum PlayStackDrmType {
  /// Google Widevine: Android (and Chrome).
  widevine,

  /// Microsoft PlayReady: Android devices that support it.
  playReady,

  /// ClearKey: unencrypted keys, for testing. Android.
  clearKey,

  /// Apple FairPlay Streaming: iOS (HLS only).
  fairPlay,
}

/// How a protected stream gets its keys. Pass it to
/// `PlayStackSource.network(drm: ...)`.
///
/// ```dart
/// PlayStackSource.network(
///   'https://cdn.example.com/movie.mpd',
///   drm: PlayStackDrm.widevine(
///     licenseUrl: 'https://license.example.com/widevine',
///     headers: {'Authorization': 'Bearer $token'},
///   ),
/// )
///
/// PlayStackSource.network(
///   'https://cdn.example.com/movie.m3u8',
///   drm: PlayStackDrm.fairPlay(
///     certificateUrl: 'https://license.example.com/fairplay.cer',
///     licenseUrl: 'https://license.example.com/fairplay',
///   ),
/// )
/// ```
///
/// Use one source per platform when your streams differ (DASH with
/// Widevine on Android, HLS with FairPlay on iOS). The license request is
/// the raw challenge in the body (SPC for FairPlay) and the raw license in
/// the response (CKC), the format most license servers accept; [headers]
/// are sent with it. A stream whose keys fail reports
/// `PlayStackErrorCode.drm`.
@immutable
class PlayStackDrm {
  /// Creates a DRM configuration.
  const PlayStackDrm({
    required this.type,
    this.licenseUrl,
    this.certificateUrl,
    this.headers = const <String, String>{},
    this.contentId,
  });

  /// Widevine with the license server [licenseUrl].
  const PlayStackDrm.widevine({
    required String this.licenseUrl,
    this.headers = const <String, String>{},
  }) : type = PlayStackDrmType.widevine,
       certificateUrl = null,
       contentId = null;

  /// PlayReady with the license server [licenseUrl], or the one in the
  /// stream when null.
  const PlayStackDrm.playReady({
    this.licenseUrl,
    this.headers = const <String, String>{},
  }) : type = PlayStackDrmType.playReady,
       certificateUrl = null,
       contentId = null;

  /// ClearKey with the license server [licenseUrl].
  const PlayStackDrm.clearKey({
    required String this.licenseUrl,
    this.headers = const <String, String>{},
  }) : type = PlayStackDrmType.clearKey,
       certificateUrl = null,
       contentId = null;

  /// FairPlay: the application certificate is downloaded from
  /// [certificateUrl] and keys come from [licenseUrl]. [contentId] is the
  /// asset id sent to the key server; null uses the host of the stream's
  /// `skd://` key URL.
  const PlayStackDrm.fairPlay({
    required String this.certificateUrl,
    required String this.licenseUrl,
    this.headers = const <String, String>{},
    this.contentId,
  }) : type = PlayStackDrmType.fairPlay;

  /// The protection system.
  final PlayStackDrmType type;

  /// The license (key) server.
  final String? licenseUrl;

  /// FairPlay: where the application certificate is.
  final String? certificateUrl;

  /// HTTP headers for license and certificate requests, for example a
  /// token.
  final Map<String, String> headers;

  /// FairPlay: the content id for the key server.
  final String? contentId;

  @override
  bool operator ==(Object other) =>
      other is PlayStackDrm &&
      other.type == type &&
      other.licenseUrl == licenseUrl &&
      other.certificateUrl == certificateUrl &&
      mapEquals(other.headers, headers) &&
      other.contentId == contentId;

  @override
  int get hashCode => Object.hash(
    type,
    licenseUrl,
    certificateUrl,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    contentId,
  );
}
