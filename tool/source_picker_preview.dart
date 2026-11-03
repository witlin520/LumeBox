import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lume_box/core/session/privacy_settings.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/source_picker_sheet.dart';

import '../test/support/fake_source_manager.dart';

const _logos = [
  'https://github.githubassets.com/favicons/favicon.png',
  'https://www.gstatic.com/youtube/img/branding/favicon/favicon_144x144.png',
];

/// Live preview of the production source-picker drawer at phone width.
///
/// Run: `flutter run -d windows -t tool/source_picker_preview.dart`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the preview's adult-content switch out of the real app settings.
  final sandbox = Directory.systemTemp.createTempSync(
    'lume_box_picker_preview',
  );
  await PrivacySettings.instance.boot(directory: sandbox);
  await PrivacySettings.instance.setShowAdult(true);
  runApp(const SourcePickerPreview());
}

class SourcePickerPreview extends StatefulWidget {
  const SourcePickerPreview({super.key});
  @override
  State<SourcePickerPreview> createState() => _SourcePickerPreviewState();
}

class _SourcePickerPreviewState extends State<SourcePickerPreview> {
  bool dark = false;
  int revision = 0;

  List<SourceDescriptor> get sources => [
    const SourceDescriptor(
      id: 'preview-adult',
      name: '成人内容示例源',
      version: '1.0.0',
      enabled: true,
    ),
    for (var i = 0; i < 6; i++)
      SourceDescriptor(
        id: 'preview-comic-$i',
        name: i.isEven ? '漫画示例源 ${i + 1}' : '一个比较长的漫画站点名称 ${i + 1}',
        version: '1.0.0',
        enabled: true,
        group: '漫画',
        iconUrl: _logos[i % _logos.length],
      ),
    for (var i = 0; i < 6; i++)
      SourceDescriptor(
        id: 'preview-photo-$i',
        name: i.isEven ? '美图示例源 ${i + 1}' : '一个比较长的美图站点名称 ${i + 1}',
        version: '1.0.0',
        enabled: true,
        group: '美图',
        iconUrl: _logos[i % _logos.length],
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = sources;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      theme: LumeTheme.build(
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Scaffold(
        backgroundColor: LumeTheme.base,
        appBar: AppBar(
          title: const Text('源选择抽屉预览 · 76px 卡片'),
          actions: [
            IconButton(
              tooltip: '切换亮暗模式',
              onPressed: () => setState(() => dark = !dark),
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              tooltip: '刷新图标',
              onPressed: () => setState(() => revision++),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: SizedBox(
            width: 430,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SourcePickerSheet(
                key: ValueKey(revision),
                section: Section.comic,
                sources: entries,
                currentId: 'preview-comic-1',
                manager: FakeSourceManager(sources: entries),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
