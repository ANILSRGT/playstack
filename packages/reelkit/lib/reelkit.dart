/// ReelKit: a native video playback manager for Flutter.
///
/// ReelKit manages native players, pooling and lifecycle. You build the UI.
///
/// Start with [ReelKitManager], create a [ReelPlayerController] per video and
/// display it with [ReelVideoView]. For scrolling feeds, let a
/// [ReelFeedManager] (`ReelKitManager.createFeed`) assign players and
/// preload around the item in view.
library;

export 'package:reelkit_platform_interface/reelkit_platform_interface.dart'
    show
        ReelAssetSource,
        ReelFileSource,
        ReelKitErrorCode,
        ReelKitException,
        ReelMemorySource,
        ReelNetworkSource,
        ReelNetworkStatus,
        ReelNetworkType,
        ReelPlatformCapabilities,
        ReelPositionSnapshot,
        ReelSource,
        ReelTrack,
        ReelTrackType,
        ReelVideoFormat,
        ReelVideoInfo,
        ReelVideoQualityLimit;

export 'src/config/reel_kit_config.dart';
export 'src/controller/reel_playback_state.dart';
export 'src/controller/reel_player_controller.dart' show ReelPlayerController;
export 'src/controller/reel_player_metrics.dart';
export 'src/feed/reel_feed_config.dart';
export 'src/feed/reel_feed_item.dart';
export 'src/feed/reel_feed_manager.dart' show ReelFeedManager;
export 'src/feed/reel_feed_stats.dart';
export 'src/feed/reel_preload_window.dart';
export 'src/manager/reel_kit_manager.dart';
export 'src/pool/reel_player_pool.dart' show ReelPlayerPriority, ReelPoolStats;
export 'src/view/reel_video_view.dart';
