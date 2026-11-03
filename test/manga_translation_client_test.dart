import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:lume_box/core/reading/manga_translation_client.dart';

void main() {
  final png = Uint8List.fromList(
    image.encodePng(image.Image(width: 2, height: 3)),
  );
  test('manga-image-translator 表单、中文目标与 manga-ocr 模型发往真实接口形状', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://manga.test/base/translate/with-form/image',
      );
      expect(request.method, 'POST');
      final body = latin1.decode(request.bodyBytes);
      expect(body, contains('name="image"; filename="page.png"'));
      expect(body, contains('"ocr":"mocr"'));
      expect(body, contains('"target_lang":"CHS"'));
      expect(body, contains('"translator":"chatgpt"'));
      expect(request.headers.containsKey('authorization'), false);
      return http.Response.bytes(png, 200);
    });
    addTearDown(client.close);
    final result = await MangaTranslationClient.translate(
      client,
      png,
      url: 'https://manga.test/base/',
      target: 'zh-Hans',
      ocr: 'mocr',
    );
    expect(result, png);
    expect(image.decodePng(result)!.height, 3);
  });

  test('错误接口、伪图片与 HTTP 错误不会当成翻译图片', () async {
    expect(
      () => MangaTranslationClient.endpoint('file:///private/image'),
      throwsFormatException,
    );
    for (final response in [
      http.Response('not an image', 200),
      http.Response('server unavailable', 502),
    ]) {
      final client = MockClient((_) async => response);
      await expectLater(
        MangaTranslationClient.translate(
          client,
          png,
          url: 'http://192.168.1.5:5003',
          target: 'zh-Hans',
        ),
        throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
      );
      client.close();
    }
  });

  test(
    'authenticated servers receive their own token and reject plain HTTP',
    () async {
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer server-only-token');
        expect(request.followRedirects, isFalse);
        return http.Response.bytes(png, 200);
      });
      addTearDown(client.close);
      await MangaTranslationClient.translate(
        client,
        png,
        url: 'https://worker.test',
        target: 'zh-Hans',
        bearerToken: 'server-only-token',
      );
      await expectLater(
        MangaTranslationClient.translate(
          client,
          png,
          url: 'http://worker.test',
          target: 'zh-Hans',
          bearerToken: 'server-only-token',
        ),
        throwsFormatException,
      );
    },
  );
}
