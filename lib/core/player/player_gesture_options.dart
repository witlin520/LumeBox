class PlayerGestureOptions {
  const PlayerGestureOptions({
    this.enabled = true,
    this.brightness = true,
    this.volume = true,
    this.seek = true,
    this.boost = true,
    this.seekSeconds = 90,
    this.boostMultiplier = 2,
  });
  final bool enabled, brightness, volume, seek, boost;
  final int seekSeconds;
  final double boostMultiplier;
  PlayerGestureOptions copyWith({
    bool? enabled,
    bool? brightness,
    bool? volume,
    bool? seek,
    bool? boost,
    int? seekSeconds,
    double? boostMultiplier,
  }) => PlayerGestureOptions(
    enabled: enabled ?? this.enabled,
    brightness: brightness ?? this.brightness,
    volume: volume ?? this.volume,
    seek: seek ?? this.seek,
    boost: boost ?? this.boost,
    seekSeconds: (seekSeconds ?? this.seekSeconds).clamp(30, 180),
    boostMultiplier: (boostMultiplier ?? this.boostMultiplier).clamp(1.5, 4),
  );
  Map<String, Object> toJson() => {
    'enabled': enabled,
    'brightness': brightness,
    'volume': volume,
    'seek': seek,
    'boost': boost,
    'seekSeconds': seekSeconds,
    'boostMultiplier': boostMultiplier,
  };
  factory PlayerGestureOptions.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    final seconds = m['seekSeconds'];
    final multiplier = m['boostMultiplier'];
    return PlayerGestureOptions(
      enabled: m['enabled'] != false,
      brightness: m['brightness'] != false,
      volume: m['volume'] != false,
      seek: m['seek'] != false,
      boost: m['boost'] != false,
      seekSeconds: seconds is num && seconds.isFinite
          ? seconds.toInt().clamp(30, 180)
          : 90,
      boostMultiplier: multiplier is num && multiplier.isFinite
          ? multiplier.toDouble().clamp(1.5, 4)
          : 2,
    );
  }
  @override
  bool operator ==(Object other) =>
      other is PlayerGestureOptions &&
      other.enabled == enabled &&
      other.brightness == brightness &&
      other.volume == volume &&
      other.seek == seek &&
      other.boost == boost &&
      other.seekSeconds == seekSeconds &&
      other.boostMultiplier == boostMultiplier;
  @override
  int get hashCode => Object.hash(
    enabled,
    brightness,
    volume,
    seek,
    boost,
    seekSeconds,
    boostMultiplier,
  );
}
