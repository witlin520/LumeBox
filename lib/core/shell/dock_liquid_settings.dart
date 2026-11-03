import 'package:flutter/foundation.dart';

enum DockLiquidEffect {
  lift('水滴鼓起', '按住时水滴浮出长胶囊边缘'),
  drag('拖动拉伸', '跟随拖动速度、方向和离落点距离改变形状'),
  capsule('胶囊联动', '下方长胶囊随触摸轻微伸缩'),
  clarity('按压变清透', '按住时减弱磨砂与白色遮盖，松手恢复'),
  optics('透镜折射', '让图标、文字和背景一起参与折射'),
  lighting('高光与阴影联动', '水滴鼓起时加强边缘反光和投影');

  const DockLiquidEffect(this.label, this.description);
  final String label, description;
}

/// 三套开箱即用的玻璃预设；只改液态参数，不动导航尺寸/排序/主题。
///
/// 预设与 APP 图标主题无关；“恢复本组默认值”仍恢复 [DockLiquidSettings] 默认值。
enum DockLiquidPreset {
  recommended('推荐', '清澈透镜 + 轻微弹性 + 整条按压放大'),
  clearRules('规则通透', '规则胶囊、更清澈的中心、色散更克制'),
  softFree('柔和自由', '圆角矩形 + 自由形变，中心更白、形变更柔和');

  const DockLiquidPreset(this.label, this.description);
  final String label, description;

  DockLiquidSettings build() {
    switch (this) {
      case DockLiquidPreset.recommended:
        return const DockLiquidSettings();
      case DockLiquidPreset.clearRules:
        return const DockLiquidSettings(
              shape: DockLensShape.capsule,
              freeDeform: false,
            )
            .withValue(DockLiquidParameter.blurReduction, 1)
            .withValue(DockLiquidParameter.clarityFeather, .22)
            .withValue(DockLiquidParameter.coreAlpha, .03)
            .withValue(DockLiquidParameter.lensGlow, .34)
            .withValue(DockLiquidParameter.lensDesaturate, .26)
            .withValue(DockLiquidParameter.dispersion, .2)
            .withValue(DockLiquidParameter.lift, .40)
            .withValue(DockLiquidParameter.spread, .66);
      case DockLiquidPreset.softFree:
        return const DockLiquidSettings(
              shape: DockLensShape.roundedRect,
              freeDeform: true,
            )
            .withValue(DockLiquidParameter.shapeRoundness, .7)
            .withValue(DockLiquidParameter.lensGlow, .5)
            .withValue(DockLiquidParameter.lensDesaturate, .34)
            .withValue(DockLiquidParameter.clarityFeather, .38)
            .withValue(DockLiquidParameter.coreAlpha, .1)
            .withValue(DockLiquidParameter.dispersion, .6)
            .withValue(DockLiquidParameter.pressScale, .02)
            .withValue(DockLiquidParameter.pressWhiten, .14);
    }
  }
}

/// 透镜/选中底座的规则基础形状。
///
/// 自由形变（[DockLiquidSettings.freeDeform]）关闭时严格保持这里的轮廓；
/// 开启后胶囊与圆角矩形才允许速度驱动的拉伸、拖尾与倾斜。
enum DockLensShape {
  capsule('胶囊'),
  roundedRect('圆角矩形'),
  ellipse('椭圆'),
  circle('圆形');

  const DockLensShape(this.label);
  final String label;

  static DockLensShape fromName(Object? name) {
    for (final shape in values) {
      if (shape.name == name) return shape;
    }
    return capsule;
  }
}

enum DockLiquidParameter {
  pressMs('按压响应时间', '数值越小，按下后鼓起越快。', 100, 50, 400),
  damping('回弹阻尼', '越低越有弹性，越高越平稳；动效时长仍控制回弹速度。', .58, .3, 1),
  lift('水滴鼓起高度', '相对静止水滴高度增加的比例。', .43, 0, 1, DockLiquidEffect.lift),
  spread('按压横向膨胀', '按住时向两侧扩展的幅度。', .72, 0, 1.5, DockLiquidEffect.lift),
  vertical(
    '上下跟手幅度',
    '手指靠近上沿或下沿时，水滴跟着轻微偏移。',
    .09,
    0,
    .25,
    DockLiquidEffect.lift,
  ),
  stretch('拖动拉伸幅度', '拖得越快、离落点越远，水滴拉得越长。', .65, 0, 1.2, DockLiquidEffect.drag),
  tail('拖尾收窄程度', '水滴后端收窄，转向时拖尾也会换方向。', .55, 0, .9, DockLiquidEffect.drag),
  capsuleX('胶囊横向伸缩', '底座胶囊左右额外伸缩的幅度。', 0, 0, .06, DockLiquidEffect.capsule),
  capsuleY('胶囊纵向伸缩', '底座胶囊上下额外伸缩的幅度。', 0, 0, .18, DockLiquidEffect.capsule),
  pressScale(
    '整条按压放大',
    '按住时整条底栏（含图标文字与透镜）一起放大的比例。',
    .034,
    0,
    .08,
    DockLiquidEffect.capsule,
  ),
  pressWhiten(
    '按压整体提亮',
    '按住时提高底座白度；参考录屏按压后底栏会明显变白。',
    .18,
    0,
    .4,
    DockLiquidEffect.capsule,
  ),
  waist(
    '局部收腰',
    '按住时底座在触点附近轻收，与浮起膨胀的水滴配合；0% 关闭。',
    .28,
    0,
    1,
    DockLiquidEffect.capsule,
  ),
  blurReduction(
    '按压磨砂减弱',
    '0% 保持原磨砂，100% 按到底时去掉磨砂。',
    .62,
    0,
    1,
    DockLiquidEffect.clarity,
  ),
  opacityReduction(
    '按压白度减弱',
    '按住时减少白色遮盖；全透和全白端点保持原设置。',
    .24,
    0,
    1,
    DockLiquidEffect.clarity,
  ),
  refraction(
    '折射放大强度',
    '调整图标、文字和背景被透镜放大、拉弯的程度。',
    1,
    0,
    2.5,
    DockLiquidEffect.optics,
  ),
  dispersion(
    '边缘彩色折光',
    '水滴边缘红蓝分色的强度；0% 无彩色折光。',
    .45,
    0,
    2.5,
    DockLiquidEffect.optics,
  ),
  highlight(
    '按压高光增强',
    '在现有边缘高光设置上增加反光，原高光为零时不额外开启。',
    .6,
    0,
    1.5,
    DockLiquidEffect.lighting,
  ),
  shadow(
    '按压阴影增强',
    '相对现有阴影浓度增强，原阴影为零时仍然无阴影。',
    3.2,
    0,
    4,
    DockLiquidEffect.lighting,
  ),
  lensGlow(
    '透镜中心提亮',
    '透镜中心的白色提亮强度；越高越接近参考里的白玻璃，0% 保留原色。',
    .42,
    0,
    1,
    DockLiquidEffect.optics,
  ),
  lensDesaturate(
    '透镜中心降饱和',
    '中心颜色向灰度收敛的幅度；越高越接近参考里的近白中心。',
    .30,
    0,
    1,
    DockLiquidEffect.optics,
  ),
  nativeTint(
    '原生材质白度',
    '仅 iOS 原生材质模式：叠在系统材质上的白色/主题色薄层。',
    .06,
    0,
    .35,
    DockLiquidEffect.optics,
  ),
  clarityFeather(
    '清澈过渡宽度',
    '透镜边缘从清澈变回磨砂的过渡带宽（相对透镜高度）。',
    .30,
    .05,
    .6,
    DockLiquidEffect.clarity,
  ),
  coreAlpha(
    '透镜核心玻璃厚度',
    '核心处保留的极薄玻璃层；0% 完全通透，100% 与底座一样磨砂。',
    .06,
    0,
    .5,
    DockLiquidEffect.clarity,
  ),
  backgroundAdapt(
    '背景明暗联动',
    '按背景亮度微调底座白度：暗背景更白，亮背景回到设定值。',
    .5,
    0,
    1,
    DockLiquidEffect.lighting,
  ),
  shapeWidth('形状宽度', '基础形状的宽度倍率（相对默认选中药丸宽度）。', 1, .6, 1.5),
  shapeHeight('形状高度', '基础形状鼓起后的高度倍率。', 1, .6, 1.5),
  shapeRoundness('圆角程度', '圆角矩形的圆角比例：100% 接近胶囊，0% 接近直角。', 1, 0, 1);

  const DockLiquidParameter(
    this.label,
    this.description,
    this.initial,
    this.min,
    this.max, [
    this.effect,
  ]);
  final String label, description;
  final double initial, min, max;
  final DockLiquidEffect? effect;
  bool get milliseconds => this == pressMs;
  String display(double value) => milliseconds
      ? '${value.round()} ms'
      : '${(value * 100).toStringAsFixed(this == capsuleX || this == capsuleY ? 1 : 0)}%';
}

/// 底座玻璃的渲染路线（对比用开关）。
///
/// - [flutter]：本项目自绘的 Shader 方案，跨平台、可调形状与透镜；
/// - [nativeIos]：iOS 26 使用 `UIGlassEffect`，旧系统使用磨砂。
///   其他平台自动回退自绘。
///   受 Flutter 平台视图限制，该模式会关闭自绘透镜的 Backdrop 折射。
enum DockGlassRenderer {
  flutter('Flutter 自绘', 'Shader 取样 + 局部清澈 + 透镜折射，跨平台一致'),
  nativeIos('iOS 原生材质', 'iOS 26 系统玻璃，旧系统回退磨砂');

  const DockGlassRenderer(this.label, this.description);
  final String label, description;

  static DockGlassRenderer fromName(Object? name) {
    for (final renderer in values) {
      if (renderer.name == name) return renderer;
    }
    return flutter;
  }
}

/// 原生系统材质的厚度风格（仅 iOS 原生渲染模式生效）。
enum DockNativeGlassStyle {
  thin('清透', 'iOS 26 清透玻璃；旧系统为超薄磨砂'),
  regular('标准', 'iOS 26 标准玻璃；旧系统为系统磨砂'),
  thick('厚实', '加厚磨砂，优先保证文字可读');

  const DockNativeGlassStyle(this.label, this.description);
  final String label, description;

  static DockNativeGlassStyle fromName(Object? name) {
    for (final style in values) {
      if (style.name == name) return style;
    }
    return regular;
  }
}

/// Stored inside the existing dock appearance; missing fields use safe defaults.
@immutable
class DockLiquidSettings {
  const DockLiquidSettings({
    this.values = const {},
    this.disabled = const {},
    this.shape = DockLensShape.capsule,
    this.freeDeform = true,
    this.glassRenderer = DockGlassRenderer.flutter,
    this.nativeGlassStyle = DockNativeGlassStyle.regular,
    this.reduceTransparency = false,
  });
  final Map<String, double> values;
  final Set<String> disabled;
  final DockLensShape shape;

  /// 开启后才允许拖动拉伸、拖尾与倾斜；关闭时保持规则轮廓。
  final bool freeDeform;

  /// A/B 对比用：Flutter 自绘或 iOS 原生系统材质底座。
  final DockGlassRenderer glassRenderer;

  /// 原生系统材质的厚度风格（仅 [DockGlassRenderer.nativeIos] 生效）。
  final DockNativeGlassStyle nativeGlassStyle;

  /// 减少透明效果（辅助功能）：系统“降低透明度”开启或用户手动打开时，
  /// 底座更白、透镜折射收敛，保证图标与文字可读。
  final bool reduceTransparency;

  double value(DockLiquidParameter parameter) =>
      values[parameter.name] ?? parameter.initial;
  bool enabled(DockLiquidEffect effect) => !disabled.contains(effect.name);

  DockLiquidSettings withValue(DockLiquidParameter parameter, double amount) =>
      DockLiquidSettings(
        values: Map.unmodifiable({
          ...values,
          parameter.name: amount.isFinite
              ? amount.clamp(parameter.min, parameter.max)
              : parameter.initial,
        }),
        disabled: disabled,
        shape: shape,
        freeDeform: freeDeform,
        glassRenderer: glassRenderer,
        nativeGlassStyle: nativeGlassStyle,
        reduceTransparency: reduceTransparency,
      );

  DockLiquidSettings withEnabled(DockLiquidEffect effect, bool enable) {
    final next = Set<String>.of(disabled);
    if (enable) {
      next.remove(effect.name);
    } else {
      next.add(effect.name);
    }
    return DockLiquidSettings(
      values: values,
      disabled: Set.unmodifiable(next),
      shape: shape,
      freeDeform: freeDeform,
      glassRenderer: glassRenderer,
      nativeGlassStyle: nativeGlassStyle,
      reduceTransparency: reduceTransparency,
    );
  }

  DockLiquidSettings withShape(DockLensShape next) => DockLiquidSettings(
    values: values,
    disabled: disabled,
    shape: next,
    freeDeform: freeDeform,
    glassRenderer: glassRenderer,
    nativeGlassStyle: nativeGlassStyle,
    reduceTransparency: reduceTransparency,
  );

  DockLiquidSettings withFreeDeform(bool next) => DockLiquidSettings(
    values: values,
    disabled: disabled,
    shape: shape,
    freeDeform: next,
    glassRenderer: glassRenderer,
    nativeGlassStyle: nativeGlassStyle,
    reduceTransparency: reduceTransparency,
  );

  DockLiquidSettings withGlassRenderer(DockGlassRenderer next) =>
      DockLiquidSettings(
        values: values,
        disabled: disabled,
        shape: shape,
        freeDeform: freeDeform,
        glassRenderer: next,
        nativeGlassStyle: nativeGlassStyle,
        reduceTransparency: reduceTransparency,
      );

  DockLiquidSettings withNativeGlassStyle(DockNativeGlassStyle next) =>
      DockLiquidSettings(
        values: values,
        disabled: disabled,
        shape: shape,
        freeDeform: freeDeform,
        glassRenderer: glassRenderer,
        nativeGlassStyle: next,
        reduceTransparency: reduceTransparency,
      );

  DockLiquidSettings withReduceTransparency(bool next) => DockLiquidSettings(
    values: values,
    disabled: disabled,
    shape: shape,
    freeDeform: freeDeform,
    glassRenderer: glassRenderer,
    nativeGlassStyle: nativeGlassStyle,
    reduceTransparency: next,
  );

  Map<String, Object?> toJson() => {
    'values': values,
    'disabled': disabled.toList(),
    'shape': shape.name,
    'freeDeform': freeDeform,
    'glassRenderer': glassRenderer.name,
    'nativeGlassStyle': nativeGlassStyle.name,
    'reduceTransparency': reduceTransparency,
  };
  static DockLiquidSettings fromJson(Object? data) {
    if (data is! Map) return const DockLiquidSettings();
    var result = DockLiquidSettings(shape: DockLensShape.capsule);
    final rawValues = data['values'];
    if (rawValues is Map) {
      for (final parameter in DockLiquidParameter.values) {
        final raw = rawValues[parameter.name];
        if (raw is num) result = result.withValue(parameter, raw.toDouble());
      }
    }
    final rawDisabled = data['disabled'];
    if (rawDisabled is List) {
      for (final effect in DockLiquidEffect.values) {
        if (rawDisabled.contains(effect.name)) {
          result = result.withEnabled(effect, false);
        }
      }
    }
    result = result.withShape(DockLensShape.fromName(data['shape']));
    final rawFreeDeform = data['freeDeform'];
    if (rawFreeDeform is bool) {
      result = result.withFreeDeform(rawFreeDeform);
    }
    result = result.withGlassRenderer(
      DockGlassRenderer.fromName(data['glassRenderer']),
    );
    result = result.withNativeGlassStyle(
      DockNativeGlassStyle.fromName(data['nativeGlassStyle']),
    );
    final rawReduceTransparency = data['reduceTransparency'];
    if (rawReduceTransparency is bool) {
      result = result.withReduceTransparency(rawReduceTransparency);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is DockLiquidSettings &&
      shape == other.shape &&
      freeDeform == other.freeDeform &&
      glassRenderer == other.glassRenderer &&
      nativeGlassStyle == other.nativeGlassStyle &&
      reduceTransparency == other.reduceTransparency &&
      DockLiquidParameter.values.every((p) => value(p) == other.value(p)) &&
      DockLiquidEffect.values.every((e) => enabled(e) == other.enabled(e));
  @override
  int get hashCode => Object.hash(
    shape,
    freeDeform,
    glassRenderer,
    nativeGlassStyle,
    reduceTransparency,
    Object.hashAll(DockLiquidParameter.values.map(value)),
    Object.hashAll(DockLiquidEffect.values.map(enabled)),
  );
}
