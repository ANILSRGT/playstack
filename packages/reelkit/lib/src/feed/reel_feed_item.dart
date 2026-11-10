import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// One entry of a `ReelFeedManager`.
///
/// The [id] identifies the item across insertions, removals and source
/// updates; it defaults to [ReelSource.id] and must be unique in the feed.
@immutable
class ReelFeedItem {
  ReelFeedItem(this.source, {String? id})
    : id = id ?? source.id ?? 'reelkit-item-${_nextId++}';

  static int _nextId = 0;

  final String id;
  final ReelSource source;

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
