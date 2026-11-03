/// Character error rate against a manually checked transcription, not a model
/// confidence score. Whitespace is ignored; punctuation and case are retained.
class OcrEvaluation {
  const OcrEvaluation(this.errors, this.referenceCharacters);
  final int errors, referenceCharacters;
  double get errorRate => errors / referenceCharacters;
  String get summary =>
      '字符错误率 ${(errorRate * 100).toStringAsFixed(1)}%（$errors 处编辑 / $referenceCharacters 字，忽略空白）';

  static OcrEvaluation compare(String reference, String recognized) {
    List<int> normalize(String value) =>
        value.replaceAll(RegExp(r'\s+'), '').runes.toList();
    final expected = normalize(reference), actual = normalize(recognized);
    if (expected.isEmpty) throw const FormatException('请先填写人工核对的原文');
    if (expected.length > 2000 || actual.length > 2000) {
      throw const FormatException('请选取不超过 2000 字的样本进行质量检查');
    }
    var row = List<int>.generate(actual.length + 1, (i) => i);
    for (var i = 0; i < expected.length; i++) {
      final next = List<int>.filled(actual.length + 1, i + 1);
      for (var j = 0; j < actual.length; j++) {
        final replace = row[j] + (expected[i] == actual[j] ? 0 : 1);
        final insert = next[j] + 1;
        final remove = row[j + 1] + 1;
        next[j + 1] = replace < insert
            ? (replace < remove ? replace : remove)
            : (insert < remove ? insert : remove);
      }
      row = next;
    }
    return OcrEvaluation(row.last, expected.length);
  }
}
