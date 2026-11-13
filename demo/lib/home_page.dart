import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'explore_page.dart';
import 'reels_page.dart';

/// Two tabs: the endless reels feed and a grid to explore.
///
/// The tabs live in an [IndexedStack], so the feed keeps its place while
/// another tab is shown. [TickerMode] tells the feed it is hidden, and
/// `PlayStackFeedView` pauses itself until the tab is shown again.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.preload});

  /// The home feed, prepared ahead by the launcher.
  final PlayStackFeedPreload<Object>? preload;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [ReelsPage(preload: widget.preload), const ExplorePage()];
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < tabs.length; i++)
            TickerMode(enabled: i == _tab, child: tabs[i]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        height: 64,
        backgroundColor: Colors.black,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline_rounded),
            selectedIcon: Icon(Icons.play_circle_rounded),
            label: 'Reels',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Explore',
          ),
        ],
      ),
    );
  }
}
