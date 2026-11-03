import '../../core/net/site_session_pool.dart';
import '../../core/js/source_script_storage.dart';
import '../../core/source/source_preferences.dart';

import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/cache/section_memory_cache.dart';
import '../../core/net/waf.dart';
import '../../core/reading/reading_library.dart';
import '../../core/session/section.dart';
import '../../core/source/source.dart';
import '../../core/source/source_subscription_sync.dart';
import '../settings/section_cache.dart';

class SourceMaintenanceResult {
  final List<SourceDescriptor> removed = [];
  final List<String> errors = [];
}

/// Only the selected section's installed sources and station data are affected.
class SourceMaintenance {
  const SourceMaintenance({
    required this.section,
    required this.manager,
    this.subscriptions,
    this.clearWebData,
  });
  final Section section;
  final SourceManager manager;
  final SourceSubscriptionSync? subscriptions;
  final Future<void> Function(Set<String> hosts, Set<String> protectedHosts)?
  clearWebData;

  Future<SourceMaintenanceResult> remove(
    List<SourceDescriptor> targets, {
    bool clearData = false,
  }) => SourceSubscriptionSync.maintenance(section, () async {
    final result = SourceMaintenanceResult();
    final service =
        subscriptions ??
        (targets.any((source) => source.subscribed) || clearData
            ? await SourceSubscriptionSync.open(section, manager: manager)
            : null);
    for (final source in targets) {
      try {
        await manager.remove(source.id);
        result.removed.add(source);
      } catch (error) {
        result.errors.add('${source.name}：$error');
      }
    }
    if (service != null) {
      if (clearData && result.errors.isEmpty) {
        await service.clearSavedSubscriptions();
      } else {
        await service.markRemoved(result.removed);
      }
    }
    if (clearData) {
      final library = await ReadingLibrary.open(section);
      final hosts = <String>{};
      for (final source in result.removed) {
        final prefs = SourcePreferences.read(section, source.id);
        for (final value in [
          source.siteUrl,
          prefs.originalOrigin,
          prefs.customOrigin,
          resolveWebViewOrigin(
                sourceId: source.id,
                originUrl: source.siteUrl,
                quiet: true,
              ) ??
              '',
        ]) {
          final host = Uri.tryParse(value)?.host ?? '';
          if (host.isNotEmpty) hosts.add(host);
        }
      }
      if (result.errors.isEmpty) {
        library.clearStationSettings();
      } else {
        for (final source in result.removed) {
          library.setSetting(SourceScriptStorage(section, source.id).key, '');
          library.setSetting('source.preferences.${source.id}', '');
          library.setSetting(WafSessionStore.keyFor(source.id), '');
          library.setSetting('${WafSessionStore.uaKeyPrefix}${source.id}', '');
        }
      }
      SectionMemoryCache.instance.clear(section);
      await const SectionCacheService().clear(section);
      if ((await const SectionCacheService().inspect(section)).cacheFiles > 0) {
        result.errors.add('部分缓存仍被占用，请稍后重试清理');
      }
      if (hosts.isNotEmpty && (Platform.isIOS || clearWebData != null)) {
        final protected = <String>{};
        for (final other in Section.values.where((value) => value != section)) {
          if (!LumeSources.runtimeAvailableFor(other)) continue;
          await ReadingLibrary.open(other);
          for (final source in await LumeSources.manager(other).list()) {
            final prefs = SourcePreferences.read(other, source.id);
            for (final value in [
              source.siteUrl,
              prefs.originalOrigin,
              prefs.customOrigin,
              resolveWebViewOrigin(
                    sourceId: source.id,
                    originUrl: source.siteUrl,
                    quiet: true,
                  ) ??
                  '',
            ]) {
              final host = Uri.tryParse(value)?.host ?? '';
              if (host.isNotEmpty) protected.add(host);
            }
          }
        }
        try {
          SiteSessionPool.shared.forgetHosts(hosts, protectedHosts: protected);
          if (clearWebData != null) {
            await clearWebData!(hosts, protected);
          } else {
            await const MethodChannel('lumebox/webview').invokeMethod<void>(
              'clearWebsiteDataForHosts',
              {'hosts': hosts.toList(), 'protectedHosts': protected.toList()},
            );
          }
        } catch (error) {
          result.errors.add('网页站点数据清理失败：$error');
        }
      }
    }
    return result;
  });
}
