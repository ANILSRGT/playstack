import 'package:flutter/material.dart';

import 'catalog.dart';

/// The comments of a post, opened from the comment button.
class CommentsSheet extends StatelessWidget {
  const CommentsSheet({super.key, required this.video});

  final DemoVideo video;

  @override
  Widget build(BuildContext context) {
    final comments = video.comments;
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          children: [
            Text(
              '${comments.length} comments',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: comments.length,
                itemBuilder: (context, index) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text('${index + 1}'),
                  ),
                  title: Text('viewer_${index + 1}'),
                  subtitle: Text(comments[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
