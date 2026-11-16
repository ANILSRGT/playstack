import 'package:flutter/material.dart';
import 'package:playstack/playstack.dart';

import 'drama_data.dart';

/// Offline viewing in the drama app: only for premium users, as in many
/// streaming apps. The demo has no accounts, so a switch stands in for the
/// subscription.
///
/// The downloads belong to the app, so this manager is enough: the episode
/// player's own manager sees the same downloads and plays them offline.
class DramaOffline extends ChangeNotifier {
  final PlayStackManager _manager = PlayStackManager();

  bool _premium = false;

  /// Whether the user may download and watch offline.
  bool get isPremium => _premium;

  PlayStackDownloads get downloads => _manager.downloads;

  Future<void> initialize() => _manager.initialize();

  /// Called when the subscription starts or ends. Without it, nothing
  /// downloads and downloaded episodes stream like the others.
  Future<void> setPremium(bool premium) async {
    _premium = premium;
    notifyListeners();
    await downloads.setEnabled(premium);
  }

  String idOf(Episode episode) => 'coastline-${episode.number}';

  PlayStackDownload? downloadOf(Episode episode) => downloads[idOf(episode)];

  Future<void> download(
    Series series,
    Episode episode,
    PlayStackDownloadQuality quality,
  ) => downloads.download(
    idOf(episode),
    episode.source,
    title: '${series.title} · Episode ${episode.number}',
    quality: quality,
    metadata: {
      'series': series.title,
      'episode': '${episode.number}',
      'title': episode.title,
      'quality': quality.label,
    },
  );
}

final offline = DramaOffline();

/// A download button for an episode: download, progress, done.
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.series,
    required this.episode,
    this.shadows,
  });

  final Series series;
  final Episode episode;
  final List<Shadow>? shadows;

  Future<void> _onPressed(BuildContext context) async {
    if (!offline.isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline viewing is a premium feature.')),
      );
      return;
    }
    final download = offline.downloadOf(episode);
    if (download == null || download.state == PlayStackDownloadState.failed) {
      final quality = await showModalBottomSheet<PlayStackDownloadQuality>(
        context: context,
        showDragHandle: true,
        builder: (context) => const _QualitySheet(),
      );
      if (quality != null) await offline.download(series, episode, quality);
    } else if (download.isActive) {
      await offline.downloads.pause(download.id);
    } else if (download.state == PlayStackDownloadState.paused) {
      await offline.downloads.resume(download.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PlayStackDownload>>(
      valueListenable: offline.downloads.downloads,
      builder: (context, _, _) {
        final download = offline.downloadOf(episode);
        final Widget icon = switch (download?.state) {
          null => Icon(Icons.download_rounded, shadows: shadows),
          PlayStackDownloadState.completed => const Icon(
            Icons.download_done_rounded,
            color: Colors.greenAccent,
          ),
          PlayStackDownloadState.failed => Icon(
            Icons.error_outline_rounded,
            shadows: shadows,
          ),
          PlayStackDownloadState.paused => Icon(
            Icons.play_arrow_rounded,
            shadows: shadows,
          ),
          _ => SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: (download!.percent ?? 0) / 100,
            ),
          ),
        };
        return IconButton(
          tooltip: switch (download?.state) {
            null => 'Download',
            PlayStackDownloadState.completed => 'Downloaded',
            PlayStackDownloadState.failed => 'Retry download',
            PlayStackDownloadState.paused => 'Resume download',
            _ => 'Pause download',
          },
          icon: icon,
          onPressed: () => _onPressed(context),
        );
      },
    );
  }
}

/// Lets the user pick how good (and how big) the download is.
class _QualitySheet extends StatelessWidget {
  const _QualitySheet();

  static const _notes = {
    PlayStackDownloadQuality.low: 'Smallest, saves space',
    PlayStackDownloadQuality.medium: 'Sharp on phones',
    PlayStackDownloadQuality.high: 'Full HD',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Download quality',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final quality in const [
            PlayStackDownloadQuality.low,
            PlayStackDownloadQuality.medium,
            PlayStackDownloadQuality.high,
          ])
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: Text(
                '${quality.name[0].toUpperCase()}${quality.name.substring(1)}'
                ' · ${quality.label}',
              ),
              subtitle: Text(_notes[quality]!),
              onTap: () => Navigator.of(context).pop(quality),
            ),
        ],
      ),
    );
  }
}

/// Every downloaded episode, with progress, pause and delete.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListenableBuilder(
        listenable: Listenable.merge([offline, offline.downloads.downloads]),
        builder: (context, _) {
          final downloads = offline.downloads.downloads.value;
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('Premium (demo)'),
                subtitle: Text(
                  offline.isPremium
                      ? 'Downloaded episodes play without a network.'
                      : 'Without premium, nothing downloads and downloaded '
                            'episodes stream like the others.',
                ),
                value: offline.isPremium,
                onChanged: offline.setPremium,
              ),
              const Divider(),
              if (downloads.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No downloads yet. Tap the download button of an '
                    'episode.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final download in downloads) _DownloadTile(download),
            ],
          );
        },
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile(this.download);

  final PlayStackDownload download;

  @override
  Widget build(BuildContext context) {
    final percent = download.percent;
    final status = switch (download.state) {
      PlayStackDownloadState.queued => 'Waiting',
      PlayStackDownloadState.downloading =>
        'Downloading ${percent?.toStringAsFixed(0) ?? '…'}%',
      PlayStackDownloadState.paused => 'Paused',
      PlayStackDownloadState.completed =>
        'Ready offline · ${_megabytes(download.bytesDownloaded)}',
      PlayStackDownloadState.failed => 'Failed: ${download.error ?? 'unknown'}',
    };
    return ListTile(
      title: Text(download.metadata['title'] ?? download.title ?? download.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${download.metadata['series'] ?? ''} · Episode '
            '${download.metadata['episode'] ?? '?'} · '
            '${download.metadata['quality'] ?? ''} · $status',
          ),
          if (!download.isCompleted && percent != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: percent / 100),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (download.isActive)
            IconButton(
              tooltip: 'Pause',
              icon: const Icon(Icons.pause_rounded),
              onPressed: () => offline.downloads.pause(download.id),
            ),
          if (download.state == PlayStackDownloadState.paused ||
              download.state == PlayStackDownloadState.failed)
            IconButton(
              tooltip: 'Resume',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => offline.downloads.resume(download.id),
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => offline.downloads.remove(download.id),
          ),
        ],
      ),
    );
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
