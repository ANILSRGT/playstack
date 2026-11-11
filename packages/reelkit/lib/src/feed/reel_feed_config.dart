import 'package:flutter/foundation.dart';

import '../config/reel_kit_config.dart';

/// How a `ReelFeedManager` prepares items around the active one.
@immutable
class ReelFeedConfig {
  /// Creates a feed configuration.
  const ReelFeedConfig({
    this.preloadAhead = 2,
    this.preloadBehind = 1,
    this.autoplay = true,
    this.maxConcurrentPreloads = 1,
    this.activeHeadStart = const Duration(milliseconds: 300),
    this.network = const ReelNetworkPreloadPolicy(),
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
  /// ahead, one behind, three preparing at a time. `ReelFeedView` uses it
  /// by default. Use it with `ReelKitConfig.reels`, whose pool has room
  /// for the window.
  static const ReelFeedConfig reels = ReelFeedConfig(
    preloadAhead: 5,
    preloadBehind: 1,
    maxConcurrentPreloads: 3,
  );

  /// Items after the active one to prepare (first frame decoded, a few
  /// seconds buffered) before the user reaches them.
  final int preloadAhead;

  /// Items before the active one to keep prepared, for scrolling back.
  final int preloadBehind;

  /// Whether the active item starts playing when it becomes active. When
  /// false it is only prepared, and the app calls `play`.
  final bool autoplay;

  /// Preparations running at the same time besides the active item. One is
  /// usually best: the next item is ready soonest and bandwidth is not split.
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

  /// Smaller preload windows on metered, constrained or missing networks.
  final ReelNetworkPreloadPolicy network;

  /// Upper bound of [preloadAhead] on devices the platform reports as low
  /// on memory (Android `isLowRamDevice`, small iOS devices). Items behind
  /// are not kept there.
  final int lowMemoryPreloadAhead;

  /// After an operating-system memory warning, preloading is limited to the
  /// next item (nothing behind) for this long.
  final Duration memoryPressureCooldown;

  /// Whether preloads that failed with a network or timeout error are tried
  /// again, at most once per item, on the next plan (index change or
  /// network recovery). The active item is always retried when activated.
  final bool retryFailedPreloads;

  /// Dart controllers of items further than the preload window plus this
  /// distance from the active item are disposed (they hold no native player
  /// anyway) and recreated by `controllerAt` on demand. Keeps memory flat in
  /// endless feeds.
  final int controllerRetention;

  /// Settings of the feed's controllers. Defaults to the manager's
  /// `ReelKitConfig.player`.
  final ReelPlayerConfig? player;

  @override
  bool operator ==(Object other) =>
      other is ReelFeedConfig &&
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

/// Preload limits by network condition. Each value caps the configured
/// window; it never enlarges it.
@immutable
class ReelNetworkPreloadPolicy {
  /// Creates a network preload policy.
  const ReelNetworkPreloadPolicy({
    this.meteredPreloadAhead = 1,
    this.meteredPreloadBehind = 0,
    this.constrainedPreloadAhead = 0,
  }) : assert(meteredPreloadAhead >= 0),
       assert(meteredPreloadBehind >= 0),
       assert(constrainedPreloadAhead >= 0);

  /// Items ahead on networks billed by volume (cellular, hotspot).
  final int meteredPreloadAhead;

  /// Items behind on metered networks.
  final int meteredPreloadBehind;

  /// Items ahead when the user asked to save data (Android Data Saver, iOS
  /// Low Data Mode, browser `saveData`). Nothing is kept behind.
  final int constrainedPreloadAhead;

  @override
  bool operator ==(Object other) =>
      other is ReelNetworkPreloadPolicy &&
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
