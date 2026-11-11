import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import '../samples.dart';

/// An endless vertical feed. [ReelFeedView] does the work: players,
/// preloading, paging and loading more. The page adds a label on top of the
/// default controls and shows live stats in the app bar.
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _view = ReelFeedViewController();
  late final List<String> _firstPage = _nextPage();
  Timer? _statsTimer;
  int _loaded = 0;

  @override
  void initState() {
    super.initState();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  /// The next 20 sample URLs, as an API would return them.
  List<String> _nextPage() => [
    for (var i = 0; i < 20; i++) sampleVideos[_loaded++ % sampleVideos.length],
  ];

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: _Header(view: _view),
      ),
      body: ReelFeedView<String>(
        items: _firstPage,
        onLoadMore: () async => _nextPage(),
        controller: _view,
        controlsBuilder: (context, page) => ReelDefaultControls(
          page: page,
          child: _Label(page: page),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view});

  final ReelFeedViewController view;

  @override
  Widget build(BuildContext context) {
    final manager = view.manager;
    final feed = view.feed;
    if (manager == null || feed == null) return const SizedBox.shrink();
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

  final ReelFeedPage<String> page;

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
