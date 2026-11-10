import 'package:flutter/foundation.dart';

/// Kind of media track.
enum ReelTrackType {
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
class ReelTrack {
  /// Creates a track description. Engines create these.
  const ReelTrack({
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
  final ReelTrackType type;

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
      other is ReelTrack &&
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
      'ReelTrack(${type.name} $id${isSelected ? ', selected' : ''}'
      '${language == null ? '' : ', $language'}'
      '${label == null ? '' : ', "$label"'}'
      '${height == null ? '' : ', ${width}x$height'}'
      '${bitrate == null ? '' : ', ${bitrate}bps'})';
}

/// Upper bounds for adaptive video selection. Null fields are unbounded.
@immutable
class ReelVideoQualityLimit {
  /// Creates a limit; null fields are unbounded.
  const ReelVideoQualityLimit({this.maxBitrate, this.maxWidth, this.maxHeight})
    : assert(maxBitrate == null || maxBitrate > 0),
      assert(maxWidth == null || maxWidth > 0),
      assert(maxHeight == null || maxHeight > 0);

  /// No limit.
  static const ReelVideoQualityLimit none = ReelVideoQualityLimit();

  /// Bits per second.
  final int? maxBitrate;

  /// Maximum video width in pixels.
  final int? maxWidth;

  /// Maximum video height in pixels.
  final int? maxHeight;

  /// Whether no field is set.
  bool get isUnbounded =>
      maxBitrate == null && maxWidth == null && maxHeight == null;

  @override
  bool operator ==(Object other) =>
      other is ReelVideoQualityLimit &&
      other.maxBitrate == maxBitrate &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(maxBitrate, maxWidth, maxHeight);

  @override
  String toString() =>
      'ReelVideoQualityLimit(bitrate: $maxBitrate, '
      'size: ${maxWidth}x$maxHeight)';
}
