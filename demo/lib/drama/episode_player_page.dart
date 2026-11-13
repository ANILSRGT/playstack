import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'drama_data.dart';
import 'series_page.dart';

/// Plays a series as a vertical feed of episodes.
///
/// * opens at the tapped episode, where the user stopped
///   (`initialIndex`, `startPosition`);
/// * moves to the next episode when one ends (`autoAdvance`);
/// * saves where the user stopped (`onItemViewed`);
/// * jumps to any episode from the episode list (`jumpToItem`).
class EpisodePlayerPage extends StatefulWidget {
  const EpisodePlayerPage({
    super.key,
    required this.series,
    required this.episode,
  });

  final Series series;
  final Episode episode;

  @override
  State<EpisodePlayerPage> createState() => _EpisodePlayerPageState();
}

class _EpisodePlayerPageState extends State<EpisodePlayerPage> {
  final _view = PlayStackFeedViewController();

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  Future<void> _showEpisodes(Episode current) async {
    _view.pause();
    final picked = await showModalBottomSheet<Episode>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _EpisodeSheet(series: widget.series, current: current),
    );
    _view.resume();
    if (picked != null && picked != current) _view.jumpToItem(picked);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return Scaffold(
      body: PlayStackFeedView<Episode>(
        items: series.episodes,
        source: (episode) => episode.source,
        posterUrl: (episode) => episode.poster,
        controller: _view,
        initialIndex: series.episodes.indexOf(widget.episode),
        startPosition: watchProgress.positionOf,
        autoAdvance: true,
        onItemViewed: watchProgress.record,
        controlsBuilder: (context, page) => PlayStackDefaultControls(
          page: page,
          // Hold to watch at 2x, as drama apps do.
          holdAction: PlayStackHoldAction.speedUp,
          child: page.isFullscreen
              ? null
              : _EpisodeOverlay(
                  series: series,
                  episode: page.data,
                  onEpisodes: () => unawaited(_showEpisodes(page.data)),
                ),
        ),
      ),
    );
  }
}

class _EpisodeOverlay extends StatelessWidget {
  const _EpisodeOverlay({
    required this.series,
    required this.episode,
    required this.onEpisodes,
  });

  final Series series;
  final Episode episode;
  final VoidCallback onEpisodes;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 8)];
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: SafeArea(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, shadows: shadow),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Text(
                  series.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    shadows: shadow,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Episode ${episode.number} of ${series.episodes.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        shadows: shadow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episode.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        shadows: shadow,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onEpisodes,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Episodes'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.series, required this.current});

  final Series series;
  final Episode current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${series.title} · ${series.episodes.length} episodes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final episode in series.episodes)
                  EpisodeTile(
                    episode: episode,
                    isCurrent: episode == current,
                    onTap: () => Navigator.of(context).pop(episode),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
