import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/translation_connection_config.dart';

void main() {
  final config = {
    'format': 'lumebox.translation-connection',
    'version': 1,
    'endpoint': 'https://private.test/v1/chat/completions',
    'model': 'lumebox-translation',
    'apiKey': 'private-example-key',
    'target': 'zh-Hans',
  };
  test('connection files retain endpoint, model and private key without requiring manual input', () {
    final value = TranslationConnectionConfig.parse(jsonEncode(config));
    expect(value.model, 'lumebox-translation');
    expect(value.apiKey, 'private-example-key');
    expect(value.target, 'zh-Hans');
  });
  test(
    'foreign JSON, insecure endpoints and header-injection keys are rejected',
    () {
      for (final value in [
        {},
        {...config, 'endpoint': 'http://private.test'},
        {...config, 'apiKey': 'key\r\nInjected: value'},
        {...config, 'target': 'invalid'},
      ]) {
        expect(
          () => TranslationConnectionConfig.parse(jsonEncode(value)),
          throwsFormatException,
        );
      }
    },
  );
}
