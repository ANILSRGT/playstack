import 'package:flutter/foundation.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

/// Track list, subtitle text and the application's track preferences for
/// one controller.
///
/// Preferences survive the controller losing and regaining a native player
/// (they are re-applied after every preparation) and are cleared when the
/// source changes, because track ids are only stable for one source.
@internal
class ReelTrackState {
  ReelTrackState(this._platform);

  final ReelKitPlatform Function() _platform;

  final ValueNotifier<List<ReelTrack>> tracks = ValueNotifier<List<ReelTrack>>(
    const <ReelTrack>[],
  );
  final ValueNotifier<List<String>> subtitles = ValueNotifier<List<String>>(
    const <String>[],
  );

  /// Requested track per type. A present key with a null value means
  /// automatic (audio, video) or disabled (text).
  final Map<ReelTrackType, String?> _preferences = <ReelTrackType, String?>{};
  ReelVideoQualityLimit _qualityLimit = ReelVideoQualityLimit.none;
  int _refreshToken = 0;

  ReelVideoQualityLimit get qualityLimit => _qualityLimit;

  /// Forgets per-source preferences. The quality limit is kept: it is a
  /// preference about the viewer's conditions, not about one source.
  void resetForNewSource() {
    _preferences.clear();
    clear();
  }

  /// Clears what the current native player reported.
  void clear() {
    _refreshToken++;
    if (tracks.value.isNotEmpty) tracks.value = const <ReelTrack>[];
    if (subtitles.value.isNotEmpty) subtitles.value = const <String>[];
  }

  Future<void> select(
    int? playerId,
    ReelTrackType type,
    String? trackId,
  ) async {
    _preferences[type] = trackId;
    if (type == ReelTrackType.text && trackId == null) {
      // Disabling subtitles must clear the text immediately.
      if (subtitles.value.isNotEmpty) subtitles.value = const <String>[];
    }
    if (playerId == null) return;
    await _platform().selectTrack(playerId, type, trackId);
  }

  Future<void> setQualityLimit(
    int? playerId,
    ReelVideoQualityLimit limit,
  ) async {
    _qualityLimit = limit;
    if (playerId == null) return;
    await _platform().setVideoQualityLimit(playerId, limit);
  }

  /// Records the limit without sending it; the controller applies it as a
  /// player setting.
  void storeQualityLimit(ReelVideoQualityLimit limit) => _qualityLimit = limit;

  /// Re-applies stored preferences to a freshly prepared player. Features
  /// the engine does not support are skipped; their direct calls already
  /// report `notImplemented` to the application.
  Future<void> applyPreferences(
    int playerId, {
    bool includeQualityLimit = true,
  }) async {
    final platform = _platform();
    if (includeQualityLimit && !_qualityLimit.isUnbounded) {
      await _ignoreUnsupported(
        () => platform.setVideoQualityLimit(playerId, _qualityLimit),
      );
    }
    for (final entry in _preferences.entries) {
      await _ignoreUnsupported(
        () => platform.selectTrack(playerId, entry.key, entry.value),
      );
    }
  }

  /// Reads the track list from the engine. Results that arrive after the
  /// source or player changed are dropped.
  Future<void> refresh(int playerId, bool Function() isCurrent) async {
    final token = ++_refreshToken;
    List<ReelTrack> list;
    try {
      list = await _platform().getTracks(playerId);
    } on ReelKitException catch (error) {
      if (error.code != ReelKitErrorCode.notImplemented &&
          error.code != ReelKitErrorCode.playerNotFound) {
        rethrow;
      }
      list = const <ReelTrack>[];
    } on UnimplementedError {
      // Engine predates track support.
      list = const <ReelTrack>[];
    }
    if (token != _refreshToken || !isCurrent()) return;
    if (!listEquals(list, tracks.value)) {
      tracks.value = List<ReelTrack>.unmodifiable(list);
    }
  }

  void onCues(List<String> texts) {
    if (_preferences[ReelTrackType.text] == null &&
        _preferences.containsKey(ReelTrackType.text)) {
      return;
    }
    if (!listEquals(texts, subtitles.value)) subtitles.value = texts;
  }

  void dispose() {
    tracks.dispose();
    subtitles.dispose();
  }

  static Future<void> _ignoreUnsupported(Future<void> Function() call) async {
    try {
      await call();
    } on ReelKitException catch (error) {
      if (error.code != ReelKitErrorCode.notImplemented) rethrow;
    } on UnimplementedError {
      // Engine predates track support.
    }
  }
}
