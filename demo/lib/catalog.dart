import 'package:reelkit/reelkit.dart';

/// One post of the demo feed.
class DemoVideo {
  const DemoVideo({
    required this.title,
    required this.author,
    required this.source,
    required this.note,
    this.isVertical = false,
    this.poster,
  });

  final String title;
  final String author;
  final String note;
  final ReelSource source;

  /// Whether the video is portrait, known before it is prepared so that the
  /// poster is laid out like the video will be.
  final bool isVertical;

  /// A still of the first frame, shown until the video renders one.
  final String? poster;
}

/// Every item is an HLS stream from a public test or demo service.
///
/// The vertical reels are Cloudinary's public demo videos, cropped to 9:16
/// and packaged as adaptive HLS on the fly (`sp_full_hd/c_fill,ar_9:16`),
/// up to 608x1080. A rendition that nobody requested recently is generated
/// on first request, so the first play of an item can be slower.
///
/// Cloudinary and Mux items have a poster: a still of the first frame from
/// the same service, shown at once while the video prepares.
final List<DemoVideo> demoCatalog = _interleave(_vertical, _landscape);

const _cloudinary = 'https://res.cloudinary.com/demo/video/upload';

DemoVideo _reel(String id, String title) => DemoVideo(
  title: title,
  author: '@cloudinary',
  note: 'HLS 9:16, adaptive up to 1080p',
  source: ReelSource.network('$_cloudinary/sp_full_hd/c_fill,ar_9:16/$id.m3u8'),
  isVertical: true,
  poster: '$_cloudinary/so_0,c_fill,ar_9:16,w_540,q_auto/$id.jpg',
);

DemoVideo _hls(
  String url,
  String title,
  String author,
  String note, {
  String? poster,
}) => DemoVideo(
  title: title,
  author: author,
  note: note,
  source: ReelSource.network(url),
  poster: poster ?? _posterFor(url),
);

/// Cloudinary and Mux serve stills of their own videos.
String? _posterFor(String url) {
  if (url.startsWith('$_cloudinary/sp_auto/')) {
    final id = url
        .substring('$_cloudinary/sp_auto/'.length)
        .replaceAll('.m3u8', '');
    return '$_cloudinary/so_0,w_960,q_auto/$id.jpg';
  }
  const mux = 'https://stream.mux.com/';
  if (url.startsWith(mux)) {
    final id = url.substring(mux.length).replaceAll('.m3u8', '');
    return 'https://image.mux.com/$id/thumbnail.jpg?time=1&width=960';
  }
  return null;
}

final _vertical = <DemoVideo>[
  _reel('samples/dance-2', 'Dance'),
  _reel('samples/sea-turtle', 'Sea turtle'),
  _reel('skate', 'Skate'),
  _reel('samples/cld-sample-video', 'City and nature'),
  _reel('snow_horses', 'Horses in the snow'),
  _reel('docs/walking_talking', 'Walking and talking'),
  _reel('rafting', 'Rafting'),
  _reel('elephants', 'Elephants'),
  _reel('glide-over-coastal-beach', 'Coastal glide'),
  _reel('cat', 'Cat'),
  _reel('outdoors', 'Outdoors'),
  _reel('sea_turtle', 'Turtle, close up'),
  _reel('samples/elephants', 'Elephant herd'),
  _reel('ski_jump', 'Ski jump'),
  _reel('dog', 'Dog'),
];

final _landscape = <DemoVideo>[
  _hls(
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    'Big Buck Bunny',
    '@mux',
    'HLS TS, 5 renditions',
  ),
  _hls(
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
    'Bip bop (fMP4)',
    '@apple',
    'HLS fMP4, alternate audio, subtitles',
  ),
  _hls(
    'https://test-streams.mux.dev/tos_ismc/main.m3u8',
    'Tears of Steel',
    '@mux',
    'HLS with subtitles',
  ),
  _hls(
    'https://stream.mux.com/v69RSHhFelSm4701snP22dYz2jICy4E4FUyk02rW4gxRM.m3u8',
    'Mux demo 1',
    '@mux',
    'HLS up to 1080p',
  ),
  _hls(
    'https://storage.googleapis.com/shaka-demo-assets/angel-one-hls/hls.m3u8',
    'Angel One',
    '@shaka',
    'HLS, several audio languages',
  ),
  _hls(
    'https://d2zihajmogu5jn.cloudfront.net/sintel/master.m3u8',
    'Sintel',
    '@blender',
    'HLS',
  ),
  _hls(
    '$_cloudinary/sp_auto/samples/sea-turtle.m3u8',
    'Sea turtle (wide)',
    '@cloudinary',
    'HLS 16:9, adaptive',
  ),
  _hls(
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8',
    'Bip bop (TS)',
    '@apple',
    'HLS TS, many renditions',
  ),
  _hls(
    'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8',
    'Tears of Steel (USP)',
    '@unified-streaming',
    'HLS packaged on the fly',
  ),
  _hls(
    'https://stream.mux.com/VZtzUzGRv02OhRnZCxcNg49OilvolTqdnFLEqBsTwaxU.m3u8',
    'Mux demo 2',
    '@mux',
    'HLS up to 1080p',
  ),
  _hls(
    'https://storage.googleapis.com/shaka-demo-assets/bbb-dark-truths-hls/hls.m3u8',
    'Dark Truths',
    '@shaka',
    'HLS',
  ),
  _hls(
    'https://d2zihajmogu5jn.cloudfront.net/elephantsdream/hls/ed_hd.m3u8',
    "Elephants Dream",
    '@blender',
    'HLS',
  ),
  _hls(
    'https://cdn.jwplayer.com/manifests/pZxWPRg4.m3u8',
    'JW Player sample',
    '@jwplayer',
    'HLS, 6 renditions',
  ),
  _hls(
    '$_cloudinary/sp_auto/snow_horses.m3u8',
    'Horses (wide)',
    '@cloudinary',
    'HLS 16:9, adaptive',
  ),
  _hls(
    'https://ireplay.tv/test/blender.m3u8',
    'Blender montage',
    '@ireplay',
    'HLS',
  ),
  _hls(
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8',
    'Bip bop (HEVC)',
    '@apple',
    'HLS HEVC and H.264',
  ),
  _hls(
    'https://d2zihajmogu5jn.cloudfront.net/big-buck-bunny/master.m3u8',
    'Big Buck Bunny (CloudFront)',
    '@blender',
    'HLS',
  ),
  _hls(
    'https://content.jwplatform.com/manifests/vM7nH0Kl.m3u8',
    'JW Player cinema',
    '@jwplayer',
    'HLS, 2.39:1',
  ),
  _hls(
    '$_cloudinary/sp_auto/skate.m3u8',
    'Skate (wide)',
    '@cloudinary',
    'HLS 16:9, adaptive',
  ),
  _hls(
    'https://storage.googleapis.com/shaka-demo-assets/apple-advanced-stream-fmp4/master.m3u8',
    'Advanced stream (fMP4)',
    '@shaka',
    'HLS fMP4',
  ),
  _hls(
    'https://d2zihajmogu5jn.cloudfront.net/tears-of-steel/playlist.m3u8',
    'Tears of Steel (CloudFront)',
    '@blender',
    'HLS',
  ),
  _hls(
    'https://diceyk6a7voy4.cloudfront.net/e78752a1-2e83-43fa-85ae-3d508be29366/hls/fitfest-sample-1_Ott_Hls_Ts_Avc_Aac_16x9_1280x720p_30Hz_6.0Mbps_qvbr.m3u8',
    'Fitness sample',
    '@aws-media',
    'HLS 720p',
  ),
  _hls(
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8',
    'Bip bop 16:9 (classic)',
    '@apple',
    'HLS TS',
  ),
  _hls(
    '$_cloudinary/sp_auto/rafting.m3u8',
    'Rafting (wide)',
    '@cloudinary',
    'HLS 16:9, adaptive',
  ),
  _hls(
    'https://storage.googleapis.com/shaka-demo-assets/apple-advanced-stream-ts/master.m3u8',
    'Advanced stream (TS)',
    '@shaka',
    'HLS TS',
  ),
  _hls(
    'https://d2zihajmogu5jn.cloudfront.net/bipbop-advanced/bipbop_16x9_variant.m3u8',
    'Bip bop advanced (CloudFront)',
    '@apple',
    'HLS',
  ),
  _hls(
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8',
    'Bip bop 4:3 (classic)',
    '@apple',
    'HLS TS, 4:3',
  ),
  _hls(
    'https://test-streams.mux.dev/x36xhzz/url_0/193039199_mp4_h264_aac_hd_7.m3u8',
    'Big Buck Bunny (single rendition)',
    '@mux',
    'HLS media playlist, no ABR',
  ),
];

/// Two vertical reels, then one landscape stream, until both run out.
List<DemoVideo> _interleave(List<DemoVideo> vertical, List<DemoVideo> wide) {
  final result = <DemoVideo>[];
  var v = 0;
  var w = 0;
  while (v < vertical.length || w < wide.length) {
    for (var i = 0; i < 2 && v < vertical.length; i++) {
      result.add(vertical[v++]);
    }
    if (w < wide.length) result.add(wide[w++]);
  }
  return List.unmodifiable(result);
}
