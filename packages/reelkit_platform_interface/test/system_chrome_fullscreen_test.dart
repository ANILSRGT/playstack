import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

class _Engine with SystemChromeFullscreen {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  List<Object?> orientationCalls() => [
    for (final call in calls)
      if (call.method == 'SystemChrome.setPreferredOrientations')
        call.arguments,
  ];

  test('keeps the orientation policy when none is requested', () async {
    final engine = _Engine();
    await engine.enterFullscreen(const ReelFullscreenRequest());
    await engine.exitFullscreen(
      const ReelFullscreenRestore(
        orientations: [],
        systemUiMode: SystemUiMode.edgeToEdge,
      ),
    );
    expect(orientationCalls(), isEmpty);
    expect(
      calls.map((c) => c.method),
      everyElement('SystemChrome.setEnabledSystemUIMode'),
    );
  });

  test(
    'rotates back to the previous orientation, then restores the policy',
    () async {
      final engine = _Engine();
      await engine.enterFullscreen(
        const ReelFullscreenRequest(
          orientations: [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        ),
      );
      await engine.exitFullscreen(
        const ReelFullscreenRestore(
          orientations: [],
          systemUiMode: SystemUiMode.edgeToEdge,
          previousOrientations: [DeviceOrientation.portraitUp],
          changedOrientations: true,
        ),
      );
      expect(orientationCalls(), [
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        ['DeviceOrientation.portraitUp'],
        <String>[],
      ]);
    },
  );

  test('never rotates to an orientation the app does not allow', () async {
    final engine = _Engine();
    await engine.exitFullscreen(
      const ReelFullscreenRestore(
        orientations: [DeviceOrientation.landscapeLeft],
        systemUiMode: SystemUiMode.edgeToEdge,
        previousOrientations: [DeviceOrientation.portraitUp],
        changedOrientations: true,
      ),
    );
    expect(orientationCalls(), [
      ['DeviceOrientation.landscapeLeft'],
    ]);
  });
}
