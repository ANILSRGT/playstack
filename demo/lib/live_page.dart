import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'loading_animation.dart';

/// A live stream in a feed: the default controls show a LIVE badge, and a
/// tap on it returns to live after a pause. Swipe up for the second
/// channel.
class LivePage extends StatelessWidget {
  const LivePage({super.key});

  /// Public test streams.
  static const _channels = [
    // Unified Streaming's 24/7 test channel, with a DVR window.
    'https://demo.unified-streaming.com/k8s/live/stable/live.isml/.m3u8',
    'https://moctobpltc-i.akamaihd.net/hls/live/571329/eight/playlist.m3u8',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PlayStackFeedView<String>(
        items: _channels,
        controlsBuilder: (context, page) => PlayStackDefaultControls(
          page: page,
          bufferingIndicator: const LoadingAnimation(),
          child: Align(
            alignment: Alignment.topRight,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
