import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_cast/playstack_cast.dart';

import '../catalog.dart';
import 'drama_data.dart';
import 'offline.dart';
import 'series_page.dart';
import '../loading_animation.dart';

/// Plays a series as a vertical feed of episodes.
///
/// * opens at the tapped episode, where the user stopped
///   (`initialIndex`, `startPosition`);
/// * moves to the next episode when one ends (`autoAdvance`);
/// * saves where the user stopped (`onItemViewed`);
/// * jumps to any episode from the episode list (`jumpToItem`);
/// * hides the controls in fullscreen until the screen is tapped
///   (`cinemaMode`);
/// * keeps playing on the lock screen and in the notification, with skip
///   buttons between episodes (`mediaInfo`);
/// * keeps playing in a small window when the user leaves the app
///   (`pictureInPicture`);
/// * continues each episode where it was left, skips the intro and offers
///   the next episode with a countdown (`series`);
/// * plays a pre-roll ad before even episodes for users without premium
///   (`ads`, a sample VAST tag), at most once a day per episode
///   (`shouldShow` with [PlayStackShowRules]);
/// * shows a banner in a strip below the video, which shrinks for it, at
///   most once a minute (a cue with `PlayStackSlotLayout.below`);
/// * double tap to jump 10 s, drag for brightness and volume in fullscreen;
/// * sleep timer, audio only, debug panel, Chromecast and AirPlay in the
///   menu.
class EpisodePlayerPage extends StatefulWidget {
  const EpisodePlayerPage({
    super.key,
    required this.series,
    required this.episode,
  });

  final Series series;
  final Episode episode;

  @override
  State<EpisodePlayerPage> createState() => _EpisodePlayerPageState();
}

/// When ads and banners were shown, for the rules below. In memory for the
/// demo; a real app keeps it in a file (`PlayStackShowStore.file`), in
/// SharedPreferences (`PlayStackShowStore.custom`), or asks its server in
/// `shouldShow` instead.
final _shows = PlayStackShowRules();

class _EpisodePlayerPageState extends State<EpisodePlayerPage> {
  final _view = PlayStackFeedViewController();
  bool _debugInfo = false;

  /// Google's sample VAST tag: one linear ad, skippable after 5 seconds.
  static const _sampleVast =
      'https://pubads.g.doubleclick.net/gampad/ads?iu=/21775744923/external/'
      'single_ad_samples&sz=640x480&cust_params=sample_ct%3Dlinear&ciu_szs='
      '300x250%2C728x90&gdfp_req=1&output=vast&unviewed_position_start=1&'
      'env=vp&impl=s&correlator=[CACHEBUSTING]';

  @override
  void initState() {
    super.initState();
    // PlayStack does not open URLs itself; a real app would use
    // url_launcher here.
    PlayStackAds.onClick = (ad, url) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Advertiser page: $url')));
    };
  }

  Future<void> _showMenu(PlayStackFeedPage<Episode> page) async {
    final manager = _view.manager;
    if (manager == null) return;
    _view.pause();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _PlayerMenu(
        controller: page.controller,
        sleepTimer: manager.sleepTimer,
        debugInfo: _debugInfo,
        onDebugInfo: (value) => setState(() => _debugInfo = value),
      ),
    );
    _view.resume();
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  Future<void> _showEpisodes(Episode current) async {
    _view.pause();
    final picked = await showModalBottomSheet<Episode>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _EpisodeSheet(series: widget.series, current: current),
    );
    _view.resume();
    if (picked != null && picked != current) _view.jumpToItem(picked);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return Scaffold(
      // Rebuilt when an episode is unlocked: isLocked is asked again and the
      // episode starts playing.
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: watchProgress,
          builder: (context, _) => PlayStackFeedView<Episode>(
            items: series.episodes,
            source: (episode) => episode.source,
            posterUrl: (episode) => episode.poster,
            itemId: (episode) => episode.id,
            controller: _view,
            initialIndex: series.episodes.indexOf(widget.episode),
            isLocked: watchProgress.isLocked,
            lockedBuilder: (context, episode, isActive) =>
                _Paywall(series: series, episode: episode),
            autoAdvance: true,
            series: PlayStackSeries(
              progress: episodeProgress,
              skipMarkers: (episode) => [
                PlayStackSkipMarker.intro(
                  start: const Duration(milliseconds: 500),
                  end: episode.introEnd,
                ),
              ],
              nextUp: const PlayStackNextUp(
                countdown: Duration(seconds: 5),
                showBefore: Duration(seconds: 8),
              ),
              nextUpLabel: (next) => 'Episode ${next.number}: ${next.title}',
            ),
            ads: PlayStackFeedAds(
              breaks: (episode) => [
                if (!offline.isPremium && episode.number.isEven)
                  PlayStackAdBreak.preRoll(
                    PlayStackAdSource.vast(_sampleVast),
                    id: 'pre',
                  ),
              ],
              // Each episode's pre-roll at most once a day: coming back to
              // an episode does not show it again.
              shouldShow: (episode, adBreak) => _shows.allows(
                '${episode.id}/${adBreak.id}',
                const PlayStackShowRule.every(Duration(days: 1)),
              ),
              onEvent: (episode, adBreak, event) {
                debugPrint(
                  '[ads] ${episode.id} ${adBreak.id} ${event.type.name}',
                );
                if (event.type == PlayStackAdBreakEventType.started) {
                  unawaited(_shows.record('${episode.id}/${adBreak.id}'));
                }
              },
            ),
            // The app's own moments. A poll card a few seconds into odd
            // episodes, and an interstitial between episodes for free
            // users: where a real app calls its ad SDK (AdMob and the
            // like). The next episode waits until it closes.
            cues: PlayStackFeedCues(
              cues: (episode) => [
                if (episode.number.isOdd)
                  const PlayStackCue(
                    at: Duration(seconds: 6),
                    id: 'poll',
                    showFor: Duration(seconds: 8),
                  ),
                // A banner in a strip below the video, which shrinks for
                // it and keeps playing. Where an app puts its ad SDK's
                // banner (AdMob's AdWidget, for example).
                if (!offline.isPremium)
                  const PlayStackCue(
                    at: Duration(seconds: 2),
                    id: 'banner',
                    showFor: Duration(seconds: 6),
                    layout: PlayStackSlotLayout.below(height: 64),
                  ),
              ],
              // The banner at most once a minute, whatever the episode; the
              // poll every time.
              shouldShow: (episode, cue) => cue.id == 'banner'
                  ? _shows.allows(
                      'banner',
                      const PlayStackShowRule.every(Duration(minutes: 1)),
                    )
                  : true,
              onEvent: (episode, cue, event) {
                debugPrint('[cues] ${episode.id} ${cue.id} ${event.name}');
                if (cue.id == 'banner' && event == PlayStackCueEvent.shown) {
                  unawaited(_shows.record('banner'));
                }
              },
              builder: (context, page, cue, dismiss) => switch (cue.id) {
                'banner' => _BannerAd(onClose: dismiss),
                _ => _PollCard(onClose: dismiss),
              },
              onTransition: (context, move) async {
                if (offline.isPremium || !move.isForward) return;
                if (move.count % 3 != 0) return;
                await _InterstitialAd.show(context);
              },
            ),
            cinemaMode: PlayStackCinemaMode.fullscreen,
            mediaInfo: (episode) => PlayStackMediaInfo(
              title: 'Episode ${episode.number}: ${episode.title}',
              artist: series.title,
              artworkUrl: episode.poster,
            ),
            pictureInPicture: true,
            // The app's own error screen: a message for the user and a way
            // back to the episode list.
            errorBuilder: (context, page, error) => _EpisodeError(
              episode: page.data,
              error: error,
              onRetry: page.controller.retry,
              onEpisodes: () => unawaited(_showEpisodes(page.data)),
            ),
            controlsBuilder: (context, page) => PlayStackDefaultControls(
              page: page,
              // Hold to watch at 2x, as drama apps do.
              holdAction: PlayStackHoldAction.speedUp,
              doubleTapToSeek: const Duration(seconds: 10),
              dragGestures: PlayStackDragGestures.fullscreen,
              horizontalDragToSeek: true,
              thumbnails: previewThumbnails(page.data.source),
              scrubPreviewBuilder: (context, position, thumbnail) =>
                  PlayStackScrubPreview(
                    position: position,
                    thumbnail: thumbnail,
                    thumbnailSize: const Size(90, 160),
                  ),
              showDebugInfo: _debugInfo,
              bufferingIndicator: const LoadingAnimation(),
              child: page.isFullscreen
                  ? null
                  : _EpisodeOverlay(
                      series: series,
                      episode: page.data,
                      onEpisodes: () => unawaited(_showEpisodes(page.data)),
                      onPictureInPicture: () =>
                          unawaited(_view.startPictureInPicture()),
                      onMenu: () => unawaited(_showMenu(page)),
                      onCast: () => unawaited(
                        PlayStackCast.instance.castController(
                          page.controller,
                          info: PlayStackMediaInfo(
                            title:
                                'Episode ${page.data.number}: ${page.data.title}',
                            artist: series.title,
                            artworkUrl: page.data.poster,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What an episode shows when it cannot play.
class _EpisodeError extends StatelessWidget {
  const _EpisodeError({
    required this.episode,
    required this.error,
    required this.onRetry,
    required this.onEpisodes,
  });

  final Episode episode;
  final PlayStackException error;
  final VoidCallback onRetry;
  final VoidCallback onEpisodes;

  @override
  Widget build(BuildContext context) {
    final offlineError =
        error.code == PlayStackErrorCode.network ||
        error.code == PlayStackErrorCode.timeout;
    return ColoredBox(
      color: const Color(0xCC000000),
      child: SafeArea(
        child: Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      offlineError
                          ? Icons.cloud_off_rounded
                          : Icons.sentiment_dissatisfied_rounded,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      offlineError
                          ? 'You are offline'
                          : 'Episode ${episode.number} cannot play',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      offlineError
                          ? 'Connect to the internet, or watch an episode '
                                'you downloaded.'
                          : 'Please try again in a moment.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try again'),
                        ),
                        OutlinedButton(
                          onPressed: onEpisodes,
                          child: const Text('Episodes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a locked episode shows over its poster.
class _Paywall extends StatelessWidget {
  const _Paywall({required this.series, required this.episode});

  final Series series;
  final Episode episode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: const Color(0xB3000000),
      child: SafeArea(
        child: Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Episode ${episode.number} is locked',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The first ${WatchProgress.freeEpisodes} episodes of '
                      '${series.title} are free.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => watchProgress.unlock(episode),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Unlock episode (demo)'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeOverlay extends StatelessWidget {
  const _EpisodeOverlay({
    required this.series,
    required this.episode,
    required this.onEpisodes,
    required this.onPictureInPicture,
    required this.onMenu,
    required this.onCast,
  });

  final Series series;
  final Episode episode;
  final VoidCallback onEpisodes;
  final VoidCallback onPictureInPicture;
  final VoidCallback onMenu;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 8)];
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, shadows: shadow),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    series.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: shadow,
                    ),
                  ),
                ),
                const PlayStackAirPlayButton(size: 36),
                PlayStackCastButton(onConnected: onCast),
                IconButton(
                  tooltip: 'Picture-in-Picture',
                  icon: const Icon(
                    Icons.picture_in_picture_alt_rounded,
                    shadows: shadow,
                  ),
                  onPressed: onPictureInPicture,
                ),
                IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert_rounded, shadows: shadow),
                  onPressed: onMenu,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Episode ${episode.number} of ${series.episodes.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        shadows: shadow,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episode.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        shadows: shadow,
                      ),
                    ),
                  ],
                ),
              ),
              DownloadButton(series: series, episode: episode, shadows: shadow),
              FilledButton.tonalIcon(
                onPressed: onEpisodes,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Episodes'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.series, required this.current});

  final Series series;
  final Episode current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${series.title} · ${series.episodes.length} episodes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final episode in series.episodes)
                  EpisodeTile(
                    episode: episode,
                    isCurrent: episode == current,
                    onTap: () => Navigator.of(context).pop(episode),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sleep timer, audio only and the debug panel.
class _PlayerMenu extends StatelessWidget {
  const _PlayerMenu({
    required this.controller,
    required this.sleepTimer,
    required this.debugInfo,
    required this.onDebugInfo,
  });

  final PlayStackPlayerController controller;
  final PlayStackSleepTimer sleepTimer;
  final bool debugInfo;
  final ValueChanged<bool> onDebugInfo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([sleepTimer, controller.audioOnly]),
        builder: (context, _) {
          final remaining = sleepTimer.remaining;
          final sleepLabel = sleepTimer.isEndOfVideo
              ? 'At the end of this episode'
              : remaining == null
              ? 'Off'
              : '${formatPosition(remaining)} left';
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Sleep timer'),
                subtitle: Text(sleepLabel),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, duration) in const [
                      ('30 s (demo)', Duration(seconds: 30)),
                      ('15 min', Duration(minutes: 15)),
                      ('30 min', Duration(minutes: 30)),
                    ])
                      ActionChip(
                        label: Text(label),
                        onPressed: () => sleepTimer.start(duration),
                      ),
                    ActionChip(
                      label: const Text('End of episode'),
                      onPressed: sleepTimer.startEndOfVideo,
                    ),
                    if (sleepTimer.isActive)
                      ActionChip(
                        label: const Text('Off'),
                        onPressed: sleepTimer.cancel,
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.headphones_rounded),
                title: const Text('Audio only'),
                subtitle: const Text('Listen with less data; the poster shows'),
                value: controller.audioOnly.value,
                onChanged: (value) => unawaited(controller.setAudioOnly(value)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.bug_report_outlined),
                title: const Text('Debug panel'),
                subtitle: const Text('Bitrate, buffer, timings, pool'),
                value: debugInfo,
                onChanged: (value) {
                  onDebugInfo(value);
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A poll over the playing episode: the app's own widget, shown by a
/// PlayStack cue and closed with `dismiss`.
/// A stand-in for an ad SDK's banner, in the strip below the video.
class _BannerAd extends StatelessWidget {
  const _BannerAd({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: const Color(0xFF1C1C1E),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Ad',
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Banner ad', style: theme.textTheme.titleSmall),
                Text(
                  'Your ad SDK\'s banner shows here; the video makes room.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          decoration: BoxDecoration(
            color: const Color(0xE6202020),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Will they meet again?',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
              Row(
                children: [
                  for (final answer in const ['Yes', 'No'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilledButton.tonal(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('You voted "$answer"')),
                            );
                            onClose();
                          },
                          child: Text(answer),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stands in for an interstitial of an ad SDK such as AdMob: full screen,
/// closable after a few seconds. A real app awaits its SDK's show call in
/// `onTransition` instead.
class _InterstitialAd extends StatefulWidget {
  const _InterstitialAd();

  static Future<void> show(BuildContext context) => showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    pageBuilder: (context, _, _) => const _InterstitialAd(),
  );

  @override
  State<_InterstitialAd> createState() => _InterstitialAdState();
}

class _InterstitialAdState extends State<_InterstitialAd> {
  int _left = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_left <= 1) timer.cancel();
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Stack(
          children: [
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign_rounded, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Interstitial ad',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your ad SDK shows its ad here.\n'
                    'The next episode starts when it closes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _left > 0
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('$_left'),
                    )
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
