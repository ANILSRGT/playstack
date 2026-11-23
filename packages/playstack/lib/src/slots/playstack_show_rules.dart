import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'playstack_show_store_io.dart'
    if (dart.library.js_interop) 'playstack_show_store_web.dart'
    as platform_store;

/// How often something may show, for [PlayStackShowRules].
///
/// ```dart
/// PlayStackShowRule.always
/// PlayStackShowRule.once                                   // never again
/// PlayStackShowRule.every(const Duration(hours: 24))       // at most once a day
/// PlayStackShowRule.atMost(3, per: const Duration(days: 1)) // three times a day
/// ```
@immutable
class PlayStackShowRule {
  const PlayStackShowRule._(this.times, this.per);

  /// Every time.
  static const PlayStackShowRule always = PlayStackShowRule._(null, null);

  /// The first time only.
  static const PlayStackShowRule once = PlayStackShowRule._(1, null);

  /// At most once in each [cooldown].
  const PlayStackShowRule.every(Duration cooldown) : this._(1, cooldown);

  /// At most [times] times, in each [per] window or ever.
  const PlayStackShowRule.atMost(int times, {Duration? per})
    : this._(times, per);

  /// How many times it may show in [per]; null for no limit.
  final int? times;

  /// The window [times] counts in; null for ever.
  final Duration? per;

  /// Whether one more showing is allowed after [shown] (oldest first).
  bool allows(List<DateTime> shown, DateTime now) {
    final limit = times;
    if (limit == null) return true;
    final window = per;
    final count = window == null
        ? shown.length
        : shown.where((at) => now.difference(at) < window).length;
    return count < limit;
  }
}

/// Where [PlayStackShowRules] keeps what was shown: one string.
///
/// ```dart
/// PlayStackShowStore.memory()                           // until the app quits
/// PlayStackShowStore.file('${dir.path}/playstack_shows.json')
/// PlayStackShowStore.custom(                            // SharedPreferences, a database...
///   read: () async => prefs.getString('playstack_shows'),
///   write: (data) => prefs.setString('playstack_shows', data),
/// )
/// ```
abstract class PlayStackShowStore {
  /// Creates a store.
  const PlayStackShowStore();

  /// Kept in memory: forgotten when the app quits.
  factory PlayStackShowStore.memory() = _MemoryStore;

  /// Kept in a file at [path] (not on the web, where it keeps nothing).
  factory PlayStackShowStore.file(String path) =>
      platform_store.fileStore(path);

  /// Kept by your own code.
  factory PlayStackShowStore.custom({
    required Future<String?> Function() read,
    required Future<void> Function(String data) write,
  }) => _CustomStore(read, write);

  /// The stored data, or null when nothing was stored yet.
  Future<String?> read();

  /// Replaces the stored data.
  Future<void> write(String data);
}

class _MemoryStore extends PlayStackShowStore {
  String? _data;

  @override
  Future<String?> read() async => _data;

  @override
  Future<void> write(String data) async => _data = data;
}

class _CustomStore extends PlayStackShowStore {
  const _CustomStore(this._read, this._write);

  final Future<String?> Function() _read;
  final Future<void> Function(String data) _write;

  @override
  Future<String?> read() => _read();

  @override
  Future<void> write(String data) => _write(data);
}

/// Ready-made rules for `shouldShow`, kept on the device: when something
/// was shown, and whether it may show again. Optional: decide in your own
/// code or on your server instead.
///
/// ```dart
/// final rules = PlayStackShowRules(store: PlayStackShowStore.file(path));
///
/// ads: PlayStackFeedAds(
///   breaks: (episode) => [
///     PlayStackAdBreak.midRoll(at: const Duration(minutes: 2), id: 'mid', source: ...),
///   ],
///   shouldShow: (episode, adBreak) =>
///       rules.allows('${episode.id}/${adBreak.id}', const PlayStackShowRule.every(Duration(days: 1))),
///   onEvent: (episode, adBreak, event) {
///     if (event.type == PlayStackAdBreakEventType.started) {
///       rules.record('${episode.id}/${adBreak.id}');
///     }
///   },
/// )
/// ```
///
/// Keys are yours: `'mid'` for every episode's mid-roll together,
/// `'${episode.id}/mid'` for each episode's own.
class PlayStackShowRules {
  /// Creates rules kept in [store] (in memory by default).
  PlayStackShowRules({PlayStackShowStore? store, DateTime Function()? clock})
    : store = store ?? PlayStackShowStore.memory(),
      _clock = clock ?? DateTime.now;

  /// Where the showings are kept.
  final PlayStackShowStore store;

  final DateTime Function() _clock;
  Map<String, List<DateTime>>? _shown;
  Future<void> _writing = Future<void>.value();

  /// How many showings are kept per key.
  static const int keptPerKey = 50;

  Future<Map<String, List<DateTime>>> _load() async {
    final loaded = _shown;
    if (loaded != null) return loaded;
    final map = <String, List<DateTime>>{};
    try {
      final data = await store.read();
      if (data != null && data.isNotEmpty) {
        final json = jsonDecode(data) as Map<String, dynamic>;
        for (final MapEntry(:key, :value) in json.entries) {
          map[key] = [
            for (final ms in value as List<dynamic>)
              DateTime.fromMillisecondsSinceEpoch(ms as int),
          ];
        }
      }
    } on Object catch (error) {
      // A broken store starts over rather than blocking playback.
      debugPrint('PlayStackShowRules: could not read the store: $error');
    }
    return _shown ??= map;
  }

  /// Whether [key] may show now under [rule].
  Future<bool> allows(String key, PlayStackShowRule rule) async {
    if (rule.times == null) return true;
    final shown = await _load();
    return rule.allows(shown[key] ?? const [], _clock());
  }

  /// Records that [key] was shown now.
  Future<void> record(String key) async {
    final shown = await _load();
    final list = shown[key] ??= <DateTime>[];
    list.add(_clock());
    if (list.length > keptPerKey) list.removeRange(0, list.length - keptPerKey);
    await _save(shown);
  }

  /// When [key] was shown, oldest first.
  Future<List<DateTime>> history(String key) async =>
      List<DateTime>.unmodifiable((await _load())[key] ?? const []);

  /// Forgets [key], or everything when null.
  Future<void> reset([String? key]) async {
    final shown = await _load();
    if (key == null) {
      shown.clear();
    } else {
      shown.remove(key);
    }
    await _save(shown);
  }

  Future<void> _save(Map<String, List<DateTime>> shown) {
    final data = jsonEncode({
      for (final MapEntry(:key, :value) in shown.entries)
        key: [for (final at in value) at.millisecondsSinceEpoch],
    });
    // One write at a time, in order.
    return _writing = _writing.then((_) => store.write(data)).catchError((
      Object error,
    ) {
      debugPrint('PlayStackShowRules: could not write the store: $error');
    });
  }
}
