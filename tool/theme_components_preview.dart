import 'package:flutter/material.dart';

import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/shared/widgets/source_rating_badge.dart';

/// Side-by-side check of the global input / chip / card contrast on white and
/// light-gray page backgrounds.
///
/// Run: `flutter run -d windows -t tool/theme_components_preview.dart`
void main() => runApp(const ThemeComponentsPreview());

class ThemeComponentsPreview extends StatefulWidget {
  const ThemeComponentsPreview({super.key});
  @override
  State<ThemeComponentsPreview> createState() => _ThemeComponentsPreviewState();
}

class _ThemeComponentsPreviewState extends State<ThemeComponentsPreview> {
  bool dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: LumeTheme.build(
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    home: ThemeComponentsShowcase(
      dark: dark,
      onToggle: () => setState(() => dark = !dark),
    ),
  );
}

class ThemeComponentsShowcase extends StatelessWidget {
  const ThemeComponentsShowcase({
    super.key,
    required this.dark,
    required this.onToggle,
  });
  final bool dark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: LumeTheme.base,
    appBar: AppBar(
      title: const Text('全局输入框 / 胶囊 / 卡片'),
      actions: [
        IconButton(
          tooltip: '切换亮暗模式',
          onPressed: onToggle,
          icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
        ),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Panel(
              title: '白底页面',
              background: Colors.white,
              autofocusField: false,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _Panel(
              title: '浅灰底页面 · #F2F2F7',
              background: const Color(0xFFF2F2F7),
              autofocusField: true,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.background,
    required this.autofocusField,
  });
  final String title;
  final Color background;
  final bool autofocusField;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: LumeTheme.inputBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: LumeTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          autofocusField ? '上：未激活 · 下：激活态（紫色边框）' : '未激活态：浅灰底 + 1px 边界',
          style: TextStyle(fontSize: 12, color: LumeTheme.descriptionColor),
        ),
        const SizedBox(height: 14),
        if (autofocusField) ...[
          TextField(
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '添加订阅地址',
              hintText: 'https://…/sources.txt',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          autofocus: autofocusField,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '添加订阅地址',
            hintText: 'https://…/sources.txt',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            const ChoiceChip(label: Text('未选中分类'), selected: false),
            const ChoiceChip(label: Text('已选中分类'), selected: true),
            ChoiceChip(
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('成人内容'),
                  SizedBox(width: 4),
                  SourceRatingBadge(compact: true),
                ],
              ),
              selected: false,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '卡片在浅灰底上仍有阴影 + 细边框，不会和页面融为一体。',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: LumeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
