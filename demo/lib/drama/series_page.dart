import 'package:flutter/material.dart';

import 'drama_data.dart';
import 'episode_player_page.dart';

/// The page of a series: continue watching, or pick any episode.
class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.series});

  final Series series;

  void _play(BuildContext context, Episode episode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EpisodePlayerPage(series: series, episode: episode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final poster = series.poster;
    return Scaffold(
      body: ListenableBuilder(
        listenable: watchProgress,
        builder: (context, _) {
          final next = watchProgress.continueWith(series);
          final start = next ?? series.episodes.first;
          final position = next == null ? null : watchProgress.positionOf(next);
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 420,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(series.title),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null)
                        Image.network(poster, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                            stops: [0.5, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.list(
                  children: [
                    Text(series.synopsis, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _play(context, start),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(
                        next == null
                            ? 'Play episode 1'
                            : position == null
                            ? 'Play episode ${next.number}'
                            : 'Continue episode ${next.number} at '
                                  '${formatPosition(position)}',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '${series.episodes.length} episodes',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid.count(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final episode in series.episodes)
                      EpisodeTile(
                        episode: episode,
                        onTap: () => _play(context, episode),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A numbered episode square: a check when finished, a bar when started.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.episode,
    required this.onTap,
    this.isCurrent = false,
  });

  final Episode episode;
  final VoidCallback onTap;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finished = watchProgress.isFinished(episode);
    final started = watchProgress.positionOf(episode) != null;
    return Material(
      color: isCurrent ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Stack(
          children: [
            Center(
              child: Text(
                '${episode.number}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isCurrent ? scheme.onPrimary : null,
                ),
              ),
            ),
            if (finished)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(Icons.check_circle, size: 14, color: Colors.green),
              ),
            if (started && !finished)
              Positioned(
                left: 8,
                right: 8,
                bottom: 6,
                child: Container(height: 3, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}
