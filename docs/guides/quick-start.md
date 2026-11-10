# Quick start

ReelKit plays video; you build the UI. Three objects do the work:

- `ReelKitManager` owns the native engine and a bounded pool of native
  players. Create one per playback context (a feed, a screen).
- `ReelPlayerController` controls one video. Creating it is free; it
  borrows a native player from the pool when it prepares or plays.
- `ReelVideoView` renders a controller's frames. It has no controls.

```dart
import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.url});

  final String url;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final manager = ReelKitManager();
  ReelPlayerController? controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await manager.initialize();
    final controller = manager.createController(
      ReelSource.network(widget.url),
    );
    setState(() => this.controller = controller);
    await controller.play(); // prepares on demand
  }

  @override
  void dispose() {
    manager.dispose(); // disposes the controller and every native player
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        ReelVideoView(controller: controller, fit: BoxFit.cover),
        // Your controls: rebuild from the controller's state.
        ValueListenableBuilder<ReelPlaybackState>(
          valueListenable: controller,
          builder: (context, state, _) => Center(
            child: IconButton(
              iconSize: 64,
              icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: state.isPlaying ? controller.pause : controller.play,
            ),
          ),
        ),
      ],
    );
  }
}
```

Next steps:

- A vertical, endless feed: [Feeds](feed.md).
- Everything a controller does: [Player controller](controller.md).
- What happens when there are more videos than native players:
  [Player manager](manager.md).
