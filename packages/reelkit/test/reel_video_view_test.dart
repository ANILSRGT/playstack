import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit/reelkit.dart';

import 'support/fake_reelkit_platform.dart';

void main() {
  late FakeReelKitPlatform platform;
  late ReelKitManager manager;

  Future<void> setUpManager(WidgetTester tester, {ReelVideoInfo? info}) async {
    platform = FakeReelKitPlatform(
      videoInfo:
          info ??
          const ReelVideoInfo(
            width: 1080,
            height: 1920,
            duration: Duration(seconds: 3),
          ),
    );
    manager = ReelKitManager(platform: platform);
    await tester.runAsync(manager.initialize);
  }

  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 400, height: 300, child: child)),
  );

  Finder nativeView() => find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('native-view-'),
  );

  testWidgets('shows the placeholder until the first frame', (tester) async {
    await setUpManager(tester);
    final controller = manager.createController(const ReelSource.file('/a'));
    await tester.pumpWidget(
      host(
        ReelVideoView(
          controller: controller,
          placeholderBuilder: (_, state) =>
              Text('loading ${state.status.name}'),
        ),
      ),
    );
    expect(find.text('loading idle'), findsOneWidget);
    expect(nativeView(), findsNothing);

    await tester.runAsync(() async {
      await controller.initialize();
      await flush();
    });
    await tester.pump();

    expect(nativeView(), findsOneWidget);
    expect(find.textContaining('loading'), findsNothing);
    await tester.runAsync(manager.dispose);
  });

  testWidgets('fits the video with the requested fit and alignment', (
    tester,
  ) async {
    await setUpManager(tester);
    final controller = manager.createController(const ReelSource.file('/a'));
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(
      host(
        ReelVideoView(
          controller: controller,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );
    final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
    expect(fitted.fit, BoxFit.cover);
    expect(fitted.alignment, Alignment.topCenter);
    // Native view is laid out at the video size, then scaled by FittedBox.
    expect(tester.getSize(nativeView()), const Size(1080, 1920));
    // cover: width 400 / 1080 vs height 300 / 1920 -> width wins.
    final rect = tester.getRect(nativeView());
    expect(rect.width, closeTo(400, 0.01));
    expect(rect.height, closeTo(1920 * 400 / 1080, 0.01));
    await tester.runAsync(manager.dispose);
  });

  testWidgets('contain keeps the whole video visible', (tester) async {
    await setUpManager(tester);
    final controller = manager.createController(const ReelSource.file('/a'));
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(ReelVideoView(controller: controller)));
    final rect = tester.getRect(nativeView());
    expect(rect.height, closeTo(300, 0.01));
    expect(rect.width, closeTo(1080 * 300 / 1920, 0.01));
    await tester.runAsync(manager.dispose);
  });

  testWidgets('applies rotation and pixel aspect ratio', (tester) async {
    await setUpManager(
      tester,
      info: const ReelVideoInfo(width: 1920, height: 1080, rotationDegrees: 90),
    );
    final controller = manager.createController(const ReelSource.file('/a'));
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(ReelVideoView(controller: controller)));
    final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotated.quarterTurns, 1);
    // Upright display is portrait 1080x1920, contained in 400x300.
    final box = tester.getRect(find.byType(RotatedBox));
    expect(box.height, closeTo(300, 0.01));
    expect(box.width, closeTo(1080 * 300 / 1920, 0.01));
    await tester.runAsync(manager.dispose);
  });

  testWidgets('shows the error builder on failure', (tester) async {
    await setUpManager(tester);
    const source = ReelSource.file('/missing');
    platform.failingSources[source] = const ReelKitException(
      ReelKitErrorCode.sourceNotFound,
      'missing',
    );
    final controller = manager.createController(source);
    await tester.pumpWidget(
      host(
        ReelVideoView(
          controller: controller,
          errorBuilder: (_, error) => Text('error ${error.code.name}'),
        ),
      ),
    );
    await tester.runAsync(() async {
      await controller.initialize().catchError((Object _) {});
    });
    await tester.pump();
    expect(find.text('error sourceNotFound'), findsOneWidget);
    await tester.runAsync(manager.dispose);
  });

  testWidgets('clips with a border radius', (tester) async {
    await setUpManager(tester);
    final controller = manager.createController(const ReelSource.file('/a'));
    await tester.pumpWidget(
      host(
        ReelVideoView(
          controller: controller,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
    expect(find.byType(ClipRRect), findsOneWidget);
    await tester.pumpWidget(
      host(ReelVideoView(controller: controller, clipBehavior: Clip.none)),
    );
    expect(find.byType(ClipRRect), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
    await tester.runAsync(manager.dispose);
  });

  testWidgets('removes the native view when the player is reassigned', (
    tester,
  ) async {
    platform = FakeReelKitPlatform();
    manager = ReelKitManager(
      config: const ReelKitConfig(pool: ReelPoolConfig(maxPlayers: 1)),
      platform: platform,
    );
    await tester.runAsync(manager.initialize);
    final background = manager.createController(const ReelSource.file('/a'))
      ..priority = ReelPlayerPriority.background;
    await tester.runAsync(background.initialize);
    await tester.pumpWidget(host(ReelVideoView(controller: background)));
    expect(nativeView(), findsOneWidget);

    final active = manager.createController(const ReelSource.file('/b'));
    await tester.runAsync(() async {
      await active.play();
      await flush();
    });
    await tester.pump();
    expect(nativeView(), findsNothing);
    await tester.runAsync(manager.dispose);
  });
}
