import 'package:flutter/material.dart';

import 'catalog.dart';
import 'reels_page.dart';

/// A grid of posters. Tapping one opens a feed of the grid at that video.
class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: VideoGrid(videos: demoCatalog, title: 'Explore'),
    );
  }
}

/// Posters of [videos] in three columns; a tap opens them as reels.
class VideoGrid extends StatelessWidget {
  const VideoGrid({super.key, required this.videos, required this.title});

  final List<DemoVideo> videos;
  final String title;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final poster = video.poster;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ReelsPage(items: videos, initialIndex: index, title: title),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.white10,
                child: poster == null
                    ? const Icon(Icons.movie_outlined, color: Colors.white38)
                    : Image.network(
                        poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.movie_outlined,
                          color: Colors.white38,
                        ),
                      ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
