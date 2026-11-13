import 'package:flutter/foundation.dart';
import 'package:playstack/playstack.dart';

import 'catalog.dart';

/// App state of the demo: likes and what the user watched. A real app would
/// keep this in its own state management and send views to its backend.
class DemoState extends ChangeNotifier {
  final Set<DemoVideo> _liked = {};
  final List<PlayStackItemView<Object>> _views = [];

  bool isLiked(DemoVideo video) => _liked.contains(video);

  void toggleLike(DemoVideo video) {
    if (!_liked.remove(video)) _liked.add(video);
    notifyListeners();
  }

  void like(DemoVideo video) {
    if (_liked.add(video)) notifyListeners();
  }

  /// Every visit reported by `PlayStackFeedView.onItemViewed`, oldest first.
  List<PlayStackItemView<Object>> get views => List.unmodifiable(_views);

  void recordView(PlayStackItemView<Object> view) {
    _views.add(view);
    notifyListeners();
  }

  Duration get totalWatchTime =>
      _views.fold(Duration.zero, (total, view) => total + view.watchTime);

  int get completedCount => _views.where((view) => view.completed).length;
}

/// One state for the whole demo, to keep the example short.
final demoState = DemoState();
