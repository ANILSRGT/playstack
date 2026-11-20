import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:playstack_platform_interface/playstack_platform_interface.dart';
import 'package:xml/xml.dart';

/// Moments of an ad that ad servers count, sent to the
/// [PlayStackAd.tracking] URLs.
enum PlayStackAdEvent {
  /// The ad was shown (its first frame).
  impression,

  /// The ad started playing.
  start,

  /// A quarter was played.
  firstQuartile,

  /// Half was played.
  midpoint,

  /// Three quarters were played.
  thirdQuartile,

  /// It played to its end.
  complete,

  /// The user skipped it.
  skip,

  /// The user tapped "Learn more".
  click,

  /// The user paused it.
  pause,

  /// The user resumed it.
  resume,

  /// The ad could not be played.
  error,
}

/// One video ad: what plays and what is reported.
@immutable
class PlayStackAd {
  /// Creates an ad.
  const PlayStackAd({
    required this.source,
    this.id,
    this.title,
    this.duration,
    this.skipAfter,
    this.clickThroughUrl,
    this.tracking = const <PlayStackAdEvent, List<String>>{},
  });

  /// The ad video.
  final PlayStackSource source;

  /// The ad server's id.
  final String? id;

  /// The advertiser's title, when given.
  final String? title;

  /// The declared length.
  final Duration? duration;

  /// When the user may skip; null for ads that cannot be skipped.
  final Duration? skipAfter;

  /// The advertiser's page, opened by "Learn more"
  /// ([PlayStackAds.onClick]).
  final String? clickThroughUrl;

  /// URLs requested at each [PlayStackAdEvent] (impression and quartile
  /// pixels).
  final Map<PlayStackAdEvent, List<String>> tracking;
}

/// Where the ads of an ad break come from.
///
/// ```dart
/// PlayStackAdSource.vast('https://ads.example.com/vast?slot=preroll')
/// PlayStackAdSource.ads([PlayStackAd(source: PlayStackSource.network(url), skipAfter: Duration(seconds: 5))])
/// PlayStackAdSource.custom(() => myAdNetwork.fetch())
/// ```
abstract class PlayStackAdSource {
  /// Creates an ad source.
  const PlayStackAdSource();

  /// A VAST (2, 3 or 4) ad tag. Wrappers are followed, tracking URLs of
  /// every level are kept.
  factory PlayStackAdSource.vast(String url, {Map<String, String> headers}) =
      _VastSource;

  /// Ads you already have.
  factory PlayStackAdSource.ads(List<PlayStackAd> ads) = _FixedSource;

  /// Ads from your own code, for example another ad network's SDK.
  factory PlayStackAdSource.custom(Future<List<PlayStackAd>> Function() load) =
      _CustomSource;

  /// The ads to play; empty when there are none (the break is skipped).
  Future<List<PlayStackAd>> load();
}

class _FixedSource extends PlayStackAdSource {
  const _FixedSource(this.ads);

  final List<PlayStackAd> ads;

  @override
  Future<List<PlayStackAd>> load() async => ads;
}

class _CustomSource extends PlayStackAdSource {
  const _CustomSource(this._load);

  final Future<List<PlayStackAd>> Function() _load;

  @override
  Future<List<PlayStackAd>> load() => _load();
}

class _VastSource extends PlayStackAdSource {
  const _VastSource(this.url, {this.headers = const <String, String>{}});

  final String url;
  final Map<String, String> headers;

  @override
  Future<List<PlayStackAd>> load() => PlayStackVast.load(url, headers: headers);
}

/// A point in a video where ads play.
@immutable
class PlayStackAdBreak {
  /// Ads at [offset] into the video.
  const PlayStackAdBreak({required Duration this.offset, required this.source})
    : isPostRoll = false;

  /// Ads before the video starts.
  const PlayStackAdBreak.preRoll(this.source)
    : offset = Duration.zero,
      isPostRoll = false;

  /// Ads when playback passes [at].
  const PlayStackAdBreak.midRoll({required Duration at, required this.source})
    : offset = at,
      isPostRoll = false;

  /// Ads after the video ends.
  const PlayStackAdBreak.postRoll(this.source)
    : offset = null,
      isPostRoll = true;

  /// Where the break is; null for a post-roll.
  final Duration? offset;

  /// Whether the break plays after the end.
  final bool isPostRoll;

  /// The ads.
  final PlayStackAdSource source;

  /// Whether it plays before the video.
  bool get isPreRoll => !isPostRoll && offset == Duration.zero;
}

/// Reads VAST ad responses.
abstract final class PlayStackVast {
  /// Downloads the VAST tag at [url] and follows wrappers up to
  /// [maxWrappers] deep.
  static Future<List<PlayStackAd>> load(
    String url, {
    Map<String, String> headers = const <String, String>{},
    int maxWrappers = 5,
  }) => _load(url, headers, maxWrappers, const _Inherited());

  static Future<List<PlayStackAd>> _load(
    String url,
    Map<String, String> headers,
    int depth,
    _Inherited inherited,
  ) async {
    final response = await http.get(
      Uri.parse(PlayStackAds.expandMacros(url)),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlayStackException(
        PlayStackErrorCode.network,
        'The ad server answered HTTP ${response.statusCode}.',
      );
    }
    return _resolve(response.body, headers, depth, inherited);
  }

  /// Parses a VAST document; wrappers are not followed.
  static List<PlayStackAd> parse(String xml) {
    final ads = <PlayStackAd>[];
    for (final ad in _ads(XmlDocument.parse(xml))) {
      final inline = ad.getElement('InLine');
      if (inline == null) continue;
      ads.addAll(_inline(ad, inline, const _Inherited()));
    }
    return ads;
  }

  static Future<List<PlayStackAd>> _resolve(
    String xml,
    Map<String, String> headers,
    int depth,
    _Inherited inherited,
  ) async {
    final document = XmlDocument.parse(xml);
    final ads = <PlayStackAd>[];
    for (final ad in _ads(document)) {
      final inline = ad.getElement('InLine');
      if (inline != null) {
        ads.addAll(_inline(ad, inline, inherited));
        continue;
      }
      final wrapper = ad.getElement('Wrapper');
      final next = wrapper?.getElement('VASTAdTagURI')?.innerText.trim();
      if (wrapper == null || next == null || next.isEmpty || depth <= 0) {
        continue;
      }
      try {
        ads.addAll(
          await _load(next, headers, depth - 1, inherited.merge(wrapper)),
        );
      } on Object {
        // One broken wrapper does not hide the other ads.
      }
    }
    return ads;
  }

  static List<XmlElement> _ads(XmlDocument document) {
    final ads = document.rootElement.findElements('Ad').toList();
    // Ads of a pod play in their sequence order.
    ads.sort((a, b) {
      final x = int.tryParse(a.getAttribute('sequence') ?? '') ?? 0;
      final y = int.tryParse(b.getAttribute('sequence') ?? '') ?? 0;
      return x.compareTo(y);
    });
    return ads;
  }

  static Iterable<PlayStackAd> _inline(
    XmlElement ad,
    XmlElement inline,
    _Inherited inherited,
  ) sync* {
    final own = inherited.merge(inline);
    final title = inline.getElement('AdTitle')?.innerText.trim();
    for (final creative
        in inline.getElement('Creatives')?.findElements('Creative') ??
            const <XmlElement>[]) {
      final linear = creative.getElement('Linear');
      if (linear == null) continue;
      final duration = _duration(linear.getElement('Duration')?.innerText);
      final media = _pickMedia(
        linear.getElement('MediaFiles')?.findElements('MediaFile') ??
            const <XmlElement>[],
      );
      if (media == null) continue;
      final tracking = own.merge(linear).tracking;
      final clickThrough = linear
          .getElement('VideoClicks')
          ?.getElement('ClickThrough')
          ?.innerText
          .trim();
      yield PlayStackAd(
        id: ad.getAttribute('id'),
        title: title,
        source: PlayStackSource.network(
          media,
          cachePolicy: PlayStackCachePolicy.bypass,
        ),
        duration: duration,
        skipAfter: _skipOffset(linear.getAttribute('skipoffset'), duration),
        clickThroughUrl: clickThrough == null || clickThrough.isEmpty
            ? null
            : clickThrough,
        tracking: tracking,
      );
    }
  }

  /// The progressive MP4 (or HLS) closest to 720 lines.
  static String? _pickMedia(Iterable<XmlElement> files) {
    String? best;
    var bestScore = double.infinity;
    for (final file in files) {
      final url = file.innerText.trim();
      if (url.isEmpty) continue;
      final type = (file.getAttribute('type') ?? '').toLowerCase();
      final playable =
          type.contains('mp4') ||
          type.contains('mpegurl') ||
          type.contains('quicktime') ||
          url.toLowerCase().contains('.mp4') ||
          url.toLowerCase().contains('.m3u8');
      if (!playable) continue;
      final height = int.tryParse(file.getAttribute('height') ?? '') ?? 720;
      final score =
          (height - 720).abs().toDouble() + (type.contains('mp4') ? 0 : 50);
      if (score < bestScore) {
        bestScore = score;
        best = url;
      }
    }
    return best;
  }

  static Duration? _duration(String? text) {
    final match = RegExp(r'^(\d+):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$')
        .firstMatch(text?.trim() ?? '');
    if (match == null) return null;
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
      milliseconds: int.parse((match.group(4) ?? '0').padRight(3, '0')),
    );
  }

  static Duration? _skipOffset(String? value, Duration? duration) {
    if (value == null || value.isEmpty) return null;
    if (value.endsWith('%')) {
      final percent = double.tryParse(value.substring(0, value.length - 1));
      if (percent == null || duration == null) return null;
      return duration * (percent / 100);
    }
    return _duration(value);
  }
}

/// Tracking collected from wrappers down to the inline ad.
class _Inherited {
  const _Inherited([this.tracking = const <PlayStackAdEvent, List<String>>{}]);

  final Map<PlayStackAdEvent, List<String>> tracking;

  static const Map<String, PlayStackAdEvent> _names = {
    'start': PlayStackAdEvent.start,
    'firstQuartile': PlayStackAdEvent.firstQuartile,
    'midpoint': PlayStackAdEvent.midpoint,
    'thirdQuartile': PlayStackAdEvent.thirdQuartile,
    'complete': PlayStackAdEvent.complete,
    'skip': PlayStackAdEvent.skip,
    'pause': PlayStackAdEvent.pause,
    'resume': PlayStackAdEvent.resume,
  };

  _Inherited merge(XmlElement element) {
    final next = <PlayStackAdEvent, List<String>>{
      for (final MapEntry(:key, :value) in tracking.entries) key: [...value],
    };
    void add(PlayStackAdEvent event, String? url) {
      final trimmed = url?.trim();
      if (trimmed == null || trimmed.isEmpty) return;
      (next[event] ??= <String>[]).add(trimmed);
    }

    for (final impression in element.findElements('Impression')) {
      add(PlayStackAdEvent.impression, impression.innerText);
    }
    for (final error in element.findElements('Error')) {
      add(PlayStackAdEvent.error, error.innerText);
    }
    // An inline ad's pixels belong to each of its creatives: they are
    // merged per Linear. A wrapper's apply to every ad below it.
    final name = element.name.local;
    if (name == 'Wrapper' || name == 'Linear') {
      for (final tracking in element.findAllElements('Tracking')) {
        final event = _names[tracking.getAttribute('event')];
        if (event != null) add(event, tracking.innerText);
      }
      for (final click in element.findAllElements('ClickTracking')) {
        add(PlayStackAdEvent.click, click.innerText);
      }
    }
    return _Inherited(next);
  }
}

/// Helpers shared by the ad player.
abstract final class PlayStackAds {
  static final math.Random _random = math.Random();

  /// Called when the user taps "Learn more" with the ad's page. Open it
  /// with url_launcher, for example; PlayStack does not open URLs itself.
  static void Function(PlayStackAd ad, String url)? onClick;

  /// Replaces the common VAST macros `[CACHEBUSTING]` and `[TIMESTAMP]`.
  static String expandMacros(String url, {String? errorCode}) => url
      .replaceAll(
        '[CACHEBUSTING]',
        (10000000 + _random.nextInt(89999999)).toString(),
      )
      .replaceAll(
        '[TIMESTAMP]',
        Uri.encodeComponent(DateTime.now().toUtc().toIso8601String()),
      )
      .replaceAll('[ERRORCODE]', errorCode ?? '900');

  /// Requests the tracking URLs of [event]; failures are ignored.
  static void track(PlayStackAd ad, PlayStackAdEvent event) {
    for (final url in ad.tracking[event] ?? const <String>[]) {
      unawaited(
        http
            .get(Uri.parse(expandMacros(url)))
            .then((_) {}, onError: (Object _) {}),
      );
    }
  }
}
