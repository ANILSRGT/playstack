import 'package:reelkit/reelkit.dart';

/// One post of the demo feed.
class DemoVideo {
  const DemoVideo({
    required this.title,
    required this.author,
    required this.source,
    required this.note,
  });

  final String title;
  final String author;
  final String note;
  final ReelSource source;
}

/// Public test media. Most clips are landscape; the feed shows them
/// letterboxed unless "fill" is switched on.
const demoCatalog = <DemoVideo>[
  DemoVideo(
    title: 'Flower',
    author: '@mdn',
    note: 'MP4, CC0',
    source: ReelSource.network(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    ),
  ),
  DemoVideo(
    title: 'Big Buck Bunny',
    author: '@blender',
    note: 'MP4, 10 s',
    source: ReelSource.network(
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4',
    ),
  ),
  DemoVideo(
    title: 'Vertical test card',
    author: '@reelkit',
    note: 'Bundled asset',
    source: ReelSource.asset('assets/portrait_1080x1920.mp4'),
  ),
  DemoVideo(
    title: 'Jellyfish',
    author: '@test-videos',
    note: 'MP4, 10 s',
    source: ReelSource.network(
      'https://test-videos.co.uk/vids/jellyfish/mp4/h264/720/Jellyfish_720_10s_1MB.mp4',
    ),
  ),
  DemoVideo(
    title: 'Big Buck Bunny (HLS)',
    author: '@mux',
    note: 'Adaptive HLS stream',
    source: ReelSource.network(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    ),
  ),
  DemoVideo(
    title: 'Sintel',
    author: '@blender',
    note: 'MP4, 10 s',
    source: ReelSource.network(
      'https://test-videos.co.uk/vids/sintel/mp4/h264/1080/Sintel_1080_10s_5MB.mp4',
    ),
  ),
  DemoVideo(
    title: 'Friday',
    author: '@mdn',
    note: 'MP4, CC0',
    source: ReelSource.network(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/friday.mp4',
    ),
  ),
  DemoVideo(
    title: 'Bip bop',
    author: '@apple',
    note: 'HLS fMP4, several renditions',
    source: ReelSource.network(
      'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
    ),
  ),
  DemoVideo(
    title: 'Sample clip',
    author: '@samplelib',
    note: 'MP4 with its index at the end: slower start',
    source: ReelSource.network(
      'https://download.samplelib.com/mp4/sample-10s.mp4',
    ),
  ),
];
