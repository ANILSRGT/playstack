import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// One video of a `ReelFeedManager`: what to play, a poster, and your own
/// object.
///
/// You only create these when you manage a feed yourself
/// (`ReelFeedView.feed`). With `ReelFeedView(items: ...)` the view creates
/// them for you.
///
/// ```dart
/// ReelFeedItem(
///   ReelSource.network(post.videoUrl),
///   id: post.id,
///   poster: NetworkImage(post.thumbnailUrl),
///   data: post,
/// )
/// ```
@immutable
class ReelFeedItem {
  /// Creates an item that plays [source].
  ///
  /// [id] identifies the item in its feed (see [id]); without it, the
  /// source's [ReelSource.id] is used, or a unique id is generated. [poster]
  /// [data] and [startPosition] are optional.
  ReelFeedItem(
    this.source, {
    String? id,
    this.poster,
    this.data,
    this.startPosition,
  }) : id = id ?? source.id ?? 'reelkit-item-${_nextId++}';

  static int _nextId = 0;

  /// Identity of the item in its feed; must be unique in that feed.
  ///
  /// The feed keeps each item's player by id, so a video keeps playing when
  /// items are inserted or removed above it, and `ReelFeedManager.remove`,
  /// `indexOf` and `updateSource` find items by it. Use your own stable id,
  /// such as a post id.
  final String id;

  /// The video to play: a network URL, an asset, a file or bytes. Change it
  /// later with `ReelFeedManager.updateSource`, for example when a signed URL
  /// expires.
  final ReelSource source;

  /// Image shown until the video's first frame appears, usually a thumbnail
  /// of that frame. `ReelFeedView` shows it and downloads the posters of the
  /// next items ahead of time. Without one, the page is black while the video
  /// loads.
  final ImageProvider? poster;

  /// Your own object for this item, such as the post it belongs to. ReelKit
  /// never reads it; `ReelFeedView` hands it back to your builders as
  /// `ReelFeedPage.data`.
  final Object? data;

  /// Where the video starts, for example where the user stopped watching an
  /// episode. Null starts at the beginning. See
  /// `ReelPlayerController.startPosition`.
  final Duration? startPosition;

  /// Returns a copy with the same [id] and the given fields replaced.
  ReelFeedItem copyWith({
    ReelSource? source,
    ImageProvider? poster,
    Object? data,
    Duration? startPosition,
  }) => ReelFeedItem(
    source ?? this.source,
    id: id,
    poster: poster ?? this.poster,
    data: data ?? this.data,
    startPosition: startPosition ?? this.startPosition,
  );

  @override
  bool operator ==(Object other) =>
      other is ReelFeedItem &&
      other.id == id &&
      other.source == source &&
      other.poster == poster &&
      other.data == data &&
      other.startPosition == startPosition;

  @override
  int get hashCode => Object.hash(id, source, poster, data, startPosition);

  @override
  String toString() => 'ReelFeedItem($id, ${source.description})';
}
