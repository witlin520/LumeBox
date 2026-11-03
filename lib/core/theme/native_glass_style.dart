/// Parameters exposed by the native material, independent of shader settings.
class NativeGlassStyle {
  const NativeGlassStyle({
    this.clear = false,
    this.tint = 0xFF7862EC,
    this.tintOpacity = 0,
    this.radiusScale = 1,
  });
  final bool clear;
  final int tint;
  final double tintOpacity, radiusScale;
  NativeGlassStyle copyWith({
    bool? clear,
    int? tint,
    double? tintOpacity,
    double? radiusScale,
  }) => NativeGlassStyle(
    clear: clear ?? this.clear,
    tint: tint ?? this.tint,
    tintOpacity: (tintOpacity ?? this.tintOpacity).clamp(0, .5),
    radiusScale: (radiusScale ?? this.radiusScale).clamp(.5, 1.5),
  );
  Map<String, Object> toJson() => {
    'clear': clear,
    'tint': tint,
    'tintOpacity': tintOpacity,
    'radiusScale': radiusScale,
  };
  factory NativeGlassStyle.fromJson(Map data) {
    double value(String key, double fallback, double min, double max) {
      final raw = data[key];
      return raw is num && raw.isFinite
          ? raw.toDouble().clamp(min, max)
          : fallback;
    }

    return NativeGlassStyle(
      clear: data['clear'] == true,
      tint: data['tint'] is int ? data['tint'] as int : 0xFF7862EC,
      tintOpacity: value('tintOpacity', 0, 0, .5),
      radiusScale: value('radiusScale', 1, .5, 1.5),
    );
  }
}
