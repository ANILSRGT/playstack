import 'package:flutter/foundation.dart';

/// Timing of a controller's most recent preparation and playback start,
/// measured in Dart from the command to the engine's event. Intended for
/// diagnostics and benchmarks; it does not notify listeners.
@immutable
class ReelPlayerMetrics {
  const ReelPlayerMetrics({
    this.preparations = 0,
    this.lastPreparationTime,
    this.lastTimeToFirstFrame,
    this.lastStartLatency,
  });

  /// How many times a source was prepared (including retries and
  /// re-preparation after losing the native player).
  final int preparations;

  /// From the start of the last preparation until the engine reported the
  /// video ready.
  final Duration? lastPreparationTime;

  /// From the start of the last preparation until its first frame was
  /// rendered.
  final Duration? lastTimeToFirstFrame;

  /// From the last `play` call until the engine reported playback. Short
  /// when the video was prepared ahead of time.
  final Duration? lastStartLatency;

  ReelPlayerMetrics copyWith({
    int? preparations,
    Duration? lastPreparationTime,
    Duration? lastTimeToFirstFrame,
    Duration? lastStartLatency,
  }) {
    return ReelPlayerMetrics(
      preparations: preparations ?? this.preparations,
      lastPreparationTime: lastPreparationTime ?? this.lastPreparationTime,
      lastTimeToFirstFrame: lastTimeToFirstFrame ?? this.lastTimeToFirstFrame,
      lastStartLatency: lastStartLatency ?? this.lastStartLatency,
    );
  }

  @override
  String toString() =>
      'ReelPlayerMetrics(preparations: $preparations, '
      'prepare: ${lastPreparationTime?.inMilliseconds} ms, '
      'firstFrame: ${lastTimeToFirstFrame?.inMilliseconds} ms, '
      'start: ${lastStartLatency?.inMilliseconds} ms)';
}
