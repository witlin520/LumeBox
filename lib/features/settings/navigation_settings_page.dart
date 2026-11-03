import 'package:flutter/material.dart';

import '../../core/shell/shell_settings.dart';
import '../shell/shell_dock_bar.dart';
import 'native_navigation_settings_card.dart';

List<ShellDockEntry> navigationPreviewEntries() {
  const catalog = [
    ShellDockEntry(
      id: 'comic',
      label: '漫画',
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories_rounded,
    ),
    ShellDockEntry(
      id: 'video',
      label: '视频',
      icon: Icons.play_circle_outline_rounded,
      selectedIcon: Icons.play_circle_fill_rounded,
    ),
    ShellDockEntry(
      id: 'settings',
      label: '设置',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];
  final tabs = ShellSettingsController.instance.settings.tabs;
  return [
    for (final tab in tabs)
      if (tab.visible)
        for (final entry in catalog)
          if (entry.id == tab.id) entry,
    ShellDockEntry.search,
  ];
}

class NavigationPreferencesPage extends StatelessWidget {
  const NavigationPreferencesPage({super.key});
  @override
  Widget build(BuildContext context) => NativeNavigationSettingsPage(
    controller: ShellSettingsController.instance,
    entries: navigationPreviewEntries(),
  );
}
