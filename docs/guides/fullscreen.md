# Fullscreen and orientation

PlayStack does not build a fullscreen screen. You show your own route or
overlay and call `manager.fullscreen.enter` and `exit` around it. PlayStack
hides the system bars, optionally locks the orientation, and on exit
rotates back and restores the app's own policy.

```dart
class FullscreenVideo extends StatefulWidget {
  const FullscreenVideo({super.key, required this.manager, required this.controller});

  final PlayStackManager manager;
  final PlayStackPlayerController controller;

  @override
  State<FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<FullscreenVideo> {
  @override
  void initState() {
    super.initState();
    widget.manager.fullscreen.enter(
      orientation: PlayStackFullscreenOrientation.matchVideo,
      controller: widget.controller,
    );
  }

  @override
  void dispose() {
    widget.manager.fullscreen.exit(); // also runs on the back gesture
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: PlayStackVideoView(controller: widget.controller),
  );
}
```

## Orientation

| `PlayStackFullscreenOrientation` | While fullscreen |
| --- | --- |
| `keepCurrent` (default) | The orientation policy is not touched |
| `landscape` | Both landscape orientations |
| `portrait` | Portrait up |
| `matchVideo` | Landscape for wide videos, portrait for tall ones, unchanged for square or unknown sizes; needs `controller` |

Calling `enter` again while fullscreen only changes the orientation.
`enter` and `exit` calls run in order, so a quick enter/exit/enter sequence
ends in the right state.

## Restoring the app's policy

Flutter cannot read the orientations or system UI mode an app has set, so
tell PlayStack what to restore:

```dart
PlayStackManager(
  config: const PlayStackConfig(
    fullscreen: PlayStackFullscreenConfig(
      appOrientations: [DeviceOrientation.portraitUp],   // empty: everything the app declares
      appSystemUiMode: SystemUiMode.edgeToEdge,
      fullscreenSystemUiMode: SystemUiMode.immersiveSticky,
    ),
  ),
);

// If a route changes the app policy at run time:
manager.fullscreen.setAppPolicy(
  const PlayStackFullscreenConfig(appOrientations: DeviceOrientation.values),
);
```

On exit PlayStack first rotates back to the orientation the app was shown
in, waits for the rotation, then applies `appOrientations`; unlocking alone
does not rotate the interface back on every platform.

`manager.fullscreen.isFullscreen` is a `ValueListenable<bool>`. On web it
also follows the browser, for example when the user presses Escape.

## Platform notes

- **Android, iOS:** `SystemChrome` immersive mode and preferred
  orientations. On iPad with multitasking enabled, iOS ignores orientation
  locks.
- **Web:** the Fullscreen API on the document. Browsers allow it only
  during a user gesture; otherwise `enter` throws `PlayStackException` with
  `notAllowed`. Orientation locking works only where the browser supports
  `screen.orientation.lock` (mostly Chrome on Android) and is ignored
  elsewhere.
- **Web, one view per controller:** a controller's video is a single
  `<video>` element, and a DOM element can only be in one place. A second
  `PlayStackVideoView` of the same controller takes the element from the first,
  which stays empty afterwards. On web, show fullscreen video by replacing
  the inline view (for example an overlay in the same widget tree position)
  rather than a route that renders the controller a second time.
