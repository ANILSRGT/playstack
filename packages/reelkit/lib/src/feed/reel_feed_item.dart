import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// One entry of a `ReelFeedManager`.
///
/// The [id] identifies the item across insertions, removals and source
/// updates; it defaults to [ReelSource.id] and must be unique in the feed.
@immutable
class ReelFeedItem {
  /// Creates an item for [source]. Without [id], the source id or a
  /// generated id is used.
  ReelFeedItem(this.source, {String? id})
    : id = id ?? source.id ?? 'reelkit-item-${_nextId++}';

  static int _nextId = 0;

  /// Identity of the item in its feed.
  final String id;

  /// The video to play.
  final ReelSource source;

  /// Returns a copy with the same [id] and a new [source].
  ReelFeedItem copyWith({ReelSource? source}) =>
      ReelFeedItem(source ?? this.source, id: id);

  @override
  bool operator ==(Object other) =>
      other is ReelFeedItem && other.id == id && other.source == source;

  @override
  int get hashCode => Object.hash(id, source);

  @override
  String toString() => 'ReelFeedItem($id, ${source.description})';
}
