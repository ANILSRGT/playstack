import 'package:flutter/material.dart';

import 'author_page.dart';
import 'catalog.dart';

/// A page without video in the reels feed: accounts to follow. The feed
/// builds it with `pageBuilder`; it takes no player and the videos around
/// it keep preloading.
class SuggestionPage extends StatelessWidget {
  const SuggestionPage({super.key, required this.card});

  final SuggestionCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B0F2E), Color(0xFF0E1A33)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suggested for you',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A page without video, mixed into the feed.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              // Taller than the screen on small phones: the list scrolls,
              // and pulling on at its end moves the feed to the next video.
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final author in card.authors)
                      Card(
                        color: Colors.white10,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(author.substring(1, 2).toUpperCase()),
                          ),
                          title: Text(author),
                          trailing: FilledButton.tonal(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AuthorPage(author: author),
                              ),
                            ),
                            child: const Text('View'),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Swipe for more videos',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
