import 'package:flutter/material.dart';

import '../../core/reading/reading.dart';
import '../../core/session/section.dart';
import '../../core/source/source.dart';
import '../reading/explore_view.dart';
import '../reading/source_filter_page.dart';
import 'comic_detail_page.dart';

/// 漫画探索页：图源下拉 + 右侧筛选抽屉 + 海报网格。
///
/// 内容获取、图源切换与筛选逻辑全在共享的 [ExploreView] 里，本页只提供漫画的
/// 区别只在布局与详情页。
class ComicExplorePage extends StatelessWidget {
  const ComicExplorePage({
    super.key,
    required this.library,
    required this.pipeline,
    this.manager,
    this.revision = 0,
  });

  final ReadingLibrary library;
  final SectionImagePipeline pipeline;
  final SourceManager? manager;

  /// 图源变更代数（宿主导入 / 删除 / 停用后 +1）：透传给 [ExploreView]，由它
  /// **原地**重新解析。
  ///
  /// 为什么不能用 Key 重挂本页（曾经就是这么写的，真机报错）：重挂会先建新实例，
  /// 而它的首次解析**同步**就能拿到板块共享的注册表（`SourceRegistry.open` 命中
  /// 缓存就直接返回、不 await）；同一帧末尾旧实例才 dispose，把那份注册表连同
  /// 数据库一起关掉——新实例在飞的那条读随后撞上已关闭的库：
  /// `Bad state: This database has already been closed`（真机在漫画导入订阅后
  /// 的探索页看到的就是这句）。原地刷新没有第二次 dispose，这条路整个不存在。
  final int revision;

  @override
  Widget build(BuildContext context) {
    final sourceManager = manager ?? LumeSources.manager(Section.comic);
    return ExploreView(
      revision: revision,
      // 用户要求：漫画两块去掉工具栏里的「排序」（视频板块保留）。
      showSort: false,
      // 顶栏已经有「源管理」：工具条的源下拉里不再重复放一个
      //（换到「探索」为默认页签后，两个同名入口会同屏出现）。
      showSourceManage: false,
      section: Section.comic,
      pipeline: pipeline,
      manager: manager,
      layout: ExploreLayout.grid,
      // 分页跳转筛选（用户口径任务 1，三板块共用）：点「筛选」直接进独立筛选页。
      onOpenFacetFilter: (context, source, currentCategoryId, originUrl) =>
          openSourceFacetFilter(
            context: context,
            source: source,
            currentCategoryId: currentCategoryId,
            originUrl: originUrl,
          ),
      onOpenItem: (selection) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ComicDetailPage(
            library: library,
            manager: sourceManager,
            target: ReadingTarget(
              sourceId: selection.sourceId,
              itemId: selection.item.id,
              title: selection.item.title,
              cover: selection.item.cover,
              subtitle: selection.item.subtitle,
            ),
          ),
        ),
      ),
    );
  }
}
