/// Chromecast for PlayStack.
///
/// ```dart
/// // A button for your controls: lists Cast devices, connects, shows the
/// // state.
/// PlayStackCastButton(onConnected: () => PlayStackCast.instance.castController(
///   page.controller,
///   info: PlayStackMediaInfo(title: episode.title, artworkUrl: episode.poster),
/// ))
/// ```
///
/// See [PlayStackCast] for the setup and the remote controls.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:playstack/playstack.dart';

/// Where the connection to a Cast device stands.
enum PlayStackCastState {
  /// Cast is not available here: web, no Google Play services, or the
  /// platform setup is missing.
  unavailable,

  /// No Cast device was found on the network.
  noDevices,

  /// Devices exist; none is connected.
  notConnected,

  /// Connecting to a device.
  connecting,

  /// Connected; media can be loaded.
  connected,
}

/// What a Cast device is doing.
@immutable
class PlayStackCastPlayback {
  /// Creates a playback snapshot.
  const PlayStackCastPlayback({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration,
    this.hasMedia = false,
  });

  /// Whether it plays.
  final bool isPlaying;

  /// Whether it is loading.
  final bool isBuffering;

  /// Where playback is.
  final Duration position;

  /// The length of the media, when known.
  final Duration? duration;

  /// Whether media is loaded.
  final bool hasMedia;
}

/// Plays videos on Chromecast and other Google Cast devices.
///
/// Setup:
///
/// * Android: nothing to declare; the plugin brings the Cast options. A
///   device needs Google Play services.
/// * iOS: add to `Info.plist` the local network description and the Bonjour
///   services:
///
///   ```xml
///   <key>NSLocalNetworkUsageDescription</key>
///   <string>Finds Cast devices on your network.</string>
///   <key>NSBonjourServices</key>
///   <array>
///     <string>_googlecast._tcp</string>
///     <string>_CC1AD845._googlecast._tcp</string>
///   </array>
///   ```
///
/// The default media receiver (`CC1AD845`) plays MP4, HLS and DASH. Use
/// your own receiver with [setReceiverApplicationId] before anything else.
///
/// While casting, the device plays and the phone is the remote: [play],
/// [pause], [seekTo], [playback]. [castController] moves a playing
/// PlayStack video to the device at its current position and pauses it
/// locally; [stopCasting] brings it back.
class PlayStackCast {
  PlayStackCast._() {
    _events.receiveBroadcastStream().listen(_onEvent, onError: (Object _) {});
    unawaited(_refresh());
  }

  /// The Cast connection of the app.
  static final PlayStackCast instance = PlayStackCast._();

  static const MethodChannel _channel = MethodChannel('dev.playstack/cast');
  static const EventChannel _events = EventChannel('dev.playstack/cast/events');

  final ValueNotifier<PlayStackCastState> _state =
      ValueNotifier<PlayStackCastState>(PlayStackCastState.unavailable);
  final ValueNotifier<PlayStackCastPlayback> _playback =
      ValueNotifier<PlayStackCastPlayback>(const PlayStackCastPlayback());
  final ValueNotifier<String?> _deviceName = ValueNotifier<String?>(null);
  PlayStackPlayerController? _local;

  /// The connection state.
  ValueListenable<PlayStackCastState> get state => _state;

  /// What the device plays, updated about once a second.
  ValueListenable<PlayStackCastPlayback> get playback => _playback;

  /// The name of the connected device, such as "Living Room TV".
  ValueListenable<String?> get deviceName => _deviceName;

  /// Whether a device is connected.
  bool get isConnected => _state.value == PlayStackCastState.connected;

  /// The local video sent with [castController], or null.
  PlayStackPlayerController? get castingController => _local;

  /// Uses your own Cast receiver app. Call it before anything else on the
  /// instance (Android reads it when Cast starts).
  static Future<void> setReceiverApplicationId(String id) =>
      _channel.invokeMethod('setReceiverApplicationId', id);

  /// Opens the system's device list (or, when connected, the device's
  /// controls with a disconnect button).
  Future<void> showDevicePicker() => _call('showDevicePicker');

  /// Plays [source] on the connected device from [position].
  ///
  /// Only network sources can be cast; headers are not sent (the device
  /// downloads the video itself).
  Future<void> load(
    PlayStackSource source, {
    PlayStackMediaInfo? info,
    Duration position = Duration.zero,
    bool autoplay = true,
  }) {
    if (source is! PlayStackNetworkSource) {
      throw const PlayStackException(
        PlayStackErrorCode.invalidSource,
        'Only network sources can be cast.',
      );
    }
    final format = source.resolvedFormat;
    return _call('load', {
      'url': source.url,
      'contentType':
          source.mimeType ??
          switch (format) {
            PlayStackVideoFormat.hls => 'application/x-mpegURL',
            PlayStackVideoFormat.dash => 'application/dash+xml',
            _ => 'video/mp4',
          },
      'title': info?.title,
      'subtitle': info?.artist,
      'artworkUrl': info?.artworkUrl,
      'positionMs': position.inMilliseconds,
      'autoplay': autoplay,
    });
  }

  /// Moves [controller]'s video to the connected device at its current
  /// position and pauses it locally. [stopCasting] (or a disconnect)
  /// resumes it where the device stopped.
  Future<void> castController(
    PlayStackPlayerController controller, {
    PlayStackMediaInfo? info,
  }) async {
    final position = (await controller.getPosition()).position;
    await controller.pause();
    _local = controller;
    await load(controller.source, info: info, position: position);
  }

  /// Ends remote playback and, after [castController], continues the video
  /// on the phone where the device was.
  Future<void> stopCasting() async {
    final local = _local;
    final position = _playback.value.position;
    _local = null;
    await _call('stop');
    if (local != null && !local.isDisposed) {
      if (position > Duration.zero) await local.seekTo(position);
      await local.play();
    }
  }

  /// Resumes remote playback.
  Future<void> play() => _call('play');

  /// Pauses remote playback.
  Future<void> pause() => _call('pause');

  /// Moves remote playback to [position].
  Future<void> seekTo(Duration position) =>
      _call('seekTo', position.inMilliseconds);

  /// Sets the device volume, 0.0 to 1.0.
  Future<void> setVolume(double volume) => _call('setVolume', volume);

  /// Disconnects from the device.
  Future<void> disconnect() async {
    await stopCasting();
    await _call('disconnect');
  }

  Future<void> _call(String method, [Object? argument]) async {
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on MissingPluginException {
      // Not available on this platform.
    } on PlatformException catch (error) {
      throw PlayStackException.fromPlatformException(error);
    }
  }

  Future<void> _refresh() async {
    try {
      final state = await _channel.invokeMethod<String>('getState');
      if (state != null) _setState(state);
    } on MissingPluginException {
      _state.value = PlayStackCastState.unavailable;
    } on PlatformException {
      _state.value = PlayStackCastState.unavailable;
    }
  }

  void _setState(String name) {
    final next = PlayStackCastState.values.firstWhere(
      (state) => state.name == name,
      orElse: () => PlayStackCastState.unavailable,
    );
    final wasConnected = isConnected;
    _state.value = next;
    // The device went away: the phone continues.
    if (wasConnected && next != PlayStackCastState.connected) {
      final local = _local;
      final position = _playback.value.position;
      _local = null;
      if (local != null && !local.isDisposed) {
        unawaited(
          () async {
            if (position > Duration.zero) await local.seekTo(position);
            await local.play();
          }().catchError((Object _) {}),
        );
      }
    }
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'state':
        _deviceName.value = event['device'] as String?;
        _setState(event['state'] as String? ?? 'unavailable');
      case 'playback':
        final duration = (event['durationMs'] as num?)?.toInt();
        _playback.value = PlayStackCastPlayback(
          isPlaying: event['playing'] == true,
          isBuffering: event['buffering'] == true,
          position: Duration(
            milliseconds: (event['positionMs'] as num?)?.toInt() ?? 0,
          ),
          duration: duration == null || duration <= 0
              ? null
              : Duration(milliseconds: duration),
          hasMedia: event['hasMedia'] == true,
        );
    }
  }
}

/// A Cast button: hidden while no device is found (or Cast is not
/// available), grey while disconnected, filled while connected. A tap
/// opens the device list.
class PlayStackCastButton extends StatelessWidget {
  /// Creates a Cast button.
  const PlayStackCastButton({
    super.key,
    this.color = const Color(0xFFFFFFFF),
    this.activeColor = const Color(0xFF2196F3),
    this.size = 24,
    this.onConnected,
    this.showWhenNoDevices = false,
  });

  /// Icon color.
  final Color color;

  /// Icon color while connected.
  final Color activeColor;

  /// Icon size.
  final double size;

  /// Called when a connection is made from this button, for example to
  /// [PlayStackCast.castController] the video in view.
  final VoidCallback? onConnected;

  /// Whether the button shows (disabled) when no device is found.
  final bool showWhenNoDevices;

  @override
  Widget build(BuildContext context) {
    final cast = PlayStackCast.instance;
    return ValueListenableBuilder<PlayStackCastState>(
      valueListenable: cast.state,
      builder: (context, state, _) {
        if (state == PlayStackCastState.unavailable ||
            (state == PlayStackCastState.noDevices && !showWhenNoDevices)) {
          return const SizedBox.shrink();
        }
        final connected = state == PlayStackCastState.connected;
        return IconButton(
          tooltip: connected ? 'Casting' : 'Cast',
          iconSize: size,
          onPressed: state == PlayStackCastState.noDevices
              ? null
              : () async {
                  final wasConnected = cast.isConnected;
                  await cast.showDevicePicker();
                  if (wasConnected || onConnected == null) return;
                  // Wait for the user to pick a device.
                  void listener() {
                    if (cast.state.value == PlayStackCastState.connected) {
                      cast.state.removeListener(listener);
                      onConnected!();
                    } else if (cast.state.value ==
                        PlayStackCastState.notConnected) {
                      cast.state.removeListener(listener);
                    }
                  }

                  cast.state.addListener(listener);
                },
          icon: Icon(
            connected
                ? Icons.cast_connected_rounded
                : state == PlayStackCastState.connecting
                ? Icons.cast_rounded
                : Icons.cast_rounded,
            color: connected ? activeColor : color,
          ),
        );
      },
    );
  }
}
