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
last one. Breaks play once while the page lives.

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
);

Stack(children: [
  PlayStackVideoView(controller: controller),
  PlayStackAdOverlay(ads: ads),
]);

ads.dispose(); // when done
```

`PlayStackVast.load(url)` and `PlayStackVast.parse(xml)` read VAST
responses on their own.

### Notes

- A pre-roll starts when the video is first played; the video may show
  for a moment before it pauses.
- Ad videos are regular PlayStack players, so they work on every platform,
  including the web.
- VPAID, companion banners and VMAP are not supported.
