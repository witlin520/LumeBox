import 'package:flutter/foundation.dart';

import '../reading/reading_library.dart';
import '../util/lume_log.dart';
import 'section.dart';
import 'section_module_settings.dart';

/// 各板块的「UI 与控件」缩放（布局方案 / 控件尺寸 / 间距）在界面上的取用口。
///
/// 为什么需要它：这些值存在**各板块自己的库**里（[SectionModuleSettings]），
/// 而读它们需要一次异步开库（真实 IO）。浏览页与播放页在 build 里不可能 await，
/// 所以这里做一层缓存：谁要用谁先 [ensure]（幂等），值到了就 [notifyListeners]
/// 让界面重排一次；设置页改完直接 [apply]，当场生效。
///
/// 真机反馈「显示模式全都没有生效」——设置页能改、但**没有任何界面读它**。
/// 这一层就是那个缺的读取端：目前接到浏览页的间距与播放器控制栏的控件尺寸上
///（见 `ExploreView` 与 `VideoPlayerPage` 的用法）。
class ModuleUiScale extends ChangeNotifier {
  ModuleUiScale._();

  static final ModuleUiScale instance = ModuleUiScale._();

  final Map<String, SectionModuleSettings> _sections =
      <String, SectionModuleSettings>{};

  /// 已经读过磁盘的板块（[ensure] 只做一次）。
  final Set<String> _loaded = <String>{};

  /// 某个板块当前生效的设置（没读过时是默认值：标准 / 100% / 100%）。
  SectionModuleSettings of(Section section) =>
      _sections[section.id] ?? const SectionModuleSettings();

  /// 控件尺寸倍率（按钮 / 图标盒）。
  double controlScale(Section section) => of(section).controlScale;

  /// 间距倍率（列表间距、面板行距）。
  double spacingScale(Section section) => of(section).spacingScale;

  /// 界面动画开关。
  bool animationEnabled(Section section) => of(section).animationEnabled;

  /// 设置页改完立刻生效（同时更新缓存）。
  void apply(Section section, SectionModuleSettings settings) {
    _loaded.add(section.id);
    _sections[section.id] = settings;
    notifyListeners();
  }

  /// 读一次该板块的落盘设置（幂等）。
  ///
  /// **只读已经打开的库**（[ReadingLibrary.find]），不主动开库：这个调用发生在
  /// 页面 initState 里，异步开库会在测试/退出的时间窗里重新建出句柄（真机上
  /// 也白白多一次 IO）。板块页渲染探索页时库早就打开了；没打开就等下一次
  /// [ensure]（或设置页 [apply]）。
  void ensure(Section section) {
    if (_loaded.contains(section.id)) return;
    final library = ReadingLibrary.find(section);
    if (library == null) return;
    try {
      _sections[section.id] = SectionModuleSettings.load(library);
      _loaded.add(section.id);
      notifyListeners();
    } catch (error) {
      _loaded.add(section.id);
      LumeLog.warn('[ui] 模块设置读取失败（${section.id}），按默认尺寸布局: $error');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _sections.clear();
    _loaded.clear();
  }
}
