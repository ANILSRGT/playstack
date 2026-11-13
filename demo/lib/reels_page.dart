import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'catalog.dart';
import 'demo_state.dart';
import 'post_controls.dart';
import 'stats_sheet.dart';
import 'suggestion_page.dart';

/// How the reels feed reads its items: videos, and suggestion cards
/// without video.
PlayStackSource? _videoOf(Object entry) =>
    entry is DemoVideo ? entry.source : null;

String? _posterOf(Object entry) => entry is DemoVideo ? entry.poster : null;

/// What the lock screen and the notification show while a post plays.
PlayStackMediaInfo? _mediaInfoOf(Object entry) => entry is DemoVideo
    ? PlayStackMediaInfo(
        title: entry.title,
        artist: entry.author,
        artworkUrl: entry.poster,
      )
    : null;

/// Starts preparing the home feed before it is opened. The launcher calls
/// it at start, like a splash screen would.
PlayStackFeedPreload<Object> preloadHomeFeed() => PlayStackFeedPreload<Object>(
  items: withSuggestions(demoCatalog),
  source: _videoOf,
  posterUrl: _posterOf,
);

/// A reels screen: the whole feed is one [PlayStackFeedView].
///
/// Without [items] it is the endless home feed: it loads more videos near
/// the end, mixes in suggestion cards and refreshes when pulled down. With
/// [preload] it shows a home feed prepared ahead. With [items] it shows that
/// list, opened at [initialIndex], as when a video is tapped in a grid.
class ReelsPage extends StatefulWidget {
  const ReelsPage({
    super.key,
    this.items,
    this.preload,
    this.initialIndex = 0,
    this.title = 'Reels',
  });

  final List<DemoVideo>? items;
  final PlayStackFeedPreload<Object>? preload;
  final int initialIndex;
  final String title;

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final _view = PlayStackFeedViewController();

  // Kept in state: a new list on every build would replace the feed.
  late final List<Object> _items = widget.items ?? withSuggestions(demoCatalog);

  bool get _isHomeFeed => widget.items == null;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  /// The next page of the endless feed, as an API would return it.
  Future<List<Object>> _loadMore() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return withSuggestions(demoCatalog);
  }

  /// A fresh feed after pull to refresh.
  Future<List<Object>> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return withSuggestions([...demoCatalog]..shuffle());
  }

  Widget _controls(BuildContext context, PlayStackFeedPage<Object> page) =>
      PostControls(page: page.cast<DemoVideo>());

  Widget _suggestion(BuildContext context, Object entry, bool isActive) =>
      SuggestionPage(card: entry as SuggestionCard);

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
          if (widget.preload case final preload?)
            // Prepared on the launcher: the first video plays at once.
            PlayStackFeedView<Object>.preloaded(
              preload,
              controller: _view,
              transition: PlayStackFeedTransition.stack,
              onLoadMore: _loadMore,
              onRefresh: _refresh,
              onItemViewed: demoState.recordView,
              controlsBuilder: _controls,
              pageBuilder: _suggestion,
              // Lock screen controls, and a small window on leaving the app.
              mediaInfo: _mediaInfoOf,
              pictureInPicture: true,
            )
          else
            PlayStackFeedView<Object>(
              items: _items,
              source: _videoOf,
              posterUrl: _posterOf,
              controller: _view,
              initialIndex: widget.initialIndex,
              transition: PlayStackFeedTransition.stack,
              onLoadMore: _isHomeFeed ? _loadMore : null,
              onRefresh: _isHomeFeed ? _refresh : null,
              onItemViewed: demoState.recordView,
              controlsBuilder: _controls,
              pageBuilder: _suggestion,
              // Lock screen controls, and a small window on leaving the app.
              mediaInfo: _mediaInfoOf,
              pictureInPicture: true,
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

  final PlayStackFeedViewController view;
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
