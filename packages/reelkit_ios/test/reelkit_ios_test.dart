import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelkit_ios/reelkit_ios.dart';
import 'package:reelkit_ios/src/messages.g.dart';
import 'package:reelkit_platform_interface/reelkit_platform_interface.dart';

class _FakeHostApi extends ReelKitHostApi {
  final List<Object?> calls = <Object?>[];
  PlatformException? failure;

  @override
  Future<PlatformCapabilities> initialize() async {
    return PlatformCapabilities(
      engineName: 'engine',
      engineVersion: '1.2.3',
      recommendedMaxPlayers: 3,
      maxHardwareDecoderInstances: 16,
      totalMemoryBytes: 4096,
      isLowRamDevice: false,
      supportsHls: true,
      supportsDash: true,
      supportsDiskCache: false,
      supportsMemorySource: false,
      supportsTrackSelection: false,
      supportsVideoTrackSelection: false,
      supportsVideoQualityLimit: false,
    );
  }

  @override
  Future<PlatformPlayerCreation> createPlayer(
    PlatformPlayerOptions options,
  ) async {
    calls.add(options);
    return PlatformPlayerCreation(playerId: 7, textureId: 42);
  }

  @override
  Future<void> disposePlayer(int playerId) async => calls.add('dispose');

  @override
  Future<void> setSource(
    int playerId,
    PlatformSource source,
    int generation,
  ) async {
    if (failure != null) throw failure!;
    calls.add(source);
  }

  @override
  Future<void> seekTo(int playerId, int positionMs) async =>
      calls.add('seek $positionMs');
}

void main() {
  late _FakeHostApi api;
  late StreamController<PlatformPlayerEvent> rawEvents;
  late ReelKitIOS platform;

  setUp(() {
    api = _FakeHostApi();
    rawEvents = StreamController<PlatformPlayerEvent>.broadcast();
    platform = ReelKitIOS(api: api, eventStream: rawEvents.stream);
  });

  tearDown(() => rawEvents.close());

  test('registers itself as the platform instance', () {
    ReelKitIOS.registerWith();
    expect(ReelKitPlatform.instance, isA<ReelKitIOS>());
  });

  test('maps capabilities', () async {
    final caps = await platform.initialize();
    expect(caps.engineName, 'engine');
    expect(caps.recommendedMaxPlayers, 3);
    expect(caps.maxHardwareDecoderInstances, 16);
    expect(caps.supportsDash, isTrue);
  });

  testWidgets('creates players and renders them through a texture', (
    tester,
  ) async {
    final handle = await platform.createPlayer(
      const ReelNativePlayerOptions(looping: true, volume: 0.5),
    );
    expect(handle, const ReelNativePlayerHandle(playerId: 7, textureId: 42));
    final options = api.calls.single! as PlatformPlayerOptions;
    expect(options.looping, isTrue);
    expect(options.volume, 0.5);

    final view = platform.buildView(7);
    expect(view, isA<Texture>());
    expect((view as Texture).textureId, 42);

    await platform.disposePlayer(7);
    expect(platform.buildView(7), isA<SizedBox>());
  });

  test('maps sources with detected formats and headers', () async {
    await platform.setSource(
      1,
      const ReelSource.network(
        'https://example.com/live.m3u8',
        headers: {'Authorization': 'Bearer t'},
      ),
      3,
    );
    final source = api.calls.single! as PlatformSource;
    expect(source.type, PlatformSourceType.network);
    expect(source.formatHint, PlatformVideoFormat.hls);
    expect(source.httpHeaders, {'Authorization': 'Bearer t'});
    expect(source.cacheKey, 'https://example.com/live.m3u8');

    api.calls.clear();
    await platform.setSource(
      1,
      const ReelSource.asset('videos/a.mp4', package: 'pkg'),
      4,
    );
    final asset = api.calls.single! as PlatformSource;
    expect(asset.type, PlatformSourceType.asset);
    expect(asset.assetName, 'videos/a.mp4');
    expect(asset.assetPackage, 'pkg');
  });

  test('maps native errors to typed exceptions', () async {
    api.failure = PlatformException(code: 'notImplemented', message: 'later');
    await expectLater(
      platform.setSource(1, const ReelSource.file('/a.mp4'), 1),
      throwsA(
        isA<ReelKitException>()
            .having((e) => e.code, 'code', ReelKitErrorCode.notImplemented)
            .having((e) => e.message, 'message', 'later'),
      ),
    );
  });

  test('converts positions to durations', () async {
    await platform.seekTo(1, const Duration(seconds: 2, milliseconds: 5));
    expect(api.calls.single, 'seek 2005');
  });

  test('maps events', () async {
    final events = <ReelPlatformEvent>[];
    final sub = platform.events.listen(events.add);
    rawEvents
      ..add(
        PlatformInitializedEvent(
          playerId: 1,
          generation: 2,
          durationMs: -1,
          width: 640,
          height: 360,
          rotationDegrees: 90,
          pixelAspectRatio: 1,
          isLive: false,
          videoCodec: 'avc1.42C01E',
        ),
      )
      ..add(
        PlatformStateEvent(
          playerId: 1,
          generation: 2,
          state: PlatformPlaybackState.buffering,
        ),
      )
      ..add(
        PlatformErrorEvent(
          playerId: 1,
          generation: 2,
          code: 'decoder',
          message: 'codec failure',
        ),
      );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    final initialized = events[0] as ReelInitializedEvent;
    expect(initialized.info.duration, isNull, reason: 'negative = unknown');
    expect(initialized.info.rotationDegrees, 90);
    expect(
      (events[1] as ReelNativeStateEvent).state,
      ReelNativePlaybackState.buffering,
    );
    final error = events[2] as ReelErrorEvent;
    expect(error.error.code, ReelKitErrorCode.decoder);
    expect(error.generation, 2);
  });
}
