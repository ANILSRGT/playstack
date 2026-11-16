import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// How good a downloaded video looks, and so how much space it takes. For
/// HLS and DASH streams it picks the renditions to save; progressive files
/// (MP4) are saved as they are.
///
/// Offer these to the user before a download, as streaming apps do:
///
/// ```dart
/// for (final quality in PlayStackDownloadQuality.values)
///   ListTile(
///     title: Text(quality.name),          // low, medium, high, best
///     subtitle: Text(quality.label),      // 360p, 720p, 1080p, Best
///     onTap: () => downloads.download(id, source, quality: quality),
///   ),
/// ```
enum PlayStackDownloadQuality {
  /// Up to 360p: the smallest files, for small screens and little space.
  low(360),

  /// Up to 720p: sharp on phones at a moderate size.
  medium(720),

  /// Up to 1080p.
  high(1080),

  /// The best rendition of the stream.
  best(null);

  const PlayStackDownloadQuality(this.maxVideoHeight);

  /// The tallest rendition saved, in lines; null for [best].
  final int? maxVideoHeight;

  /// `360p` style, or `Best`.
  String get label => maxVideoHeight == null ? 'Best' : '${maxVideoHeight}p';
}

/// Saves videos for offline viewing.
///
/// Off by default: turn it on for the users who may watch offline, for
/// example premium subscribers, and off again when they may not.
///
/// ```dart
/// await manager.downloads.setEnabled(user.isPremium);
/// await manager.downloads.download(
///   'episode-3',
///   PlayStackSource.network(episode.url),
///   title: 'Episode 3',
///   quality: PlayStackDownloadQuality.medium,
/// );
/// ```
///
/// A downloaded video needs nothing else: playing the same source (the
/// same URL or cache key) uses the saved copy, also without a network. While
/// downloads are off, nothing downloads and saved videos stream like any
/// other; the files are kept until [remove] or [removeAll].
///
/// The downloads belong to the app, not to one manager: every manager (and
/// every `PlayStackFeedView`) sees the same downloads and the same
/// [isEnabled].
///
/// Downloads go on in the background: on iOS by themselves, on Android when
/// the app declares the download service (see the offline viewing guide).
/// Not available on the web ([isSupported] is false).
class PlayStackDownloads {
  /// Creates the downloads of a manager. Apps use
  /// `PlayStackManager.downloads` instead of constructing one.
  @internal
  PlayStackDownloads(this._platform)
    : _state = _shared[_platform] ??= _SharedState();

  /// The state of the app's downloads, one per engine.
  static final Expando<_SharedState> _shared = Expando<_SharedState>();

  final PlayStackPlatform _platform;
  final _SharedState _state;
  bool _disposed = false;

  ValueNotifier<bool> get _enabled => _state.enabled;
  ValueNotifier<List<PlayStackDownload>> get _all => _state.all;

  /// Whether this platform can save videos (Android and iOS).
  Future<bool> isSupported() async {
    try {
      return _state.supported ??= await _platform.isDownloadSupported();
    } on Object {
      return false;
    }
  }

  /// Whether the user may download and watch offline right now; see
  /// [setEnabled].
  ValueListenable<bool> get isEnabled => _enabled;

  /// Every download, in the order they were started. Updates as they
  /// progress (about once a second).
  ValueListenable<List<PlayStackDownload>> get downloads => _all;

  /// The download [id], or null.
  PlayStackDownload? operator [](String id) {
    for (final download in _all.value) {
      if (download.id == id) return download;
    }
    return null;
  }

  /// The download of [source] (by its cache key or URL), or null.
  PlayStackDownload? forSource(PlayStackSource source) {
    if (source is! PlayStackNetworkSource) return null;
    final key = source.effectiveCacheKey;
    for (final download in _all.value) {
      if (download.key == key) return download;
    }
    return null;
  }

  /// Whether [source] plays without a network: it is downloaded and
  /// downloads are enabled.
  bool isAvailableOffline(PlayStackSource source) =>
      _enabled.value && (forSource(source)?.isCompleted ?? false);

  /// Turns downloading and offline viewing on or off, for example when the
  /// user subscribes or the subscription ends. While off, running downloads
  /// pause, new ones cannot start and saved videos stream from the network.
  Future<void> setEnabled(bool enabled) async {
    _throwIfDisposed();
    if (!await isSupported()) {
      _enabled.value = false;
      return;
    }
    await _platform.setDownloadsEnabled(enabled);
    _enabled.value = enabled;
    await _load();
  }

  /// Saves [source] under [id] (for example the episode id). Starting an
  /// [id] again replaces what was saved.
  ///
  /// [quality] picks the renditions of HLS and DASH streams
  /// ([PlayStackDownloadQuality.best] by default); [maxVideoHeight] sets an
  /// exact cap instead (720 saves at most 720p). [title] names the download
  /// in the
  /// Android notification; [metadata] is kept with it for your downloads
  /// screen.
  ///
  /// Throws [PlayStackException] with [PlayStackErrorCode.notAllowed] while
  /// downloads are off, [PlayStackErrorCode.invalidSource] for anything but
  /// a network source and [PlayStackErrorCode.notImplemented] where
  /// downloads are not supported.
  Future<void> download(
    String id,
    PlayStackSource source, {
    String? title,
    PlayStackDownloadQuality quality = PlayStackDownloadQuality.best,
    int? maxVideoHeight,
    Map<String, String> metadata = const {},
  }) async {
    _throwIfDisposed();
    if (!await isSupported()) {
      throw const PlayStackException(
        PlayStackErrorCode.notImplemented,
        'Downloads are not supported on this platform.',
      );
    }
    if (source is! PlayStackNetworkSource) {
      throw PlayStackException(
        PlayStackErrorCode.invalidSource,
        'Only network sources can be downloaded, not ${source.description}.',
      );
    }
    if (!_enabled.value) {
      throw const PlayStackException(
        PlayStackErrorCode.notAllowed,
        'Downloads are turned off; call setEnabled(true) first.',
      );
    }
    await _load();
    await _platform.startDownload(
      PlayStackDownloadRequest(
        id: id,
        source: source,
        title: title,
        maxVideoHeight: maxVideoHeight ?? quality.maxVideoHeight,
        metadata: metadata,
      ),
    );
  }

  /// Pauses the download [id].
  Future<void> pause(String id) => _platform.pauseDownload(id);

  /// Resumes the download [id], or retries it after a failure.
  Future<void> resume(String id) => _platform.resumeDownload(id);

  /// Deletes the download [id] and its files.
  Future<void> remove(String id) async {
    await _platform.removeDownload(id);
    _apply(PlayStackDownloadChange.removed(id));
  }

  /// Deletes every download, for example when the user signs out.
  Future<void> removeAll() async {
    await _load();
    for (final download in List.of(_all.value)) {
      await remove(download.id);
    }
  }

  /// Reads the saved downloads and follows their changes, once per app.
  Future<void> _load() async {
    if (_state.loaded || _disposed) return;
    _state.loaded = true;
    // Lives as long as the app: other managers share it.
    _state.changes = _platform.downloadChanges.listen(
      _apply,
      onError: (Object _) {},
    );
    try {
      _all.value = List.unmodifiable(await _platform.getDownloads());
    } on Object {
      _state.loaded = false;
      await _state.changes?.cancel();
      rethrow;
    }
  }

  void _apply(PlayStackDownloadChange change) {
    final list = List.of(_all.value);
    final id = change.download?.id ?? change.removedId;
    final index = list.indexWhere((download) => download.id == id);
    final download = change.download;
    if (download == null) {
      if (index < 0) return;
      list.removeAt(index);
    } else if (index < 0) {
      list.add(download);
    } else {
      if (list[index] == download) return;
      list[index] = download;
    }
    _all.value = List.unmodifiable(list);
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw const PlayStackException(
        PlayStackErrorCode.disposed,
        'The manager of these downloads was disposed.',
      );
    }
  }

  /// The manager is gone; the app's downloads and their state stay for
  /// other managers.
  @internal
  void dispose() {
    _disposed = true;
  }
}

class _SharedState {
  // Follows the engine for the app's lifetime, shared by every manager.
  // ignore: cancel_subscriptions
  StreamSubscription<PlayStackDownloadChange>? changes;
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);
  final ValueNotifier<List<PlayStackDownload>> all =
      ValueNotifier<List<PlayStackDownload>>(const []);
  bool? supported;
  bool loaded = false;
}
