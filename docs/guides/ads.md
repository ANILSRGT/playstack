# Ads

There are two ways to show ads with PlayStack:

- **Video ads from an ad server (VAST)**, played inside the player before,
  during or after a video. This page.
- **Your ad SDK** (AdMob, AppLovin MAX, Unity Ads, ...) at a moment of a
  video or between items: see [Cues and transitions](cues.md#running-code-ad-sdks).

## VAST ad breaks

```dart
PlayStackFeedView<Episode>(
  items: episodes,
  videoUrl: (episode) => episode.url,
  ads: PlayStackFeedAds(
    breaks: (episode) => [
      if (!user.isPremium) ...[
        PlayStackAdBreak.preRoll(PlayStackAdSource.vast(preRollTag)),
        PlayStackAdBreak.midRoll(
          at: const Duration(minutes: 5),
          source: PlayStackAdSource.vast(midRollTag),
        ),
        PlayStackAdBreak.postRoll(PlayStackAdSource.vast(postRollTag)),
      ],
    ],
  ),
)
```

At each break the video pauses, the ads play in their own player, and the
video resumes. The overlay shows "Ad 1 of 2", a skip button once the ad
allows it, and "Learn more". Seeking past several mid-rolls plays only the
last one. A break plays once per visit; seeking back does not bring it
back (`repeatOnSeekBack: true` does).

### Each break its own way

Every break has its own settings, so a full-screen pre-roll and a small
banner over the playing video can be in the same episode:

```dart
PlayStackAdBreak.midRoll(
  at: const Duration(minutes: 2),
  source: PlayStackAdSource.vast(bannerTag),
  id: 'banner',
  layout: const PlayStackSlotLayout.below(height: 90), // the video shrinks
  pauseContent: false,  // the video keeps playing
  muteAd: true,
)
```

| | |
| --- | --- |
| `id` | Your name for the break, for `shouldShow`, `onEvent` and rule keys |
| `layout` | Where the ad shows: over the video (default), full screen, a box, a strip above or below that shrinks the video, or your own. See [Layouts](placement-and-rules.md#layouts) |
| `pauseContent` | Whether the video pauses while the ads play. True by default; false plays the ad next to the playing video |
| `muteContent` | Mutes the video while the ad plays next to it; its sound comes back after |
| `muteAd` | Plays the ads without sound |
| `skipAfter` | When the user may skip, replacing the ad's own `skipoffset` |
| `skippable` | False hides the skip button even when the ad allows skipping |
| `repeatOnSeekBack` | Plays a mid-roll again when the user seeks back before it |
| `data` | Anything you want to attach |

### Show or skip, and what happened

`shouldShow` decides each break, on the device or on your server;
`onEvent` tells what happened (declined, started, each ad completed or
skipped, ended):

```dart
ads: PlayStackFeedAds(
  breaks: ...,
  shouldShow: (episode, adBreak) => api.canShowAd(episode.id, adBreak.id),
  onEvent: (episode, adBreak, event) => api.recordAd(episode.id, adBreak.id, event.type),
),
```

"At most once a day", "never again", "every time" and your own rules are
built on these two. [Layouts, rules and events](placement-and-rules.md)
has the details and ready-made rules kept on the device
(`PlayStackShowRules`).

### Ad sources

| | |
| --- | --- |
| `PlayStackAdSource.vast(url, headers: ...)` | A VAST 2, 3 or 4 tag. Wrappers are followed, the tracking URLs of every level are kept |
| `PlayStackAdSource.ads([PlayStackAd(...)])` | Ads you already have |
| `PlayStackAdSource.custom(() async => ...)` | Ads from your own code, for example another network's API |

A `PlayStackAd` has a `source` (the ad video), `skipAfter`, `duration`,
`clickThroughUrl` and `tracking` URLs per `PlayStackAdEvent`.

### Tracking

Impressions, start, quartiles, complete, skip, click, pause, resume and
errors are reported to the ad's tracking URLs, with `[CACHEBUSTING]`,
`[TIMESTAMP]` and `[ERRORCODE]` filled in. Listen to them yourself with
`PlayStackAdController.events`.

### "Learn more"

PlayStack does not open URLs. Set the handler once, for example with
`url_launcher`:

```dart
PlayStackAds.onClick = (ad, url) => launchUrl(Uri.parse(url));
```

### Your own look

`PlayStackFeedAds(builder: ...)` replaces the labels and buttons above the
ad (`PlayStackAdChrome` by default). The builder receives the
`PlayStackAdController`: `ad`, `adNumber`, `adCount`, `skippableIn`,
`skip()`, `click()`, `togglePause()`.

### With your own player

```dart
final ads = PlayStackAdController(
  manager: manager,
  content: controller,
  breaks: [PlayStackAdBreak.preRoll(PlayStackAdSource.vast(tag))],
  shouldShow: (adBreak) => ...,   // optional
  onEvent: (adBreak, event) => ..., // optional
);

PlayStackSlotFrame(                 // places each break by its layout
  child: Stack(children: [
    PlayStackVideoView(controller: controller),
    PlayStackAdOverlay(ads: ads),
  ]),
);

ads.dispose(); // when done
```

`ads.breakEvents` streams the same events as `onEvent`.

`PlayStackVast.load(url)` and `PlayStackVast.parse(xml)` read VAST
responses on their own.

### Notes

- A pre-roll starts when the video is first played; the video may show
  for a moment before it pauses. Its `shouldShow` is asked as soon as the
  item comes into view, so the answer is usually there by then.
- An ad that plays next to the video (`pauseContent: false`) does not take
  part in exclusive playback (`PlayStackPlayerConfig.exclusive`): both
  play at once.
- Ad videos are regular PlayStack players, so they work on every platform,
  including the web.
- VPAID, companion banners and VMAP are not supported.
