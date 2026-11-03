import 'package:flutter/material.dart';

import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/source/source_picker_sheet.dart';

import '../test/support/fake_source_manager.dart';

/// Side-by-side cat-source preview: single column vs two columns.
///
/// Run: `flutter run -d windows -t tool/cat_source_modes_preview.dart`
void main() => runApp(const CatSourceModesPreview());

class CatSourceModesPreview extends StatefulWidget {
  const CatSourceModesPreview({super.key});
  @override
  State<CatSourceModesPreview> createState() => _CatSourceModesPreviewState();
}

class _CatSourceModesPreviewState extends State<CatSourceModesPreview> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
    theme: LumeTheme.build(
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: CatSourceModesBody(
      dark: dark,
      onToggle: () => setState(() => dark = !dark),
    ),
  );
}

class CatSourceModesBody extends StatelessWidget {
  const CatSourceModesBody({
    super.key,
    required this.dark,
    required this.onToggle,
  });
  final bool dark;
  final VoidCallback onToggle;

  static const _sources = [
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
    SourceDescriptor(
      id: 'cat-6',
      name: '猫源站点六',
      version: '1.0.0',
      enabled: true,
    ),
  ];

  Widget _panel(
    BuildContext context, {
    required String title,
    required String hint,
    required bool twoColumns,
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
              // DrawerGeometry 取“屏高 - 84”，补回去让抽屉刚好填满面板。
              data: MediaQuery.of(context).copyWith(
                size: Size(constraints.maxWidth, constraints.maxHeight + 84),
              ),
              child: SourcePickerSheet(
                section: Section.cat,
                sources: _sources,
                currentId: _sources.first.id,
                manager: FakeSourceManager(sources: _sources),
                initialColumns: twoColumns,
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
      title: const Text('猫源列表 · 单列 / 双列'),
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
              title: '猫源 · 单列',
              hint: '无图标 / 无菜单 · 文字居中 · 长按拖动 · 左滑设置/删除',
              twoColumns: false,
            ),
            const SizedBox(width: 16),
            _panel(
              context,
              title: '猫源 · 双列',
              hint: '两列 10px 间距 · 文字居中 · 同样支持左滑与长按拖动',
              twoColumns: true,
            ),
          ],
        ),
      ),
    ),
  );
}
