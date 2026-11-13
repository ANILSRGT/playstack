import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

void main() {
  test('display size swaps axes for quarter turns', () {
    const portrait = PlayStackVideoInfo(
      width: 1920,
      height: 1080,
      rotationDegrees: 90,
    );
    expect(portrait.displaySize, const Size(1080, 1920));
    expect(portrait.aspectRatio, closeTo(1080 / 1920, 1e-9));

    const upsideDown = PlayStackVideoInfo(
      width: 1920,
      height: 1080,
      rotationDegrees: 180,
    );
    expect(upsideDown.displaySize, const Size(1920, 1080));

    const left = PlayStackVideoInfo(
      width: 1920,
      height: 1080,
      rotationDegrees: 270,
    );
    expect(left.displaySize, const Size(1080, 1920));
  });

  test('pixel aspect ratio stretches the width', () {
    const anamorphic = PlayStackVideoInfo(
      width: 720,
      height: 576,
      pixelAspectRatio: 64 / 45,
    );
    expect(anamorphic.displaySize.width, closeTo(1024, 1e-9));
    expect(anamorphic.aspectRatio, closeTo(16 / 9, 1e-9));
  });

  test('unknown size reports a neutral aspect ratio', () {
    const empty = PlayStackVideoInfo(width: 0, height: 0);
    expect(empty.hasSize, isFalse);
    expect(empty.aspectRatio, 1.0);
  });
}
