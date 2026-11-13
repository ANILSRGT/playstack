import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// One page of a `PlayStackFeedManager`: usually a video (what to play, a
/// poster and your own object), or a page without video such as an ad card
/// ([PlayStackFeedItem.page]).
///
/// You only create these when you manage a feed yourself
/// (`PlayStackFeedView.feed`). With `PlayStackFeedView(items: ...)` the view
/// creates them for you.
///
/// ```dart
/// PlayStackFeedItem(
///   PlayStackSource.network(post.videoUrl),
///   id: post.id,
///   poster: NetworkImage(post.thumbnailUrl),
///   data: post,
/// )
/// PlayStackFeedItem.page(id: 'ad-3', data: ad)
/// ```
@immutable
class PlayStackFeedItem {
  /// Creates an item that plays [source].
  ///
  /// [id] identifies the item in its feed (see [id]); without it, the
  /// source's [PlayStackSource.id] is used, or a unique id is generated.
  /// [poster], [data], [startPosition] and [locked] are optional.
  PlayStackFeedItem(
    PlayStackSource this.source, {
    String? id,
    this.poster,
    this.data,
    this.startPosition,
    this.locked = false,
  }) : id = id ?? source.id ?? 'playstack-item-${_nextId++}';

  /// Creates a page without video, such as an ad, a photo post or a "people
  /// to follow" card. `PlayStackFeedView` builds it with its `pageBuilder`.
  ///
  /// It takes no native player and is never preloaded.
  PlayStackFeedItem.page({String? id, this.poster, this.data})
    : source = null,
      startPosition = null,
      locked = false,
      id = id ?? 'playstack-item-${_nextId++}';

  const PlayStackFeedItem._({
    required this.id,
    required this.source,
    required this.poster,
    required this.data,
    required this.startPosition,
    required this.locked,
  });

  static int _nextId = 0;

  /// Identity of the item in its feed; must be unique in that feed.
  ///
  /// The feed keeps each item's player by id, so a video keeps playing when
  /// items are inserted or removed above it, and
  /// `PlayStackFeedManager.remove`, `indexOf` and `updateSource` find items by
  /// it. Use your own stable id, such as a post id.
  final String id;

  /// The video to play: a network URL, an asset, a file or bytes; null for a
  /// page without video ([PlayStackFeedItem.page]). Change it later with
  /// `PlayStackFeedManager.updateSource`, for example when a signed URL
  /// expires.
  final PlayStackSource? source;

  /// Image shown until the video's first frame appears, usually a thumbnail
  /// of that frame, and behind a locked item. `PlayStackFeedView` shows it
  /// and downloads the posters of the next items ahead of time. Without one,
  /// the page is black while the video loads.
  final ImageProvider? poster;

  /// Your own object for this item, such as the post it belongs to.
  /// PlayStack never reads it; `PlayStackFeedView` hands it back to your
  /// builders as `PlayStackFeedPage.data`.
  final Object? data;

  /// Where the video starts, for example where the user stopped watching an
  /// episode. Null starts at the beginning. See
  /// `PlayStackPlayerController.startPosition`.
  final Duration? startPosition;

  /// Whether the video is locked, for example an episode the user has not
  /// paid for. A locked item is never prepared or played; the feed shows it
  /// like a page without video until `PlayStackFeedManager.setLocked`
  /// unlocks it.
  final bool locked;

  /// Whether the item has a video ([source] is not null), locked or not.
  bool get isVideo => source != null;

  /// Whether the feed may prepare and play this item: it has a video and is
  /// not [locked].
  bool get isPlayable => source != null && !locked;

  /// Returns a copy with the same [id] and the given fields replaced.
  PlayStackFeedItem copyWith({
    PlayStackSource? source,
    ImageProvider? poster,
    Object? data,
    Duration? startPosition,
    bool? locked,
  }) => PlayStackFeedItem._(
    id: id,
    source: source ?? this.source,
    poster: poster ?? this.poster,
    data: data ?? this.data,
    startPosition: startPosition ?? this.startPosition,
    locked: locked ?? this.locked,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayStackFeedItem &&
      other.id == id &&
      other.source == source &&
      other.poster == poster &&
      other.data == data &&
      other.startPosition == startPosition &&
      other.locked == locked;

  @override
  int get hashCode =>
      Object.hash(id, source, poster, data, startPosition, locked);

  @override
  String toString() => switch (source) {
    null => 'PlayStackFeedItem.page($id)',
    final source =>
      'PlayStackFeedItem($id, ${source.description}'
          '${locked ? ', locked' : ''})',
  };
}
