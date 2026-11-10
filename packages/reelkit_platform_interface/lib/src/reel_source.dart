import 'package:flutter/foundation.dart';

/// Whether a network source uses the engine's disk cache.
enum ReelCachePolicy {
  /// Read from and write to the cache when caching is enabled.
  cache,

  /// Always load from the network, for example for private content that
  /// must not be written to disk.
  bypass,
}

/// Container or streaming format of a [ReelSource].
enum ReelVideoFormat {
  /// Detect the format from the URI or path.
  auto,

  /// Progressive file such as MP4, MOV or WebM.
  progressive,

  /// HTTP Live Streaming (`.m3u8`).
  hls,

  /// MPEG-DASH (`.mpd`).
  dash,
}

/// A video to play.
///
/// Platform behaviour differs per source type:
///
/// * [ReelSource.network] works on every platform. HTTP headers are honoured
///   by the native engines; browsers cannot attach custom headers to a
///   `<video>` element request, so headers are only applied on web when the
///   web engine fetches the media itself.
/// * [ReelSource.file] needs a real file system and is not available on web.
/// * [ReelSource.asset] plays a Flutter asset bundled with the app.
/// * [ReelSource.memory] plays in-memory bytes. Check
///   `ReelPlatformCapabilities.supportsMemorySource` before using it.
@immutable
sealed class ReelSource {
  const ReelSource({this.id, this.formatHint = ReelVideoFormat.auto});

  /// Plays a video from a network URL.
  const factory ReelSource.network(
    String url, {
    Map<String, String> headers,
    ReelVideoFormat formatHint,
    String? mimeType,
    String? cacheKey,
    ReelCachePolicy cachePolicy,
    String? id,
  }) = ReelNetworkSource;

  /// Plays a video from an absolute file path.
  const factory ReelSource.file(
    String path, {
    ReelVideoFormat formatHint,
    String? id,
  }) = ReelFileSource;

  /// Plays a video bundled as a Flutter asset.
  const factory ReelSource.asset(
    String assetName, {
    String? package,
    ReelVideoFormat formatHint,
    String? id,
  }) = ReelAssetSource;

  /// Plays a video held in memory.
  const factory ReelSource.memory(
    Uint8List bytes, {
    required String mimeType,
    String? id,
  }) = ReelMemorySource;

  /// Optional application-defined identifier, for example a post id.
  final String? id;

  /// Format declared by the application. [ReelVideoFormat.auto] means the
  /// format is detected from the location, see [resolvedFormat].
  final ReelVideoFormat formatHint;

  /// Human-readable location used in logs and error messages.
  String get description;

  /// [formatHint] when explicit, otherwise the format detected from the
  /// location. Falls back to [ReelVideoFormat.progressive].
  ReelVideoFormat get resolvedFormat {
    if (formatHint != ReelVideoFormat.auto) return formatHint;
    return detectFormat(_locationForDetection);
  }

  String get _locationForDetection;

  /// Detects the streaming format from a URI or path by its extension,
  /// ignoring query strings and fragments.
  static ReelVideoFormat detectFormat(String location) {
    var path = location;
    final uri = Uri.tryParse(location);
    if (uri != null && uri.hasScheme && uri.path.isNotEmpty) path = uri.path;
    path = path.split('?').first.split('#').first.toLowerCase();
    if (path.endsWith('.m3u8')) return ReelVideoFormat.hls;
    if (path.endsWith('.mpd')) return ReelVideoFormat.dash;
    return ReelVideoFormat.progressive;
  }
}

/// A video loaded over HTTP(S).
final class ReelNetworkSource extends ReelSource {
  /// Creates a network source for [url].
  const ReelNetworkSource(
    this.url, {
    this.headers = const <String, String>{},
    super.formatHint,
    this.mimeType,
    this.cacheKey,
    this.cachePolicy = ReelCachePolicy.cache,
    super.id,
  });

  /// HTTP or HTTPS URL of the video or manifest.
  final String url;

  /// Whether this source uses the disk cache (when caching is enabled).
  final ReelCachePolicy cachePolicy;

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
      other is ReelNetworkSource &&
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
  String toString() => 'ReelSource.network($url)';
}

/// A video stored on the device file system.
final class ReelFileSource extends ReelSource {
  /// Creates a source for the file at [path].
  const ReelFileSource(this.path, {super.formatHint, super.id});

  /// Absolute path of the file.
  final String path;

  @override
  String get description => path;

  @override
  String get _locationForDetection => path;

  @override
  bool operator ==(Object other) =>
      other is ReelFileSource &&
      other.path == path &&
      other.formatHint == formatHint &&
      other.id == id;

  @override
  int get hashCode => Object.hash(path, formatHint, id);

  @override
  String toString() => 'ReelSource.file($path)';
}

/// A video bundled as a Flutter asset.
final class ReelAssetSource extends ReelSource {
  /// Creates a source for the Flutter asset [assetName].
  const ReelAssetSource(
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
      other is ReelAssetSource &&
      other.assetName == assetName &&
      other.package == package &&
      other.formatHint == formatHint &&
      other.id == id;

  @override
  int get hashCode => Object.hash(assetName, package, formatHint, id);

  @override
  String toString() => 'ReelSource.asset($description)';
}

/// A video held in memory.
///
/// The bytes are sent to the native engine once per preparation, so this
/// source is intended for short clips only.
final class ReelMemorySource extends ReelSource {
  /// Creates a source from [bytes] of type [mimeType].
  const ReelMemorySource(this.bytes, {required this.mimeType, super.id})
    : super(formatHint: ReelVideoFormat.progressive);

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
      other is ReelMemorySource &&
      identical(other.bytes, bytes) &&
      other.mimeType == mimeType &&
      other.id == id;

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), mimeType, id);

  @override
  String toString() => 'ReelSource.$description';
}
