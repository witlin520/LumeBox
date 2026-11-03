import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lume_box/core/speech/speech_advanced.dart';
import 'package:lume_box/core/speech/speech_cloud.dart';
import 'package:lume_box/core/speech/speech_settings.dart';
import 'package:lume_box/core/speech/speech_segments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failure in ['network', 'invalid SSML', 'rewritten text']) {
    test(
      'AI $failure automatically falls back to plain TTS without failed event',
      () async {
        final config = SpeechCloudConfig();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => '.cache/speech-unit-config',
            );
        final finished = Completer<void>();
        final methods = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('lumebox/speech'), (
              call,
            ) async {
              methods.add(call.method);
              if (call.method == 'speechGetKey') {
                return jsonEncode({
                  'endpoint': (call.arguments as Map)['kind'] == 'llm'
                      ? 'https://llm.example/v1'
                      : 'https://tts.example/v1',
                  'key': 'unit-only',
                });
              }
              if (call.method == 'streamFinish') finished.complete();
              return null;
            });
        await config.load();
        config.ttsUrl = 'https://tts.example/v1';
        config.ttsModel = 'user-tts';
        config.llmUrl = 'https://llm.example/v1';
        config.llmModel = 'user-llm';
        var llmCalls = 0, ttsCalls = 0;
        final source = AdvancedSpeechSource(
          const MethodChannel('lumebox/speech'),
          config: config,
          clientFactory: (config) => SpeechCloudClient(
            config,
            client: MockClient((request) async {
              if (request.url.host == 'llm.example') {
                llmCalls++;
                expect(
                  jsonDecode(request.body)['messages'][1]['content'],
                  '妹妹：你好！\n旁白：结束。',
                );
                if (failure == 'network') throw http.ClientException('offline');
                return http.Response(
                  jsonEncode({
                    'choices': [
                      {
                        'message': {
                          'content': failure == 'invalid SSML'
                              ? 'bad'
                              : '<speak>总结</speak>',
                        },
                      },
                    ],
                  }),
                  200,
                );
              }
              ttsCalls++;
              expect(
                jsonDecode(request.body)['input'],
                isNot(contains('<speak>')),
              );
              return http.Response.bytes([0, 0, 1, 0], 200);
            }),
          ),
        );
        const chapter = '妹妹：你好！\n旁白：结束。';
        source.prepare([const SpeechSegment(text: chapter, start: 0)]);
        await source.speak(
          const SpeechSegment(text: chapter, start: 0),
          const SpeechSettings(mode: SpeechMode.cloudAi, autoDialogue: true),
        );
        await finished.future.timeout(const Duration(seconds: 2));
        expect(llmCalls, 1);
        expect(ttsCalls, 2);
        expect(methods, contains('streamPCM'));
        expect(methods, contains('streamMark'));
        expect(methods, isNot(contains('streamFail')));
        source.cancel();
      },
    );
  }
}
