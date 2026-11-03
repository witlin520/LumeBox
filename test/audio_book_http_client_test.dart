import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lume_box/core/audio_book/audio_book_http_client.dart';

void main() {
  test(
    'native audio transport preserves source headers, ranges and streaming',
    () async {
      final native = _NativeClient();
      final client = AudioBookHttpClient(client: native, closeClient: false);
      final outgoing =
          http.Request('GET', Uri.parse('https://audio.example/one.mp3'))
            ..followRedirects = false
            ..headers.addAll({
              'User-Agent': 'source-browser-agent',
              'Referer': 'https://source.example/chapter/1',
              'Range': 'bytes=100-199',
            });
      final response = await client.send(outgoing);
      expect(native.request.headers['User-Agent'], 'source-browser-agent');
      expect(
        native.request.headers['Referer'],
        'https://source.example/chapter/1',
      );
      expect(native.request.headers['Range'], 'bytes=100-199');
      expect(native.request.followRedirects, false);
      expect(response.statusCode, 206);
      final chunks = <List<int>>[];
      final subscription = response.stream.listen(chunks.add);
      native.bytes.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      expect(chunks, [
        [1, 2],
      ]);
      native.bytes.add([3, 4]);
    final done = subscription.asFuture<void>();
      await native.bytes.close();
    await done;
      client.close();
      await (native.request as http.Abortable).abortTrigger;
      expect(
        native.closed,
        false,
        reason: 'Other tracks still share the native session',
      );
      await expectLater(
        client.send(outgoing),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('owned non-native clients are closed with the request', () {
    final native = _NativeClient();
    final client = AudioBookHttpClient(client: native, closeClient: true);
    client.close();
    expect(native.closed, true);
  });
}

class _NativeClient extends http.BaseClient {
  late http.BaseRequest request;
  final bytes = StreamController<List<int>>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest value) async {
    request = value;
    return http.StreamedResponse(bytes.stream, 206);
  }

  @override
  void close() => closed = true;
}
