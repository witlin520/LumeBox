import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/chapter_display_order.dart';
import 'package:lume_box/core/source/source.dart';

void main() {
  test('recognizes real chapter numbers across common naming conventions', () {
    for (final pair in <String, double>{
      '第十二章': 12,
      '第两百零三话': 203,
      '第一千零二章': 1002,
      '第一万零一章': 10001,
      '第一〇二回': 102,
      '第１２章': 12,
      'Chapter 10.5': 10.5,
      '003 开始': 3,
      '第廿三話': 23,
    }.entries) {
      expect(
        ChapterDisplayOrder.chapterNumber(pair.key),
        pair.value,
        reason: pair.key,
      );
    }
    expect(ChapterDisplayOrder.chapterNumber('番外'), null);
  });
  test(
    'sorts indexes only, preserves unknown slots, duplicate order and volumes',
    () {
      List<SourceChapter> chapters(List<String> titles) => [
        for (var i = 0; i < titles.length; i++)
          SourceChapter(id: 'id-$i', title: titles[i]),
      ];
      final original = chapters(['第三章', '序言', '第一章', '第二章', '第二章']);
      final ids = original.map((c) => c.id).toList();
      expect(ChapterDisplayOrder.correctedIndexes(original), [2, 1, 3, 4, 0]);
      expect(original.map((c) => c.id), ids);
      expect(
        ChapterDisplayOrder.correctedIndexes(
          chapters(['第一卷', '第二章', '第一章', '第二卷', '第三章', '第一章']),
        ),
        [0, 2, 1, 3, 5, 4],
      );
      expect(
        ChapterDisplayOrder.correctedIndexes(
          chapters(['第二卷 第一章', '第一卷 第二章', '第一卷 第一章']),
        ),
        [2, 1, 0],
      );
    },
  );
}
