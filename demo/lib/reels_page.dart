import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';
import 'reel_tile.dart';
import 'settings.dart';
import 'stats_sheet.dart';

/// A vertical, endless short-video feed driven by [ReelFeedManager].
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  static const _startMuted = kIsWeb;

  final ReelKitManager _manager = ReelKitManager(config: demoKitConfig());
  final PageController _pages = PageController();
  final Map<String, DemoVideo> _videos = <String, DemoVideo>{};
  final Set<String> _liked = <String>{};

  ReelFeedManager? _feed;
  Object? _initError;
  int _batches = 0;
  bool _muted = _startMuted;
  bool _fill = false;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _manager.initialize();
    } on Object catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    if (!mounted) return;
    final feed = _manager.createFeed(_nextBatch(), config: demoFeedConfig);
    setState(() => _feed = feed);
    feed.setActiveIndex(0);
    _precachePosters(from: 0);
  }

  /// Downloads the posters of the next items, so a swipe never shows black
  /// while the video prepares.
  void _precachePosters({required int from}) {
    final feed = _feed!;
    for (var i = from; i < from + 6 && i < feed.length; i++) {
      final url = _videos[feed.items[i].id]?.poster;
      if (url != null) {
        unawaited(
          precacheImage(NetworkImage(url), context, onError: (_, _) {}),
        );
      }
    }
  }

  /// The catalog again, with fresh ids, for an endless feed.
  List<ReelFeedItem> _nextBatch() {
    final batch = _batches++;
    return [
      for (var i = 0; i < demoCatalog.length; i++)
        () {
          final id = 'b$batch-$i';
          _videos[id] = demoCatalog[i];
          return ReelFeedItem(demoCatalog[i].source, id: id);
        }(),
    ];
  }

  void _onPageChanged(int index) {
    final feed = _feed!;
    // Apply the mute state before the feed starts the item.
    _applyMute(around: index);
    feed.setActiveIndex(index);
    _precachePosters(from: index + 1);
    if (index >= feed.length - 3) {
      setState(() => feed.addAll(_nextBatch()));
    }
  }

  void _applyMute({required int around}) {
    final feed = _feed!;
    for (var i = around - 1; i <= around + 2; i++) {
      if (i < 0 || i >= feed.length) continue;
      unawaited(
        feed.controllerAt(i).setMuted(_muted).catchError((Object _) {}),
      );
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _applyMute(around: _feed!.activeIndex.value ?? 0);
  }

  Future<void> _toggleFullscreen(ReelPlayerController controller) async {
    final fullscreen = _manager.fullscreen;
    if (_fullscreen) {
      setState(() => _fullscreen = false);
      await fullscreen.exit();
      await controller.setVideoQualityLimit(screenQualityLimit());
      return;
    }
    setState(() => _fullscreen = true);
    // Fullscreen shows the video at the screen's long side: allow 1080p.
    unawaited(
      controller
          .setVideoQualityLimit(ReelVideoQualityLimit.none)
          .catchError((Object _) {}),
    );
    try {
      await fullscreen.enter(
        orientation: ReelFullscreenOrientation.matchVideo,
        controller: controller,
      );
    } on ReelKitException catch (error) {
      if (!mounted) return;
      setState(() => _fullscreen = false);
      unawaited(
        controller
            .setVideoQualityLimit(screenQualityLimit())
            .catchError((Object _) {}),
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _showStats() {
    final feed = _feed;
    if (feed == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => StatsSheet(manager: _manager, feed: feed),
      ),
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    unawaited(_manager.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final Widget body;
    if (_initError case final error?) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('ReelKit could not start:\n$error'),
        ),
      );
    } else if (feed == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        children: [
          PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            physics: _fullscreen ? const NeverScrollableScrollPhysics() : null,
            itemCount: feed.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final item = feed.items[index];
              final controller = feed.controllerAt(index);
              return ValueListenableBuilder<int?>(
                key: ValueKey(item.id),
                valueListenable: feed.activeIndex,
                builder: (context, active, _) => ReelTile(
                  controller: controller,
                  video: _videos[item.id]!,
                  isActive: active == index,
                  muted: _muted,
                  fill: _fill,
                  fullscreen: _fullscreen,
                  liked: _liked.contains(item.id),
                  onLike: (liked) => setState(
                    () => liked ? _liked.add(item.id) : _liked.remove(item.id),
                  ),
                  onToggleMute: _toggleMute,
                  onToggleFill: () => setState(() => _fill = !_fill),
                  onToggleFullscreen: () =>
                      unawaited(_toggleFullscreen(controller)),
                ),
              );
            },
          ),
          if (!_fullscreen)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Text(
                      'ReelKit',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Stats',
                      icon: const Icon(
                        Icons.insights,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                      onPressed: _showStats,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) {
          final controller = _feed?.activeController;
          if (controller != null) unawaited(_toggleFullscreen(controller));
        }
      },
      child: Scaffold(backgroundColor: Colors.black, body: body),
    );
  }
}
