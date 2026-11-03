import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../util/lume_log.dart';

/// Drop only the retired module's disposable cache. Existing reading records
/// remain recoverable; active modules and account settings are never touched.
Future<void> clearRetiredModuleCache({Directory? supportDirectory}) async {
  try {
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    final root = p.normalize(p.absolute(support.path));
    final retired = p.join(root, 'sections', 'novel');
    if (!p.isWithin(root, retired)) return;
    // Never follow a link in an old data directory into another module.
    for (final path in [p.join(root, 'sections'), retired]) {
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.link) {
        return;
      }
    }
    for (final relative in ['cache', 'reading_cache/images']) {
      final target = p.join(retired, relative);
      if (await FileSystemEntity.type(p.dirname(target), followLinks: false) ==
              FileSystemEntityType.link ||
          await FileSystemEntity.type(target, followLinks: false) ==
              FileSystemEntityType.link) {
        continue;
      }
      final cache = Directory(target);
      if (await cache.exists()) await cache.delete(recursive: true);
    }
  } catch (error, stackTrace) {
    LumeLog.error(error, stackTrace);
  }
}
