import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';
import 'reel_overlay.dart';
import 'settings.dart';
import 'stats_sheet.dart';

/// The transitions the demo offers, by name.
const demoTransitions = <String, ReelFeedTransition>{
  'Slide': ReelFeedTransition.slide,
  'Parallax': ReelFeedTransition.parallax,
  'Stack': ReelFeedTransition.stack,
  'Fade': ReelFeedTransition.fade,
  'Zoom': ReelFeedTransition.zoom,
  'Cube': ReelFeedTransition.cube,
};

/// An endless short-video feed: ReelKit's [ReelFeedView] with the demo's
/// overlay on top.
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final ReelKitManager _manager = ReelKitManager(config: demoKitConfig());
  final Set<String> _liked = <String>{};

  ReelFeedManager? _feed;
  Object? _initError;
  int _batches = 0;
  bool _fill = false;
  bool _fullscreen = false;
  String _transition = 'Slide';
  Axis _axis = Axis.vertical;
  bool _reverse = false;

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
  }

  /// The catalog again, with fresh ids, for an endless feed.
  List<ReelFeedItem> _nextBatch() {
    final batch = _batches++;
    return [
      for (var i = 0; i < demoCatalog.length; i++)
        ReelFeedItem(
          demoCatalog[i].source,
          id: 'b$batch-$i',
          poster: switch (demoCatalog[i].poster) {
            final url? => NetworkImage(url),
            null => null,
          },
          data: demoCatalog[i],
        ),
    ];
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

  void _showLayout() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => StatefulBuilder(
          builder: (context, setSheetState) {
            void update(VoidCallback change) {
              setState(change);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transition',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in demoTransitions.keys)
                          ChoiceChip(
                            label: Text(name),
                            selected: _transition == name,
                            onSelected: (_) => update(() => _transition = name),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Direction',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<Axis>(
                      segments: const [
                        ButtonSegment(
                          value: Axis.vertical,
                          label: Text('Vertical'),
                          icon: Icon(Icons.swap_vert),
                        ),
                        ButtonSegment(
                          value: Axis.horizontal,
                          label: Text('Horizontal'),
                          icon: Icon(Icons.swap_horiz),
                        ),
                      ],
                      selected: {_axis},
                      onSelectionChanged: (value) =>
                          update(() => _axis = value.single),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Reverse'),
                      subtitle: Text(
                        _axis == Axis.vertical
                            ? 'Next video comes from above'
                            : 'Next video comes from the left',
                      ),
                      value: _reverse,
                      onChanged: (value) => update(() => _reverse = value),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
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
          ReelFeedView(
            feed: feed,
            transition: demoTransitions[_transition]!,
            scrollDirection: _axis,
            reverse: _reverse,
            physics: _fullscreen ? const NeverScrollableScrollPhysics() : null,
            precachePosters: 6,
            onEndReached: () => feed.addAll(_nextBatch()),
            videoBuilder: (context, page) =>
                ValueListenableBuilder<ReelPlaybackState>(
                  valueListenable: page.controller,
                  builder: (context, state, _) {
                    final landscape = isLandscape(
                      state,
                      page.data! as DemoVideo,
                    );
                    return ReelVideoView(
                      controller: page.controller,
                      fit: !landscape || (_fill && !_fullscreen)
                          ? BoxFit.cover
                          : BoxFit.contain,
                      poster: page.item.poster,
                    );
                  },
                ),
            controlsBuilder: (context, page) => ReelOverlay(
              page: page,
              fill: _fill,
              fullscreen: _fullscreen,
              liked: _liked.contains(page.item.id),
              onLike: (liked) => setState(
                () => liked
                    ? _liked.add(page.item.id)
                    : _liked.remove(page.item.id),
              ),
              onToggleFill: () => setState(() => _fill = !_fill),
              onToggleFullscreen: () =>
                  unawaited(_toggleFullscreen(page.controller)),
            ),
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
                      tooltip: 'Transition and direction',
                      icon: const Icon(
                        Icons.tune,
                        shadows: [Shadow(blurRadius: 6)],
                      ),
                      onPressed: _showLayout,
                    ),
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
