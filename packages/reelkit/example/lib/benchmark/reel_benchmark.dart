import 'dart:async';
import 'dart:math' as math;

import 'package:reelkit/reelkit.dart';

import '../samples.dart';
import 'process_memory.dart';

/// Measures ReelKit on the device it runs on.
///
/// Every scenario uses a bundled clip ([source], by default a 1080x1920
/// H.264 file), so the numbers describe the engine and the device, not the
/// network. Timings are wall-clock times measured in Dart, from the call to
/// the moment the app can observe the effect, so they include the platform
/// channel round trips an app also pays. A start is measured until the
/// playback position moves, not until the engine accepts `play`: an
/// accepted `play` can still wait for data or a decoder.
///
/// Used by the example's benchmark page and by
/// `integration_test/benchmark_test.dart`.
class ReelBenchmark {
  /// Creates a benchmark. Smaller numbers make a quicker, noisier run.
  ReelBenchmark({
    this.source = const ReelSource.asset(portraitHdAsset),
    this.iterations = 10,
    this.feedScrollItems = 500,
    this.swipeTransitions = 20,
    this.swipeDwell = const Duration(milliseconds: 1200),
    this.memoryWarmupCycles = 10,
    this.memoryCycles = 60,
    this.onProgress,
  });

  /// The clip played by every scenario.
  final ReelSource source;

  /// Samples taken for the start-latency scenarios.
  final int iterations;

  /// Items scrolled through, one per frame, by the rapid scroll scenario.
  final int feedScrollItems;

  /// Index changes of the swipe scenario.
  final int swipeTransitions;

  /// Time spent on each item of the swipe scenario before moving on.
  final Duration swipeDwell;

  /// Cycles run before the first memory sample, so caches and code paths
  /// are warm.
  final int memoryWarmupCycles;

  /// Create/prepare/dispose cycles of the memory scenario.
  final int memoryCycles;

  /// Receives a short description of the step being run.
  final void Function(String step)? onProgress;

  /// Runs every scenario in sequence and returns the measurements.
  Future<ReelBenchmarkResults> run() async {
    final startup = await _measureStartup();
    final scroll = await _measureRapidScroll();
    final swipe = await _measureSwipe();
    final memory = await _measureMemory();
    return ReelBenchmarkResults(
      capabilities: startup.capabilities,
      firstStart: startup.firstStart,
      coldStart: startup.cold,
      preparation: startup.preparation,
      timeToFirstFrame: startup.timeToFirstFrame,
      preloadedStart: startup.preloaded,
      rapidScroll: scroll,
      swipe: swipe,
      memory: memory,
    );
  }

  Future<ReelKitManager> _manager({int maxPlayers = 2}) async {
    final manager = ReelKitManager(
      config: ReelKitConfig(
        pool: ReelPoolConfig(maxPlayers: maxPlayers),
        player: const ReelPlayerConfig(looping: true, muted: true),
        cache: ReelCacheConfig.disabled,
      ),
    );
    await manager.initialize();
    return manager;
  }

  Future<_StartupResults> _measureStartup() async {
    final manager = await _manager();
    try {
      final cold = <Duration>[];
      final preparation = <Duration>[];
      final firstFrame = <Duration>[];
      Duration? firstStart;
      for (var i = 0; i <= iterations; i++) {
        _progress('Cold start ${i + 1}/${iterations + 1}');
        final controller = manager.createController(source);
        final watch = Stopwatch()..start();
        await controller.play();
        await _waitUntilAdvancing(controller, 'cold start');
        watch.stop();
        // The first start also creates the native player; later starts
        // reuse it, which is what a running app mostly does.
        if (i == 0) {
          firstStart = watch.elapsed;
        } else {
          cold.add(watch.elapsed);
          final metrics = controller.metrics;
          if (metrics.lastPreparationTime case final time?) {
            preparation.add(time);
          }
          if (metrics.lastTimeToFirstFrame case final time?) {
            firstFrame.add(time);
          }
        }
        await controller.dispose();
      }

      final preloaded = <Duration>[];
      for (var i = 0; i < iterations; i++) {
        _progress('Preloaded start ${i + 1}/$iterations');
        final controller = manager.createController(source);
        await controller.initialize();
        await _waitUntil(
          () => controller.value.hasRenderedFirstFrame,
          'preload first frame',
        );
        final watch = Stopwatch()..start();
        await controller.play();
        await _waitUntilAdvancing(controller, 'preloaded start');
        watch.stop();
        preloaded.add(watch.elapsed);
        await controller.dispose();
      }
      return _StartupResults(
        capabilities: manager.capabilities,
        firstStart: firstStart!,
        cold: ReelBenchmarkSeries(cold),
        preparation: ReelBenchmarkSeries(preparation),
        timeToFirstFrame: ReelBenchmarkSeries(firstFrame),
        preloaded: ReelBenchmarkSeries(preloaded),
      );
    } finally {
      await manager.dispose();
    }
  }

  Future<ReelRapidScrollResults> _measureRapidScroll() async {
    const maxPlayers = 3;
    final manager = await _manager(maxPlayers: maxPlayers);
    try {
      final feed = manager.createFeed([
        for (var i = 0; i < feedScrollItems; i++)
          ReelFeedItem(source, id: 'scroll-$i'),
      ]);
      var peakAllocated = 0;
      final watch = Stopwatch()..start();
      for (var i = 0; i < feedScrollItems; i++) {
        if (i % 50 == 0) _progress('Rapid scroll $i/$feedScrollItems');
        feed.setActiveIndex(i);
        // One index change per frame at 60 Hz: far faster than a person
        // can swipe, so nearly every preparation is cancelled.
        await Future<void>.delayed(const Duration(milliseconds: 16));
        peakAllocated = math.max(peakAllocated, manager.poolStats.allocated);
      }
      final scrolled = watch.elapsed;
      final settle = Stopwatch()..start();
      final last = feed.controllerAt(feedScrollItems - 1);
      await _waitUntilAdvancing(last, 'last item plays');
      settle.stop();
      final stats = manager.poolStats;
      final result = ReelRapidScrollResults(
        items: feedScrollItems,
        maxPlayers: maxPlayers,
        peakAllocated: math.max(peakAllocated, stats.allocated),
        created: stats.created,
        reused: stats.reused,
        revoked: stats.revoked,
        scrollTime: scrolled,
        settleTime: settle.elapsed,
        preloadsCancelled: feed.stats.preloadsCancelled,
      );
      feed.dispose();
      return result;
    } finally {
      await manager.dispose();
    }
  }

  Future<ReelSwipeResults> _measureSwipe() async {
    final manager = await _manager(maxPlayers: 3);
    try {
      final feed = manager.createFeed([
        for (var i = 0; i <= swipeTransitions; i++)
          ReelFeedItem(source, id: 'swipe-$i'),
      ]);
      feed.setActiveIndex(0);
      await _waitUntil(() => feed.controllerAt(0).value.isPlaying, 'first');
      final starts = <Duration>[];
      for (var i = 1; i <= swipeTransitions; i++) {
        _progress('Swipe $i/$swipeTransitions');
        await Future<void>.delayed(swipeDwell);
        final controller = feed.controllerAt(i);
        final watch = Stopwatch()..start();
        feed.setActiveIndex(i);
        await _waitUntilAdvancing(controller, 'swipe $i plays');
        starts.add(watch.elapsed);
      }
      final stats = feed.stats;
      feed.dispose();
      return ReelSwipeResults(
        transitions: swipeTransitions,
        dwell: swipeDwell,
        start: ReelBenchmarkSeries(starts),
        preloadHitRate: stats.preloadHitRate,
      );
    } finally {
      await manager.dispose();
    }
  }

  Future<ReelMemoryResults> _measureMemory() async {
    final manager = await _manager(maxPlayers: 1);
    try {
      Future<void> cycle() async {
        final controller = manager.createController(source);
        await controller.initialize();
        await _waitUntil(
          () => controller.value.hasRenderedFirstFrame,
          'memory cycle first frame',
        );
        await controller.dispose();
        // Destroy the native player too, so every cycle creates one.
        await manager.trimIdlePlayers();
      }

      final before = currentRss();
      for (var i = 0; i < memoryWarmupCycles; i++) {
        _progress('Memory warm-up ${i + 1}/$memoryWarmupCycles');
        await cycle();
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final warm = currentRss();
      final watch = Stopwatch()..start();
      for (var i = 0; i < memoryCycles; i++) {
        if (i % 10 == 0) _progress('Memory cycle ${i + 1}/$memoryCycles');
        await cycle();
      }
      watch.stop();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final after = currentRss();
      final stats = manager.poolStats;
      return ReelMemoryResults(
        cycles: memoryCycles,
        rssBefore: before,
        rssWarm: warm,
        rssAfter: after,
        playersCreated: stats.created,
        playersDisposed: stats.disposed,
        averageCycle: watch.elapsed ~/ math.max(1, memoryCycles),
      );
    } finally {
      await manager.dispose();
    }
  }

  void _progress(String step) => onProgress?.call(step);

  /// Waits until [controller] plays and its position has left the start.
  /// Every measured video starts at position zero.
  Future<void> _waitUntilAdvancing(
    ReelPlayerController controller,
    String what,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      if (controller.value.isPlaying) {
        final snapshot = await controller.getPosition();
        if (snapshot.position > Duration.zero) return;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Benchmark step timed out: $what');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> _waitUntil(
    bool Function() condition,
    String what, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Benchmark step timed out: $what', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }
}

class _StartupResults {
  _StartupResults({
    required this.capabilities,
    required this.firstStart,
    required this.cold,
    required this.preparation,
    required this.timeToFirstFrame,
    required this.preloaded,
  });

  final ReelPlatformCapabilities capabilities;
  final Duration firstStart;
  final ReelBenchmarkSeries cold;
  final ReelBenchmarkSeries preparation;
  final ReelBenchmarkSeries timeToFirstFrame;
  final ReelBenchmarkSeries preloaded;
}

/// Repeated measurements of one duration.
class ReelBenchmarkSeries {
  /// Wraps [samples]; they are sorted for the percentiles.
  ReelBenchmarkSeries(List<Duration> samples)
    : samples = List<Duration>.unmodifiable([...samples]..sort());

  /// The measurements, shortest first.
  final List<Duration> samples;

  /// Middle sample, or null without samples.
  Duration? get median => _at(0.5);

  /// 90th percentile (nearest rank), or null without samples.
  Duration? get p90 => _at(0.9);

  /// Shortest sample, or null without samples.
  Duration? get min => samples.isEmpty ? null : samples.first;

  /// Longest sample, or null without samples.
  Duration? get max => samples.isEmpty ? null : samples.last;

  Duration? _at(double quantile) {
    if (samples.isEmpty) return null;
    final rank = (quantile * samples.length).ceil().clamp(1, samples.length);
    return samples[rank - 1];
  }

  /// Summary as milliseconds.
  Map<String, Object?> toJson() => {
    'samples': samples.length,
    'median_ms': _ms(median),
    'p90_ms': _ms(p90),
    'min_ms': _ms(min),
    'max_ms': _ms(max),
  };

  @override
  String toString() => samples.isEmpty
      ? 'no samples'
      : 'median ${_ms(median)} ms, p90 ${_ms(p90)} ms '
            '(${_ms(min)}-${_ms(max)} ms, n=${samples.length})';
}

/// Result of scrolling through a long feed one item per frame.
class ReelRapidScrollResults {
  /// Creates the result.
  ReelRapidScrollResults({
    required this.items,
    required this.maxPlayers,
    required this.peakAllocated,
    required this.created,
    required this.reused,
    required this.revoked,
    required this.scrollTime,
    required this.settleTime,
    required this.preloadsCancelled,
  });

  /// Items scrolled through.
  final int items;

  /// Pool limit during the scenario.
  final int maxPlayers;

  /// Most native players alive at any sample.
  final int peakAllocated;

  /// Native players created.
  final int created;

  /// Leases served by an idle native player.
  final int reused;

  /// Leases taken from a lower-priority controller.
  final int revoked;

  /// Time spent issuing index changes.
  final Duration scrollTime;

  /// From the last index change until the last item's playback advanced.
  final Duration settleTime;

  /// Preloads abandoned because the window moved.
  final int preloadsCancelled;

  /// The measurements as JSON-compatible values.
  Map<String, Object?> toJson() => {
    'items': items,
    'max_players': maxPlayers,
    'peak_allocated': peakAllocated,
    'players_created': created,
    'leases_reused': reused,
    'leases_revoked': revoked,
    'scroll_ms': scrollTime.inMilliseconds,
    'settle_ms': settleTime.inMilliseconds,
    'preloads_cancelled': preloadsCancelled,
  };
}

/// Result of swiping through a feed at a human pace.
class ReelSwipeResults {
  /// Creates the result.
  ReelSwipeResults({
    required this.transitions,
    required this.dwell,
    required this.start,
    required this.preloadHitRate,
  });

  /// Index changes measured.
  final int transitions;

  /// Time spent on each item.
  final Duration dwell;

  /// From each index change until the new item's playback advanced.
  final ReelBenchmarkSeries start;

  /// Share of transitions whose item was already prepared.
  final double preloadHitRate;

  /// The measurements as JSON-compatible values.
  Map<String, Object?> toJson() => {
    'transitions': transitions,
    'dwell_ms': dwell.inMilliseconds,
    'start': start.toJson(),
    'preload_hit_rate': preloadHitRate,
  };
}

/// Resident memory around repeated native player creation and disposal.
class ReelMemoryResults {
  /// Creates the result.
  ReelMemoryResults({
    required this.cycles,
    required this.rssBefore,
    required this.rssWarm,
    required this.rssAfter,
    required this.playersCreated,
    required this.playersDisposed,
    required this.averageCycle,
  });

  /// Measured create/prepare/dispose cycles after warm-up.
  final int cycles;

  /// Resident set size before the scenario; null on web.
  final int? rssBefore;

  /// Resident set size after warm-up; null on web.
  final int? rssWarm;

  /// Resident set size after the measured cycles; null on web.
  final int? rssAfter;

  /// Native players created, including warm-up.
  final int playersCreated;

  /// Native players destroyed, including warm-up.
  final int playersDisposed;

  /// Mean duration of one cycle.
  final Duration averageCycle;

  /// Growth across the measured cycles in bytes; null on web. A leak of
  /// native players or decoders shows up here.
  int? get growth {
    final warm = rssWarm;
    final after = rssAfter;
    return warm == null || after == null ? null : after - warm;
  }

  /// The measurements as JSON-compatible values.
  Map<String, Object?> toJson() => {
    'cycles': cycles,
    'rss_before_mb': _mb(rssBefore),
    'rss_warm_mb': _mb(rssWarm),
    'rss_after_mb': _mb(rssAfter),
    'growth_mb': _mb(growth),
    'players_created': playersCreated,
    'players_disposed': playersDisposed,
    'average_cycle_ms': averageCycle.inMilliseconds,
  };
}

/// Everything [ReelBenchmark.run] measured.
class ReelBenchmarkResults {
  /// Creates the results.
  ReelBenchmarkResults({
    required this.capabilities,
    required this.firstStart,
    required this.coldStart,
    required this.preparation,
    required this.timeToFirstFrame,
    required this.preloadedStart,
    required this.rapidScroll,
    required this.swipe,
    required this.memory,
  });

  /// Engine and device the run was measured on.
  final ReelPlatformCapabilities capabilities;

  /// `play()` to advancing playback for the first controller, including
  /// native player creation.
  final Duration firstStart;

  /// `play()` to advancing playback on a reused native player, preparing
  /// on demand.
  final ReelBenchmarkSeries coldStart;

  /// Preparation time reported by `ReelPlayerController.metrics`.
  final ReelBenchmarkSeries preparation;

  /// Preparation start to first frame, from `ReelPlayerController.metrics`.
  final ReelBenchmarkSeries timeToFirstFrame;

  /// `play()` to advancing playback for a controller prepared ahead of
  /// time.
  final ReelBenchmarkSeries preloadedStart;

  /// Rapid scroll scenario.
  final ReelRapidScrollResults rapidScroll;

  /// Swipe scenario.
  final ReelSwipeResults swipe;

  /// Memory scenario.
  final ReelMemoryResults memory;

  /// The measurements as JSON-compatible values, for
  /// `IntegrationTestWidgetsFlutterBinding.reportData`.
  Map<String, Object?> toJson() => {
    'engine': '${capabilities.engineName} ${capabilities.engineVersion}',
    'recommended_max_players': capabilities.recommendedMaxPlayers,
    'low_ram_device': capabilities.isLowRamDevice,
    'first_start_ms': firstStart.inMilliseconds,
    'cold_start': coldStart.toJson(),
    'preparation': preparation.toJson(),
    'time_to_first_frame': timeToFirstFrame.toJson(),
    'preloaded_start': preloadedStart.toJson(),
    'rapid_scroll': rapidScroll.toJson(),
    'swipe': swipe.toJson(),
    'memory': memory.toJson(),
  };

  /// Human-readable report, one measurement per line.
  List<String> toLines() {
    final scroll = rapidScroll;
    return [
      'Engine: ${capabilities.engineName} ${capabilities.engineVersion}'
          '${capabilities.isLowRamDevice ? ' (low-RAM device)' : ''}',
      'First start (creates player): ${firstStart.inMilliseconds} ms',
      'Cold start (play to playback advancing): $coldStart',
      '  preparation: $preparation',
      '  time to first frame: $timeToFirstFrame',
      'Preloaded start (play to playback advancing): $preloadedStart',
      'Swipe start (${swipe.transitions} swipes, '
          '${swipe.dwell.inMilliseconds} ms dwell): ${swipe.start}, '
          'preload hit rate ${(swipe.preloadHitRate * 100).round()}%',
      'Rapid scroll (${scroll.items} items, 1 per frame): peak '
          '${scroll.peakAllocated}/${scroll.maxPlayers} players, '
          '${scroll.created} created, ${scroll.reused} reused, '
          'last item advancing ${scroll.settleTime.inMilliseconds} ms after '
          'scrolling stopped',
      if (memory.growth case final growth?)
        'Memory: RSS ${_mb(memory.rssWarm)} MB after warm-up, '
            '${_mb(memory.rssAfter)} MB after ${memory.cycles} player '
            'create/dispose cycles (${growth >= 0 ? '+' : ''}${_mb(growth)} MB)'
      else
        'Memory: RSS not available on this platform',
      '  ${memory.cycles} cycles, ${memory.averageCycle.inMilliseconds} ms '
          'each, ${memory.playersCreated} players created, '
          '${memory.playersDisposed} disposed',
    ];
  }
}

int? _ms(Duration? duration) => duration?.inMilliseconds;

String? _mb(int? bytes) =>
    bytes == null ? null : (bytes / (1024 * 1024)).toStringAsFixed(1);
