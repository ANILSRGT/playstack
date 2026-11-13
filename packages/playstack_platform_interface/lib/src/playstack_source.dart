import 'package:flutter/foundation.dart';

/// Whether a network source uses the engine's disk cache.
enum PlayStackCachePolicy {
  /// Read from and write to the cache when caching is enabled.
  cache,

  /// Always load from the network, for example for private content that
  /// must not be written to disk.
  bypass,
}

/// Container or streaming format of a [PlayStackSource].
enum PlayStackVideoFormat {
  /// Detect the format from the URI or path.
  auto,

  /// Progressive file such as MP4, MOV or WebM.
  progressive,

  /// HTTP Live Streaming (`.m3u8`).
  hls,

  /// MPEG-DASH (`.mpd`).
  dash,
}

/// Where a video comes from: a URL, a file, an app asset or bytes in
/// memory.
///
/// ```dart
/// PlayStackSource.network('https://example.com/video.m3u8')
/// PlayStackSource.network(url, headers: {'Authorization': 'Bearer $token'})
/// PlayStackSource.asset('assets/intro.mp4')
/// PlayStackSource.file('/path/on/device/clip.mp4')
/// ```
///
/// What works where:
///
/// * [PlayStackSource.network] works everywhere. Native engines send [headers];
///   browsers cannot add headers to a `<video>` request, so on the web they
///   apply only when the web engine downloads the media itself.
/// * [PlayStackSource.file] needs a file system, so not on the web.
/// * [PlayStackSource.asset] plays a video bundled with the app.
/// * [PlayStackSource.memory] plays bytes; check
///   `PlayStackPlatformCapabilities.supportsMemorySource` first.
@immutable
sealed class PlayStackSource {
  /// Constructor for the source classes. Use the named factories instead.
  const PlayStackSource({this.id, this.formatHint = PlayStackVideoFormat.auto});

  /// A video at [url]: an MP4 or other file, an HLS stream (`.m3u8`) or a
  /// DASH stream (`.mpd`).
  ///
  /// * [headers]: sent with every request, for example `Authorization`.
  /// * [formatHint]: the format when the URL does not show it (no `.m3u8` or
  ///   `.mpd` extension).
  /// * [mimeType]: the MIME type, when the server reports a wrong one.
  /// * [cacheKey]: a stable key when the same video comes from changing URLs,
  ///   such as signed URLs, so the disk cache still finds it.
  /// * [cachePolicy]: [PlayStackCachePolicy.noCache] for private videos that must
  ///   not be stored.
  /// * [id]: your own identifier, used as the feed item id when none is
  ///   given.
  const factory PlayStackSource.network(
    String url, {
    Map<String, String> headers,
    PlayStackVideoFormat formatHint,
    String? mimeType,
    String? cacheKey,
    PlayStackCachePolicy cachePolicy,
    String? id,
  }) = PlayStackNetworkSource;

  /// A video file on the device at the absolute [path], for example one the
  /// user recorded. Not available on the web.
  const factory PlayStackSource.file(
    String path, {
    PlayStackVideoFormat formatHint,
    String? id,
  }) = PlayStackFileSource;

  /// A video bundled with the app and declared under `assets:` in
  /// `pubspec.yaml`. [package] names the package that bundles it, or null for
  /// the app's own assets.
  const factory PlayStackSource.asset(
    String assetName, {
    String? package,
    PlayStackVideoFormat formatHint,
    String? id,
  }) = PlayStackAssetSource;

  /// A video held in memory as [bytes] of type [mimeType] (for example
  /// `video/mp4`). The bytes are copied to the engine on every preparation,
  /// so use it only for short clips.
  const factory PlayStackSource.memory(
    Uint8List bytes, {
    required String mimeType,
    String? id,
  }) = PlayStackMemorySource;

  /// Your own identifier for this video, for example a post id. A feed uses
  /// it as the item id when the item has none.
  final String? id;

  /// The format you declare. [PlayStackVideoFormat.auto] (default) detects it from
  /// the URL or path; set it when the URL has no telling extension.
  final PlayStackVideoFormat formatHint;

  /// Human-readable location used in logs and error messages.
  String get description;

  /// [formatHint] when explicit, otherwise the format detected from the
  /// location. Falls back to [PlayStackVideoFormat.progressive].
  PlayStackVideoFormat get resolvedFormat {
    if (formatHint != PlayStackVideoFormat.auto) return formatHint;
    return detectFormat(_locationForDetection);
  }

  String get _locationForDetection;

  /// Detects the streaming format from a URI or path by its extension,
  /// ignoring query strings and fragments.
  static PlayStackVideoFormat detectFormat(String location) {
    var path = location;
    final uri = Uri.tryParse(location);
    if (uri != null && uri.hasScheme && uri.path.isNotEmpty) path = uri.path;
    path = path.split('?').first.split('#').first.toLowerCase();
    if (path.endsWith('.m3u8')) return PlayStackVideoFormat.hls;
    if (path.endsWith('.mpd')) return PlayStackVideoFormat.dash;
    return PlayStackVideoFormat.progressive;
  }
}

/// A video loaded over HTTP(S).
final class PlayStackNetworkSource extends PlayStackSource {
  /// Creates a network source for [url].
  const PlayStackNetworkSource(
    this.url, {
    this.headers = const <String, String>{},
    super.formatHint,
    this.mimeType,
    this.cacheKey,
    this.cachePolicy = PlayStackCachePolicy.cache,
    super.id,
  });

  /// HTTP or HTTPS URL of the video or manifest.
  final String url;

  /// Whether this source uses the disk cache (when caching is enabled).
  final PlayStackCachePolicy cachePolicy;

  /// HTTP headers sent with every media request, for example
  /// `Authorization`.
  final Map<String, String> headers;

  /// Optional MIME type, for example `video/mp4`.
  final String? mimeType;

  /// Stable key for caching. Set it when the same video is served from
  /// changing URLs (for example signed URLs). Defaults to [url].
  final String? cacheKey;

  /// Key used to identify this media in caches.
  String get effectiveCacheKey => cacheKey ?? url;

  @override
  String get description => url;

  @override
  String get _locationForDetection => url;

  @override
  bool operator ==(Object other) =>
      other is PlayStackNetworkSource &&
      other.url == url &&
      mapEquals(other.headers, headers) &&
      other.formatHint == formatHint &&
      other.mimeType == mimeType &&
      other.cacheKey == cacheKey &&
      other.cachePolicy == cachePolicy &&
      other.id == id;

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    formatHint,
    mimeType,
    cacheKey,
    cachePolicy,
    id,
  );

  @override
  String toString() => 'PlayStackSource.network($url)';
}

/// A video stored on the device file system.
final class PlayStackFileSource extends PlayStackSource {
  /// Creates a source for the file at [path].
  const PlayStackFileSource(this.path, {super.formatHint, super.id});

  /// Absolute path of the file.
  final String path;

  @override
  String get description => path;

  @override
  String get _locationForDetection => path;

  @override
  bool operator ==(Object other) =>
      other is PlayStackFileSource &&
      other.path == path &&
      other.formatHint == formatHint &&
      other.id == id;

  @override
  int get hashCode => Object.hash(path, formatHint, id);

  @override
  String toString() => 'PlayStackSource.file($path)';
}

/// A video bundled as a Flutter asset.
final class PlayStackAssetSource extends PlayStackSource {
  /// Creates a source for the Flutter asset [assetName].
  const PlayStackAssetSource(
    this.assetName, {
    this.package,
    super.formatHint,
    super.id,
  });

  /// Asset key as declared in `pubspec.yaml`.
  final String assetName;

  /// Package that bundles the asset, or null for the app's own assets.
  final String? package;

  @override
  String get description =>
      package == null ? assetName : 'packages/$package/$assetName';

  @override
  String get _locationForDetection => assetName;

  @override
  bool operator ==(Object other) =>
      other is PlayStackAssetSource &&
      other.assetName == assetName &&
      other.package == package &&
      other.formatHint == formatHint &&
      other.id == id;

  @override
  int get hashCode => Object.hash(assetName, package, formatHint, id);

  @override
  String toString() => 'PlayStackSource.asset($description)';
}

/// A video held in memory.
///
/// The bytes are sent to the native engine once per preparation, so this
/// source is intended for short clips only.
final class PlayStackMemorySource extends PlayStackSource {
  /// Creates a source from [bytes] of type [mimeType].
  const PlayStackMemorySource(this.bytes, {required this.mimeType, super.id})
    : super(formatHint: PlayStackVideoFormat.progressive);

  /// The encoded video file.
  final Uint8List bytes;

  /// MIME type of [bytes], for example `video/mp4`.
  final String mimeType;

  @override
  String get description => 'memory(${bytes.lengthInBytes} bytes, $mimeType)';

  @override
  String get _locationForDetection => '';

  /// Memory sources compare by identity of their byte buffer; comparing the
  /// content of large buffers on every equality check would be too costly.
  @override
  bool operator ==(Object other) =>
      other is PlayStackMemorySource &&
      identical(other.bytes, bytes) &&
      other.mimeType == mimeType &&
      other.id == id;

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), mimeType, id);

  @override
  String toString() => 'PlayStackSource.$description';
}
