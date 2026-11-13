import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// One video of a `PlayStackFeedManager`: what to play, a poster, and your own
/// object.
///
/// You only create these when you manage a feed yourself
/// (`PlayStackFeedView.feed`). With `PlayStackFeedView(items: ...)` the view creates
/// them for you.
///
/// ```dart
/// PlayStackFeedItem(
///   PlayStackSource.network(post.videoUrl),
///   id: post.id,
///   poster: NetworkImage(post.thumbnailUrl),
///   data: post,
/// )
/// ```
@immutable
class PlayStackFeedItem {
  /// Creates an item that plays [source].
  ///
  /// [id] identifies the item in its feed (see [id]); without it, the
  /// source's [PlayStackSource.id] is used, or a unique id is generated. [poster]
  /// [data] and [startPosition] are optional.
  PlayStackFeedItem(
    this.source, {
    String? id,
    this.poster,
    this.data,
    this.startPosition,
  }) : id = id ?? source.id ?? 'playstack-item-${_nextId++}';

  static int _nextId = 0;

  /// Identity of the item in its feed; must be unique in that feed.
  ///
  /// The feed keeps each item's player by id, so a video keeps playing when
  /// items are inserted or removed above it, and `PlayStackFeedManager.remove`,
  /// `indexOf` and `updateSource` find items by it. Use your own stable id,
  /// such as a post id.
  final String id;

  /// The video to play: a network URL, an asset, a file or bytes. Change it
  /// later with `PlayStackFeedManager.updateSource`, for example when a signed URL
  /// expires.
  final PlayStackSource source;

  /// Image shown until the video's first frame appears, usually a thumbnail
  /// of that frame. `PlayStackFeedView` shows it and downloads the posters of the
  /// next items ahead of time. Without one, the page is black while the video
  /// loads.
  final ImageProvider? poster;

  /// Your own object for this item, such as the post it belongs to. PlayStack
  /// never reads it; `PlayStackFeedView` hands it back to your builders as
  /// `PlayStackFeedPage.data`.
  final Object? data;

  /// Where the video starts, for example where the user stopped watching an
  /// episode. Null starts at the beginning. See
  /// `PlayStackPlayerController.startPosition`.
  final Duration? startPosition;

  /// Returns a copy with the same [id] and the given fields replaced.
  PlayStackFeedItem copyWith({
    PlayStackSource? source,
    ImageProvider? poster,
    Object? data,
    Duration? startPosition,
  }) => PlayStackFeedItem(
    source ?? this.source,
    id: id,
    poster: poster ?? this.poster,
    data: data ?? this.data,
    startPosition: startPosition ?? this.startPosition,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayStackFeedItem &&
      other.id == id &&
      other.source == source &&
      other.poster == poster &&
      other.data == data &&
      other.startPosition == startPosition;

  @override
  int get hashCode => Object.hash(id, source, poster, data, startPosition);

  @override
  String toString() => 'PlayStackFeedItem($id, ${source.description})';
}
