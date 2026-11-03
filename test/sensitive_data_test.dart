import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/util/debug_request_log.dart';
import 'package:lume_box/core/util/lume_log.dart';
import 'package:lume_box/core/util/sensitive_data.dart';
import 'package:lume_box/features/settings/diagnostic_exporter.dart';

void main() {
  test('运行日志入库及堆栈先脱敏，覆盖签名、自定义token、账号与URL参数', () {
    LumeLog.clear();
    addTearDown(LumeLog.clear);
    const raw =
        'GET https://account-name:password-value@source.example/search?key=query-secret#fragment-secret\n'
        'x-gaze-proof: gaze-secret\nx-source-sign: sign-secret\nCookie: cookie-secret\n'
        'username: user-secret\nAuthorization: Bearer bearer-secret\naccess_token=token-secret';
    LumeLog.error(
      StateError(raw),
      StackTrace.fromString('signature=stack-secret'),
    );
    final record = LumeLog.snapshot.single;
    final text = '${record.message}\n${record.detail}';
    for (final secret in [
      'account-name',
      'password-value',
      'query-secret',
      'fragment-secret',
      'gaze-secret',
      'sign-secret',
      'cookie-secret',
      'user-secret',
      'bearer-secret',
      'token-secret',
      'stack-secret',
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
    expect(text, contains('source.example/search'));
  });

  test('抓包缓存二次防护，调用者未主动脱敏也不保存凭据', () {
    DebugRequestLog.setEnabled(true);
    addTearDown(DebugRequestLog.resetForTesting);
    DebugRequestLog.record(
      DebugRequestRecord(
        time: DateTime(2026),
        method: 'GET',
        url: 'https://user:pass@site.example/api?token=private-query',
        source: 'source-a',
        host: 'site.example',
        status: 403,
        elapsed: Duration.zero,
        requestHeaders: {
          'x-source-sign': 'private-sign',
          'x-gaze-proof': 'private-proof',
          'Accept': 'application/json',
        },
        error: 'session=private-session',
        note: 'token=private-note',
      ),
    );
    final record = DebugRequestLog.snapshot.single;
    final text =
        '${record.url} ${record.requestHeaders} ${record.error} ${record.note}';
    for (final secret in [
      'user:pass',
      'private-query',
      'private-sign',
      'private-proof',
      'private-session',
      'private-note',
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
    expect(record.requestHeaders['Accept'], 'application/json');
    expect(
      SensitiveData.redact('HTTP 403 signature rejected'),
      contains('HTTP 403'),
    );
  });

  test('导出结构化元数据中的动态签名也隐藏', () {
    final value = DiagnosticExporter.sanitize({
      'x-gaze-proof': 'private-proof',
      'signature': 'private-signature',
      'status': 403,
    });
    expect('$value', isNot(contains('private-')));
    expect((value as Map)['status'], 403);
  });
}
