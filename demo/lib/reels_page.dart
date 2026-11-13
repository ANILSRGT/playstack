import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';
import 'demo_state.dart';
import 'post_controls.dart';
import 'stats_sheet.dart';

/// A reels screen: the whole feed is one [ReelFeedView].
///
/// Without [items] it is the endless home feed: it loads more videos near
/// the end and refreshes when pulled down. With [items] it shows that list,
/// opened at [initialIndex], as when a video is tapped in a grid.
class ReelsPage extends StatefulWidget {
  const ReelsPage({
    super.key,
    this.items,
    this.initialIndex = 0,
    this.title = 'Reels',
  });

  final List<DemoVideo>? items;
  final int initialIndex;
  final String title;

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final _view = ReelFeedViewController();

  bool get _isHomeFeed => widget.items == null;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// The next page of the endless feed, as an API would return it.
  Future<List<DemoVideo>> _loadMore() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return demoCatalog;
  }

  /// A fresh feed after pull to refresh.
  Future<List<DemoVideo>> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return [...demoCatalog]..shuffle();
  }

  void _showStats() {
    final manager = _view.manager;
    final feed = _view.feed;
    if (manager == null || feed == null) return;
    // A sheet leaves the feed visible, so the video keeps playing under it.
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => StatsSheet(manager: manager, feed: feed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ReelFeedView<DemoVideo>(
            items: widget.items ?? demoCatalog,
            source: (video) => video.source,
            posterUrl: (video) => video.poster,
            controller: _view,
            initialIndex: widget.initialIndex,
            transition: ReelFeedTransition.stack,
            onLoadMore: _isHomeFeed ? _loadMore : null,
            onRefresh: _isHomeFeed ? _refresh : null,
            onItemViewed: demoState.recordView,
            controlsBuilder: (context, page) => PostControls(page: page),
          ),
          _TopBar(view: _view, title: widget.title, onStats: _showStats),
        ],
      ),
    );
  }
}

/// Title, back button and stats button above the feed, hidden in
/// fullscreen.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.view,
    required this.title,
    required this.onStats,
  });

  final ReelFeedViewController view;
  final String title;
  final VoidCallback onStats;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    const shadow = [Shadow(blurRadius: 8)];
    // The controller is a Listenable: rebuild when fullscreen changes.
    return ListenableBuilder(
      listenable: view,
      builder: (context, _) {
        if (view.isFullscreen) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  if (canPop)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        shadows: shadow,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: IgnorePointer(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          shadows: shadow,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Stats',
                    icon: const Icon(Icons.insights_rounded, shadows: shadow),
                    onPressed: onStats,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
