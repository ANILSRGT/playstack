import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// One timed line (or lines) of a subtitle file.
@immutable
class PlayStackSubtitleCue {
  /// Creates a cue shown from [start] to [end].
  const PlayStackSubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  /// When it appears.
  final Duration start;

  /// When it disappears.
  final Duration end;

  /// The text, without formatting tags.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PlayStackSubtitleCue &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'PlayStackSubtitleCue($start-$end, $text)';
}

/// Parses WebVTT and SubRip subtitle files.
abstract final class PlayStackSubtitleParser {
  /// Parses [content] as [format] (`auto` detects it).
  static List<PlayStackSubtitleCue> parse(
    String content, {
    PlayStackSubtitleFormat format = PlayStackSubtitleFormat.auto,
  }) {
    final text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cues = <PlayStackSubtitleCue>[];
    // Both formats are blocks separated by blank lines; a block holds a
    // timing line "start --> end" followed by the text.
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n');
      final timing = lines.indexWhere((line) => line.contains('-->'));
      if (timing < 0) continue;
      final parts = lines[timing].split('-->');
      final start = _time(parts[0]);
      final end = _time(parts[1].trim().split(RegExp(r'\s+')).first);
      if (start == null || end == null) continue;
      final body = lines
          .skip(timing + 1)
          .map(_stripTags)
          .where((line) => line.trim().isNotEmpty)
          .join('\n');
      if (body.isEmpty) continue;
      cues.add(PlayStackSubtitleCue(start: start, end: end, text: body));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// "01:02:03.456", "02:03.456" (WebVTT) or "01:02:03,456" (SubRip).
  static Duration? _time(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    final match = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?$')
        .firstMatch(value);
    if (match == null) return null;
    final hours = int.parse(match.group(1) ?? '0');
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final fraction = (match.group(4) ?? '0').padRight(3, '0');
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: int.parse(fraction),
    );
  }

  static final RegExp _tags = RegExp(r'<[^>]*>|\{\\[^}]*\}');

  static String _stripTags(String line) => line
      .replaceAll(_tags, '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}

/// Downloads, parses and shows the subtitle files of a source.
@internal
class PlayStackSidecarSubtitles {
  PlayStackSidecarSubtitles(this._sources);

  /// The prefix of the ids of sidecar tracks.
  static const String idPrefix = 'sidecar:';

  final List<PlayStackSubtitleSource> _sources;
  final Map<int, Future<List<PlayStackSubtitleCue>>> _loaded =
      <int, Future<List<PlayStackSubtitleCue>>>{};
  List<PlayStackSubtitleCue>? _cues;
  int? _selected;
  int _selection = 0;

  bool get isEmpty => _sources.isEmpty;

  /// The index of the selected file, or null.
  int? get selected => _selected;

  /// Whether a sidecar track is selected.
  bool get isActive => _selected != null;

  /// The files as text tracks.
  List<PlayStackTrack> tracks() => [
    for (var i = 0; i < _sources.length; i++)
      PlayStackTrack(
        id: '$idPrefix$i',
        type: PlayStackTrackType.text,
        isSelected: _selected == i,
        label: _sources[i].label,
        language: _sources[i].language,
      ),
  ];

  /// The index of the file marked `isDefault`, or null.
  int? get defaultIndex {
    final index = _sources.indexWhere((source) => source.isDefault);
    return index < 0 ? null : index;
  }

  static int? indexOf(String? trackId) {
    if (trackId == null || !trackId.startsWith(idPrefix)) return null;
    return int.tryParse(trackId.substring(idPrefix.length));
  }

  /// Selects file [index] (null turns sidecar subtitles off) and loads it.
  Future<void> select(int? index) async {
    final selection = ++_selection;
    _selected = index;
    _cues = null;
    if (index == null || index < 0 || index >= _sources.length) {
      _selected = null;
      return;
    }
    try {
      final loading = _loaded[index] ??= _load(_sources[index]);
      final cues = await loading;
      if (selection == _selection) _cues = cues;
    } on Object catch (error, stack) {
      unawaited(_loaded.remove(index)?.then((_) {}, onError: (Object _) {}));
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'playstack',
          context: ErrorDescription('while loading a subtitle file'),
        ),
      );
    }
  }

  /// The lines to show at [position].
  List<String> at(Duration position) {
    final cues = _cues;
    if (cues == null) return const <String>[];
    return [
      for (final cue in cues)
        if (cue.start <= position && position < cue.end) cue.text,
    ];
  }

  static Future<List<PlayStackSubtitleCue>> _load(
    PlayStackSubtitleSource source,
  ) async {
    final text = source.text ?? await _download(source);
    return compute(_parse, (text, source.resolvedFormat));
  }

  static List<PlayStackSubtitleCue> _parse(
    (String, PlayStackSubtitleFormat) input,
  ) => PlayStackSubtitleParser.parse(input.$1, format: input.$2);

  static Future<String> _download(PlayStackSubtitleSource source) async {
    final response = await http.get(
      Uri.parse(source.url!),
      headers: source.headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlayStackException(
        PlayStackErrorCode.network,
        'Subtitle file ${source.url} answered HTTP ${response.statusCode}.',
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}
