import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'drama/drama_data.dart';
import 'drama/series_page.dart';
import 'home_page.dart';
import 'reels_page.dart';

/// The first screen: pick which app to try.
///
/// It also plays the role of a splash screen: it starts preparing the reels
/// feed right away, so the first video plays the moment Reels opens.
class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key});

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  PlayStackFeedPreload<Object>? _preload = preloadHomeFeed();

  @override
  void dispose() {
    _preload?.dispose();
    super.dispose();
  }

  Future<void> _openReels() async {
    // A preload is shown once; prepare a fresh one for the next visit.
    final preload = _preload;
    _preload = null;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => HomePage(preload: preload)));
    if (mounted) _preload = preloadHomeFeed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'PlayStack',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Two apps built on one widget, PlayStackFeedView.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              _DemoButton(
                icon: Icons.play_circle_rounded,
                title: 'Reels',
                subtitle:
                    'Endless short videos: likes, comments, pull to refresh, '
                    'explore grid',
                onTap: () => unawaited(_openReels()),
              ),
              const SizedBox(height: 16),
              _DemoButton(
                icon: Icons.movie_filter_rounded,
                title: 'Drama',
                subtitle:
                    'A series in episodes: jump to any episode, continue '
                    'where you stopped, next episode on its own',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SeriesPage(series: demoSeries),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  const _DemoButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 44, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
