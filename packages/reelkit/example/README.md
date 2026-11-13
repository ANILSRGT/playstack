# reelkit example

A reels feed is one widget:

```dart
import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

void main() => runApp(const MaterialApp(home: FeedScreen()));

class Post {
  const Post(this.title, this.videoUrl, this.thumbnailUrl);

  final String title;
  final String videoUrl;
  final String thumbnailUrl;
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final List<Post> posts = [
    const Post(
      'Dance',
      'https://res.cloudinary.com/demo/video/upload/sp_full_hd/c_fill,ar_9:16/samples/dance-2.m3u8',
      'https://res.cloudinary.com/demo/video/upload/so_0,c_fill,ar_9:16,w_540,q_auto/samples/dance-2.jpg',
    ),
    // ...
  ];

  Future<List<Post>> fetchMore() async => []; // your API; [] when there are no more

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ReelFeedView<Post>(
        items: posts,
        videoUrl: (post) => post.videoUrl,
        posterUrl: (post) => post.thumbnailUrl,
        onLoadMore: fetchMore,
        controlsBuilder: (context, page) => ReelDefaultControls(
          page: page,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(page.data.title),
            ),
          ),
        ),
      ),
    );
  }
}
```

## This app

The app in this folder exercises every feature on a device:

| Page | Shows |
| --- | --- |
| Single player | Your own controls, seek bar, speed, loop, tracks and subtitles, source switching, errors, fullscreen |
| Vertical feed | `ReelFeedView` with loading more, pull to refresh, watch time and live stats |
| Player grid | Several controllers, exclusive or concurrent playback |
| Diagnostics | Capabilities, pool usage per priority, creating and disposing controllers |
| Benchmark | Start latency, preloading, rapid scrolling and memory |

```bash
flutter run
flutter test integration_test -d <device-id>
```

For a complete short-video app, see the
[demo](https://github.com/ANILSRGT/reelkit/tree/main/demo).
