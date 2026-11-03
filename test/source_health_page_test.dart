import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/source_section_page.dart';

import 'support/fake_source_manager.dart';

const demo = SourceDescriptor(
  id: 'demo',
  name: '待检查源',
  version: '2',
  enabled: true,
);

class RevisionManager extends FakeSourceManager
    implements SourceRevisionManager {
  RevisionManager()
    : super(
        sources: [demo],
        opened: {'demo': const MockDataSource(section: Section.video)},
      );
  final restored = <String>[];
  @override
  Future<SourceRevisionInfo?> previousVersion(String sourceId) async =>
      SourceRevisionInfo(version: '1', savedAt: DateTime(2026, 10, 21));
  @override
  Future<SourceImportResult> restorePreviousVersion(String sourceId) async {
    restored.add(sourceId);
    return const SourceImportResult.success(demo);
  }
}

void main() {
  Future<void> openMenu(
    WidgetTester tester,
    RevisionManager manager,
    String action,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: LumeTheme.build(),
        home: SourceSectionPage(section: Section.video, manager: manager),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('站点维护'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('待检查源'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('源管理体检入口实际打开逐项结果，且不改变源选择', (tester) async {
    final manager = RevisionManager();
    await openMenu(tester, manager, '一键源体检');
    expect(find.text('源体检'), findsOneWidget);
    expect(find.text('检查结束，请查看每项结果。'), findsOneWidget);
    expect(find.text('分类接口'), findsOneWidget);
    expect(find.text('重新体检'), findsOneWidget);
    expect(manager.selectedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('恢复前能核对版本，取消不改脚本', (tester) async {
    final manager = RevisionManager();
    await openMenu(tester, manager, '恢复上一版源');
    expect(find.textContaining('当前版本：2'), findsOneWidget);
    expect(find.textContaining('恢复版本：1'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(manager.restored, isEmpty);
  });
  testWidgets('确认恢复调用对应源并给出重新打开提示', (tester) async {
    final manager = RevisionManager();
    await openMenu(tester, manager, '恢复上一版源');
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    expect(manager.restored, ['demo']);
    expect(find.text('已恢复上一版，请重新打开源或进行体检。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
