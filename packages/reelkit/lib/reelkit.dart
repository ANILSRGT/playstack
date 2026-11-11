/// ReelKit: a native video playback manager for Flutter.
///
/// ReelKit manages native players, pooling and lifecycle.
///
/// Start with [ReelKitManager]. For a short-video feed, create a
/// [ReelFeedManager] (`ReelKitManager.createFeed`) and show it with
/// [ReelFeedView]: paging, transitions, playback and preloading are handled,
/// and you supply the controls (or keep [ReelDefaultControls]). For a single
/// player, create a [ReelPlayerController] and display it with
/// [ReelVideoView].
library;

export 'package:reelkit_platform_interface/reelkit_platform_interface.dart'
    show
        ReelAssetSource,
        ReelAudioSessionCategory,
        ReelCacheInfo,
        ReelCachePolicy,
        ReelFileSource,
        ReelInterruptionType,
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

export 'src/cache/reel_cache_manager.dart';
export 'src/config/reel_kit_config.dart';
export 'src/controller/reel_playback_state.dart';
export 'src/controller/reel_player_controller.dart'
    show ReelInterruption, ReelPlayerController;
export 'src/controller/reel_player_metrics.dart';
export 'src/feed/reel_feed_config.dart';
export 'src/feed/reel_feed_item.dart';
export 'src/feed/reel_feed_manager.dart' show ReelFeedManager;
export 'src/feed/reel_feed_stats.dart';
export 'src/feed/reel_preload_window.dart';
export 'src/feed_view/reel_default_controls.dart';
export 'src/feed_view/reel_feed_transition.dart';
export 'src/feed_view/reel_feed_view.dart';
export 'src/fullscreen/reel_fullscreen_manager.dart';
export 'src/manager/reel_kit_manager.dart';
export 'src/pool/reel_player_pool.dart' show ReelPlayerPriority, ReelPoolStats;
export 'src/view/reel_video_view.dart';
