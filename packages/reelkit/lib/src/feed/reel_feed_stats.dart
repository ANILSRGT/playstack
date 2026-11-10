import 'package:flutter/foundation.dart';

/// Counters of a `ReelFeedManager`, for diagnostics and benchmarks.
@immutable
class ReelFeedStats {
  const ReelFeedStats({
    this.transitions = 0,
    this.preparedOnArrival = 0,
    this.preloadsStarted = 0,
    this.preloadsCompleted = 0,
    this.preloadsFailed = 0,
    this.preloadsCancelled = 0,
    this.lastStartLatency,
    this.totalStartLatency = Duration.zero,
    this.measuredStarts = 0,
  });

  /// Changes of the active item.
  final int transitions;

  /// Transitions whose new active item was already prepared.
  final int preparedOnArrival;

  final int preloadsStarted;
  final int preloadsCompleted;
  final int preloadsFailed;

  /// Preloads abandoned because the window moved before they finished.
  final int preloadsCancelled;

  /// From the last index change until its item played (autoplay only).
  final Duration? lastStartLatency;

  final Duration totalStartLatency;
  final int measuredStarts;

  /// Share of transitions that found the item prepared, from 0 to 1.
  double get preloadHitRate =>
      transitions == 0 ? 0 : preparedOnArrival / transitions;

  /// Mean time from index change to playback, or null before any start.
  Duration? get averageStartLatency =>
      measuredStarts == 0 ? null : totalStartLatency ~/ measuredStarts;

  ReelFeedStats copyWith({
    int? transitions,
    int? preparedOnArrival,
    int? preloadsStarted,
    int? preloadsCompleted,
    int? preloadsFailed,
    int? preloadsCancelled,
    Duration? lastStartLatency,
    Duration? totalStartLatency,
    int? measuredStarts,
  }) {
    return ReelFeedStats(
      transitions: transitions ?? this.transitions,
      preparedOnArrival: preparedOnArrival ?? this.preparedOnArrival,
      preloadsStarted: preloadsStarted ?? this.preloadsStarted,
      preloadsCompleted: preloadsCompleted ?? this.preloadsCompleted,
      preloadsFailed: preloadsFailed ?? this.preloadsFailed,
      preloadsCancelled: preloadsCancelled ?? this.preloadsCancelled,
      lastStartLatency: lastStartLatency ?? this.lastStartLatency,
      totalStartLatency: totalStartLatency ?? this.totalStartLatency,
      measuredStarts: measuredStarts ?? this.measuredStarts,
    );
  }

  @override
  String toString() =>
      'ReelFeedStats(transitions: $transitions, hitRate: '
      '${(preloadHitRate * 100).toStringAsFixed(0)}%, preloads: '
      '$preloadsStarted started / $preloadsCompleted done / '
      '$preloadsFailed failed / $preloadsCancelled cancelled, '
      'avg start: ${averageStartLatency?.inMilliseconds} ms)';
}
