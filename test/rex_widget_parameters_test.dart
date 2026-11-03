import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/rex_widget_host.dart';
import 'package:lume_box/core/reading/reading_library.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/features/source/rex_widget_parameters.dart';

import 'js_sandbox/support/js_sandbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Widget 参数表单支持枚举、CSV、敏感输入与恢复默认', (tester) async {
    final root = Directory.systemTemp.createTempSync('rex_params');
    await installTempSectionRoot(root);
    addTearDown(() async {
      ReadingLibrary.disposeAll();
      await SectionScope.closeAll();
      root.deleteSync(recursive: true);
    });
    await tester.runAsync(
      () => RexWidgetSettings.saveDefinitions(Section.video, 'form', [
        {
          'name': 'kind',
          'title': '聚合开关',
          'type': 'enumeration',
          'enumOptions': [
            {'title': '启用', 'value': 'enabled'},
            {'title': '禁用', 'value': 'disabled'},
          ],
        },
        {
          'name': 'VodData',
          'title': 'CSV源列表',
          'type': 'input',
          'value': '源一,https://fixture.invalid/',
        },
        {'name': 'api_key', 'title': '接口密钥', 'type': 'input', 'value': ''},
      ]),
    );
    final key = GlobalKey<RexWidgetParametersState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RexWidgetParametersEditor(
              key: key,
              section: Section.video,
              sourceId: 'form',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Widget 参数'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isTrue,
    );
    await tester.enterText(
      find.byType(TextField).first,
      '源二,https://fixture.invalid/new',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁用').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() => key.currentState!.save());
    expect(
      RexWidgetSettings.parameters(Section.video, 'form')['kind'],
      'disabled',
    );
    expect(
      RexWidgetSettings.parameters(Section.video, 'form')['VodData'],
      '源二,https://fixture.invalid/new',
    );
    key.currentState!.reset();
    await tester.pumpAndSettle();
    await tester.runAsync(() => key.currentState!.save());
    expect(
      RexWidgetSettings.parameters(Section.video, 'form')['kind'],
      'enabled',
    );
    expect(
      RexWidgetSettings.parameters(Section.video, 'form')['VodData'],
      '源一,https://fixture.invalid/',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
