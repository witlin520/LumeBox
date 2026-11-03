import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/browse_layout.dart';
import 'package:lume_box/core/theme/interface_typography.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/compact_browse_header.dart';
import 'package:lume_box/features/reading/poster_card.dart';
import 'package:lume_box/shared/widgets/source_switch_button.dart';
import 'package:lume_box/shared/widgets/column_list.dart';

void main() {
  testWidgets('应用字号100到160仅放大文字，顶栏、封面和网格位置保持一致', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rectangles = <List<Rect>>[];
    final fontSizes = <double>[];
    for (final factor in [1.0, 1.6]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: InterfaceTextScaler(TextScaler.noScaling, factor),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  CompactBrowseHeader(
                    source: SourceSwitchButton(
                      name: '瓜子影视',
                      onPressed: () {},
                      iconSlot: 'test',
                      compact: true,
                    ),
                    actions: [
                      TextButton(onPressed: () {}, child: const Text('历史')),
                      TextButton(onPressed: () {}, child: const Text('收藏')),
                    ],
                    mode: BrowseLayoutMode.grid3,
                    onLayoutChanged: (_) {},
                  ),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 8,
                            childAspectRatio: .62,
                          ),
                      itemCount: 6,
                      itemBuilder: (_, i) => PosterTile(
                        item: SourceItem(id: '$i', title: '作品$i'),
                        onTap: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      rectangles.add([
        tester.getRect(find.byType(CompactBrowseHeader)),
        tester.getRect(find.byType(SourceSwitchButton)),
        tester.getRect(find.widgetWithText(TextButton, '历史')),
        tester.getRect(find.byType(PosterCard).first),
        tester.getRect(find.byType(CoverThumb).first),
        tester.getRect(find.byType(PosterCard).at(3)),
      ]);
      final paragraph = tester.renderObject<RenderParagraph>(find.text('作品0'));
      fontSizes.add(paragraph.textScaler.scale(13));
      expect(tester.takeException(), isNull);
    }
    expect(rectangles[1], rectangles[0]);
    expect(fontSizes[1], closeTo(fontSizes[0] * 1.6, .001));
  });

  testWidgets('双列列表不会按应用字号拉高单元格', (tester) async {
    final sizes = <Size>[];
    for (final factor in [1.0, 1.6]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: InterfaceTextScaler(TextScaler.noScaling, factor),
            ),
            child: Scaffold(
              body: ColumnList(
                columns: 2,
                itemCount: 2,
                itemBuilder: (_, i) => SizedBox(
                  key: ValueKey('cell$i'),
                  child: const Text('列表标题'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      sizes.add(tester.getSize(find.byKey(const ValueKey('cell0'))));
    }
    expect(sizes[1], sizes[0]);
  });
}
