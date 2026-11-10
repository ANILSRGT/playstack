import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'reel_kit_exception.dart';
import 'reel_native_player.dart';
import 'reel_platform_capabilities.dart';
import 'reel_platform_event.dart';
import 'reel_source.dart';

/// The contract every ReelKit engine implements.
///
/// Engines manage native players identified by integer ids. They never push
/// per-frame or per-tick data to Dart: position is pulled with [getPosition]
/// and only state transitions are delivered through [events].
///
/// Platform implementations must extend this class rather than implement it,
/// so that new methods can be added without breaking them.
abstract class ReelKitPlatform extends PlatformInterface {
  ReelKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static ReelKitPlatform _instance = _UnregisteredReelKitPlatform();

  /// The engine used by ReelKit. Platform packages set this when they
  /// register.
  static ReelKitPlatform get instance => _instance;

  static set instance(ReelKitPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initializes the engine. Must be idempotent.
  Future<ReelPlatformCapabilities> initialize() {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Allocates a native player and its render target.
  Future<ReelNativePlayerHandle> createPlayer(ReelNativePlayerOptions options) {
    throw UnimplementedError('createPlayer() has not been implemented.');
  }

  /// Releases a native player. Must succeed for unknown ids.
  Future<void> disposePlayer(int playerId) {
    throw UnimplementedError('disposePlayer() has not been implemented.');
  }

  /// Replaces the source of a player and starts preparing it. Preparation
  /// completes with a [ReelInitializedEvent] or a [ReelErrorEvent] carrying
  /// the same [generation].
  Future<void> setSource(int playerId, ReelSource source, int generation) {
    throw UnimplementedError('setSource() has not been implemented.');
  }

  /// Stops playback and detaches the current source so its decoder and
  /// buffers are released. The player stays alive for reuse. Must succeed
  /// for players without a source.
  Future<void> clearSource(int playerId) {
    throw UnimplementedError('clearSource() has not been implemented.');
  }

  Future<void> play(int playerId) {
    throw UnimplementedError('play() has not been implemented.');
  }

  Future<void> pause(int playerId) {
    throw UnimplementedError('pause() has not been implemented.');
  }

  Future<void> seekTo(int playerId, Duration position) {
    throw UnimplementedError('seekTo() has not been implemented.');
  }

  Future<void> setLooping(int playerId, bool looping) {
    throw UnimplementedError('setLooping() has not been implemented.');
  }

  /// Sets the volume in the range 0.0 to 1.0.
  Future<void> setVolume(int playerId, double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  Future<void> setPlaybackSpeed(int playerId, double speed) {
    throw UnimplementedError('setPlaybackSpeed() has not been implemented.');
  }

  Future<ReelPositionSnapshot> getPosition(int playerId) {
    throw UnimplementedError('getPosition() has not been implemented.');
  }

  /// Events of all native players of this engine.
  Stream<ReelPlatformEvent> get events {
    throw UnimplementedError('events has not been implemented.');
  }

  /// Builds the widget that displays the frames of [playerId].
  Widget buildView(int playerId) {
    throw UnimplementedError('buildView() has not been implemented.');
  }
}

/// Fallback used when no platform package registered an engine, for example
/// in unit tests or on unsupported platforms.
class _UnregisteredReelKitPlatform extends ReelKitPlatform {
  Never _fail() => throw const ReelKitException(
    ReelKitErrorCode.unsupportedPlatform,
    'No ReelKit engine is registered for this platform. ReelKit supports '
    'Android, iOS and web.',
  );

  @override
  Future<ReelPlatformCapabilities> initialize() async => _fail();

  @override
  Future<ReelNativePlayerHandle> createPlayer(
    ReelNativePlayerOptions options,
  ) async => _fail();

  @override
  Future<void> disposePlayer(int playerId) async {}

  @override
  Stream<ReelPlatformEvent> get events => const Stream.empty();

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
}
