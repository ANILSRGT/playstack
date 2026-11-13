import 'package:flutter/material.dart';

import 'catalog.dart';
import 'explore_page.dart';

/// The videos of one author, opened from a reel's caption.
class AuthorPage extends StatelessWidget {
  const AuthorPage({super.key, required this.author});

  final String author;

  @override
  Widget build(BuildContext context) {
    final videos = [
      for (final video in demoCatalog)
        if (video.author == author) video,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(author)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  child: Text(
                    author.substring(1, 2).toUpperCase(),
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${videos.length} videos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: VideoGrid(videos: videos, title: author),
          ),
        ],
      ),
    );
  }
}
