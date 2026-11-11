import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import '../samples.dart';

/// A vertical feed: [ReelFeedView] pages through a [ReelFeedManager], which
/// decides which items hold native players, plays the item in view and
/// prepares the next ones. The page keeps ReelKit's default controls and
/// adds its own label.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _pageSize = 20;

  final ReelKitManager _manager = ReelKitManager(
    config: const ReelKitConfig(
      pool: ReelPoolConfig(maxPlayers: 3),
      player: ReelPlayerConfig(looping: true),
    ),
  );
  ReelFeedManager? _feed;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  List<ReelFeedItem> _page(int from) => [
    for (var i = from; i < from + _pageSize; i++)
      ReelFeedItem(
        ReelSource.network(sampleVideos[i % sampleVideos.length]),
        id: 'item-$i',
      ),
  ];

  Future<void> _start() async {
    await _manager.initialize();
    final feed = _manager.createFeed(_page(0));
    if (!mounted) {
      feed.dispose();
      return;
    }
    setState(() => _feed = feed);
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    unawaited(_manager.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: feed == null ? null : _Header(manager: _manager, feed: feed),
      ),
      body: feed == null
          ? const Center(child: CircularProgressIndicator())
          : ReelFeedView(
              feed: feed,
              // Endless feed: append the next page shortly before the end.
              onEndReached: () => feed.addAll(_page(feed.length)),
              controlsBuilder: (context, page) => ReelDefaultControls(
                page: page,
                child: _Label(page: page),
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.manager, required this.feed});

  final ReelKitManager manager;
  final ReelFeedManager feed;

  @override
  Widget build(BuildContext context) {
    final pool = manager.poolStats;
    final stats = feed.stats;
    final window = feed.preloadWindow.value;
    final network = manager.networkStatus.value;
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12, color: Colors.white),
      child: Text(
        '#${(feed.activeIndex.value ?? 0) + 1} · pool '
        '${pool.allocated}/${pool.maxPlayers} · window '
        '+${window.ahead}/-${window.behind} · ${network.type.name}'
        '${network.isMetered ? ' (metered)' : ''}\n'
        'ready on arrival ${(stats.preloadHitRate * 100).round()}% · '
        'avg start ${stats.averageStartLatency?.inMilliseconds ?? '-'} ms',
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.page});

  final ReelFeedPage page;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        child: ValueListenableBuilder<ReelPlaybackState>(
          valueListenable: page.controller,
          builder: (_, state, _) => Text(
            '#${page.index + 1} · ${state.status.name}'
            '${state.isBuffering ? ' · buffering' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
