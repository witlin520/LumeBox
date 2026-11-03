import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/ocr_evaluation.dart';

void main() {
  test('人工对照统计替换、插入、删除，空白与换行不计入错误', () {
    expect(OcrEvaluation.compare('你好\n世界', '你好 世界').errors, 0);
    final changed = OcrEvaluation.compare('你好世界', '你号世');
    expect(changed.errors, 2);
    expect(changed.errorRate, .5);
    expect(OcrEvaluation.compare('AB', 'AxyzB').errors, 3);
    expect(OcrEvaluation.compare('你好😀', '你好😀').referenceCharacters, 3);
  });
  test('无人工原文或样本过大时不伪造准确率', () {
    expect(() => OcrEvaluation.compare(' \n', '识别结果'), throwsFormatException);
    expect(() => OcrEvaluation.compare('字' * 2001, '字'), throwsFormatException);
  });
}
