import 'package:flutter/foundation.dart';

import '../config/playstack_config.dart';

/// How a feed prepares videos around the one in view, so that swiping to
/// them starts playback at once.
///
/// Preparing a video means loading it far enough to show its first frame
/// and play a few seconds. More videos prepared ahead means fewer waits when
/// swiping fast, at the cost of data, memory and decoders. The feed lowers
/// these numbers by itself on mobile data, with data saver, on low-memory
/// devices and after memory warnings.
///
/// ```dart
/// const PlayStackFeedConfig(preloadAhead: 2, preloadBehind: 1) // lighter
/// PlayStackFeedConfig.reels                                     // fast swiping
/// ```
@immutable
class PlayStackFeedConfig {
  /// Creates a feed configuration. Defaults: two items prepared ahead, one
  /// behind, one preparation at a time, autoplay on.
  const PlayStackFeedConfig({
    this.preloadAhead = 2,
    this.preloadBehind = 1,
    this.autoplay = true,
    this.maxConcurrentPreloads = 1,
    this.activeHeadStart = const Duration(milliseconds: 300),
    this.network = const PlayStackNetworkPreloadPolicy(),
    this.lowMemoryPreloadAhead = 1,
    this.memoryPressureCooldown = const Duration(seconds: 30),
    this.retryFailedPreloads = true,
    this.controllerRetention = 20,
    this.player,
  }) : assert(preloadAhead >= 0),
       assert(preloadBehind >= 0),
       assert(maxConcurrentPreloads > 0),
       assert(lowMemoryPreloadAhead >= 0),
       assert(controllerRetention >= 0);

  /// Preloading tuned for swiping two or three videos a second: five items
  /// ahead, one behind, three preparing at a time. `PlayStackFeedView` uses it
  /// by default. Use it with `PlayStackConfig.reels`, whose pool has room
  /// for the window.
  static const PlayStackFeedConfig reels = PlayStackFeedConfig(
    preloadAhead: 5,
    preloadBehind: 1,
    maxConcurrentPreloads: 3,
  );

  /// How many upcoming items are prepared before the user reaches them, 2 by
  /// default. Raise it for users who swipe fast; lower it to save data.
  final int preloadAhead;

  /// How many previous items stay prepared, so swiping back is instant, 1 by
  /// default.
  final int preloadBehind;

  /// Whether the item in view starts playing on its own, true by default.
  /// When false it is only prepared, and you call `play` (for example on a
  /// tap).
  final bool autoplay;

  /// How many items prepare at the same time besides the one in view, 1 by
  /// default. One gets the next item ready soonest; [PlayStackFeedConfig.reels]
  /// uses three so that fast swipes find more items ready.
  final int maxConcurrentPreloads;

  /// How long preloads wait for an active item that is still preparing
  /// before they start anyway.
  ///
  /// The active item gets the network first, but HLS and DASH startup is
  /// bound by round trips rather than bandwidth: if preloads waited for a
  /// slow active item to finish, a user swiping quickly would arrive at
  /// item after item that nobody had started preparing. [Duration.zero]
  /// starts preloads together with the active item.
  final Duration activeHeadStart;

  /// How far ahead to prepare on mobile data and with data saver. By default
  /// one item ahead and none behind on mobile data, and none ahead with data
  /// saver (only the item in view loads).
  final PlayStackNetworkPreloadPolicy network;

  /// Most items prepared ahead on devices the system reports as low on memory
  /// (Android `isLowRamDevice`, small iOS devices), 1 by default. Nothing is
  /// kept behind there.
  final int lowMemoryPreloadAhead;

  /// After the system warns that memory is low, only the next item is
  /// prepared for this long, 30 seconds by default.
  final Duration memoryPressureCooldown;

  /// Whether an item that failed to prepare ahead (network error, timeout) is
  /// tried once more when the user moves or the network returns, true by
  /// default. The item in view is always retried.
  final bool retryFailedPreloads;

  /// How far from the item in view (beyond the preparation window)
  /// controllers are kept, 20 by default. Further ones are disposed and
  /// recreated when needed, so endless feeds use flat memory.
  final int controllerRetention;

  /// Settings of the feed's players (looping, mute, quality caps). Null uses
  /// the manager's `PlayStackConfig.player`.
  final PlayStackPlayerConfig? player;

  @override
  bool operator ==(Object other) =>
      other is PlayStackFeedConfig &&
      other.preloadAhead == preloadAhead &&
      other.preloadBehind == preloadBehind &&
      other.autoplay == autoplay &&
      other.maxConcurrentPreloads == maxConcurrentPreloads &&
      other.activeHeadStart == activeHeadStart &&
      other.network == network &&
      other.lowMemoryPreloadAhead == lowMemoryPreloadAhead &&
      other.memoryPressureCooldown == memoryPressureCooldown &&
      other.retryFailedPreloads == retryFailedPreloads &&
      other.controllerRetention == controllerRetention &&
      other.player == player;

  @override
  int get hashCode => Object.hash(
    preloadAhead,
    preloadBehind,
    autoplay,
    maxConcurrentPreloads,
    activeHeadStart,
    network,
    lowMemoryPreloadAhead,
    memoryPressureCooldown,
    retryFailedPreloads,
    controllerRetention,
    player,
  );
}

/// How far ahead a feed prepares on limited networks. Each value only
/// lowers the configured window, never raises it.
@immutable
class PlayStackNetworkPreloadPolicy {
  /// Creates a network policy. Defaults: one item ahead and none behind on
  /// mobile data; none ahead with data saver.
  const PlayStackNetworkPreloadPolicy({
    this.meteredPreloadAhead = 1,
    this.meteredPreloadBehind = 0,
    this.constrainedPreloadAhead = 0,
  }) : assert(meteredPreloadAhead >= 0),
       assert(meteredPreloadBehind >= 0),
       assert(constrainedPreloadAhead >= 0);

  /// Most items prepared ahead on networks billed by volume (mobile data, a
  /// hotspot), 1 by default.
  final int meteredPreloadAhead;

  /// Most items kept prepared behind on networks billed by volume, 0 by default.
  final int meteredPreloadBehind;

  /// Items ahead when the user asked to save data (Android Data Saver, iOS
  /// Low Data Mode, browser `saveData`). Nothing is kept behind.
  final int constrainedPreloadAhead;

  @override
  bool operator ==(Object other) =>
      other is PlayStackNetworkPreloadPolicy &&
      other.meteredPreloadAhead == meteredPreloadAhead &&
      other.meteredPreloadBehind == meteredPreloadBehind &&
      other.constrainedPreloadAhead == constrainedPreloadAhead;

  @override
  int get hashCode => Object.hash(
    meteredPreloadAhead,
    meteredPreloadBehind,
    constrainedPreloadAhead,
  );
}
