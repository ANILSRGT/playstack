import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reelkit/reelkit.dart';

import 'catalog.dart';
import 'reel_overlay.dart';
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

/// The demo's feed: ReelKit's [ReelFeedView] with the demo's overlay, plus
/// menus to change the transition and to show stats.
class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final _view = ReelFeedViewController();
  final _liked = <String>{};
  String _transition = 'Slide';
  Axis _axis = Axis.vertical;
  bool _reverse = false;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ReelFeedView<DemoVideo>(
            items: demoCatalog,
            source: (video) => video.source,
            posterUrl: (video) => video.poster,
            // Endless: the catalog again whenever the end is near.
            onLoadMore: () async => demoCatalog,
            controller: _view,
            transition: demoTransitions[_transition]!,
            scrollDirection: _axis,
            reverse: _reverse,
            controlsBuilder: (context, page) => ReelOverlay(
              page: page,
              liked: _liked.contains(page.item.id),
              onLike: (liked) => setState(
                () => liked
                    ? _liked.add(page.item.id)
                    : _liked.remove(page.item.id),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _view,
            builder: (context, _) =>
                _view.isFullscreen ? const SizedBox.shrink() : _topBar(),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    const shadows = [Shadow(blurRadius: 6)];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Text(
              'ReelKit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                shadows: shadows,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Transition and direction',
              icon: const Icon(Icons.tune, shadows: shadows),
              onPressed: _showLayout,
            ),
            IconButton(
              tooltip: 'Stats',
              icon: const Icon(Icons.insights, shadows: shadows),
              onPressed: _showStats,
            ),
          ],
        ),
      ),
    );
  }

  void _showStats() {
    final manager = _view.manager;
    final feed = _view.feed;
    if (manager == null || feed == null) return;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => StatsSheet(manager: manager, feed: feed),
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

            final title = Theme.of(context).textTheme.titleSmall;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transition', style: title),
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
                    Text('Direction', style: title),
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
}
