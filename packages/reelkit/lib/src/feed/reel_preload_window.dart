import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

import 'reel_feed_config.dart';

/// The number of items prepared around the active one right now, after
/// network, memory and decoder limits.
@immutable
class ReelPreloadWindow {
  /// Creates a window of [ahead] following and [behind] previous items.
  const ReelPreloadWindow({required this.ahead, required this.behind});

  /// Only the active item is prepared.
  static const none = ReelPreloadWindow(ahead: 0, behind: 0);

  /// Items after the active one that are prepared.
  final int ahead;

  /// Items before the active one that are prepared.
  final int behind;

  /// Resolves the effective window.
  ///
  /// The configured window is capped by the network policy, by low-memory
  /// limits, and finally by the pool: one native player is reserved for the
  /// active item, so at most `maxPlayers - 1` items are prepared around it
  /// (items behind give way first).
  static ReelPreloadWindow resolve({
    required ReelFeedConfig config,
    required ReelNetworkStatus network,
    required bool isLowRamDevice,
    required bool underMemoryPressure,
    required int maxPlayers,
  }) {
    var ahead = config.preloadAhead;
    var behind = config.preloadBehind;
    final policy = config.network;
    if (network.isConstrained) {
      ahead = math.min(ahead, policy.constrainedPreloadAhead);
      behind = 0;
    } else if (network.isMetered) {
      ahead = math.min(ahead, policy.meteredPreloadAhead);
      behind = math.min(behind, policy.meteredPreloadBehind);
    }
    if (isLowRamDevice) {
      ahead = math.min(ahead, config.lowMemoryPreloadAhead);
      behind = 0;
    }
    if (underMemoryPressure) {
      ahead = math.min(ahead, 1);
      behind = 0;
    }
    final capacity = math.max(0, maxPlayers - 1);
    if (ahead + behind > capacity) {
      behind = math.max(0, capacity - ahead);
      ahead = math.min(ahead, capacity);
    }
    return ReelPreloadWindow(ahead: ahead, behind: behind);
  }

  /// Indices to prepare around [active] in a list of [length], most
  /// important first: the next item, the previous item, further items
  /// ahead, further items behind.
  List<int> order(int active, int length) {
    final result = <int>[];
    void add(int index) {
      if (index >= 0 && index < length) result.add(index);
    }

    if (ahead > 0) add(active + 1);
    if (behind > 0) add(active - 1);
    for (var i = 2; i <= ahead; i++) {
      add(active + i);
    }
    for (var i = 2; i <= behind; i++) {
      add(active - i);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ReelPreloadWindow &&
      other.ahead == ahead &&
      other.behind == behind;

  @override
  int get hashCode => Object.hash(ahead, behind);

  @override
  String toString() => 'ReelPreloadWindow(ahead: $ahead, behind: $behind)';
}
