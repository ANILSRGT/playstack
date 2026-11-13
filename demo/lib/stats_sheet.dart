import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'demo_state.dart';

/// Live view of what PlayStack is doing: pool, preloading, start latency,
/// network, cache, and what the user watched (`onItemViewed`).
class StatsSheet extends StatefulWidget {
  const StatsSheet({super.key, required this.manager, required this.feed});

  final PlayStackManager manager;
  final PlayStackFeedManager feed;

  @override
  State<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<StatsSheet> {
  late final Timer _refresh;
  PlayStackCacheInfo? _cache;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_readCache());
  }

  Future<void> _readCache() async {
    final cache = widget.manager.cache;
    final info = await cache.info();
    if (mounted) setState(() => _cache = info);
  }

  Future<void> _clearCache() async {
    await widget.manager.cache.clear();
    await _readCache();
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  static String _ms(Duration? d) => d == null ? '-' : '${d.inMilliseconds} ms';

  static String _mb(int bytes) =>
      '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    final feed = widget.feed;
    final caps = manager.capabilities;
    final pool = manager.poolStats;
    final stats = feed.stats;
    final window = feed.preloadWindow.value;
    final network = manager.networkStatus.value;
    final active = feed.activeController;
    final metrics = active?.metrics;
    final info = active?.value.videoInfo;
    final cache = _cache;
    final views = demoState.views;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Section('Engine', [
              caps.engineName,
              'recommended players: ${caps.recommendedMaxPlayers}'
                  '${caps.isLowRamDevice ? ' (low-RAM device)' : ''}',
            ]),
            _Section('Watching (onItemViewed)', [
              '${views.length} videos watched, ${demoState.completedCount} '
                  'to the end',
              'total watch time ${(demoState.totalWatchTime.inMilliseconds / 1000).toStringAsFixed(1)} s',
              for (final view in views.reversed.take(3))
                '· ${view.data.title}: '
                    '${(view.watchTime.inMilliseconds / 1000).toStringAsFixed(1)} s'
                    '${view.watchedFraction == null ? '' : ' (${(view.watchedFraction! * 100).round()}%)'}',
            ]),
            _Section('Native player pool', [
              '${pool.leased} leased, ${pool.idle} idle, limit ${pool.maxPlayers}',
              '${pool.created} created, ${pool.reused} reused, '
                  '${pool.revoked} taken over',
              'by priority: ${pool.leasedByPriority.entries.map((e) => '${e.key.name} ${e.value}').join(', ')}',
            ]),
            _Section('Feed', [
              'item ${(feed.activeIndex.value ?? 0) + 1} of ${feed.length}, '
                  'preparing ${window.ahead} ahead / ${window.behind} behind',
              'preload hit rate ${(stats.preloadHitRate * 100).round()}% '
                  'over ${stats.transitions} swipes',
              'average start ${_ms(stats.averageStartLatency)} '
                  '(engine accepted play)',
              'preloads: ${stats.preloadsStarted} started, '
                  '${stats.preloadsCompleted} done, '
                  '${stats.preloadsCancelled} cancelled, '
                  '${stats.preloadsFailed} failed',
            ]),
            _Section('Current video', [
              if (info != null)
                '${info.displaySize.width.round()}x${info.displaySize.height.round()}'
                    '${info.videoCodec == null ? '' : ', ${info.videoCodec}'}'
                    '${info.bitrate == null ? '' : ', ${(info.bitrate! / 1000).round()} kbps'}',
              'preparation ${_ms(metrics?.lastPreparationTime)}, '
                  'first frame ${_ms(metrics?.lastTimeToFirstFrame)}',
              'prepared ${metrics?.preparations ?? 0}x',
            ]),
            _Section('Network', [
              network.isConnected
                  ? '${network.type.name}'
                        '${network.isMetered ? ', metered' : ''}'
                        '${network.isConstrained ? ', data saver' : ''}'
                  : 'offline',
            ]),
            _Section('Disk cache', [
              if (!manager.cache.isSupported)
                'not available on this platform (browser cache only)'
              else if (cache == null)
                'reading...'
              else
                '${_mb(cache.usedBytes)} of ${_mb(cache.maxBytes)}',
            ]),
            if (manager.cache.isSupported)
              OutlinedButton.icon(
                onPressed: () => unawaited(_clearCache()),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear cache'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.lines);

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Text(line, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
