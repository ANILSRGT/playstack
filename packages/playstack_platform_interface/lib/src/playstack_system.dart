import 'package:flutter/foundation.dart';

/// What the system's media controls (lock screen, notification, headphones,
/// car) show about the playing video.
@immutable
class PlayStackMediaInfo {
  /// Creates media details. Every field is optional.
  const PlayStackMediaInfo({
    this.title,
    this.artist,
    this.album,
    this.artworkUrl,
  });

  /// The title, for example the episode's name.
  final String? title;

  /// The second line, for example the series or the author.
  final String? artist;

  /// A third line where the platform shows one, for example the season.
  final String? album;

  /// An image URL (HTTP or HTTPS) shown next to the controls, usually the
  /// poster.
  final String? artworkUrl;

  @override
  bool operator ==(Object other) =>
      other is PlayStackMediaInfo &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.artworkUrl == artworkUrl;

  @override
  int get hashCode => Object.hash(title, artist, album, artworkUrl);
}

/// What a system event asks for; see [PlayStackSystemEvent].
enum PlayStackSystemEventType {
  /// Play, from the lock screen, notification, headphones or car.
  play,

  /// Pause, from the same places.
  pause,

  /// Move to [PlayStackSystemEvent.position].
  seek,

  /// Skip to the next item.
  next,

  /// Skip to the previous item.
  previous,

  /// Picture-in-Picture started.
  pictureInPictureStarted,

  /// Picture-in-Picture ended.
  pictureInPictureStopped,
}

/// A command from the system's media controls, or a Picture-in-Picture
/// change, reported by the engine.
@immutable
class PlayStackSystemEvent {
  /// Creates an event.
  const PlayStackSystemEvent(this.type, {this.position});

  /// What happened.
  final PlayStackSystemEventType type;

  /// Where to move, for [PlayStackSystemEventType.seek].
  final Duration? position;

  @override
  bool operator ==(Object other) =>
      other is PlayStackSystemEvent &&
      other.type == type &&
      other.position == position;

  @override
  int get hashCode => Object.hash(type, position);

  @override
  String toString() => 'PlayStackSystemEvent($type, $position)';
}
