import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_extension_settings.dart';
import 'package:lume_box/core/source/source_settings_policy.dart';
import 'package:lume_box/features/source/source_action_dialogs.dart';

void main() {
  testWidgets('App 通用设置裁决冲突，动作参数校验、取消与保存互不影响', (tester) async {
    SourceSettingsResult? saved;
    Map<String, Object?>? inputs, values;
    final config = SourceSiteConfig(
      commonDefinitions: SourceSettingsPolicy.parseCommon([
        {'key': 'pageSize', 'default': 20},
      ]),
      settingDefinitions: SourceSetting.parseAll([
        {'key': 'pageSize', 'title': '源伪造数量', 'type': 'text'},
        {
          'key': 'refresh',
          'title': '更新索引',
          'type': 'action',
          'group': '索引维护',
          'inputs': [
            {'key': 'path', 'title': '目录', 'type': 'text', 'required': true},
            {
              'key': 'count',
              'title': '抽样数量',
              'type': 'number',
              'min': 1,
              'max': 5,
              'integer': true,
              'default': 2,
            },
          ],
        },
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('打开'),
              onPressed: () async {
                saved = await showDialog<SourceSettingsResult>(
                  context: context,
                  builder: (_) => SourceNetworkDialog(
                    source: SourceDescriptor(
                      id: 'test',
                      name: '测试',
                      version: '1',
                      enabled: true,
                      section: Section.video,
                      siteConfig: config,
                    ),
                    onSettingAction: (field, current, site, parameters) async {
                      inputs = parameters;
                      values = current;
                      return '完成';
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    Future<void> tap(Finder finder) async {
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tap(find.text('打开'));
    expect(find.text('源伪造数量'), findsNothing);
    final page = find.widgetWithText(TextFormField, '每页数量');
    await tester.ensureVisible(page);
    await tester.enterText(page, '42');
    await tap(find.text('更新索引'));
    await tap(find.widgetWithText(FilledButton, '执行'));
    expect(find.text('目录：此项必填'), findsOneWidget);
    expect(inputs, isNull);
    await tap(find.widgetWithText(TextButton, '取消').last);
    expect(inputs, isNull);
    await tap(find.text('更新索引'));
    await tester.enterText(
      find.widgetWithText(TextFormField, '目录'),
      '/catalog',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '抽样数量'), '9');
    await tap(find.widgetWithText(FilledButton, '执行'));
    expect(find.text('抽样数量：不能大于 5'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '抽样数量'), '3');
    await tap(find.widgetWithText(FilledButton, '执行'));
    expect(inputs, {'path': '/catalog', 'count': 3});
    expect(values?['pageSize'], 42);
    expect(saved, isNull);
    await tap(find.widgetWithText(FilledButton, '保存'));
    expect(saved?.site.appSettingValues['pageSize'], 42);
    expect(saved?.site.settingValues.containsKey('path'), false);
    expect(config.appSettingValues, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('多镜像、独立 CDN、自定义优先、专用设置和操作完整保存，取消不提交', (tester) async {
    SourceSettingsResult? saved;
    Map<String, Object?>? preview;
    final definitions = SourceSetting.parseAll([
      {'key': 'autoNext', 'type': 'toggle', 'title': '自动翻页'},
      {'key': 'limit', 'type': 'number', 'title': '每页数量', 'default': 20},
      {'key': 'refresh', 'type': 'action', 'title': '刷新分类', 'action': 'source'},
    ]);
    final config = SourceSiteConfig(
      mirrors: List.generate(5, (i) => 'https://m$i.example'),
      domainOverride: 'https://custom.example',
      images: SourceRoute.parse(['https://i1.example', 'https://i2.example']),
      video: SourceRoute.parse(['https://v1.example', 'https://v2.example']),
      settingDefinitions: definitions,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<SourceSettingsResult>(
                  context: context,
                  builder: (_) => SourceNetworkDialog(
                    source: SourceDescriptor(
                      id: 'test',
                      name: '测试源',
                      version: '1',
                      enabled: true,
                      section: Section.video,
                      siteConfig: config,
                    ),
                    onSettingAction: (field, values, site, inputs) async {
                      preview = {...values, 'domain': site.resolvedDomain};
                      return '分类已刷新';
                    },
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    Future<void> tap(Finder finder) async {
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tap(find.text('更多镜像（2）'));
    await tap(find.text('m4.example'));
    expect(find.text('当前生效：https://custom.example'), findsOneWidget);
    await tap(find.widgetWithText(DropdownButtonFormField<String>, '图床线路'));
    await tester.tap(find.text('https://i2.example').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, '自定义视频 CDN地址（填了优先）'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '自定义视频 CDN地址（填了优先）'),
      'https://custom-v.example',
    );
    tester.testTextInput.hide();
    await tap(find.widgetWithText(SwitchListTile, '自动翻页'));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(TextFormField, '每页数量'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '每页数量'), '30');
    await tap(find.text('刷新分类'));
    expect(preview?['autoNext'], true);
    expect(preview?['limit'], 30);
    expect(preview?['domain'], 'https://custom.example');
    expect(saved, isNull, reason: '执行预览操作不自动提交整个设置');
    await tap(find.widgetWithText(FilledButton, '保存'));
    expect(saved?.site.selectedMirror, 'https://m4.example');
    expect(saved?.site.resolvedDomain, 'https://custom.example');
    expect(saved?.site.images.resolved, 'https://i2.example');
    expect(saved?.site.video.resolved, 'https://custom-v.example');
    expect(saved?.site.resolvedSettings, {'autoNext': true, 'limit': 30});
    saved = null;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tap(find.widgetWithText(TextButton, '取消'));
    expect(saved, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('无效 CDN 与数字不保存，保留输入供修正', (tester) async {
    SourceSettingsResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<SourceSettingsResult>(
                  context: context,
                  builder: (_) => SourceNetworkDialog(
                    source: SourceDescriptor(
                      id: 'x',
                      name: 'X',
                      version: '1',
                      enabled: true,
                      siteConfig: SourceSiteConfig(
                        settingDefinitions: SourceSetting.parseAll([
                          {'key': 'n', 'type': 'number', 'title': '数量'},
                        ]),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final image = find.widgetWithText(TextFormField, '自定义图床地址（填了优先）');
    await tester.ensureVisible(image);
    await tester.enterText(image, 'javascript:bad');
    final number = find.widgetWithText(TextFormField, '数量');
    await tester.ensureVisible(number);
    await tester.enterText(number, 'oops');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('请填写有效的 HTTP(S) 图床地址'), findsOneWidget);
    expect(find.text('数量：请输入有效数字'), findsOneWidget);
  });
}
