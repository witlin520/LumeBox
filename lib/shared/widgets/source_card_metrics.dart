import 'package:flutter/widgets.dart';

/// 漫画与视频源选择面板共用的卡片度量。
abstract final class SourceCardMetrics {
  static const double height = 55;
  static const double horizontalPadding = 14;
  static const double columnGap = 8;
  static const double rowGap = 5;

  /// 卡片圆角。
  static const double radius = 10;

  /// 左侧图标的边长。
  static const double iconSize = 33;

  /// 未选中态描边：浅灰 #E5E5EA。
  static const Color unselectedBorder = Color(0xFFE5E5EA);

  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(radius),
  );

  /// 紧凑卡片的轻阴影：比全局 [LumeTheme.cardShadow] 更淡、更短，
  /// 避免阴影比 1px 描边更深，把线框感吃掉。
  static const List<BoxShadow> shadow = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}
