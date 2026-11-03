import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/shared/widgets/source_category_columns.dart';

void main() {
  testWidgets(
    'active final source opens at the top of its lane; manual scroll and rebuild do not relocate it',
    (tester) async {
      final selected = GlobalKey();
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SourceCategoryColumns(
                  initialSectionId: '1',
                  initialChildIndex: 59,
                  focusKey: selected,
                  sections: [
                    for (var lane = 0; lane < 2; lane++)
                      SourceColumnSection(
                        id: '$lane',
                        title: '分类$lane',
                        children: [
                          for (var row = 0; row < 60; row++)
                            SizedBox(
                              key: lane == 1 && row == 59 ? selected : null,
                              height: 50,
                              child: Text('源$lane-$row'),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final right = find.byKey(const PageStorageKey('picker-column-1'));
      ScrollPosition position(int lane) => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(PageStorageKey('picker-column-$lane')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(find.byKey(selected), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(selected)).dy,
        closeTo(tester.getTopLeft(right).dy, 1),
      );
      expect(position(0).pixels, 0);
      expect(position(1).pixels, greaterThan(3000));
      position(1).jumpTo(0);
      await tester.pumpAndSettle();
      rebuild(() {});
      await tester.pumpAndSettle();
      expect(position(1).pixels, 0);
      expect(find.text('源1-0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('two physical category lanes scroll independently at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SourceCategoryColumns(
            sections: [
              for (var group = 0; group < 2; group++)
                SourceColumnSection(
                  id: '$group',
                  title: '分类$group',
                  children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(height: 48, child: Text('源$group-$i')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('picker-category-columns')))
          .dx,
      14,
    );
    final left = find.byKey(const PageStorageKey('picker-column-0'));
    final right = find.byKey(const PageStorageKey('picker-column-1'));
    ScrollPosition position(Finder lane) => tester
        .state<ScrollableState>(
          find.descendant(of: lane, matching: find.byType(Scrollable)),
        )
        .position;
    final rightTop = tester.getTopLeft(find.text('源1-0'));
    final headerTop = tester.getTopLeft(find.text('分类0'));
    await tester.drag(left, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(position(left).pixels, greaterThan(100));
    expect(position(right).pixels, 0);
    expect(tester.getTopLeft(find.text('源1-0')), rightTop);
    expect(tester.getTopLeft(find.text('分类0')), headerTop);
    expect(find.byType(GridView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
