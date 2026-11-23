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
        PlayStackDownload,
        PlayStackDownloadState,
        PlayStackDrm,
        PlayStackDrmType,
        PlayStackFileSource,
        PlayStackInterruptionType,
        PlayStackErrorCode,
        PlayStackException,
        PlayStackMediaInfo,
        PlayStackMemorySource,
        PlayStackNetworkSource,
        PlayStackNetworkStatus,
        PlayStackNetworkType,
        PlayStackPlatformCapabilities,
        PlayStackPositionSnapshot,
        PlayStackSource,
        PlayStackSubtitleFormat,
        PlayStackSubtitleSource,
        PlayStackTrack,
        PlayStackTrackType,
        PlayStackVideoFormat,
        PlayStackVideoInfo,
        PlayStackVideoQualityLimit;

export 'src/ads/playstack_ad.dart';
export 'src/ads/playstack_ad_controller.dart' hide PlayStackFeedAdLayer;
export 'src/cues/playstack_cues.dart' hide PlayStackFeedCueLayer;
export 'src/slots/playstack_show_rules.dart';
export 'src/slots/playstack_slot_layout.dart';
export 'src/analytics/playstack_analytics.dart' hide PlayStackAnalyticsTracker;
export 'src/cache/playstack_cache_manager.dart';
export 'src/config/playstack_config.dart';
export 'src/download/playstack_downloads.dart';
export 'src/controller/playstack_playback_state.dart';
export 'src/controller/playstack_player_controller.dart'
    show PlayStackInterruption, PlayStackPlayerController;
export 'src/controller/playstack_video_quality.dart';
export 'src/controller/playstack_player_metrics.dart';
export 'src/controller/playstack_sidecar_subtitles.dart'
    show PlayStackSubtitleCue, PlayStackSubtitleParser;
export 'src/feed/playstack_feed_config.dart';
export 'src/feed/playstack_feed_item.dart';
export 'src/feed/playstack_feed_manager.dart' show PlayStackFeedManager;
export 'src/feed/playstack_feed_stats.dart';
export 'src/feed/playstack_preload_window.dart';
export 'src/feed_view/playstack_debug_overlay.dart';
export 'src/feed_view/playstack_default_controls.dart';
export 'src/feed_view/playstack_feed_transition.dart';
export 'src/feed_view/playstack_feed_view.dart';
export 'src/feed_view/playstack_thumbnails.dart';
export 'src/fullscreen/playstack_fullscreen_manager.dart';
export 'src/manager/playstack_manager.dart';
export 'src/pool/playstack_player_pool.dart'
    show PlayStackPlayerPriority, PlayStackPoolStats;
export 'src/series/playstack_series.dart' hide PlayStackSeriesLayer;
export 'src/series/playstack_watch_progress.dart';
export 'src/system/playstack_airplay_button.dart';
export 'src/system/playstack_media_session.dart';
export 'src/system/playstack_sleep_timer.dart';
export 'src/view/playstack_video_view.dart';
