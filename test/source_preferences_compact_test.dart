import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/source/source_extension_settings.dart';
import 'package:lume_box/core/source/source_preferences.dart';
import 'package:lume_box/features/source/source_preferences_page.dart';
import 'package:lume_box/features/source/source_action_dialogs.dart';
import 'package:lume_box/features/source/source_extension_editor.dart';

import 'support/fake_source_manager.dart';

void main() {
  testWidgets('首页直接编辑站点并一次保存，滚到页底后仍保留输入且没有重复入口', (tester) async {
    final root = Directory.systemTemp.createTempSync('compact-source-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    await tester.runAsync(() => ReadingLibrary.open(Section.video));
    addTearDown(() async {
      ReadingLibrary.disposeAll();
      ReadingStore.disposeAll();
      await SectionScope.closeAll();
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      root.deleteSync(recursive: true);
    });
    const source = SourceDescriptor(
      id: 'compact',
      name: '测试源',
      version: '1',
      enabled: true,
      section: Section.video,
      siteUrl: 'https://old.example',
      siteConfig: SourceSiteConfig(
        mirrors: ['https://old.example'],
        account: 'fixture-user',
        password: 'fixture-password',
        settingDefinitions: [
          SourceSetting(
            key: 'more',
            title: '额外开关',
            type: 'toggle',
            defaultValue: false,
          ),
        ],
      ),
    );
    final manager = FakeSourceManager(sources: [source]);
    await tester.pumpWidget(
      MaterialApp(
        home: SourcePreferencesPage(
          section: Section.video,
          sourceId: source.id,
          name: source.name,
          descriptor: source,
          siteUrl: source.siteUrl,
          manager: manager,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('源设置（站点 / 图床 / 视频 CDN / 参数）'), findsNothing);
    expect(find.text('打开当前站点'), findsNothing);
    expect(find.text('打开站点网页登录 / 检查状态'), findsNothing);
    expect(find.text('站点账号'), findsOneWidget);
    expect(find.text('站点账号登录'), findsNothing);
    expect(find.text('登录站点'), findsOneWidget);
    expect(find.textContaining('检查登录'), findsNothing);
    expect(find.text('账号与密码'), findsNothing);
    expect(
      find.byKey(const ValueKey('source-account-web-login')),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, '账号'), findsNothing);
    expect(find.text('账号密码（可选）'), findsNothing);
    expect(find.text('此源只提供主站，暂无备用镜像。'), findsOneWidget);
    final domain = find.widgetWithText(TextField, '自定义域名（填了优先）');
    await tester.ensureVisible(domain);
    await tester.enterText(domain, 'https://new.example');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-extensions-entry')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('source-extensions-entry')),
    );
    final common = find.byType(SourceExtensionEditor).first;
    expect(tester.getSize(common).height, lessThanOrEqualTo(60));
    await tester.tap(find.byKey(const ValueKey('source-extensions-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '额外开关'));
    await tester.pumpAndSettle();
    expect(manager.siteConfigs, isEmpty, reason: '扩展页改动在源设置统一保存');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('恢复默认源设置'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('清理此源的浏览缓存'), findsOneWidget);
    expect(find.text('清理源浏览缓存'), findsNothing);
    await tester.tap(find.text('保存'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    expect(manager.siteConfigs, hasLength(1));
    expect(manager.siteConfigs.single.$2.resolvedDomain, 'https://new.example');
    expect(manager.siteConfigs.single.$2.resolvedSettings['more'], isTrue);
    expect(manager.siteConfigs.single.$2.account, 'fixture-user');
    expect(manager.siteConfigs.single.$2.password, 'fixture-password');
    expect(manager.networks, hasLength(1));
    expect(
      SourcePreferences.read(Section.video, source.id).customOrigin,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('镜像可切换，自定义地址优先；无扩展的源也能找到说明', (tester) async {
    final editor = GlobalKey<SourceNetworkDialogState>();
    const source = SourceDescriptor(
      id: 'mirror-fixture',
      name: '测试源',
      version: '1',
      enabled: true,
      section: Section.video,
      siteUrl: 'https://main.example',
      siteConfig: SourceSiteConfig(
        mirrors: ['https://main.example', 'https://backup.example'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceNetworkDialog(
              key: editor,
              source: source,
              embedded: true,
            ),
          ),
        ),
      ),
    );
    final dropdown = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('backup.example').last);
    await tester.pumpAndSettle();
    expect(
      editor.currentState!.readResult()!.site.resolvedDomain,
      'https://backup.example',
    );
    final domain = find.widgetWithText(TextField, '自定义域名（填了优先）');
    await tester.enterText(domain, 'https://custom.example');
    expect(
      editor.currentState!.readResult()!.site.resolvedDomain,
      'https://custom.example',
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('主站 · main.example').last);
    await tester.pumpAndSettle();
    expect(
      editor.currentState!.readResult()!.site.resolvedDomain,
      'https://custom.example',
    );
    await tester.enterText(domain, '');
    expect(
      editor.currentState!.readResult()!.site.resolvedDomain,
      'https://main.example',
    );
    final imageRoute = find.widgetWithText(ExpansionTile, '图床 · 默认线路');
    await tester.ensureVisible(imageRoute);
    expect(tester.getSize(imageRoute).height, lessThanOrEqualTo(60));
    await tester.tap(imageRoute);
    await tester.pumpAndSettle();
    final imageDomain = find.widgetWithText(TextFormField, '自定义图床地址（填了优先）');
    await tester.ensureVisible(imageDomain);
    await tester.enterText(imageDomain, 'https://images.example');
    await tester.pumpAndSettle();
    final customRoute = find.widgetWithText(ExpansionTile, '图床 · 自定义地址');
    await tester.ensureVisible(customRoute);
    await tester.tap(customRoute);
    await tester.pumpAndSettle();
    expect(
      editor.currentState!.readResult()!.site.images.resolved,
      'https://images.example',
    );
    final entry = find.byKey(const ValueKey('source-extensions-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.textContaining('此源暂无扩展功能'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
