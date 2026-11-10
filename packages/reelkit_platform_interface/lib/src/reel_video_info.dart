import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

/// Intrinsic properties of a prepared video.
@immutable
class ReelVideoInfo {
  const ReelVideoInfo({
    required this.width,
    required this.height,
    this.duration,
    this.rotationDegrees = 0,
    this.pixelAspectRatio = 1.0,
    this.isLive = false,
    this.frameRate,
    this.bitrate,
    this.videoCodec,
  });

  /// Width of the frames delivered to the render target, in pixels.
  final int width;

  /// Height of the frames delivered to the render target, in pixels.
  final int height;

  /// Total duration, or null when unknown (for example live streams).
  final Duration? duration;

  /// Clockwise rotation, in degrees, that must still be applied to the
  /// rendered frames to show the video upright. Always a multiple of 90.
  final int rotationDegrees;

  /// Width-to-height ratio of a single pixel. 1.0 for square pixels.
  final double pixelAspectRatio;

  /// Whether the source is a live stream.
  final bool isLive;

  /// Nominal frames per second, when known.
  final double? frameRate;

  /// Bitrate of the selected video in bits per second, when known.
  final int? bitrate;

  /// Video codec as an RFC 6381 string (for example `avc1.42C01E`) or a
  /// FourCC (for example `avc1`), when known.
  final String? videoCodec;

  /// Whether the video has a known, non-zero size.
  bool get hasSize => width > 0 && height > 0;

  bool get _isQuarterTurned => (rotationDegrees ~/ 90).isOdd;

  /// Size at which the upright video should be displayed, with pixel aspect
  /// ratio and rotation applied.
  Size get displaySize {
    final scaledWidth = width * pixelAspectRatio;
    return _isQuarterTurned
        ? Size(height.toDouble(), scaledWidth)
        : Size(scaledWidth, height.toDouble());
  }

  /// Display aspect ratio, or 1.0 when the size is unknown.
  double get aspectRatio {
    if (!hasSize) return 1.0;
    final size = displaySize;
    return size.width / size.height;
  }

  ReelVideoInfo copyWith({
    int? width,
    int? height,
    Duration? duration,
    int? rotationDegrees,
    double? pixelAspectRatio,
    bool? isLive,
    double? frameRate,
    int? bitrate,
    String? videoCodec,
  }) {
    return ReelVideoInfo(
      width: width ?? this.width,
      height: height ?? this.height,
      duration: duration ?? this.duration,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      pixelAspectRatio: pixelAspectRatio ?? this.pixelAspectRatio,
      isLive: isLive ?? this.isLive,
      frameRate: frameRate ?? this.frameRate,
      bitrate: bitrate ?? this.bitrate,
      videoCodec: videoCodec ?? this.videoCodec,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReelVideoInfo &&
      other.width == width &&
      other.height == height &&
      other.duration == duration &&
      other.rotationDegrees == rotationDegrees &&
      other.pixelAspectRatio == pixelAspectRatio &&
      other.isLive == isLive &&
      other.frameRate == frameRate &&
      other.bitrate == bitrate &&
      other.videoCodec == videoCodec;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    duration,
    rotationDegrees,
    pixelAspectRatio,
    isLive,
    frameRate,
    bitrate,
    videoCodec,
  );

  @override
  String toString() =>
      'ReelVideoInfo(${width}x$height, duration: $duration, '
      'rotation: $rotationDegrees, par: $pixelAspectRatio'
      '${isLive ? ', live' : ''}'
      '${videoCodec == null ? '' : ', $videoCodec'})';
}
