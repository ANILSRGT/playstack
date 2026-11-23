# Where and when: layouts, rules and events

Ad breaks ([Ads](ads.md)) and cues ([Cues and transitions](cues.md)) share
three things, all optional:

- **Layout:** where each one shows, relative to the video.
- **Rules:** whether it shows this time (`shouldShow`), decided by your
  code, on the device or on your server.
- **Events:** what happened (`onEvent`), to record it wherever you like.

Each break and each cue has its own settings, so different ads in the same
video can behave differently.

## Layouts

```dart
PlayStackAdBreak.midRoll(at: ..., source: ..., layout: const PlayStackSlotLayout.below(height: 90))
PlayStackCue(at: ..., id: 'banner', layout: const PlayStackSlotLayout.overlay(alignment: Alignment.topRight, widthFactor: 0.4))
```

| | Where |
| --- | --- |
| `PlayStackSlotLayout.videoArea()` | Over the video and its controls, filling them. The default |
| `PlayStackSlotLayout.fullScreen()` | Over the whole screen: app bars, tabs and the feed included |
| `PlayStackSlotLayout.overlay(...)` | A box over the video, like a banner: `alignment`, `size` or `widthFactor` with `aspectRatio`, `margin`, `safeArea` |
| `PlayStackSlotLayout.below(height: 60)` | A strip below the video. The video shrinks to make room and grows back after |
| `PlayStackSlotLayout.above(height: 60)` | A strip above the video, the same way |
| `PlayStackSlotLayout.custom((context, video, slot) => ...)` | Your own arrangement: `video` is the video with its controls, `slot` the ad or the cue |

```dart
// The ad on the right, the video on the left.
PlayStackSlotLayout.custom(
  (context, video, slot) => Row(children: [
    Expanded(child: video),
    SizedBox(width: 280, child: slot),
  ]),
)
```

The video keeps playing and keeps its state while it shrinks or moves. A
strip keeps clear of the home indicator (`safeArea: true`, the default).

What shows inside the slot is yours too: the ad's labels and buttons
(`PlayStackFeedAds.builder`) and the cue's widget (`PlayStackFeedCues.builder`).

## Rules: `shouldShow`

Asked before each break or cue. Return true to show it, false to skip it;
the video goes on as if it were not there.

```dart
ads: PlayStackFeedAds(
  breaks: (episode) => [
    PlayStackAdBreak.preRoll(PlayStackAdSource.vast(tag), id: 'pre'),
    PlayStackAdBreak.midRoll(at: const Duration(minutes: 2), id: 'mid', source: ...),
  ],
  shouldShow: (episode, adBreak) async {
    // On your server:
    return api.canShowAd(userId, episode.id, adBreak.id);
  },
),
```

Give breaks and cues an `id` so your rule knows which one it is asked
about. Anything goes: per episode or for every episode, per user, by time
of day, by subscription.

**Timing.** The question is asked ahead: the pre-roll as soon as the item
comes into view, every other break and cue `decisionLead` before its
point (5 seconds by default), so a server's answer is there in time. If
the answer is still missing when the point is reached, a break or cue that
pauses the video waits up to `decisionTimeout` (3 seconds), then it is
skipped. Both are settings of `PlayStackFeedAds` and `PlayStackFeedCues`.
An error in `shouldShow` skips it too.

**Seeking back.** A break or cue shows once per visit; seeking back before
it does not bring it back, like on YouTube. `repeatOnSeekBack: true` makes
it show again (asking `shouldShow` again).

**The ad server.** An ad server can have its own rules, such as Google Ad
Manager's frequency caps ("once a day per user"). When it answers with no
ads, the break is skipped (`PlayStackAdBreakEventType.empty`). This works
together with `shouldShow`.

## Events: `onEvent`

```dart
onEvent: (episode, adBreak, event) {
  if (event.type == PlayStackAdBreakEventType.adCompleted) {
    api.recordAdWatched(userId, episode.id, adBreak.id);
  }
},
```

| Ad breaks (`PlayStackAdBreakEventType`) | |
| --- | --- |
| `declined` | `shouldShow` said no or did not answer in time |
| `started` | The break began |
| `empty` | The ad source had no ads |
| `adStarted`, `adCompleted`, `adSkipped`, `adClicked`, `adFailed` | For each ad (`event.ad`, `event.adNumber`, `event.adCount`) |
| `ended` | The break is over; the video continues |

| Cues (`PlayStackCueEvent`) | |
| --- | --- |
| `declined` | `shouldShow` said no or did not answer in time |
| `shown` | The cue fired |
| `dismissed` | Closed with `dismiss`: by the user or by your code |
| `expired` | Its `showFor` ran out |
| `handled` | `onCue`'s future completed (an ad SDK's ad closed) |

Events reported by the device can be changed by a determined user. When
something valuable depends on an ad being watched (a reward, an unlocked
episode), confirm it with the ad network's server-side verification (for
example AdMob's SSV for rewarded ads), not with these events alone.

## Ready-made rules on the device

`PlayStackShowRules` keeps when things were shown and answers whether they
may show again. Optional; your own code or server can do the same.

```dart
final shows = PlayStackShowRules(
  store: PlayStackShowStore.file('${supportDir.path}/playstack_shows.json'),
);

ads: PlayStackFeedAds(
  breaks: ...,
  shouldShow: (episode, adBreak) => shows.allows(
    '${episode.id}/${adBreak.id}',
    const PlayStackShowRule.every(Duration(days: 1)),
  ),
  onEvent: (episode, adBreak, event) {
    if (event.type == PlayStackAdBreakEventType.started) {
      shows.record('${episode.id}/${adBreak.id}');
    }
  },
),
```

| Rule | |
| --- | --- |
| `PlayStackShowRule.always` | Every time |
| `PlayStackShowRule.once` | The first time only, never again |
| `PlayStackShowRule.every(Duration(hours: 24))` | At most once in each period |
| `PlayStackShowRule.atMost(3, per: Duration(days: 1))` | At most 3 times a day; without `per`, 3 times ever |

The key is yours: `'mid'` counts every episode's mid-roll together,
`'${episode.id}/mid'` each episode's own. `history(key)` lists when a key
was shown, `reset(key)` forgets it.

| Store | |
| --- | --- |
| `PlayStackShowStore.memory()` | Until the app quits (the default) |
| `PlayStackShowStore.file(path)` | A JSON file, for example in `getApplicationSupportDirectory()` of path_provider. Memory on the web |
| `PlayStackShowStore.custom(read: ..., write: ...)` | Your own: SharedPreferences, a database, secure storage |

```dart
final prefs = await SharedPreferences.getInstance();
final store = PlayStackShowStore.custom(
  read: () async => prefs.getString('playstack_shows'),
  write: (data) => prefs.setString('playstack_shows', data),
);
```

## With your own player

`PlayStackFeedView` lays out every page this way for you. Around your own
player, wrap the video in a `PlayStackSlotFrame` and put the overlays
inside it:

```dart
PlayStackSlotFrame(
  child: Stack(children: [
    PlayStackVideoView(controller: controller),
    MyControls(controller: controller),
    PlayStackAdOverlay(ads: ads),                       // each break's layout
    PlayStackCueOverlay(
      cues: cues,
      builder: (context, cue, dismiss) => MyCueWidget(cue, onClose: dismiss),
    ),
  ]),
)
```

`PlayStackAdController` and `PlayStackCueController` take the same
`shouldShow`, `onEvent`, `decisionLead` and `decisionTimeout`, without the
item argument. Without a frame, the overlays fill the space they are
given, as before.
