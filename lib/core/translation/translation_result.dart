final _foreignText = RegExp(
  r'[A-Za-z]{3,}|[\u3040-\u30ff\uac00-\ud7af\u0400-\u052f\u0600-\u06ff\u0900-\u097f\u0e00-\u0e7f]',
);

/// Returning a foreign title unchanged does not complete a Chinese translation.
bool unresolvedTranslation(String original, String value, String target) =>
    target.toLowerCase().split('-').first == 'zh' &&
    original.trim() == value.trim() &&
    _foreignText.hasMatch(original);
