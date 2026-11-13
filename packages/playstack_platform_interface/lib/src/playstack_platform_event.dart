import 'package:flutter/foundation.dart';

import 'playstack_exception.dart';
import 'playstack_video_info.dart';

/// Native playback state, independent of whether playback is requested.
enum PlayStackNativePlaybackState {
  /// No media, or preparation has not started.
  idle,

  /// Not enough data to play at the current position.
  buffering,

  /// Able to play immediately.
  ready,

  /// Reached the end of the media.
  ended,
}

/// A low-frequency event emitted by a native player.
///
/// [generation] identifies the source the event belongs to. Pooled players
/// switch sources; consumers must drop events whose generation does not match
/// the source they assigned.
@immutable
sealed class PlayStackPlatformEvent {
  /// Creates an event.
  const PlayStackPlatformEvent({
    required this.playerId,
    required this.generation,
  });

  /// The native player that emitted the event.
  final int playerId;

  /// The source generation the event belongs to.
  final int generation;
}

/// The source finished preparing and its properties are known.
final class PlayStackInitializedEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackInitializedEvent({
    required super.playerId,
    required super.generation,
    required this.info,
  });

  /// Properties of the prepared source.
  final PlayStackVideoInfo info;
}

/// The native playback state changed.
final class PlayStackNativeStateEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackNativeStateEvent({
    required super.playerId,
    required super.generation,
    required this.state,
  });

  /// The new state.
  final PlayStackNativePlaybackState state;
}

/// Playback was requested (`true`) or stopped being requested (`false`), for
/// example by play/pause, reaching the end, or a system interruption.
///
/// Stalls while playback is requested are reported as
/// [PlayStackNativePlaybackState.buffering], not as `isPlaying == false`.
final class PlayStackIsPlayingEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackIsPlayingEvent({
    required super.playerId,
    required super.generation,
    required this.isPlaying,
  });

  /// Whether playback is requested.
  final bool isPlaying;
}

/// The rendered video size changed, for example after an ABR switch.
final class PlayStackVideoSizeEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackVideoSizeEvent({
    required super.playerId,
    required super.generation,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.pixelAspectRatio,
  });

  /// Encoded width in pixels.
  final int width;

  /// Encoded height in pixels.
  final int height;

  /// Clockwise rotation to apply for display: 0, 90, 180 or 270.
  final int rotationDegrees;

  /// Width of a pixel relative to its height.
  final double pixelAspectRatio;
}

/// The first frame of the current source reached the render target.
final class PlayStackFirstFrameEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackFirstFrameEvent({
    required super.playerId,
    required super.generation,
  });
}

/// The native player failed.
final class PlayStackErrorEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackErrorEvent({
    required super.playerId,
    required super.generation,
    required this.error,
  });

  /// What failed.
  final PlayStackException error;
}

/// The available or selected tracks changed.
final class PlayStackTracksChangedEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackTracksChangedEvent({
    required super.playerId,
    required super.generation,
  });
}

/// Why the system interrupted playback.
enum PlayStackInterruptionType {
  /// Another app took audio focus (Android) or the system interrupted the
  /// audio session (iOS: phone call, alarm, Siri).
  audioInterruption,

  /// Headphones or another audio route went away; playback was paused.
  audioRouteLost,
}

/// The system paused or resumed playback, not the app.
final class PlayStackInterruptionEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackInterruptionEvent({
    required super.playerId,
    required super.generation,
    required this.type,
    required this.ended,
  });

  /// What interrupted playback.
  final PlayStackInterruptionType type;

  /// False when the interruption began, true when it ended.
  final bool ended;
}

/// The subtitle text to display changed. An empty list clears it.
///
/// Engines deliver plain text; styling and positioning of the source format
/// are not preserved, so the application renders subtitles its own way.
final class PlayStackCuesEvent extends PlayStackPlatformEvent {
  /// Creates the event.
  const PlayStackCuesEvent({
    required super.playerId,
    required super.generation,
    required this.texts,
  });

  /// Lines of subtitle text to show, top to bottom.
  final List<String> texts;
}
