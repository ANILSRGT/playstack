import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

/// A picture quality the user can choose for a video: one rendition of an
/// adaptive stream, such as 720p.
///
/// Read the choices from `PlayStackPlayerController.videoQualities` and pick
/// one with `setVideoQuality`; [PlayStackSettingsSheet] lists them.
@immutable
class PlayStackVideoQuality {
  /// Creates a quality of [width] x [height] pixels.
  const PlayStackVideoQuality({
    required this.width,
    required this.height,
    this.bitrate,
    this.trackId,
  });

  /// Width of the rendition in pixels.
  final int width;

  /// Height of the rendition in pixels.
  final int height;

  /// Peak bitrate of the rendition in bits per second, when known.
  final int? bitrate;

  /// The video track of this rendition, where the engine can select one
  /// (Android). Null for qualities made by hand.
  final String? trackId;

  /// The short side in pixels: 720 for 1280x720 and for 720x1280.
  int get lines => math.min(width, height);

  /// `720p` style.
  String get label => '${lines}p';

  /// The cap that plays this rendition, or a lower one when the network
  /// cannot keep up.
  PlayStackVideoQualityLimit get limit => PlayStackVideoQualityLimit(
    maxBitrate: bitrate,
    maxWidth: width,
    maxHeight: height,
  );

  /// The qualities among [tracks]: one per [lines], highest first. Fewer
  /// than two means there is nothing to choose.
  static List<PlayStackVideoQuality> fromTracks(List<PlayStackTrack> tracks) {
    final byLines = <int, PlayStackVideoQuality>{};
    for (final track in tracks) {
      final width = track.width;
      final height = track.height;
      if (track.type != PlayStackTrackType.video ||
          width == null ||
          height == null ||
          width <= 0 ||
          height <= 0) {
        continue;
      }
      final quality = PlayStackVideoQuality(
        width: width,
        height: height,
        bitrate: track.bitrate,
        trackId: track.id,
      );
      final known = byLines[quality.lines];
      // The best rendition of each size.
      if (known == null || (quality.bitrate ?? 0) > (known.bitrate ?? 0)) {
        byLines[quality.lines] = quality;
      }
    }
    return byLines.values.toList()..sort((a, b) => b.lines - a.lines);
  }

  @override
  bool operator ==(Object other) =>
      other is PlayStackVideoQuality &&
      other.width == width &&
      other.height == height &&
      other.bitrate == bitrate;

  @override
  int get hashCode => Object.hash(width, height, bitrate);

  @override
  String toString() => 'PlayStackVideoQuality($label, ${width}x$height)';
}
