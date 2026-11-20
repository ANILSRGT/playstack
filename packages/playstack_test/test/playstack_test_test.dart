import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack/playstack.dart';
import 'package:playstack_test/playstack_test.dart';

void main() {
  testWidgets('a feed view plays in a widget test without a device', (
    tester,
  ) async {
    final engine = FakePlayStackPlatform.install();
    await tester.pumpWidget(
      const MaterialApp(
        home: PlayStackFeedView<String>(
          items: ['https://example.com/a.mp4', 'https://example.com/b.mp4'],
        ),
      ),
    );
    await tester.pumpPlayStack();
    expect(engine.calls, contains('play(1)'));
    await tester.disposePlayStack();
  });
}
