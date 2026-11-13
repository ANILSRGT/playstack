/// PlayStack: a native video playback manager for Flutter.
///
/// PlayStack manages native players, pooling and lifecycle.
///
/// Start with [PlayStackManager]. For a short-video feed, create a
/// [PlayStackFeedManager] (`PlayStackManager.createFeed`) and show it with
/// [PlayStackFeedView]: paging, transitions, playback and preloading are handled,
/// and you supply the controls (or keep [PlayStackDefaultControls]). For a single
/// player, create a [PlayStackPlayerController] and display it with
/// [PlayStackVideoView].
library;

export 'package:playstack_platform_interface/playstack_platform_interface.dart'
    show
        PlayStackAssetSource,
        PlayStackAudioSessionCategory,
        PlayStackCacheInfo,
        PlayStackCachePolicy,
        PlayStackFileSource,
        PlayStackInterruptionType,
        PlayStackErrorCode,
        PlayStackException,
        PlayStackMemorySource,
        PlayStackNetworkSource,
        PlayStackNetworkStatus,
        PlayStackNetworkType,
        PlayStackPlatformCapabilities,
        PlayStackPositionSnapshot,
        PlayStackSource,
        PlayStackTrack,
        PlayStackTrackType,
        PlayStackVideoFormat,
        PlayStackVideoInfo,
        PlayStackVideoQualityLimit;

export 'src/cache/playstack_cache_manager.dart';
export 'src/config/playstack_config.dart';
export 'src/controller/playstack_playback_state.dart';
export 'src/controller/playstack_player_controller.dart'
    show PlayStackInterruption, PlayStackPlayerController;
export 'src/controller/playstack_player_metrics.dart';
export 'src/feed/playstack_feed_config.dart';
export 'src/feed/playstack_feed_item.dart';
export 'src/feed/playstack_feed_manager.dart' show PlayStackFeedManager;
export 'src/feed/playstack_feed_stats.dart';
export 'src/feed/playstack_preload_window.dart';
export 'src/feed_view/playstack_default_controls.dart';
export 'src/feed_view/playstack_feed_transition.dart';
export 'src/feed_view/playstack_feed_view.dart';
export 'src/fullscreen/playstack_fullscreen_manager.dart';
export 'src/manager/playstack_manager.dart';
export 'src/pool/playstack_player_pool.dart'
    show PlayStackPlayerPriority, PlayStackPoolStats;
export 'src/view/playstack_video_view.dart';
