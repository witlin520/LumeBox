import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/translation/ai_text_translation.dart';

http.Response reply(List<String> values) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': jsonEncode(values)},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<List<String>> translate(http.Client client, List<String> texts) =>
    AiTextTranslation.translate(
      client,
      texts,
      url: 'https://translation.test/v1/chat/completions',
      model: 'fixture',
      key: 'fixture-key',
      language: '简体中文',
      target: 'zh-Hans',
    );

List<String> inputs(http.Request request) => (jsonDecode(
  (jsonDecode(request.body)['messages'] as List).last['content'],
) as List).cast<String>();

void main() {
  test(
    'truncated batch recovers in smaller requests with original order',
    () async {
      final sizes = <int>[];
      final client = MockClient((request) async {
        final texts = inputs(request);
        sizes.add(texts.length);
        if (texts.length > 1) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'length',
                  'message': {'content': '["'},
                },
              ],
            }),
            200,
          );
        }
        return reply(['译${texts.single}']);
      });
      expect(await translate(client, ['Hello', 'World', 'Title']), [
        '译Hello',
        '译World',
        '译Title',
      ]);
      expect(sizes, [3, 1, 2, 1, 1]);
    },
  );

  test(
    'malformed batch recovers successes while a single entry fails',
    () async {
      final client = MockClient((request) async {
        final texts = inputs(request);
        if (texts.length > 1) return reply(['数量错误']);
        if (texts.single == 'World') return http.Response('unavailable', 503);
        return reply(['你好']);
      });
      await expectLater(
        translate(client, ['Hello', 'World']),
        throwsA(
          isA<PlatformException>().having((e) => e.details, 'retained', [
            '你好',
            '',
          ]),
        ),
      );
    },
  );

  test(
    'empty, truncated and rejected responses report a useful reason',
    () async {
      for (final entry in <(Map<String, Object?>, String)>[
        ({'choices': []}, '未返回译文'),
        (
          {
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': '["'},
              },
            ],
          },
          '截断',
        ),
        (
          {
            'choices': [
              {
                'message': {'refusal': 'unavailable', 'content': null},
              },
            ],
          },
          '未接受',
        ),
      ]) {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode(entry.$1),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        );
        await expectLater(
          translate(client, ['Foreign title']),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'reason',
              contains(entry.$2),
            ),
          ),
        );
      }
    },
  );
  test('large pages split into small requests and preserve order without a 100-title cutoff', () async {
    final batches = <List<String>>[];
    final client = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      final texts = inputs(request);
      batches.add(texts);
      return reply(texts.map((text) => '译$text').toList());
    });
    final texts = List.generate(122, (i) => 'Title $i');
    expect(
      await translate(client, texts),
      texts.map((text) => '译$text').toList(),
    );
    expect(batches, hasLength(7));
    expect(batches.every((batch) => batch.length <= 20), isTrue);
  });

  test(
    'unchanged foreign results retry once using only unresolved titles',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(
          inputs(request),
          calls == 1 ? ['Foreign title', 'Hello world'] : ['Foreign title'],
        );
        return reply(calls == 1 ? ['Foreign title', '你好世界'] : ['外文标题']);
      });
      expect(await translate(client, ['Foreign title', 'Hello world']), [
        '外文标题',
        '你好世界',
      ]);
      expect(calls, 2);
    },
  );

  test('failed batch retains other batches and a retry failure keeps first-pass successes', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 2) return http.Response('unavailable', 503);
      return reply(inputs(request).map((text) => '译$text').toList());
    });
    await expectLater(
      translate(client, List.generate(45, (i) => 'Title $i')),
      throwsA(
        isA<PlatformException>().having((error) => error.details, 'partial', [
          for (var i = 0; i < 45; i++) i >= 20 && i < 40 ? '' : '译Title $i',
        ]),
      ),
    );
    expect(calls, 3);
    calls = 0;
    final retryFailure = MockClient((request) async {
      calls++;
      return calls == 1
          ? reply(['已完成', 'Foreign title'])
          : http.Response('no', 503);
    });
    await expectLater(
      translate(retryFailure, ['Completed title', 'Foreign title']),
      throwsA(
        isA<PlatformException>().having((error) => error.details, 'retained', [
          '已完成',
          '',
        ]),
      ),
    );
    expect(calls, 2);
  });

  test('authentication failures stop the queue and permanently unchanged titles stop after one retry', () async {
    var calls = 0;
    final unauthorized = MockClient((_) async {
      calls++;
      return http.Response('private response must not be exposed', 401);
    });
    await expectLater(
      translate(unauthorized, List.generate(45, (i) => 'Title $i')),
      throwsFormatException,
    );
    expect(calls, 1);
    calls = 0;
    final unchanged = MockClient((request) async {
      calls++;
      return reply(inputs(request));
    });
    await expectLater(
      translate(unchanged, ['Foreign title']),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, 2);
  });
}
