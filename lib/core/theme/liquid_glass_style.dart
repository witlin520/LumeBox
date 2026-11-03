enum GlassParameter {
  blur('背景模糊', 10, 0, 30),
  opacity('底色浓度', .68, .08, 1),
  tint('主题色融入', .035, 0, .25),
  saturation('背景饱和度', 1.08, 0, 1.8),
  border('边缘亮度', .32, 0, 1),
  borderWidth('边缘厚度', .65, 0, 2),
  highlight('表面高光', .12, 0, .5),
  shadow('投影浓度', .035, 0, .3),
  shadowBlur('投影柔和度', 24, 0, 40),
  radius('圆角比例', 1, .4, 1.6),
  pressScale('按压下沉', .012, 0, .04),
  duration('过渡时长', 180, 80, 400),
  refraction('按压透镜折射', .25, 0, 1),
  dispersion('按压边缘色散', .12, 0, 1);

  const GlassParameter(this.label, this.fallback, this.min, this.max);
  final String label;
  final double fallback, min, max;
  String display(double value) => switch (this) {
    duration => '${value.round()} ms',
    blur || borderWidth || shadowBlur => value.toStringAsFixed(1),
    _ => '${(value * 100).round()}%',
  };
}

class LiquidGlassStyle {
  const LiquidGlassStyle({
    this.enabled = true,
    this.motion = true,
    this.values = const {},
  });
  final bool enabled, motion;
  final Map<GlassParameter, double> values;
  double value(GlassParameter p) => values[p] ?? p.fallback;
  LiquidGlassStyle withValue(GlassParameter p, double value) =>
      LiquidGlassStyle(
        enabled: enabled,
        motion: motion,
        values: {
          ...values,
          p: value.isFinite ? value.clamp(p.min, p.max) : p.fallback,
        },
      );
  LiquidGlassStyle copyWith({bool? enabled, bool? motion}) => LiquidGlassStyle(
    enabled: enabled ?? this.enabled,
    motion: motion ?? this.motion,
    values: values,
  );
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'motion': motion,
    for (final p in GlassParameter.values) p.name: value(p),
  };
  factory LiquidGlassStyle.fromJson(Map data) => LiquidGlassStyle(
    enabled: data['enabled'] != false,
    motion: data['motion'] != false,
    values: {
      for (final p in GlassParameter.values)
        if (data[p.name] is num && (data[p.name] as num).isFinite)
          p: (data[p.name] as num).toDouble().clamp(p.min, p.max),
    },
  );
}
