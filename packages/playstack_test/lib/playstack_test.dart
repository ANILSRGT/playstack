/// Test helpers for apps that use PlayStack.
///
/// [FakePlayStackPlatform.install] replaces the native video engine with an
/// in-memory one, so screens with `PlayStackFeedView` or
/// `PlayStackVideoView` run in widget tests. [PlayStackWidgetTester.pumpPlayStack]
/// lets its asynchronous work finish between frames.
library;

export 'src/fake_playstack_platform.dart';
export 'src/widget_tester.dart';
