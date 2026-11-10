import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the engine applies when entering fullscreen.
@immutable
class ReelFullscreenRequest {
  /// Creates a fullscreen request.
  const ReelFullscreenRequest({
    this.orientations,
    this.systemUiMode = SystemUiMode.immersiveSticky,
  });

  /// Orientations to allow while fullscreen; null keeps the current
  /// orientation policy untouched.
  final List<DeviceOrientation>? orientations;

  /// System bars while fullscreen (Android and iOS).
  final SystemUiMode systemUiMode;
}

/// What the engine restores when leaving fullscreen.
@immutable
class ReelFullscreenRestore {
  /// Creates a restore description.
  const ReelFullscreenRestore({
    required this.orientations,
    required this.systemUiMode,
    this.overlays,
    this.previousOrientations,
    this.changedOrientations = false,
  });

  /// The application's orientation policy; empty means every orientation
  /// the app declares.
  final List<DeviceOrientation> orientations;

  /// System bars after fullscreen.
  final SystemUiMode systemUiMode;

  /// Overlays for [SystemUiMode.manual].
  final List<SystemUiOverlay>? overlays;

  /// The orientation(s) the app was shown in before fullscreen, for example
  /// `[portraitUp]`. Used to rotate back before the policy is restored,
  /// because unlocking alone does not rotate the interface back on every
  /// platform.
  final List<DeviceOrientation>? previousOrientations;

  /// Whether fullscreen changed the orientation policy (otherwise the
  /// policy is not touched on exit either).
  final bool changedOrientations;
}

/// Fullscreen through `SystemChrome`, shared by the Android and iOS engines.
///
/// Flutter cannot read the current preferred orientations, so the policy to
/// restore comes from the application ([ReelFullscreenRestore]).
mixin SystemChromeFullscreen {
  /// Hides the system bars and applies the requested orientations.
  Future<void> enterFullscreen(ReelFullscreenRequest request) async {
    await SystemChrome.setEnabledSystemUIMode(request.systemUiMode);
    final orientations = request.orientations;
    if (orientations != null) {
      await SystemChrome.setPreferredOrientations(orientations);
    }
  }

  /// Restores the system bars, rotates back and restores the orientation
  /// policy.
  Future<void> exitFullscreen(ReelFullscreenRestore restore) async {
    await SystemChrome.setEnabledSystemUIMode(
      restore.systemUiMode,
      overlays: restore.overlays,
    );
    if (!restore.changedOrientations) return;
    final previous = restore.previousOrientations;
    final allowed = restore.orientations;
    if (previous != null &&
        previous.isNotEmpty &&
        (allowed.isEmpty || previous.any(allowed.contains))) {
      // Rotate back to where the user was, then unlock to the app policy.
      await SystemChrome.setPreferredOrientations(
        allowed.isEmpty ? previous : previous.where(allowed.contains).toList(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await SystemChrome.setPreferredOrientations(allowed);
  }

  /// Fullscreen changes made outside ReelKit; mobile platforms have none.
  Stream<bool> get fullscreenChanges => const Stream<bool>.empty();
}
