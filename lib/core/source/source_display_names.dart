/// 图源的**展示名**（只影响界面文字，不动脚本、不动数据）。
///
/// 用户口径：下拉框等处的名字要中文、要好认（例：`NN韩漫` → **鸟鸟韩漫**）。
/// **脚本内部的 id / 变量 / 解析逻辑一个都不改**——收藏、阅读记录、阅读进度、
/// 分页记忆、WAF 会话全部按图源 id 存，改展示名不会碰它们。
///
/// 落地方式：只在**界面拿到的展示模型**（`SourceDescriptor.name`）与验证窗标题上
/// 过一道映射；脚本自报的名字（`LumeSource.name`、数据库里的 name 字段）保持原样，
/// 「更新订阅源」时也不会被这里覆盖——它只是显示层的一层别名字典。
///
/// 表里没有的 id 原样透传：新源导入后立刻就有名字，不需要先来登记。
class SourceDisplayNames {
  SourceDisplayNames._();

  /// id → 中文展示名。新增一条即生效（不用改任何脚本）。
  static const Map<String, String> _names = <String, String>{
    // 漫画
    'mh92_comic': '92漫画',
    'daniao5_comic': '大鸟禁漫',
    'p5mh_comic': 'P5韩漫',
    'seyoumanhua_comic': '色友漫画',
    'nnhanman_comic': '鸟鸟韩漫',
    'jm18_comic': '18禁漫',
    'xman6_comic': 'X漫',
    'jcomic_comic': 'JComic',
    'gmh_comic': 'G社漫画',
    'mycomic_comic': '我的漫画',
    'bakamh_comic': '巴卡漫画',
    'cartoon18_comic': '色漫網',
    'fxcomic_comic': '漫小肆',
    'hanman18_comic': '十八韩漫',
    'jmcomic_comic': '禁漫天堂',
    'kmh001_comic': 'K漫画',
    'manwa_comic': '漫蛙',
    'mh18_comic': '十八漫画',
    'mmcg18_comic': '18H漫画',
    'nnmh_comic': '楠楠漫画',
    'relamanhua_comic': '熱辣漫畫',
    'rouman5_comic': '肉漫屋',
    'sansi_comic': '三四漫画',
    'z8pt_comic': 'Z8PT图库',
    'asmrhoney_video': '蜜糖助眠',
    'chaturbate_video': '查特直播',
    'chaturbate-live': '查特直播',
    'hanime1_video': 'H动漫一号',
    'hanime_video': 'H動漫網',
    // 视频
    'gztv5_video': '瓜子影视',
    'dage_video': '大哥视频',
    'luttt_video': '北觅影视',
    'vv3nwjk_video': '金牌影院',
    'jpyy2_video': '金牌影院',
    'xanimu_video': '成人动漫',
  };

  /// 这个图源在界面上该显示什么名字。[fallback] 是脚本自报的名字。
  static String of(String sourceId, [String fallback = '']) {
    final mapped = _names[sourceId.trim()];
    return withoutRatingSuffix(
      mapped != null && mapped.isNotEmpty ? mapped : fallback,
    );
  }

  /// Age classification remains separate; only remove a duplicate trailing label.
  static String withoutRatingSuffix(String name) {
    final clean = name
        .replaceFirst(
          RegExp(r'(?:\s*(?:[\[（(【]\s*18\s*\+\s*[\]）)】]|18\s*\+))+\s*$'),
          '',
        )
        .trimRight();
    return clean.isEmpty ? name : clean;
  }

  /// 仅测试用：表里有哪些 id（钉住「映射不改 id」这条口径）。
  static Map<String, String> get table =>
      Map<String, String>.unmodifiable(_names);
}
