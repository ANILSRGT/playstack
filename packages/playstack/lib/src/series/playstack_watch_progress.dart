import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

import '../controller/playstack_playback_state.dart';
import '../controller/playstack_player_controller.dart';

/// Where the user stopped watching one video.
@immutable
class PlayStackWatchEntry {
  /// Creates an entry. [PlayStackWatchProgress] creates these.
  const PlayStackWatchEntry({
    required this.id,
    required this.position,
    required this.updatedAt,
    this.duration,
    this.finished = false,
  });

  /// Your id of the video, for example the episode id.
  final String id;

  /// Where playback was.
  final Duration position;

  /// The length of the video, when known.
  final Duration? duration;

  /// When the entry was saved.
  final DateTime updatedAt;

  /// Whether the user watched the video to its end
  /// ([PlayStackWatchProgress.finishedAt]).
  final bool finished;

  /// How much was watched, from 0.0 to 1.0, or null when the length is
  /// unknown. For progress bars on posters.
  double? get fraction {
    final total = duration;
    if (finished) return 1;
    if (total == null || total <= Duration.zero) return null;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  /// The entry as JSON, for your own storage.
  Map<String, Object?> toJson() => {
    'p': position.inMilliseconds,
    if (duration case final duration?) 'd': duration.inMilliseconds,
    't': updatedAt.millisecondsSinceEpoch,
    if (finished) 'f': true,
  };

  /// Reads an entry written by [toJson].
  factory PlayStackWatchEntry.fromJson(String id, Map<String, Object?> json) {
    final duration = json['d'];
    return PlayStackWatchEntry(
      id: id,
      position: Duration(milliseconds: (json['p'] as num?)?.toInt() ?? 0),
      duration: duration is num
          ? Duration(milliseconds: duration.toInt())
          : null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['t'] as num?)?.toInt() ?? 0,
      ),
      finished: json['f'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayStackWatchEntry &&
      other.id == id &&
      other.position == position &&
      other.duration == duration &&
      other.updatedAt == updatedAt &&
      other.finished == finished;

  @override
  int get hashCode => Object.hash(id, position, duration, updatedAt, finished);

  @override
  String toString() =>
      'PlayStackWatchEntry($id, $position of $duration'
      '${finished ? ', finished' : ''})';
}

/// Where [PlayStackWatchProgress] keeps its entries between app starts.
///
/// PlayStack has no storage dependency of its own. Connect the one your app
/// uses; with a key-value store such as shared_preferences it is two lines:
///
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// final storage = PlayStackProgressStorage.keyValue(
///   read: () => prefs.getString('watch_progress'),
///   write: (json) => prefs.setString('watch_progress', json),
/// );
/// ```
///
/// Or implement this interface to save entries in a database or on your
/// server.
abstract interface class PlayStackProgressStorage {
  /// Keeps all entries in one JSON string, read with [read] and saved with
  /// [write]: shared_preferences, a file, secure storage.
  factory PlayStackProgressStorage.keyValue({
    required FutureOr<String?> Function() read,
    required FutureOr<void> Function(String json) write,
  }) = _KeyValueStorage;

  /// Returns every saved entry.
  Future<List<PlayStackWatchEntry>> readAll();

  /// Saves the current entries. [changed] are the ones that changed since
  /// the last call and [removed] the ids deleted since then; [all] is
  /// everything, for storages that write it whole.
  Future<void> save({
    required List<PlayStackWatchEntry> all,
    required List<PlayStackWatchEntry> changed,
    required List<String> removed,
  });
}

class _KeyValueStorage implements PlayStackProgressStorage {
  _KeyValueStorage({required this.read, required this.write});

  final FutureOr<String?> Function() read;
  final FutureOr<void> Function(String json) write;

  @override
  Future<List<PlayStackWatchEntry>> readAll() async {
    final text = await read();
    if (text == null || text.isEmpty) return const [];
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) return const [];
    return [
      for (final MapEntry(:key, :value) in decoded.entries)
        if (value is Map<String, Object?>)
          PlayStackWatchEntry.fromJson(key, value),
    ];
  }

  @override
  Future<void> save({
    required List<PlayStackWatchEntry> all,
    required List<PlayStackWatchEntry> changed,
    required List<String> removed,
  }) async {
    await write(
      jsonEncode({for (final entry in all) entry.id: entry.toJson()}),
    );
  }
}

/// Remembers where the user stopped each video, so episodes continue where
/// they left off and the app can show a "continue watching" row.
///
/// ```dart
/// final progress = PlayStackWatchProgress(storage: storage);
/// await progress.load(); // once, at start
///
/// PlayStackFeedView<Episode>(
///   items: episodes,
///   itemId: (episode) => episode.id,
///   series: PlayStackSeries(progress: progress),
/// )
/// ```
///
/// The feed then starts each episode where it was left and saves the
/// position while it plays. With your own players, call [track]:
///
/// ```dart
/// controller.startPosition = progress.resumePosition(episode.id);
/// final tracking = progress.track(controller, episode.id);
/// // when done
/// tracking.stop();
/// ```
///
/// Without a [storage] the entries live only while the app runs.
class PlayStackWatchProgress extends ChangeNotifier {
  /// Creates a progress store.
  PlayStackWatchProgress({
    this.storage,
    this.saveInterval = const Duration(seconds: 5),
    this.finishedAt = 0.95,
    this.minimumPosition = const Duration(seconds: 5),
    this.maxEntries = 500,
  }) : assert(finishedAt > 0 && finishedAt <= 1),
       assert(maxEntries > 0);

  /// Where entries are kept between app starts, or null for memory only.
  final PlayStackProgressStorage? storage;

  /// How often the position of a playing video is written to [storage]. 5
  /// seconds by default; it is also written on pause, at the end and when
  /// tracking stops.
  final Duration saveInterval;

  /// The share of a video after which it counts as watched
  /// ([PlayStackWatchEntry.finished]) and starts from the beginning next
  /// time: 0.95 by default, so the credits do not count.
  final double finishedAt;

  /// Positions before this are not worth resuming: 5 seconds by default.
  final Duration minimumPosition;

  /// The most entries kept; the oldest are dropped beyond it. 500 by
  /// default.
  final int maxEntries;

  final Map<String, PlayStackWatchEntry> _entries =
      <String, PlayStackWatchEntry>{};
  final Map<String, PlayStackWatchEntry> _changed =
      <String, PlayStackWatchEntry>{};
  final Set<String> _removed = <String>{};
  Future<void>? _loading;
  Future<void> _saving = Future<void>.value();
  bool _disposed = false;

  /// Whether [load] finished.
  bool get isLoaded => _loaded;
  bool _loaded = false;

  /// Reads the saved entries from [storage]. Call it once before the first
  /// feed opens; later calls return the same future.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final storage = this.storage;
    if (storage != null) {
      for (final entry in await storage.readAll()) {
        _entries.putIfAbsent(entry.id, () => entry);
      }
    }
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  /// The entry of [id], or null when the user has not watched it.
  PlayStackWatchEntry? operator [](String id) => _entries[id];

  /// All entries, most recent first.
  List<PlayStackWatchEntry> get entries =>
      _entries.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// The videos started but not finished, most recent first: a "continue
  /// watching" row.
  List<PlayStackWatchEntry> get unfinished => [
    for (final entry in entries)
      if (!entry.finished && entry.position >= minimumPosition) entry,
  ];

  /// Where [id] should start: the saved position, or null to start from the
  /// beginning (never watched, finished, or barely started).
  Duration? resumePosition(String id) {
    final entry = _entries[id];
    if (entry == null || entry.finished) return null;
    if (entry.position < minimumPosition) return null;
    return entry.position;
  }

  /// Saves [position] for [id] yourself, for example from your server.
  void update(String id, Duration position, {Duration? duration}) {
    final total = duration ?? _entries[id]?.duration;
    final finished =
        total != null &&
        total > Duration.zero &&
        position.inMilliseconds >= total.inMilliseconds * finishedAt;
    _put(
      PlayStackWatchEntry(
        id: id,
        position: position,
        duration: total,
        updatedAt: DateTime.now(),
        finished: finished,
      ),
    );
  }

  /// Marks [id] as watched to the end.
  void markFinished(String id) {
    final entry = _entries[id];
    _put(
      PlayStackWatchEntry(
        id: id,
        position: entry?.duration ?? entry?.position ?? Duration.zero,
        duration: entry?.duration,
        updatedAt: DateTime.now(),
        finished: true,
      ),
    );
  }

  /// Forgets [id].
  Future<void> remove(String id) {
    if (_entries.remove(id) == null) return _saving;
    _changed.remove(id);
    _removed.add(id);
    notifyListeners();
    return flush();
  }

  /// Forgets everything, for example when the user signs out.
  Future<void> clear() {
    _removed.addAll(_entries.keys);
    _entries.clear();
    _changed.clear();
    notifyListeners();
    return flush();
  }

  void _put(PlayStackWatchEntry entry) {
    if (_disposed) return;
    _entries[entry.id] = entry;
    _changed[entry.id] = entry;
    _removed.remove(entry.id);
    if (_entries.length > maxEntries) {
      final oldest = entries.last;
      _entries.remove(oldest.id);
      _changed.remove(oldest.id);
      _removed.add(oldest.id);
    }
    notifyListeners();
  }

  /// Writes the pending changes to [storage] now.
  Future<void> flush() {
    final storage = this.storage;
    if (storage == null || (_changed.isEmpty && _removed.isEmpty)) {
      _changed.clear();
      _removed.clear();
      return _saving;
    }
    final changed = _changed.values.toList();
    final removed = _removed.toList();
    final all = _entries.values.toList();
    _changed.clear();
    _removed.clear();
    return _saving = _saving
        .then((_) => storage.save(all: all, changed: changed, removed: removed))
        .catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'playstack',
              context: ErrorDescription('while saving watch progress'),
            ),
          );
        });
  }

  /// Saves the position of [controller] under [id] while it plays, on
  /// pause and at the end. Call [PlayStackProgressTracking.stop] when the
  /// video is done.
  PlayStackProgressTracking track(
    PlayStackPlayerController controller,
    String id,
  ) => PlayStackProgressTracking._(this, controller, id);

  @override
  void dispose() {
    _disposed = true;
    unawaited(flush());
    super.dispose();
  }
}

/// A video whose position [PlayStackWatchProgress] saves. See
/// [PlayStackWatchProgress.track].
class PlayStackProgressTracking {
  PlayStackProgressTracking._(this._progress, this._controller, this.id) {
    _controller.addListener(_onState);
    _positions = _controller
        .positions(interval: const Duration(seconds: 1))
        .listen(_onPosition, onError: (Object _) {});
    _saveTimer = Timer.periodic(_progress.saveInterval, (_) {
      if (_controller.value.isPlaying) unawaited(_progress.flush());
    });
  }

  final PlayStackWatchProgress _progress;
  final PlayStackPlayerController _controller;

  /// The id the position is saved under.
  final String id;

  StreamSubscription<PlayStackPositionSnapshot>? _positions;
  Timer? _saveTimer;
  Duration? _last;
  bool _stopped = false;
  PlayStackPlaybackStatus? _status;

  void _onPosition(PlayStackPositionSnapshot snapshot) {
    final position = snapshot.position;
    // Nothing has played yet: the beginning would overwrite a saved
    // position while the video prepares to resume.
    if (!_controller.value.isInitialized) return;
    if (position == Duration.zero && _last == null) return;
    _last = position;
    _progress.update(id, position, duration: _controller.value.duration);
  }

  void _onState() {
    final state = _controller.value;
    final status = state.status;
    if (status == _status) return;
    final previous = _status;
    _status = status;
    if (status == PlayStackPlaybackStatus.completed) {
      if (state.duration case final duration?) {
        _progress.update(id, duration, duration: duration);
      } else {
        _progress.markFinished(id);
      }
      unawaited(_progress.flush());
    } else if (previous == PlayStackPlaybackStatus.playing &&
        status == PlayStackPlaybackStatus.paused) {
      unawaited(_save());
    }
  }

  Future<void> _save() async {
    if (_controller.isDisposed || !_controller.value.isInitialized) {
      return _progress.flush();
    }
    try {
      final position = (await _controller.getPosition()).position;
      if (position > Duration.zero) {
        _progress.update(id, position, duration: _controller.value.duration);
      }
    } on Object {
      // The player went away; the last position stays.
    }
    return _progress.flush();
  }

  /// Saves the last position and stops following the video.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _saveTimer?.cancel();
    unawaited(_positions?.cancel());
    if (!_controller.isDisposed) _controller.removeListener(_onState);
    if (_controller.value.status != PlayStackPlaybackStatus.completed) {
      await _save();
    } else {
      await _progress.flush();
    }
  }
}
