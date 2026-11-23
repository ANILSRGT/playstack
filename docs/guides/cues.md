# Your own moments: cues and transitions

Show something of your own at a point of a video or between two items: a
poll, a "rate this episode" card, a banner, an interstitial of your ad SDK
(AdMob, AppLovin MAX, Unity Ads, ...), a paywall. PlayStack only tells you
when; what appears is yours. Nothing is shown unless you add it.

```dart
PlayStackFeedView<Episode>(
  items: episodes,
  videoUrl: (episode) => episode.url,
  cues: PlayStackFeedCues(
    cues: (episode) => [
      const PlayStackCue(at: Duration(seconds: 30), id: 'poll'),
      const PlayStackCue(at: Duration(minutes: 5), id: 'ad', pause: true),
    ],
    builder: ...,       // draw a widget over the video
    onCue: ...,         // or run code (an ad SDK)
    onTransition: ...,  // between items
  ),
)
```

## Cues

A `PlayStackCue` is a point in a video:

| | |
| --- | --- |
| `PlayStackCue(at: Duration(seconds: 30))` | 30 s from the start; `Duration.zero` fires when the video first plays |
| `PlayStackCue.fromEnd(Duration(seconds: 15))` | 15 s before the end, placed once the length is known |
| `id` | Your name for it, to tell cues apart |
| `pause` | Pause the video while the cue is active, play again after. False by default |
| `showFor` | End the cue on its own after this long |
| `layout` | Where its widget shows: over the video (default), full screen, a box, a strip above or below that shrinks the video, or your own. See [Layouts](placement-and-rules.md#layouts) |
| `repeatOnSeekBack` | Fire again when the user seeks back before it |
| `data` | Anything you attach: a poll question, an ad unit id |

A cue fires once per page, when playback reaches it. Seeking past a cue
does not fire it. When the user swipes away, an active cue ends.

## Show or skip, and what happened

```dart
cues: PlayStackFeedCues(
  cues: (episode) => [
    const PlayStackCue(at: Duration(minutes: 5), id: 'interstitial', pause: true),
  ],
  // Decide each cue yourself: on the device or on your server.
  shouldShow: (episode, cue) => api.canShow(episode.id, cue.id),
  // shown, dismissed, expired, handled, declined
  onEvent: (episode, cue, event) => api.record(episode.id, cue.id, event),
  onCue: ...,
),
```

`shouldShow` is asked a few seconds ahead (`decisionLead`); a missing
answer skips the cue. [Layouts, rules and events](placement-and-rules.md)
has the details and ready-made rules kept on the device
(`PlayStackShowRules`): "once a day", "never again", "three times a day".
`onTransition` is your own code already: decide and record there.

## Showing a widget

`builder` draws the active cue where its `layout` says (over the video,
above the controls, by default). Call `dismiss` to end it:

```dart
cues: PlayStackFeedCues(
  cues: (episode) => [
    const PlayStackCue(at: Duration(seconds: 6), id: 'poll', showFor: Duration(seconds: 8)),
  ],
  builder: (context, page, cue, dismiss) => PollCard(
    question: 'Will they meet again?',
    onAnswer: (answer) {
      api.vote(page.data.id, answer);
      dismiss();
    },
  ),
),
```

With a `builder`, a cue lasts until `dismiss` is called or `showFor` runs
out.

An ad SDK's banner in a strip below the video, which shrinks for it and
keeps playing:

```dart
const PlayStackCue(
  at: Duration(minutes: 2),
  id: 'banner',
  showFor: Duration(seconds: 30),
  layout: PlayStackSlotLayout.below(height: 50),
),
// in builder:
'banner' => AdWidget(ad: bannerAd), // google_mobile_ads
```

## Running code: ad SDKs

`onCue` is called when a cue fires. Without a `builder`, the cue lasts
until the `Future` that `onCue` returns completes. With `pause: true` the
video waits that long and then plays again. That is all an interstitial
needs:

```dart
cues: PlayStackFeedCues(
  cues: (episode) => [
    const PlayStackCue(at: Duration(minutes: 5), pause: true),
  ],
  onCue: (context, page, cue) => interstitials.show(), // completes when the ad closes
),
```

Use `pause: true` for full-screen ads: the ad covers the screen, but
without the pause the video keeps playing (and sounding) underneath.

### Turning ad callbacks into a Future

Most ad SDKs do not return a `Future` that completes when the ad closes;
they call a callback. A `Completer` turns any callback into one:

```dart
import 'dart:async';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class Interstitials {
  InterstitialAd? _ad;

  /// Load ahead: loading when the moment comes is too slow.
  void preload() {
    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _ad = ad,
        onAdFailedToLoad: (_) => _ad = null,
      ),
    );
  }

  /// Completes when the ad is closed, or at once when none is ready.
  Future<void> show() {
    final ad = _ad;
    if (ad == null) return Future.value(); // nothing to show: the video goes on
    _ad = null;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        closed.complete();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        closed.complete(); // also on failure, or the video waits forever
        preload();
      },
    );
    ad.show();
    return closed.future;
  }
}
```

The same pattern works with every SDK; only the callback names differ:

| SDK | The ad closed |
| --- | --- |
| AdMob (`google_mobile_ads`) | `onAdDismissedFullScreenContent` |
| AppLovin MAX | `onAdHiddenCallback` |
| Unity Ads | `onComplete` of `show` |
| ironSource / LevelPlay | `onAdClosed` |
| Meta Audience Network | the `INTERSTITIAL_DISMISSED` event |
| Yandex Ads | `onAdDismissed` |

Rules for the `Future` you return:

- **Complete it on failure too.** If the ad cannot be shown and the close
  callback never comes, the video stays paused.
- **Complete it at once when no ad is ready.** The video then does not
  wait.
- **Add a time limit if you do not trust the SDK:**

  ```dart
  onCue: (context, page, cue) => interstitials.show().timeout(
    const Duration(seconds: 90),
    onTimeout: () {},
  ),
  ```

- An SDK with no close callback at all is rare. For one, use the app
  coming back to the foreground (`AppLifecycleState.resumed`) or a time
  limit as the end.

`cue.id` and `cue.data` tell several moments apart, for example a rewarded
ad at one cue and an interstitial at another.

## Between items

`onTransition` is called when the user moves to another item, or the feed
advances on its own (`autoAdvance`, the next-episode countdown). The new
item stays paused until the returned `Future` completes:

```dart
cues: PlayStackFeedCues(
  onTransition: (context, move) async {
    if (user.isPremium || !move.isForward) return; // plays at once
    if (move.count % 3 == 0) await interstitials.show();
  },
),
```

`PlayStackTransition` has `from` and `to` (your items), `fromIndex`,
`toIndex`, `isForward` and `count`: how many moves the user made in this
feed, the current one included, for "every third video" rules. The same
`Future` rules as above apply. A dialog works too:
`await showDialog(...)`.

## With your own player

Outside a feed, `PlayStackCueController` runs cues on one controller:

```dart
final cues = PlayStackCueController(
  controller: controller,
  cues: const [PlayStackCue(at: Duration(minutes: 5), pause: true)],
  onCue: (cue) => interstitials.show(),
);

cues.active;    // the cue showing now, or null
cues.dismiss(); // end it
cues.cues;      // Stream of cues as they fire
cues.dispose();
```

Pass `endWhenHandled: false` when you draw the cue yourself and end it
with `dismiss`. `PlayStackCueOverlay` draws it by its layout inside a
`PlayStackSlotFrame` (see [With your own player](placement-and-rules.md#with-your-own-player)).
`shouldShow`, `onEvent` and `events` work as in a feed.

For video ads served by an ad server (VAST), see [Ads](ads.md): those
play inside the player instead of through an SDK.
