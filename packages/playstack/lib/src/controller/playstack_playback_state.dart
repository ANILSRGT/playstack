import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// Where a `PlayStackPlayerController` is in its life, from created to disposed.
/// Read it as `controller.value.status`.
///
/// Typical order: [idle], [initializing], [ready], [playing] and [paused]
/// back and forth, then [completed] at the end of a non-looping video.
/// [error] can happen at any point; `retry()` leaves it.
enum PlayStackPlaybackStatus {
  /// Not prepared: nothing is loaded. A new controller starts here, and a
  /// controller returns here when it gives its native player away (to a more
  /// important controller or through `release`). The next `play` or
  /// `initialize` prepares it again.
  idle,

  /// Loading the video: connecting, reading its format, buffering the start.
  initializing,

  /// Prepared and able to start at once, but never played yet.
  ready,

  /// Playing, or trying to: check [PlayStackPlaybackState.isBuffering] for pauses
  /// while data loads.
  playing,

  /// Paused after playing. The video stays loaded and resumes at once.
  paused,

  /// Reached the end of a video that does not loop. `play` starts it over.
  completed,

  /// Loading or playback failed. [PlayStackPlaybackState.error] says why;
  /// `controller.retry()` tries again.
  error,

  /// The controller was disposed and can no longer be used.
  disposed,
}

/// Everything about a controller's playback at one moment: status,
/// buffering, size, duration, volume, error. Read it as `controller.value`
/// and rebuild with a `ValueListenableBuilder`:
///
/// ```dart
/// ValueListenableBuilder<PlayStackPlaybackState>(
///   valueListenable: controller,
///   builder: (context, state, _) {
///     if (state.hasError) return Text(state.error!.message);
///     if (state.isBuffering) return const CircularProgressIndicator();
///     return Icon(state.isPlaying ? Icons.pause : Icons.play_arrow);
///   },
/// )
/// ```
///
/// The position is not part of it, because it changes every frame and would
/// rebuild listeners constantly. Read it with
/// `PlayStackPlayerController.positions` or `getPosition`.
@immutable
class PlayStackPlaybackState {
  /// Creates a state. Controllers create these; apps only read them.
  const PlayStackPlaybackState({
    this.status = PlayStackPlaybackStatus.idle,
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

  /// Where the controller is: idle, loading, ready, playing, paused, completed, failed or disposed.
  final PlayStackPlaybackStatus status;

  /// Size, duration, rotation and frame rate of the video, known once it is
  /// prepared. Kept when the native player is given away, so layouts do not
  /// jump when the video prepares again.
  final PlayStackVideoInfo? videoInfo;

  /// What went wrong when [status] is [PlayStackPlaybackStatus.error]: its
  /// [PlayStackException.code] tells the kind (network, unsupported format...)
  /// and [PlayStackException.message] describes it.
  final PlayStackException? error;

  /// Whether playback waits for data, for example on a slow network. The
  /// status stays [PlayStackPlaybackStatus.playing] meanwhile; show a spinner from
  /// this flag (or use `PlayStackBufferingIndicator`).
  final bool isBuffering;

  /// Whether the controller holds a native player right now. False while
  /// idle, and after the player went to another controller.
  final bool isAttached;

  /// Whether a frame of the video is on screen. Until then `PlayStackVideoView`
  /// shows the poster; use it to fade a thumbnail out.
  final bool hasRenderedFirstFrame;

  /// Whether the video starts over at the end.
  final bool isLooping;

  /// Volume from 0.0 (silent) to 1.0 (full), as set with `setVolume`. While
  /// [isMuted], nothing is heard whatever the volume.
  final double volume;

  /// Whether sound is off. Muting keeps [volume], so unmuting restores it.
  final bool isMuted;

  /// Playback speed: 1.0 is normal, 2.0 double speed, 0.5 half speed.
  final double playbackSpeed;

  /// Whether the video is loaded and can play at once: ready, playing, paused
  /// or completed.
  bool get isInitialized => switch (status) {
    PlayStackPlaybackStatus.ready ||
    PlayStackPlaybackStatus.playing ||
    PlayStackPlaybackStatus.paused ||
    PlayStackPlaybackStatus.completed => true,
    _ => false,
  };

  /// Whether the video is playing (status [PlayStackPlaybackStatus.playing]). It
  /// can still be waiting for data; see [isBuffering].
  bool get isPlaying => status == PlayStackPlaybackStatus.playing;

  /// Whether [status] is [PlayStackPlaybackStatus.error]; see [error].
  bool get hasError => status == PlayStackPlaybackStatus.error;

  /// Length of the video, or null before it is prepared and for live streams.
  Duration? get duration => videoInfo?.duration;

  /// Width divided by height as displayed (rotation and pixel shape applied),
  /// or null before the size is known. Greater than 1 for landscape videos.
  double? get aspectRatio {
    final info = videoInfo;
    if (info == null || !info.hasSize) return null;
    return info.aspectRatio;
  }

  /// Returns a copy with the given fields replaced.
  PlayStackPlaybackState copyWith({
    PlayStackPlaybackStatus? status,
    PlayStackVideoInfo? videoInfo,
    bool clearVideoInfo = false,
    PlayStackException? error,
    bool clearError = false,
    bool? isBuffering,
    bool? isAttached,
    bool? hasRenderedFirstFrame,
    bool? isLooping,
    double? volume,
    bool? isMuted,
    double? playbackSpeed,
  }) {
    return PlayStackPlaybackState(
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
      other is PlayStackPlaybackState &&
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
      'PlayStackPlaybackState(${status.name}, attached: $isAttached, '
      'buffering: $isBuffering, firstFrame: $hasRenderedFirstFrame, '
      'info: $videoInfo, error: $error)';
}
