import 'dart:convert';

/// Shared playback preferences. Per-kernel speed and subtitle values remain
/// in PlayerSettings.
class PlayerExperience {
  const PlayerExperience._(this.values);
  const PlayerExperience() : values = const {};
  final Map<String, Object?> values;

  bool flag(String key, [bool fallback = false]) =>
      values[key] is bool ? values[key] as bool : fallback;
  String text(String key, [String fallback = '']) =>
      values[key] is String ? values[key] as String : fallback;
  double number(String key, double fallback, double min, double max) {
    final value = values[key];
    return value is num && value.isFinite
        ? value.toDouble().clamp(min, max)
        : fallback;
  }

  bool get autoKernelSwitch => flag('autoKernelSwitch', true);
  bool get backgroundPlayback => flag('backgroundPlayback', true);
  bool get swapGestureSides => flag('swapGestureSides');
  bool get swipeEpisodes => flag('swipeEpisodes');
  bool get twoFingerEpisodes => flag('twoFingerEpisodes');
  bool get followSystemBrightness => flag('followSystemBrightness', true);
  bool get rememberBrightness => flag('rememberBrightness', true);
  bool get selectEpisodeOnly => flag('selectEpisodeOnly');
  bool get shortDramaPreload => flag('shortDramaPreload');
  int get preloadMinutes => number('preloadMinutes', 5, 1, 10).round();
  String get browserUA => text('browserUA').trim();
  String get subtitleLanguage =>
      const [
        'source',
        'zh-Hans',
        'zh-Hant',
        'yue',
        'en',
        'ja',
        'ko',
        'off',
      ].contains(text('subtitleLanguage'))
      ? text('subtitleLanguage')
      : 'source';
  PlayerExperience update(Map<String, Object?> patch) =>
      PlayerExperience._(Map.unmodifiable({...values, ...patch}));
  Map<String, Object?> toJson() => Map.of(values);
  factory PlayerExperience.fromJson(Object? raw) => raw is Map
      ? PlayerExperience._(
          Map.unmodifiable({
            for (final entry in raw.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }),
        )
      : const PlayerExperience();
  static PlayerExperience decode(String? raw) {
    try {
      return PlayerExperience.fromJson(jsonDecode(raw ?? '{}'));
    } catch (_) {
      return const PlayerExperience();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerExperience &&
      jsonEncode(other.values) == jsonEncode(values);
  @override
  int get hashCode => jsonEncode(values).hashCode;
}
