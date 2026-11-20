# Analytics

PlayStack reports what happens to every video as typed events: loaded,
started (with the startup time), paused, resumed, seeked, reached 25 / 50 /
75 %, completed, rebuffered, changed quality, failed, and ended with the
watch time. Send them to Firebase, Mixpanel, Amplitude or your backend.

## Listening

Every video of the app, also the ones of a `PlayStackFeedView` that created
its own manager:

```dart
PlayStackAnalytics.all.listen((event) {
  FirebaseAnalytics.instance.logEvent(
    name: event.name,              // video_start, video_progress, ...
    parameters: event.parameters,  // content_id, position_ms, ...
  );
});
```

Only the videos of one manager:

```dart
manager.analytics.events.listen(send);
```

Events cost nothing while nobody listens.

## Events

| Event | `name` | Extra fields |
| --- | --- | --- |
| `PlayStackLoadEvent` | `video_load` | |
| `PlayStackStartEvent` | `video_start` | `startupTime`: from the play request to the first frame |
| `PlayStackPauseEvent` | `video_pause` | |
| `PlayStackResumeEvent` | `video_resume` | |
| `PlayStackSeekEvent` | `video_seek` | `from` (`position` is where it went) |
| `PlayStackProgressEvent` | `video_progress` | `percent`: a milestone passed for the first time |
| `PlayStackCompleteEvent` | `video_complete` | |
| `PlayStackRebufferEvent` | `video_rebuffer` | `stall`: how long it waited; `afterSeek` |
| `PlayStackQualityEvent` | `video_quality` | `width`, `height`, `chosenByUser` |
| `PlayStackFailureEvent` | `video_error` | `error` (`PlayStackException`) |
| `PlayStackEndEvent` | `video_end` | `watchTime`, `stallTime`, `stalls`, `completed`, `furthest` |

Every event also has `controller`, `source`, `contentId`, `position`,
`duration` and `time`. `PlayStackEndEvent` comes once per visit: when the
user swipes away, the source changes or the controller is disposed.

The event classes are sealed, so a `switch` can pick the ones you need:

```dart
PlayStackAnalytics.all.listen((event) {
  switch (event) {
    case PlayStackStartEvent(:final startupTime):
      metrics.recordStartup(startupTime);
    case PlayStackRebufferEvent(:final stall):
      metrics.recordStall(stall);
    case PlayStackEndEvent(:final watchTime, :final completed):
      backend.view(event.contentId, watchTime, completed);
    default:
  }
});
```

## Content ids

`contentId` is your id for the video. Feeds set it to the item id
(`PlayStackFeedView.itemId`); for a single player set
`controller.contentId = 'movie-42'`.

## Configuration

```dart
PlayStackManager(
  config: PlayStackConfig(
    analytics: PlayStackAnalyticsConfig(
      progressMilestones: [10, 25, 50, 75, 90], // default 25, 50, 75
      positionInterval: Duration(seconds: 1),    // how often milestones are checked
    ),
  ),
);

PlayStackConfig(analytics: PlayStackAnalyticsConfig.disabled); // none at all
```
