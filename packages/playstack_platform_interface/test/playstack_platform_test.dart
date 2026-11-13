import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playstack_platform_interface/playstack_platform_interface.dart';

class _ExtendingPlatform extends PlayStackPlatform {}

class _ImplementingPlatform implements PlayStackPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('the default instance reports an unsupported platform', () async {
    await expectLater(
      PlayStackPlatform.instance.initialize(),
      throwsA(
        isA<PlayStackException>().having(
          (e) => e.code,
          'code',
          PlayStackErrorCode.unsupportedPlatform,
        ),
      ),
    );
  });

  test('implementations must extend the platform interface', () {
    PlayStackPlatform.instance = _ExtendingPlatform();
    expect(
      () => PlayStackPlatform.instance = _ImplementingPlatform(),
      throwsA(isA<AssertionError>()),
    );
  });

  test('maps platform exceptions to typed errors', () {
    final error = PlayStackException.fromPlatformException(
      PlatformException(code: 'network', message: 'offline', details: 'x'),
    );
    expect(error.code, PlayStackErrorCode.network);
    expect(error.message, 'offline');
    expect(error.details, 'x');

    final unknown = PlayStackException.fromPlatformException(
      PlatformException(code: 'something-else'),
    );
    expect(unknown.code, PlayStackErrorCode.unknown);
    expect(unknown.message, 'something-else');
  });
}
