import 'dart:async';

import '../../core/session/privacy_settings.dart';

import '../../core/cat/cat_data_source.dart';
import '../../core/cat/cat_service.dart';
import '../../core/source/source.dart';
import '../../core/util/lume_log.dart';
import '../../core/reading/cover_warmup.dart';
import '../../core/reading/reading.dart';
import '../../core/session/section.dart';
import '../../core/net/network_settings.dart';

class CatWarmPage {
  CatWarmPage(this.source, this.categories, this.groups, this.list);
  final CatDataSource source;
  final List<SourceCategory> categories;
  final List<SourceFilterGroup> groups;
  final SourceList list;
  final at = DateTime.now();
}

/// Cat uses its own Node service, never the ordinary QuickJS registry.
class CatPreloader {
  static Future<void>? _task;
  static CatWarmPage? _page;
  static int _generation = 0;

  static CatSite? selectedSite(CatService service) {
    final records = service.subscriptions.where((r) => r.enabled).toList();
    final sites = records
        .expand((r) => r.sites)
        .where((s) => PrivacySettings.instance.allowsSource(s.id, s.name))
        .toList();
    return sites.where((s) => s.id == service.selectedSiteId).firstOrNull ??
        sites
            .where(
              (s) => !RegExp(
                r'config|setting|website|version|calendar|about|配置|我的网盘|日历|日期|更新日志|免责声明|公告',
                caseSensitive: false,
              ).hasMatch(s.key + s.name),
            )
            .firstOrNull ??
        sites.firstOrNull;
  }

  static Future<void> warm(CatService service) {
    if (_task != null) return _task!;
    final generation = _generation;
    late Future<void> task;
    task = _warm(service, generation).whenComplete(() {
      if (identical(_task, task)) _task = null;
    });
    _task = task;
    return task;
  }

  static Future<void> _warm(CatService service, int generation) async {
    try {
      await service.boot();
      if (service.needsSiteSelection) return;
      final site = selectedSite(service);
      // Background warming only uses an already downloaded, configured site.
      if (site == null) return;
      final record = service.subscriptions.firstWhere(
        (r) => r.id == site.subscriptionId,
      );
      if (record.hash.isEmpty || record.error.isNotEmpty) return;
      if (_page?.source.site.id == site.id &&
          DateTime.now().difference(_page!.at) < const Duration(seconds: 60)) {
        return;
      }
      final source = CatDataSource(service, site);
      final categories = await source.categories();
      final groups = await source.filtersFor();
      final list = await source.homeList();
      if (generation == _generation) {
        _page = CatWarmPage(source, categories, groups, list);
        final library = await ReadingLibrary.open(Section.cat);
        if (generation != _generation) return;
        unawaited(
          CoverWarmup.start(
            section: Section.cat,
            source: source,
            network: NetworkProfile.none,
            cacheDir: library.imageCacheDir,
            items: list.items,
          ),
        );
      }
    } catch (error) {
      LumeLog.info('[cat] 首页预热未完成，页面可重试：$error');
    }
  }

  static Future<CatWarmPage?> take(CatService service) async {
    final pending = _task;
    if (pending != null) {
      await pending.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    final page = _page;
    if (page == null ||
        selectedSite(service)?.id != page.source.site.id ||
        DateTime.now().difference(page.at) > const Duration(seconds: 60)) {
      return null;
    }
    _page = null;
    return page;
  }

  static void discard() {
    CoverWarmup.discard(Section.cat);
    _generation++;
    _page = null;
  }
}
