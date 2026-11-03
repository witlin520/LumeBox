import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/browse_layout.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/features/reading/history_sheet.dart';
import 'package:lume_box/features/reading/poster_card.dart';

void main() {
  tearDown(BrowseLayoutSettings.instance.resetForTesting);
  for (final history in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        '${history ? '历史收藏' : '浏览搜索'}遮罩长标题保持单行与底部8，辅助信息不挤动标题 $scale',
        (tester) async {
          await BrowseLayoutSettings.instance.setGridTitleStyle(
            GridTitleStyle.overlay,
          );
          const title = '这是很长的标题用于验证单行省略与全局位置一致';
          final item = LibraryItem(
            section: Section.comic,
            itemId: 'one',
            sourceId: 'test',
            title: title,
            chapterCount: 2,
            readChapterIndex: -1,
            addedAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 110,
                      height: 190,
                      child: history
                          ? HistoryGridTile(
                              item: item,
                              progress: null,
                              pipeline: null,
                              onTap: () {},
                            )
                          : PosterTile(
                              item: const SourceItem(id: 'one', title: title),
                              meta: '播放来源',
                              onTap: () {},
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final text = tester.widget<Text>(find.text(title));
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          expect(text.style!.fontSize, 13);
          expect(text.style!.color, Colors.white);
          final card = tester.getRect(find.byType(PosterCard));
          final titleRect = tester.getRect(find.text(title));
          expect(titleRect.left - card.left, closeTo(8, .1));
          expect(card.bottom - titleRect.bottom, closeTo(8, .1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
