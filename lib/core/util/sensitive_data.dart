/// Redaction at log ingestion, before console output, buffering or export.
class SensitiveData {
  static bool isSecretKey(String key) => RegExp(
    r'cookie|authorization|token|password|passwd|username|account|secret|credential|session|signature|(?:^|[-_])sign(?:$|[-_])|api[-_]?key|x-gaze-|账号|密码|密钥',
    caseSensitive: false,
  ).hasMatch(key);

  static String redact(String input) {
    var text = input.replaceAllMapped(
      RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false),
      (match) {
        try {
          final uri = Uri.parse(match[0]!);
          return uri
              .replace(
                userInfo: '',
                query: uri.hasQuery ? '[hidden]' : null,
                fragment: uri.hasFragment ? '[hidden]' : null,
              )
              .toString();
        } catch (_) {
          return '[URL hidden]';
        }
      },
    );
    text = text.replaceAll(
      RegExp(
        r'''(?:[\w-]*(?:cookie|authorization|token|password|passwd|username|account|secret|credential|session|sign|api[-_]?key|x-gaze-)[\w-]*|账号|密码|密钥)\s*["']?\s*[:=]\s*[^\r\n]+''',
        caseSensitive: false,
      ),
      '[credential hidden]',
    );
    return text.replaceAll(
      RegExp(r'\bBearer\s+[^\s,}]+', caseSensitive: false),
      'Bearer [hidden]',
    );
  }
}
