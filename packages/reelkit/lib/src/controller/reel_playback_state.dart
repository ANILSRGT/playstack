import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// Lifecycle and playback status of a `ReelPlayerController`.
enum ReelPlaybackStatus {
  /// Not prepared. Either never initialized, or the native player was handed
  /// to a higher-priority controller.
  idle,

  /// Preparing the source.
  initializing,

  /// Prepared and able to play, never started.
  ready,

  /// Playing. Check [ReelPlaybackState.isBuffering] for stalls.
  playing,

  /// Paused after playing.
  paused,

  /// Reached the end of a non-looping video.
  completed,

  /// Failed. See [ReelPlaybackState.error].
  error,

  /// The controller was disposed.
  disposed,
}

/// Immutable snapshot of a controller's playback state.
///
/// Position is deliberately not part of this snapshot: it changes every frame
/// and would rebuild every listener continuously. Read it on demand with
/// `ReelPlayerController.getPosition`.
@immutable
class ReelPlaybackState {
  const ReelPlaybackState({
    this.status = ReelPlaybackStatus.idle,
    this.videoInfo,
    this.error,
    this.isBuffering = false,
    this.isAttached = false,
    this.hasRenderedFirstFrame = false,
    this.isLooping = false,
    this.volume = 1.0,
    this.isMuted = false,
    this.playbackSpeed = 1.0,
  });

  final ReelPlaybackStatus status;

  /// Size, duration and orientation of the prepared video. Retained after the
  /// native player is reassigned so layouts do not jump.
  final ReelVideoInfo? videoInfo;

  /// The last error, set when [status] is [ReelPlaybackStatus.error].
  final ReelKitException? error;

  /// Whether playback is stalled waiting for data.
  final bool isBuffering;

  /// Whether the controller currently holds a native player.
  final bool isAttached;

  /// Whether the current source has drawn at least one frame.
  final bool hasRenderedFirstFrame;

  final bool isLooping;

  /// Volume from 0.0 to 1.0. The audible volume is 0 while [isMuted].
  final double volume;

  final bool isMuted;

  final double playbackSpeed;

  /// Whether the source is prepared.
  bool get isInitialized => switch (status) {
    ReelPlaybackStatus.ready ||
    ReelPlaybackStatus.playing ||
    ReelPlaybackStatus.paused ||
    ReelPlaybackStatus.completed => true,
    _ => false,
  };

  bool get isPlaying => status == ReelPlaybackStatus.playing;

  bool get hasError => status == ReelPlaybackStatus.error;

  Duration? get duration => videoInfo?.duration;

  /// Display aspect ratio, or null before the size is known.
  double? get aspectRatio {
    final info = videoInfo;
    if (info == null || !info.hasSize) return null;
    return info.aspectRatio;
  }

  ReelPlaybackState copyWith({
    ReelPlaybackStatus? status,
    ReelVideoInfo? videoInfo,
    bool clearVideoInfo = false,
    ReelKitException? error,
    bool clearError = false,
    bool? isBuffering,
    bool? isAttached,
    bool? hasRenderedFirstFrame,
    bool? isLooping,
    double? volume,
    bool? isMuted,
    double? playbackSpeed,
  }) {
    return ReelPlaybackState(
      status: status ?? this.status,
      videoInfo: clearVideoInfo ? null : (videoInfo ?? this.videoInfo),
      error: clearError ? null : (error ?? this.error),
      isBuffering: isBuffering ?? this.isBuffering,
      isAttached: isAttached ?? this.isAttached,
      hasRenderedFirstFrame:
          hasRenderedFirstFrame ?? this.hasRenderedFirstFrame,
      isLooping: isLooping ?? this.isLooping,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReelPlaybackState &&
      other.status == status &&
      other.videoInfo == videoInfo &&
      other.error == error &&
      other.isBuffering == isBuffering &&
      other.isAttached == isAttached &&
      other.hasRenderedFirstFrame == hasRenderedFirstFrame &&
      other.isLooping == isLooping &&
      other.volume == volume &&
      other.isMuted == isMuted &&
      other.playbackSpeed == playbackSpeed;

  @override
  int get hashCode => Object.hash(
    status,
    videoInfo,
    error,
    isBuffering,
    isAttached,
    hasRenderedFirstFrame,
    isLooping,
    volume,
    isMuted,
    playbackSpeed,
  );

  @override
  String toString() =>
      'ReelPlaybackState(${status.name}, attached: $isAttached, '
      'buffering: $isBuffering, firstFrame: $hasRenderedFirstFrame, '
      'info: $videoInfo, error: $error)';
}
