# Series: continue watching, skip intro, next episode

`PlayStackFeedView(series: PlayStackSeries(...))` adds what streaming apps
have for series. Every part is optional and its look is replaceable.

```dart
final progress = PlayStackWatchProgress(
  storage: PlayStackProgressStorage.keyValue(
    read: () => prefs.getString('progress'),
    write: (json) => prefs.setString('progress', json),
  ),
);
await progress.load();

PlayStackFeedView<Episode>(
  items: episodes,
  videoUrl: (episode) => episode.url,
  itemId: (episode) => episode.id,   // needed for progress
  autoAdvance: true,
  series: PlayStackSeries(
    progress: progress,
    skipMarkers: (episode) => [
      PlayStackSkipMarker.intro(start: Duration.zero, end: episode.introEnd),
      PlayStackSkipMarker.credits(start: episode.creditsStart),
    ],
    nextUp: const PlayStackNextUp(countdown: Duration(seconds: 5)),
    nextUpLabel: (next) => 'Episode ${next.number}',
  ),
)
```

## Watch progress

`PlayStackWatchProgress` remembers where the user stopped in each video and
saves it through your storage (shared preferences, a database, your
backend). With `progress` set, the feed opens each episode where the user
stopped and saves the position while it plays.

```dart
progress.resumePosition('ep-3');   // Duration?, null when barely started or finished
progress['ep-3']?.fraction;        // 0.0 to 1.0, for a progress line on a thumbnail
progress.unfinished;               // "Continue watching" row, newest first
progress.markFinished('ep-3');
await progress.remove('ep-3');
```

| Option | Default | |
| --- | --- | --- |
| `saveInterval` | 5 s | How often positions are written while playing |
| `finishedAt` | 0.95 | The fraction from which a video counts as watched |
| `minimumPosition` | 5 s | Earlier positions do not resume |
| `maxEntries` | 500 | The oldest entries are dropped beyond this |

For a full storage of your own (a table row per entry), implement
`PlayStackProgressStorage` (`readAll`, `save`). With a single player,
`progress.track(controller, 'ep-3')` saves its position; call `stop()` on
the result when done.

## Skip buttons

`PlayStackSkipMarker.intro`, `.recap`, `.credits` or your own type show a
"Skip intro" style button while the position is inside the marker. A tap
jumps to its end. `skipButtonBuilder` replaces the button:

```dart
skipButtonBuilder: (context, page, marker, skip) =>
    OutlinedButton(onPressed: skip, child: Text(marker.label ?? 'Skip')),
```

## Next episode

`PlayStackNextUp` shows the next item near the end (`showBefore`, 10 s by
default, or at the credits marker) with a countdown (`countdown`, 5 s).
The countdown only runs while the video plays. Pass `nextUp: null` to turn
it off, or `nextUpBuilder` to draw your own:

```dart
nextUpBuilder: (context, page, details) => MyNextCard(
  next: details.next,
  progress: details.progress,   // 0 to 1
  onPlay: details.playNow,
  onCancel: details.cancel,
),
```

To show something between episodes (an interstitial ad, a paywall), use
[`cues: PlayStackFeedCues(onTransition: ...)`](cues.md#between-items).
