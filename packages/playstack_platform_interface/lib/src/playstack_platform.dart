import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'playstack_engine_config.dart';
import 'playstack_fullscreen.dart';
import 'playstack_exception.dart';
import 'playstack_native_player.dart';
import 'playstack_network_status.dart';
import 'playstack_platform_capabilities.dart';
import 'playstack_platform_event.dart';
import 'playstack_source.dart';
import 'playstack_track.dart';

/// The contract every PlayStack engine implements.
///
/// Engines manage native players identified by integer ids. They never push
/// per-frame or per-tick data to Dart: position is pulled with [getPosition]
/// and only state transitions are delivered through [events].
///
/// Platform implementations must extend this class rather than implement it,
/// so that new methods can be added without breaking them.
abstract class PlayStackPlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  PlayStackPlatform() : super(token: _token);

  static final Object _token = Object();

  static PlayStackPlatform _instance = _UnregisteredPlayStackPlatform();

  /// The engine used by PlayStack. Platform packages set this when they
  /// register.
  static PlayStackPlatform get instance => _instance;

  static set instance(PlayStackPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initializes the engine. Must be idempotent.
  Future<PlayStackPlatformCapabilities> initialize([
    PlayStackEngineConfig config = const PlayStackEngineConfig(),
  ]) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Allocates a native player and its render target.
  Future<PlayStackNativePlayerHandle> createPlayer(
    PlayStackNativePlayerOptions options,
  ) {
    throw UnimplementedError('createPlayer() has not been implemented.');
  }

  /// Releases a native player. Must succeed for unknown ids.
  Future<void> disposePlayer(int playerId) {
    throw UnimplementedError('disposePlayer() has not been implemented.');
  }

  /// Replaces the source of a player and starts preparing it. Preparation
  /// completes with a [PlayStackInitializedEvent] or a [PlayStackErrorEvent] carrying
  /// the same [generation].
  Future<void> setSource(int playerId, PlayStackSource source, int generation) {
    throw UnimplementedError('setSource() has not been implemented.');
  }

  /// Stops playback and detaches the current source so its decoder and
  /// buffers are released. The player stays alive for reuse. Must succeed
  /// for players without a source.
  Future<void> clearSource(int playerId) {
    throw UnimplementedError('clearSource() has not been implemented.');
  }

  /// Starts or resumes playback.
  Future<void> play(int playerId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  /// Pauses playback.
  Future<void> pause(int playerId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// Seeks to [position].
  Future<void> seekTo(int playerId, Duration position) {
    throw UnimplementedError('seekTo() has not been implemented.');
  }

  /// Sets whether playback restarts at the end.
  Future<void> setLooping(int playerId, bool looping) {
    throw UnimplementedError('setLooping() has not been implemented.');
  }

  /// Sets the volume in the range 0.0 to 1.0.
  Future<void> setVolume(int playerId, double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  /// Sets the playback rate; 1.0 is normal speed.
  Future<void> setPlaybackSpeed(int playerId, double speed) {
    throw UnimplementedError('setPlaybackSpeed() has not been implemented.');
  }

  /// Reads the current playback and buffered positions.
  Future<PlayStackPositionSnapshot> getPosition(int playerId) {
    throw UnimplementedError('getPosition() has not been implemented.');
  }

  /// Tracks of the current source. Empty before preparation.
  Future<List<PlayStackTrack>> getTracks(int playerId) {
    throw UnimplementedError('getTracks() has not been implemented.');
  }

  /// Selects [trackId] for [type]. A null [trackId] restores automatic
  /// selection for audio and video, and disables text tracks.
  Future<void> selectTrack(
    int playerId,
    PlayStackTrackType type,
    String? trackId,
  ) {
    throw UnimplementedError('selectTrack() has not been implemented.');
  }

  /// Caps adaptive video selection.
  Future<void> setVideoQualityLimit(
    int playerId,
    PlayStackVideoQualityLimit limit,
  ) {
    throw UnimplementedError(
      'setVideoQualityLimit() has not been implemented.',
    );
  }

  /// Stops forward buffering at [limit] while the player is not playing;
  /// null removes the limit. See
  /// [PlayStackPlatformCapabilities.supportsPreloadBufferLimit].
  Future<void> setPreloadBufferLimit(int playerId, Duration? limit) {
    throw UnimplementedError(
      'setPreloadBufferLimit() has not been implemented.',
    );
  }

  /// Current connectivity. See
  /// [PlayStackPlatformCapabilities.supportsNetworkStatus].
  Future<PlayStackNetworkStatus> getNetworkStatus() {
    throw UnimplementedError('getNetworkStatus() has not been implemented.');
  }

  /// Connectivity changes. Engines monitor the network only while this
  /// stream has a listener.
  Stream<PlayStackNetworkStatus> get networkStatusChanges {
    throw UnimplementedError('networkStatusChanges has not been implemented.');
  }

  /// Usage of the disk cache. See
  /// [PlayStackPlatformCapabilities.supportsDiskCache].
  Future<PlayStackCacheInfo> getCacheInfo() {
    throw UnimplementedError('getCacheInfo() has not been implemented.');
  }

  /// Deletes every cached entry that is not being read right now.
  Future<void> clearCache() {
    throw UnimplementedError('clearCache() has not been implemented.');
  }

  /// Deletes the cached data of the source with [cacheKey].
  Future<void> removeCached(String cacheKey) {
    throw UnimplementedError('removeCached() has not been implemented.');
  }

  /// Bytes of the source with [cacheKey] available in the cache.
  Future<int> getCachedBytes(String cacheKey) {
    throw UnimplementedError('getCachedBytes() has not been implemented.');
  }

  /// Hides system UI and applies the requested orientation policy (mobile),
  /// or requests browser fullscreen (web).
  Future<void> enterFullscreen(PlayStackFullscreenRequest request) {
    throw UnimplementedError('enterFullscreen() has not been implemented.');
  }

  /// Restores system UI and the application's orientation policy.
  Future<void> exitFullscreen(PlayStackFullscreenRestore restore) {
    throw UnimplementedError('exitFullscreen() has not been implemented.');
  }

  /// Fullscreen changes made outside PlayStack, for example the user pressing
  /// Escape in a browser. Mobile engines report none.
  Stream<bool> get fullscreenChanges {
    throw UnimplementedError('fullscreenChanges has not been implemented.');
  }

  /// Events of all native players of this engine.
  Stream<PlayStackPlatformEvent> get events {
    throw UnimplementedError('events has not been implemented.');
  }

  /// Builds the widget that displays the frames of [playerId].
  Widget buildView(int playerId) {
    throw UnimplementedError('buildView() has not been implemented.');
  }
}

/// Fallback used when no platform package registered an engine, for example
/// in unit tests or on unsupported platforms.
class _UnregisteredPlayStackPlatform extends PlayStackPlatform {
  Never _fail() => throw const PlayStackException(
    PlayStackErrorCode.unsupportedPlatform,
    'No PlayStack engine is registered for this platform. PlayStack supports '
    'Android, iOS and web.',
  );

  @override
  Future<PlayStackPlatformCapabilities> initialize([
    PlayStackEngineConfig config = const PlayStackEngineConfig(),
  ]) async => _fail();

  @override
  Future<PlayStackNativePlayerHandle> createPlayer(
    PlayStackNativePlayerOptions options,
  ) async => _fail();

  @override
  Future<void> disposePlayer(int playerId) async {}

  @override
  Stream<PlayStackPlatformEvent> get events => const Stream.empty();

  @override
  Stream<PlayStackNetworkStatus> get networkStatusChanges =>
      const Stream.empty();

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}
