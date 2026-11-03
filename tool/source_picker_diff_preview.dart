import 'package:flutter/material.dart';

import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/source_picker_sheet.dart';

import '../test/support/fake_source_manager.dart';

const _logoA = 'https://github.githubassets.com/favicons/favicon.png';
const _logoB =
    'https://www.gstatic.com/youtube/img/branding/favicon/favicon_144x144.png';

/// Standalone side-by-side preview of the two source-card shapes.
///
/// Run: `flutter run -d windows -t tool/source_picker_diff_preview.dart`
void main() => runApp(const SourcePickerDiffPreview());

class SourcePickerDiffPreview extends StatefulWidget {
  const SourcePickerDiffPreview({super.key});
  @override
  State<SourcePickerDiffPreview> createState() =>
      _SourcePickerDiffPreviewState();
}

class _SourcePickerDiffPreviewState extends State<SourcePickerDiffPreview> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
    theme: LumeTheme.build(
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: SourcePickerDiffBody(
      dark: dark,
      onToggle: () => setState(() => dark = !dark),
    ),
  );
}

class SourcePickerDiffBody extends StatelessWidget {
  const SourcePickerDiffBody({
    super.key,
    required this.dark,
    required this.onToggle,
  });
  final bool dark;
  final VoidCallback onToggle;

  static const _realSources = [
    SourceDescriptor(
      id: 'real-1',
      name: '漫画示例源 1',
      version: '1.0.0',
      enabled: true,
      group: '漫画',
      iconUrl: _logoA,
    ),
    SourceDescriptor(
      id: 'real-2',
      name: '一个比较长的漫画站点名称',
      version: '1.0.0',
      enabled: true,
      group: '漫画',
      iconUrl: _logoB,
    ),
    SourceDescriptor(
      id: 'real-3',
      name: '漫画示例源 3',
      version: '1.0.0',
      enabled: true,
      group: '漫画',
      iconUrl: _logoA,
    ),
    SourceDescriptor(
      id: 'real-4',
      name: '美图示例源 1',
      version: '1.0.0',
      enabled: true,
      group: '美图',
      iconUrl: _logoB,
    ),
    SourceDescriptor(
      id: 'real-5',
      name: '一个比较长的美图站点名称',
      version: '1.0.0',
      enabled: true,
      group: '美图',
      iconUrl: _logoA,
    ),
    SourceDescriptor(
      id: 'real-6',
      name: '美图示例源 3',
      version: '1.0.0',
      enabled: true,
      group: '美图',
      iconUrl: _logoB,
    ),
  ];

  static const _catSources = [
    SourceDescriptor(
      id: 'cat-1',
      name: '猫源站点一',
      version: '1.0.0',
      enabled: true,
    ),
    SourceDescriptor(
      id: 'cat-2',
      name: '猫源站点二 · 长名称检查',
      version: '1.0.0',
      enabled: true,
    ),
    SourceDescriptor(
      id: 'cat-3',
      name: '猫源站点三',
      version: '1.0.0',
      enabled: true,
    ),
    SourceDescriptor(
      id: 'cat-4',
      name: '猫源站点四',
      version: '1.0.0',
      enabled: true,
    ),
    SourceDescriptor(
      id: 'cat-5',
      name: '猫源站点五 · 长名称检查',
      version: '1.0.0',
      enabled: true,
    ),
  ];

  Widget _panel(
    BuildContext context, {
    required String title,
    required String hint,
    required Section section,
    required List<SourceDescriptor> sources,
  }) => Expanded(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(fontSize: 12, color: LumeTheme.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
              // DrawerGeometry 取“屏高 - 84”，这里补回去，让抽屉刚好填满面板。
              data: MediaQuery.of(context).copyWith(
                size: Size(constraints.maxWidth, constraints.maxHeight + 84),
              ),
              child: SourcePickerSheet(
                section: section,
                sources: sources,
                currentId: sources.first.id,
                manager: FakeSourceManager(sources: sources),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LumeTheme.base,
    appBar: AppBar(
      title: const Text('源列表双形态 · 统一 51px 卡片'),
      actions: [
        IconButton(
          tooltip: '切换亮暗模式',
          onPressed: onToggle,
          icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
        ),
      ],
    ),
    body: Center(
      child: SizedBox(
        width: 920,
        child: Row(
          children: [
            _panel(
              context,
              title: '小说 / 漫画 / 视频',
              hint: '32px 图标 + 名称/版本 + 三点菜单',
              section: Section.comic,
              sources: _realSources,
            ),
            const SizedBox(width: 16),
            _panel(
              context,
              title: '猫源',
              hint: '仅名称 · 长按拖动 · 左滑设置/删除',
              section: Section.cat,
              sources: _catSources,
            ),
          ],
        ),
      ),
    ),
  );
}
