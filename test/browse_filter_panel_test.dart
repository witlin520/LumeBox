import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/features/reading/browse_choice_access.dart';

void main() {
  testWidgets('一个入口统一分类和两组筛选，应用前不提交', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ({String? category, Map<String, String> filters})? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () async {
                result = await showBrowseFilters(
                  context: context,
                  categories: const [SourceCategory(id: 'movie', title: '电影')],
                  groups: const [
                    SourceFilterGroup(
                      id: 'area',
                      title: '地区',
                      options: [SourceFilterOption(id: 'cn', title: '大陆')],
                    ),
                    SourceFilterGroup(
                      id: 'year',
                      title: '年份',
                      options: [SourceFilterOption(id: '2026', title: '2026')],
                    ),
                  ],
                  category: null,
                  filters: const {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final frame = tester.getRect(
      find.byKey(const Key('classification-drawer-frame')),
    );
    final background = tester.getRect(
      find.byKey(const Key('filter-content-background')),
    );
    expect(
      background.bottom,
      frame.bottom,
      reason: 'Drawer background must cover footer and bottom safe area',
    );
    final apply = find.widgetWithText(FilledButton, '应用筛选');
    expect(
      (tester.getCenter(find.text('应用筛选')).dy - tester.getCenter(apply).dy)
          .abs(),
      lessThan(3),
    );
    await tester.tap(find.text('电影'));
    await tester.tap(find.text('大陆'));
    await tester.tap(find.text('2026'));
    await tester.pump();
    expect(result, isNull);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(result?.category, 'movie');
    expect(result?.filters, {'area': 'cn', 'year': '2026'});
    expect(tester.takeException(), isNull);
  });
}
