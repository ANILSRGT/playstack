/// ReelKit: a native video playback manager for Flutter.
///
/// ReelKit manages native players, pooling and lifecycle. You build the UI.
///
/// Start with [ReelKitManager], create a [ReelPlayerController] per video and
/// display it with [ReelVideoView].
library;

export 'package:reelkit_platform_interface/reelkit_platform_interface.dart'
    show
        ReelAssetSource,
        ReelFileSource,
        ReelKitErrorCode,
        ReelKitException,
        ReelMemorySource,
        ReelNetworkSource,
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
export 'src/manager/reel_kit_manager.dart';
export 'src/pool/reel_player_pool.dart' show ReelPlayerPriority, ReelPoolStats;
export 'src/view/reel_video_view.dart';
