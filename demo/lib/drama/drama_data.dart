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

  /// The id PlayStack saves the position under.
  String get id => 'coastline-$number';

  /// The opening titles, skipped with "Skip intro". Made up for the demo.
  Duration get introEnd => const Duration(seconds: 4);
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
        source: i == 0 ? _withSubtitles(video.source) : video.source,
        poster: video.poster,
      ),
  ],
);

/// Adds subtitle files to a source. A real app would point
/// `PlayStackSubtitleSource.network` at its `.vtt` or `.srt` files.
PlayStackSource _withSubtitles(PlayStackSource source) {
  if (source is! PlayStackNetworkSource) return source;
  return PlayStackSource.network(
    source.url,
    cacheKey: source.cacheKey,
    subtitles: const [
      PlayStackSubtitleSource.text(
        'WEBVTT\n\n00:00.500 --> 00:03.000\nPrevious summer, on the coast…\n\n'
        '00:03.500 --> 00:07.000\nThe waves had not changed.\n\n'
        '00:07.500 --> 00:12.000\nBut we had.',
        language: 'en',
        label: 'English',
      ),
      PlayStackSubtitleSource.text(
        'WEBVTT\n\n00:00.500 --> 00:03.000\nGeçen yaz, sahilde…\n\n'
        '00:03.500 --> 00:07.000\nDalgalar değişmemişti.\n\n'
        '00:07.500 --> 00:12.000\nAma biz değişmiştik.',
        language: 'tr',
        label: 'Türkçe',
      ),
    ],
  );
}

/// Where the user is in each episode, and which episodes are unlocked.
///
/// Positions are kept by PlayStack's `PlayStackWatchProgress`
/// ([episodeProgress]), which the episode feed fills by itself
/// (`PlayStackSeries.progress`). A real app would give it a storage, for
/// example shared_preferences.
class WatchProgress extends ChangeNotifier {
  WatchProgress() {
    episodeProgress.addListener(notifyListeners);
  }

  /// Episodes after this one need unlocking, as in short-drama apps.
  static const freeEpisodes = 5;

  final Set<int> _unlocked = {};

  /// Whether [episode] is still locked for this user.
  bool isLocked(Episode episode) =>
      episode.number > freeEpisodes && !_unlocked.contains(episode.number);

  /// Unlocks [episode], as after a purchase or a rewarded ad. A real app
  /// would ask its store or backend first.
  void unlock(Episode episode) {
    if (_unlocked.add(episode.number)) notifyListeners();
  }

  /// Where to continue [episode], or null to start at the beginning.
  Duration? positionOf(Episode episode) =>
      episodeProgress.resumePosition(episode.id);

  bool isFinished(Episode episode) =>
      episodeProgress[episode.id]?.finished ?? false;

  /// The episode to continue with: the last one left unfinished, or the one
  /// after the last finished one.
  Episode? continueWith(Series series) {
    for (final entry in episodeProgress.entries) {
      final index = series.episodes.indexWhere((e) => e.id == entry.id);
      if (index < 0) continue;
      if (!entry.finished) return series.episodes[index];
      return index + 1 < series.episodes.length
          ? series.episodes[index + 1]
          : null;
    }
    return null;
  }
}

/// Saves where the user stopped each episode. Without a storage it lives
/// while the app runs; pass `PlayStackProgressStorage.keyValue(...)` to keep
/// it.
final episodeProgress = PlayStackWatchProgress();

final watchProgress = WatchProgress();

/// `1:05` style.
String formatPosition(Duration position) {
  final minutes = position.inMinutes;
  final seconds = (position.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
