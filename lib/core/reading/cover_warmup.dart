import 'dart:async';

import '../cache/media_preload.dart';
import '../net/network_settings.dart';
import '../net/network_queue.dart';
import '../util/lume_log.dart';
import '../session/section.dart';
import '../source/source.dart';
import 'image_pipeline.dart';

/// Downloads only the first covers after a background list request completes.
/// Original bytes are reused by the foreground's source-scoped image pipeline.
class CoverWarmup {
  static final _entries = <Section, SectionImagePipeline>{};
  static bool _registered = false;

  static Future<void> start({
    required DataSource source,
    required NetworkProfile network,
    required String cacheDir,
    required Iterable<SourceItem> items,
    NetworkSender? requestSender,
    Section? section,
  }) {
    final owner = section ?? source.section;
    final policy = MediaPreload.instance;
    if (!policy.images || policy.clearing) return Future.value();
    if (!_registered) {
      policy.onClear(() => discard());
      _registered = true;
    }
    discard(owner);
    final parent = SectionImagePipeline(
      cacheDir: cacheDir,
      memoryBudgetBytes: SectionImagePipeline.thumbnailBudgetBytes,
      maxConcurrent: SectionImagePipeline.coverConcurrency,
      diskCache: SectionImagePipeline.diskCacheFor(owner),
      requestSender: requestSender,
    );
    final pipeline = parent.forSource(owner, source.id, network)
      ..bindSource(source);
    final covers = items
        .where((item) => item.cover?.trim().isNotEmpty ?? false)
        .take(12)
        .toList();
    for (final item in covers) {
      pipeline.configureImageHeaders({item.cover!: item.coverHeaders});
    }
    _entries[owner] = parent;
    final generation = policy.generation;
    final deadline = Timer(const Duration(seconds: 60), parent.dispose);
    return () async {
      try {
        // Keep foreground page requests ahead of this bounded two-image batch.
        var next = 0;
        Future<void> worker() async {
          while (next < covers.length) {
            if (parent.isDisposed ||
                !policy.images ||
                policy.clearing ||
                generation != policy.generation) {
              return;
            }
            final item = covers[next++];
            await pipeline.bytes(item.cover!, preload: true);
          }
        }

        await Future.wait([worker(), worker()]);
      } catch (error) {
        LumeLog.info('封面预热已停止：$error');
      } finally {
        deadline.cancel();
        if (identical(_entries[owner], parent)) {
          _entries.remove(owner);
        }
        parent.dispose();
      }
    }();
  }

  static void discard([Section? section]) {
    for (final key in section == null ? _entries.keys.toList() : [section]) {
      _entries.remove(key)?.dispose();
    }
  }
}
