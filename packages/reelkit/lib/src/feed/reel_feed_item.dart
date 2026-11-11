import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// One entry of a `ReelFeedManager`.
///
/// The [id] identifies the item across insertions, removals and source
/// updates; it defaults to [ReelSource.id] and must be unique in the feed.
@immutable
class ReelFeedItem {
  /// Creates an item for [source]. Without [id], the source id or a
  /// generated id is used.
  ReelFeedItem(this.source, {String? id, this.poster, this.data})
    : id = id ?? source.id ?? 'reelkit-item-${_nextId++}';

  static int _nextId = 0;

  /// Identity of the item in its feed.
  final String id;

  /// The video to play.
  final ReelSource source;

  /// Image shown until the first frame is rendered. `ReelFeedView` shows it
  /// and downloads the posters of the next items ahead of time.
  final ImageProvider? poster;

  /// Anything the app attaches to the item, such as the post it belongs to.
  /// Read it back in `ReelFeedView` builders through `ReelFeedPage.data`.
  final Object? data;

  /// Returns a copy with the same [id] and the given fields replaced.
  ReelFeedItem copyWith({
    ReelSource? source,
    ImageProvider? poster,
    Object? data,
  }) => ReelFeedItem(
    source ?? this.source,
    id: id,
    poster: poster ?? this.poster,
    data: data ?? this.data,
  );

  @override
  bool operator ==(Object other) =>
      other is ReelFeedItem &&
      other.id == id &&
      other.source == source &&
      other.poster == poster &&
      other.data == data;

  @override
  int get hashCode => Object.hash(id, source, poster, data);

  @override
  String toString() => 'ReelFeedItem($id, ${source.description})';
}
