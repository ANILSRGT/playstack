import 'package:flutter/foundation.dart';

/// Kind of media track.
enum PlayStackTrackType {
  /// An audio track.
  audio,

  /// A video track; several video tracks are different qualities.
  video,

  /// A subtitle or caption track.
  text,
}

/// One selectable audio, video (quality) or text (subtitle) track.
///
/// Track ids are engine-defined and stable for the same source; do not
/// persist them across sources or platforms.
@immutable
class PlayStackTrack {
  /// Creates a track description. Engines create these.
  const PlayStackTrack({
    required this.id,
    required this.type,
    required this.isSelected,
    this.label,
    this.language,
    this.bitrate,
    this.width,
    this.height,
    this.frameRate,
    this.codecs,
    this.channelCount,
  });

  /// Engine-defined id, used to select the track.
  final String id;

  /// Kind of track.
  final PlayStackTrackType type;

  /// Whether the track is currently selected.
  final bool isSelected;

  /// Human-readable name declared by the media, when present.
  final String? label;

  /// BCP 47 language tag, when known.
  final String? language;

  /// Bits per second, when known.
  final int? bitrate;

  /// Video width in pixels, for video tracks.
  final int? width;

  /// Video height in pixels, for video tracks.
  final int? height;

  /// Frames per second, for video tracks, when known.
  final double? frameRate;

  /// RFC 6381 codec string, when known.
  final String? codecs;

  /// Audio channel count, for audio tracks.
  final int? channelCount;

  @override
  bool operator ==(Object other) =>
      other is PlayStackTrack &&
      other.id == id &&
      other.type == type &&
      other.isSelected == isSelected &&
      other.label == label &&
      other.language == language &&
      other.bitrate == bitrate &&
      other.width == width &&
      other.height == height &&
      other.frameRate == frameRate &&
      other.codecs == codecs &&
      other.channelCount == channelCount;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    isSelected,
    label,
    language,
    bitrate,
    width,
    height,
    frameRate,
    codecs,
    channelCount,
  );

  @override
  String toString() =>
      'PlayStackTrack(${type.name} $id${isSelected ? ', selected' : ''}'
      '${language == null ? '' : ', $language'}'
      '${label == null ? '' : ', "$label"'}'
      '${height == null ? '' : ', ${width}x$height'}'
      '${bitrate == null ? '' : ', ${bitrate}bps'})';
}

/// The highest video quality an adaptive stream (HLS, DASH) may switch to.
/// Streams come in several qualities; the engine picks one by bandwidth,
/// and this caps its choice. Null fields mean no limit.
///
/// ```dart
/// // At most 720p, or what fits the screen:
/// controller.setVideoQualityLimit(const PlayStackVideoQualityLimit(maxHeight: 720));
/// // At most 2 Mbit/s, for example on mobile data:
/// controller.setVideoQualityLimit(const PlayStackVideoQualityLimit(maxBitrate: 2000000));
/// // No limit:
/// controller.setVideoQualityLimit(PlayStackVideoQualityLimit.none);
/// ```
///
/// Lower caps save data and start faster; they have no effect on single
/// files such as MP4.
@immutable
class PlayStackVideoQualityLimit {
  /// Creates a cap. Leave a field null to not limit it.
  const PlayStackVideoQualityLimit({
    this.maxBitrate,
    this.maxWidth,
    this.maxHeight,
  }) : assert(maxBitrate == null || maxBitrate > 0),
       assert(maxWidth == null || maxWidth > 0),
       assert(maxHeight == null || maxHeight > 0);

  /// No cap: the engine may pick any quality.
  static const PlayStackVideoQualityLimit none = PlayStackVideoQualityLimit();

  /// Highest bitrate in bits per second, for example `2000000` for 2 Mbit/s.
  final int? maxBitrate;

  /// Widest video allowed, in pixels.
  final int? maxWidth;

  /// Tallest video allowed, in pixels, for example `720` for 720p.
  final int? maxHeight;

  /// Whether nothing is limited (every field is null).
  bool get isUnbounded =>
      maxBitrate == null && maxWidth == null && maxHeight == null;

  @override
  bool operator ==(Object other) =>
      other is PlayStackVideoQualityLimit &&
      other.maxBitrate == maxBitrate &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(maxBitrate, maxWidth, maxHeight);

  @override
  String toString() =>
      'PlayStackVideoQualityLimit(bitrate: $maxBitrate, '
      'size: ${maxWidth}x$maxHeight)';
}
