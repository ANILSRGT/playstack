import 'dart:io';
import 'dart:typed_data';

/// A tiny HTTP server for one media file with byte-range support, so tests
/// can exercise network sources, caching and retries without the internet.
class MediaServer {
  MediaServer._(this._server, this.bytes);

  static Future<MediaServer> start(Uint8List bytes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final media = MediaServer._(server, bytes);
    server.listen(media._handle);
    return media;
  }

  final HttpServer _server;
  final Uint8List bytes;

  /// Requests answered with HTTP 503 before serving normally.
  int failNextRequests = 0;

  /// Whether requests are refused (simulates going offline).
  bool offline = false;

  int requests = 0;

  Uri url(String name) => Uri.parse('http://127.0.0.1:${_server.port}/$name');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final response = request.response;
    if (offline) {
      await request.response.detachSocket().then((socket) => socket.destroy());
      return;
    }
    if (failNextRequests > 0) {
      failNextRequests--;
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }
    var start = 0;
    var end = bytes.length - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    response.headers
      ..contentType = ContentType('video', 'mp4')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      start = int.parse(parts[0]);
      if (parts.length > 1 && parts[1].isNotEmpty) {
        end = int.parse(parts[1]).clamp(start, bytes.length - 1);
      }
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${bytes.length}',
        );
    }
    response.contentLength = end - start + 1;
    if (request.method != 'HEAD') response.add(bytes.sublist(start, end + 1));
    await response.close();
  }
}
