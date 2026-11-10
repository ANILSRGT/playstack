import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

class _ExtendingPlatform extends ReelKitPlatform {}

class _ImplementingPlatform implements ReelKitPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('the default instance reports an unsupported platform', () async {
    await expectLater(
      ReelKitPlatform.instance.initialize(),
      throwsA(
        isA<ReelKitException>().having(
          (e) => e.code,
          'code',
          ReelKitErrorCode.unsupportedPlatform,
        ),
      ),
    );
  });

  test('implementations must extend the platform interface', () {
    ReelKitPlatform.instance = _ExtendingPlatform();
    expect(
      () => ReelKitPlatform.instance = _ImplementingPlatform(),
      throwsA(isA<AssertionError>()),
    );
  });

  test('maps platform exceptions to typed errors', () {
    final error = ReelKitException.fromPlatformException(
      PlatformException(code: 'network', message: 'offline', details: 'x'),
    );
    expect(error.code, ReelKitErrorCode.network);
    expect(error.message, 'offline');
    expect(error.details, 'x');

    final unknown = ReelKitException.fromPlatformException(
      PlatformException(code: 'something-else'),
    );
    expect(unknown.code, ReelKitErrorCode.unknown);
    expect(unknown.message, 'something-else');
  });
}
