import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// One preview image: an image, or a region of a sprite sheet.
@immutable
class PlayStackThumbnail {
  /// Creates a thumbnail from [image], cut to [region] when it is a sprite.
  const PlayStackThumbnail(this.image, {this.region});

  /// The image or sprite sheet.
  final ImageProvider image;

  /// The part of [image] to show, in image pixels; null shows all of it.
  final Rect? region;

  @override
  bool operator ==(Object other) =>
      other is PlayStackThumbnail &&
      other.image == image &&
      other.region == region;

  @override
  int get hashCode => Object.hash(image, region);
}

/// Preview images of a video, shown above the progress bar while the user
/// drags it ([PlayStackProgressBar.thumbnails]).
///
/// ```dart
/// // A WebVTT thumbnail track, as made by most encoders and video hosts:
/// PlayStackThumbnails.webVtt('https://cdn.example.com/ep3/thumbs.vtt')
///
/// // One sprite sheet: a grid of frames, one every 10 seconds.
/// PlayStackThumbnails.sprite(
///   image: NetworkImage('https://cdn.example.com/ep3/sprite.jpg'),
///   columns: 10,
///   rows: 10,
///   interval: Duration(seconds: 10),
/// )
///
/// // Frames read from the video itself; no files to prepare (MP4 and
/// // files; streams have none):
/// PlayStackThumbnails.frames(page.controller.source)
///
/// // Anything else, for example an image per position from your server:
/// PlayStackThumbnails.builder(
///   (position) => PlayStackThumbnail(
///     NetworkImage('https://img.example.com/ep3/${position.inSeconds ~/ 5}.jpg'),
///   ),
/// )
/// ```
abstract class PlayStackThumbnails {
  /// Creates a thumbnail source.
  const PlayStackThumbnails();

  /// A WebVTT thumbnail track: each cue names an image, often a region of a
  /// sprite (`sprite.jpg#xywh=0,0,160,90`). Relative image URLs are read
  /// against [url]. The file is downloaded once per URL.
  factory PlayStackThumbnails.webVtt(
    String url, {
    Map<String, String> headers,
  }) = _WebVttThumbnails;

  /// One sprite sheet: [columns] by [rows] frames, left to right and top to
  /// bottom, one every [interval].
  factory PlayStackThumbnails.sprite({
    required ImageProvider image,
    required int columns,
    required int rows,
    required Duration interval,
  }) = _SpriteThumbnails;

  /// Frames read from the video itself, one every [interval], at most
  /// [maxWidth] pixels wide. They are read in the background while the
  /// user drags, nearest first, and kept for the next drag.
  ///
  /// Works for progressive downloads (MP4) and files on Android and iOS.
  /// HLS, DASH, protected streams and the web show the time only; give
  /// those a [PlayStackThumbnails.webVtt] track.
  factory PlayStackThumbnails.frames(
    PlayStackSource source, {
    Duration interval,
    int maxWidth,
  }) = _FrameThumbnails;

  /// Thumbnails from your own function; return null where there is none.
  factory PlayStackThumbnails.builder(
    PlayStackThumbnail? Function(Duration position) builder,
  ) = _BuilderThumbnails;

  /// Prepares the thumbnails (downloads an index, for example). Called when
  /// the user starts dragging; safe to call often.
  Future<void> load() async {}

  /// The thumbnail for [position], or null while none is known.
  PlayStackThumbnail? at(Duration position);

  /// Notifies when new thumbnails arrive while the user drags, so the
  /// preview can show them. Null (the default) for sources that never
  /// change.
  Listenable? get updates => null;
}

class _FrameThumbnails extends PlayStackThumbnails {
  _FrameThumbnails(
    PlayStackSource source, {
    Duration interval = const Duration(seconds: 5),
    int maxWidth = 240,
  }) : _store = _FrameStore.of(source, interval, maxWidth);

  final _FrameStore _store;

  @override
  PlayStackThumbnail? at(Duration position) => _store.at(position);

  @override
  Listenable get updates => _store;
}

/// The frames of one video, shared by every [_FrameThumbnails] of it.
class _FrameStore extends ChangeNotifier {
  _FrameStore(this.source, this.interval, this.maxWidth);

  static final Map<Object, _FrameStore> _stores = <Object, _FrameStore>{};

  static _FrameStore of(PlayStackSource source, Duration interval, int max) {
    final key = (source, interval, max);
    final store = _stores.remove(key) ?? _FrameStore(source, interval, max);
    // The most recent last; a few videos are kept.
    _stores[key] = store;
    while (_stores.length > 8) {
      _stores.remove(_stores.keys.first);
    }
    return store;
  }

  final PlayStackSource source;
  final Duration interval;
  final int maxWidth;
  final Map<int, PlayStackThumbnail> _frames = <int, PlayStackThumbnail>{};
  int? _wanted;
  bool _busy = false;
  int _failures = 0;

  /// Set once the platform gives no frames for this video.
  bool _unsupported = false;

  PlayStackThumbnail? at(Duration position) {
    final step = interval.inMilliseconds <= 0 ? 1 : interval.inMilliseconds;
    final bucket = position.inMilliseconds ~/ step;
    final frame = _frames[bucket];
    if (frame != null) return frame;
    _request(bucket);
    // The nearest frame read so far, until this one arrives.
    PlayStackThumbnail? nearest;
    var distance = 1 << 30;
    for (final entry in _frames.entries) {
      final d = (entry.key - bucket).abs();
      if (d < distance) {
        distance = d;
        nearest = entry.value;
      }
    }
    return nearest;
  }

  void _request(int bucket) {
    if (_unsupported) return;
    _wanted = bucket;
    if (!_busy) unawaited(_pump());
  }

  Future<void> _pump() async {
    _busy = true;
    try {
      while (_wanted != null && !_unsupported) {
        final bucket = _wanted!;
        _wanted = null;
        if (_frames.containsKey(bucket)) continue;
        Uint8List? bytes;
        try {
          bytes = await PlayStackPlatform.instance.getFrame(
            source,
            interval * bucket,
            maxWidth: maxWidth,
          );
        } on Object {
          bytes = null;
        }
        if (bytes == null || bytes.isEmpty) {
          if (++_failures >= 3 && _frames.isEmpty) _unsupported = true;
          continue;
        }
        _frames[bucket] = PlayStackThumbnail(MemoryImage(bytes));
        notifyListeners();
      }
    } finally {
      _busy = false;
    }
  }
}

class _BuilderThumbnails extends PlayStackThumbnails {
  _BuilderThumbnails(this._builder);

  final PlayStackThumbnail? Function(Duration position) _builder;

  @override
  PlayStackThumbnail? at(Duration position) => _builder(position);
}

class _SpriteThumbnails extends PlayStackThumbnails {
  _SpriteThumbnails({
    required this.image,
    required this.columns,
    required this.rows,
    required this.interval,
  }) : assert(columns > 0 && rows > 0);

  final ImageProvider image;
  final int columns;
  final int rows;
  final Duration interval;
  Size? _size;

  @override
  Future<void> load() async {
    if (_size != null) return;
    final completer = Completer<Size>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()),
          );
        }
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    _size = await completer.future;
  }

  @override
  PlayStackThumbnail? at(Duration position) {
    final size = _size;
    if (size == null || interval <= Duration.zero) return null;
    final index = (position.inMilliseconds ~/ interval.inMilliseconds).clamp(
      0,
      columns * rows - 1,
    );
    final width = size.width / columns;
    final height = size.height / rows;
    return PlayStackThumbnail(
      image,
      region: Rect.fromLTWH(
        (index % columns) * width,
        (index ~/ columns) * height,
        width,
        height,
      ),
    );
  }
}

class _VttCue {
  const _VttCue(this.start, this.end, this.thumbnail);

  final Duration start;
  final Duration end;
  final PlayStackThumbnail thumbnail;
}

class _WebVttThumbnails extends PlayStackThumbnails {
  _WebVttThumbnails(this.url, {this.headers = const <String, String>{}});

  final String url;
  final Map<String, String> headers;

  static final Map<String, Future<List<_VttCue>>> _cache =
      <String, Future<List<_VttCue>>>{};

  List<_VttCue>? _cues;

  @override
  Future<void> load() async {
    if (_cues != null) return;
    try {
      _cues = await (_cache[url] ??= _download(url, headers));
    } on Object {
      unawaited(_cache.remove(url)?.then((_) {}, onError: (Object _) {}));
    }
  }

  @override
  PlayStackThumbnail? at(Duration position) {
    final cues = _cues;
    if (cues == null || cues.isEmpty) return null;
    // Binary search for the last cue starting at or before the position.
    var low = 0;
    var high = cues.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (cues[mid].start <= position) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return cues[low].thumbnail;
  }

  static Future<List<_VttCue>> _download(
    String url,
    Map<String, String> headers,
  ) async {
    final base = Uri.parse(url);
    final response = await http.get(base, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Thumbnail track $url answered ${response.statusCode}');
    }
    return parse(utf8.decode(response.bodyBytes, allowMalformed: true), base);
  }

  static List<_VttCue> parse(String content, Uri base) {
    final cues = <_VttCue>[];
    final images = <String, ImageProvider>{};
    final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    for (final block in blocks) {
      final lines = block.split('\n');
      final timing = lines.indexWhere((line) => line.contains('-->'));
      if (timing < 0 || timing + 1 >= lines.length) continue;
      final parts = lines[timing].split('-->');
      final start = _time(parts[0]);
      final end = _time(parts[1].trim().split(' ').first);
      final target = lines[timing + 1].trim();
      if (start == null || end == null || target.isEmpty) continue;
      final hash = target.indexOf('#');
      final file = hash < 0 ? target : target.substring(0, hash);
      final image = images[file] ??= NetworkImage(
        base.resolve(file).toString(),
      );
      Rect? region;
      final match = RegExp(r'xywh=(\d+),(\d+),(\d+),(\d+)')
          .firstMatch(hash < 0 ? '' : target.substring(hash));
      if (match != null) {
        final v = [for (var i = 1; i <= 4; i++) double.parse(match.group(i)!)];
        region = Rect.fromLTWH(v[0], v[1], v[2], v[3]);
      }
      cues.add(_VttCue(start, end, PlayStackThumbnail(image, region: region)));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static Duration? _time(String raw) {
    final match = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?$')
        .firstMatch(raw.trim());
    if (match == null) return null;
    return Duration(
      hours: int.parse(match.group(1) ?? '0'),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
      milliseconds: int.parse((match.group(4) ?? '0').padRight(3, '0')),
    );
  }
}

/// Draws a [PlayStackThumbnail], cutting sprite regions.
class PlayStackThumbnailImage extends StatefulWidget {
  /// Creates the image of [thumbnail].
  const PlayStackThumbnailImage({
    super.key,
    required this.thumbnail,
    this.fit = BoxFit.cover,
  });

  /// What to draw.
  final PlayStackThumbnail thumbnail;

  /// How it fits its box.
  final BoxFit fit;

  @override
  State<PlayStackThumbnailImage> createState() =>
      _PlayStackThumbnailImageState();
}

class _PlayStackThumbnailImageState extends State<PlayStackThumbnailImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (!mounted) return;
    setState(() {
      _info?.dispose();
      _info = info;
    });
  }, onError: (_, _) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PlayStackThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnail.image != widget.thumbnail.image) _resolve();
  }

  void _resolve() {
    final stream = widget.thumbnail.image.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (image == null) return const SizedBox.expand();
    return CustomPaint(
      size: Size.infinite,
      painter: _RegionPainter(image, widget.thumbnail.region, widget.fit),
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter(this.image, this.region, this.fit);

  final ui.Image image;
  final Rect? region;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final source =
        region ??
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(fit, source.size, size);
    final input = Alignment.center.inscribe(fitted.source, source);
    final output = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      input,
      output,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.region != region ||
      oldDelegate.fit != fit;
}
