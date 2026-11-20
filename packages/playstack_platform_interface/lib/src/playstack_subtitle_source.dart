import 'package:flutter/foundation.dart';

/// The format of a [PlayStackSubtitleSource].
enum PlayStackSubtitleFormat {
  /// Detect from the URL: `.srt` is SubRip, anything else WebVTT.
  auto,

  /// WebVTT (`.vtt`).
  webVtt,

  /// SubRip (`.srt`).
  srt,
}

/// A subtitle file next to the video, such as `episode-3.tr.vtt`, for
/// videos without subtitles inside the stream.
///
/// ```dart
/// PlayStackSource.network(
///   'https://cdn.example.com/episode-3.mp4',
///   subtitles: [
///     PlayStackSubtitleSource.network(
///       'https://cdn.example.com/episode-3.tr.vtt',
///       language: 'tr',
///       label: 'Türkçe',
///     ),
///     PlayStackSubtitleSource.text(srtText, language: 'en', label: 'English'),
///   ],
/// )
/// ```
///
/// They appear in `controller.tracks` as text tracks next to the stream's
/// own, are chosen the same way (`selectTrack`, the settings sheet), and
/// fill `controller.subtitles`, so they work on every platform.
@immutable
class PlayStackSubtitleSource {
  /// A subtitle file at [url].
  const PlayStackSubtitleSource.network(
    String this.url, {
    this.language,
    this.label,
    this.format = PlayStackSubtitleFormat.auto,
    this.headers = const <String, String>{},
    this.isDefault = false,
  }) : text = null;

  /// Subtitles you already have as [text], for example from your API.
  const PlayStackSubtitleSource.text(
    String this.text, {
    this.language,
    this.label,
    this.format = PlayStackSubtitleFormat.auto,
    this.isDefault = false,
  }) : url = null,
       headers = const <String, String>{};

  /// Where the file is, for [PlayStackSubtitleSource.network].
  final String? url;

  /// The content, for [PlayStackSubtitleSource.text].
  final String? text;

  /// BCP 47 language tag, such as `tr`.
  final String? language;

  /// The name shown in menus, such as "Türkçe".
  final String? label;

  /// WebVTT or SubRip.
  final PlayStackSubtitleFormat format;

  /// HTTP headers for downloading [url].
  final Map<String, String> headers;

  /// Whether these subtitles are on when the video starts.
  final bool isDefault;

  /// [format], or the one detected from [url] and [text].
  PlayStackSubtitleFormat get resolvedFormat {
    if (format != PlayStackSubtitleFormat.auto) return format;
    final path = (url ?? '').split('?').first.toLowerCase();
    if (path.endsWith('.srt')) return PlayStackSubtitleFormat.srt;
    final content = text?.trimLeft() ?? '';
    if (url == null && !content.startsWith('WEBVTT')) {
      return PlayStackSubtitleFormat.srt;
    }
    return PlayStackSubtitleFormat.webVtt;
  }

  @override
  bool operator ==(Object other) =>
      other is PlayStackSubtitleSource &&
      other.url == url &&
      other.text == text &&
      other.language == language &&
      other.label == label &&
      other.format == format &&
      mapEquals(other.headers, headers) &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(
    url,
    text,
    language,
    label,
    format,
    Object.hashAllUnordered(
      headers.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    isDefault,
  );
}
