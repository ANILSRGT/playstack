import 'package:flutter/foundation.dart';

import 'playstack_source.dart';

/// Where an offline download stands.
enum PlayStackDownloadState {
  /// Waiting to start, for example for another download or a network.
  queued,

  /// Saving now.
  downloading,

  /// Paused by the app, or because downloads are turned off.
  paused,

  /// Saved: plays without a network.
  completed,

  /// Stopped by an error; see [PlayStackDownload.error]. Start it again to
  /// retry.
  failed,
}

/// A video to save for offline viewing.
@immutable
class PlayStackDownloadRequest {
  /// Creates a request to save [source] under [id].
  const PlayStackDownloadRequest({
    required this.id,
    required this.source,
    this.title,
    this.maxVideoHeight,
    this.metadata = const {},
  });

  /// The app's id for the download, for example the episode id.
  final String id;

  /// The video. Playing the same URL (or cache key) later uses the download.
  final PlayStackNetworkSource source;

  /// Shown in the download notification on Android.
  final String? title;

  /// For adaptive streams (HLS, DASH): the tallest rendition to save, in
  /// lines (720 for 720p). Null saves the best one. Progressive files are
  /// saved as they are.
  final int? maxVideoHeight;

  /// The app's own values, kept with the download, for example a series
  /// name for a downloads screen.
  final Map<String, String> metadata;
}

/// One offline download and its progress.
@immutable
class PlayStackDownload {
  /// Creates the state of one download.
  const PlayStackDownload({
    required this.id,
    required this.key,
    required this.state,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.percent,
    this.title,
    this.metadata = const {},
    this.error,
  });

  /// The id given to the request.
  final String id;

  /// The source's cache key, or its URL when it has none. Playing a source
  /// with this key uses the download.
  final String key;

  /// Where the download stands.
  final PlayStackDownloadState state;

  /// Bytes saved so far.
  final int bytesDownloaded;

  /// Size of the whole download, when known.
  final int? totalBytes;

  /// Progress from 0 to 100, when known.
  final double? percent;

  /// The request's title.
  final String? title;

  /// The request's metadata.
  final Map<String, String> metadata;

  /// Why the download failed.
  final String? error;

  /// Whether it plays without a network.
  bool get isCompleted => state == PlayStackDownloadState.completed;

  /// Whether it is waiting or saving.
  bool get isActive =>
      state == PlayStackDownloadState.queued ||
      state == PlayStackDownloadState.downloading;

  @override
  bool operator ==(Object other) =>
      other is PlayStackDownload &&
      other.id == id &&
      other.key == key &&
      other.state == state &&
      other.bytesDownloaded == bytesDownloaded &&
      other.totalBytes == totalBytes &&
      other.percent == percent &&
      other.title == title &&
      mapEquals(other.metadata, metadata) &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    id,
    key,
    state,
    bytesDownloaded,
    totalBytes,
    percent,
    title,
    Object.hashAllUnordered(metadata.entries.map((e) => '${e.key}=${e.value}')),
    error,
  );

  @override
  String toString() =>
      'PlayStackDownload($id, ${state.name}, ${percent?.toStringAsFixed(0)}%)';
}

/// A change of one download, from `PlayStackPlatform.downloadChanges`.
@immutable
class PlayStackDownloadChange {
  /// A new state of [download].
  const PlayStackDownloadChange.updated(PlayStackDownload this.download)
    : removedId = null;

  /// The download [removedId] was deleted.
  const PlayStackDownloadChange.removed(String this.removedId)
    : download = null;

  /// The new state, or null when the download was removed.
  final PlayStackDownload? download;

  /// The id of the removed download, or null.
  final String? removedId;
}
