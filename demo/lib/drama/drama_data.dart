import 'package:flutter/foundation.dart';
import 'package:playstack/playstack.dart';

import '../catalog.dart';

/// One episode of a series.
@immutable
class Episode {
  const Episode({
    required this.number,
    required this.title,
    required this.source,
    this.poster,
  });

  final int number;
  final String title;
  final PlayStackSource source;
  final String? poster;
}

/// A short vertical drama: a series of episodes watched in order.
class Series {
  Series({required this.title, required this.synopsis, required this.episodes});

  final String title;
  final String synopsis;
  final List<Episode> episodes;

  String? get poster => episodes.first.poster;
}

/// The demo series. Its episodes are the catalog's vertical clips; a real
/// app would load them from its backend.
final Series demoSeries = Series(
  title: 'Coastline',
  synopsis:
      'A summer on the coast, told in short vertical episodes. Swipe for '
      'the next one, or pick any episode from the list.',
  episodes: [
    for (final (i, video) in verticalVideos.indexed)
      Episode(
        number: i + 1,
        title: video.title,
        source: video.source,
        poster: video.poster,
      ),
  ],
);

/// Where the user is in each episode. A real app would save this on the
/// device or its backend.
class WatchProgress extends ChangeNotifier {
  /// Episodes after this one need unlocking, as in short-drama apps.
  static const freeEpisodes = 5;

  final Map<int, Duration> _positions = {};
  final Set<int> _unlocked = {};

  /// Whether [episode] is still locked for this user.
  bool isLocked(Episode episode) =>
      episode.number > freeEpisodes && !_unlocked.contains(episode.number);

  /// Unlocks [episode], as after a purchase or a rewarded ad. A real app
  /// would ask its store or backend first.
  void unlock(Episode episode) {
    if (_unlocked.add(episode.number)) notifyListeners();
  }

  final Set<int> _finished = {};
  int? _lastEpisode;

  /// Where to continue [episode], or null to start at the beginning.
  Duration? positionOf(Episode episode) => _positions[episode.number];

  bool isFinished(Episode episode) => _finished.contains(episode.number);

  /// The episode to continue with: the last one left unfinished, or the one
  /// after the last finished one.
  Episode? continueWith(Series series) {
    final last = _lastEpisode;
    if (last == null) return null;
    final index = series.episodes.indexWhere((e) => e.number == last);
    if (index < 0) return null;
    final episode = series.episodes[index];
    if (!isFinished(episode)) return episode;
    return index + 1 < series.episodes.length
        ? series.episodes[index + 1]
        : null;
  }

  /// Records a visit reported by `PlayStackFeedView.onItemViewed`.
  void record(PlayStackItemView<Episode> view) {
    final episode = view.data;
    if (view.position == null && !view.completed) return; // never played
    _lastEpisode = episode.number;
    if (view.completed) {
      _finished.add(episode.number);
      _positions.remove(episode.number);
    } else {
      _positions[episode.number] = view.position!;
    }
    notifyListeners();
  }
}

final watchProgress = WatchProgress();

/// `1:05` style.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = (position.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
