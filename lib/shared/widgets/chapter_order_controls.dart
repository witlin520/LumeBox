import 'native_glass_controls.dart';

import 'package:flutter/material.dart';

import '../../core/reading/chapter_display_order.dart';

/// 章节顺序：自动按章节号修正，或手动正序 / 倒序。
enum ChapterOrderMode {
  automatic('自动排序'),
  ascending('正序'),
  descending('倒序');

  const ChapterOrderMode(this.label);

  final String label;
}

class ChapterAutoOrderSwitch extends StatefulWidget {
  const ChapterAutoOrderSwitch({
    super.key,
    required this.order,
    this.onChanged,
  });
  final ChapterDisplayOrder order;
  final VoidCallback? onChanged;
  @override
  State<ChapterAutoOrderSwitch> createState() => _AutoState();
}

class _AutoState extends State<ChapterAutoOrderSwitch> {
  @override
  Widget build(BuildContext context) => NativeSwitchListTile.adaptive(
    title: const Text('章节自动修正排序'),
    subtitle: const Text('按章节号展示；关闭后恢复手动正序 / 倒序，不改源数据'),
    value: widget.order.automatic,
    onChanged: (v) {
      setState(() => widget.order.automatic = v);
      widget.onChanged?.call();
    },
  );
}

/// 阅读器章节目录里的顺序下拉：自动 / 正序 / 倒序。
///
/// 以前这里只有正序 / 倒序，自动排序开关藏在「排版」或「阅读设置」里；
/// 用户翻目录时想改顺序还得先找到那个开关。现在三种模式收在同一个下拉里，
/// 选择「自动排序」等价于打开自动修正，选择正序 / 倒序会关闭自动并写入手动值。
class ChapterManualOrderDropdown extends StatelessWidget {
  const ChapterManualOrderDropdown({
    super.key,
    required this.order,
    required this.onChanged,
  });
  final ChapterDisplayOrder order;
  final VoidCallback onChanged;

  ChapterOrderMode get _mode => order.automatic
      ? ChapterOrderMode.automatic
      : order.descending
      ? ChapterOrderMode.descending
      : ChapterOrderMode.ascending;

  @override
  Widget build(BuildContext context) => DropdownButton<ChapterOrderMode>(
    key: const ValueKey('reader-chapter-manual-order'),
    value: _mode,
    items: [
      for (final mode in ChapterOrderMode.values)
        DropdownMenuItem(value: mode, child: Text(mode.label)),
    ],
    onChanged: (mode) {
      if (mode == null) return;
      switch (mode) {
        case ChapterOrderMode.automatic:
          order.automatic = true;
        case ChapterOrderMode.ascending:
          order.automatic = false;
          order.descending = false;
        case ChapterOrderMode.descending:
          order.automatic = false;
          order.descending = true;
      }
      onChanged();
    },
  );
}
