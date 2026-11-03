import 'dart:convert';

import '../../core/reading/reading.dart';

/// Extra reader controls live beside the existing settings, preserving old keys.
class ComicReaderPreferences {
  static const key = 'comic.reader.experience.v1';
  String flow = 'webtoon';
  String tapZones = 'disabled';
  bool reverseZones = false;
  bool showZones = false;
  bool showZonesOnStart = false;
  bool zoomLocked = false;
  bool splitWide = false;
  double cropRatio = 0;
  List<int> customZones = [-1, 0, 1, -1, 0, 1, -1, 0, 1];
  String orientation = 'device';
  double brightness = 1;
  double warmth = 0;
  double contrast = 1;
  double gamma = 1;
  double sharpness = 0;
  bool denoise = false;
  bool grayscale = false;
  bool inverted = false;
  double autoSpeed = 36;
  static const double maxAutoSpeed = 2400;
  bool volumeKeys = false;
  bool autoLandscapeDouble = false;
  bool autoNextChapter = true;
  bool circleTranslation = false;
  List<String> toolbar = ['auto', 'slider', 'thumbnails'];

  static ComicReaderPreferences load(ReadingLibrary library) {
    final result = ComicReaderPreferences();
    try {
      final json = jsonDecode(library.setting(key) ?? '{}');
      if (json is! Map) return result;
      double number(String key, double fallback, double min, double max) {
        final value = json[key];
        return value is num && value.isFinite
            ? value.toDouble().clamp(min, max)
            : fallback;
      }

      if ([
        'webtoon',
        'vertical',
        'horizontal',
        'ltr',
        'rtl',
        'spread',
      ].contains(json['flow'])) {
        result.flow = json['flow'] as String;
      }
      if ([
        'disabled',
        'vertical',
        'horizontal',
        'lshape',
        'edge',
        'kindle',
        'custom',
      ].contains(json['tapZones'])) {
        result.tapZones = json['tapZones'] as String;
      }
      result.reverseZones = json['reverseZones'] == true;
      result.showZones = json['showZones'] == true;
      result.showZonesOnStart = json['showZonesOnStart'] == true;
      result.zoomLocked = json['zoomLocked'] == true;
      result.splitWide = json['splitWide'] == true;
      result.cropRatio = number('cropRatio', 0, 0, .15);
      final zones = json['customZones'];
      if (zones is List &&
          zones.length == 9 &&
          zones.every((v) => v is int && v >= -1 && v <= 1)) {
        result.customZones = zones.cast<int>();
      }
      if (['device', 'portrait', 'landscape'].contains(json['orientation'])) {
        result.orientation = json['orientation'] as String;
      }
      result.brightness = number('brightness', 1, .15, 1);
      result.warmth = number('warmth', 0, 0, 1);
      result.contrast = number('contrast', 1, .5, 1.5);
      result.gamma = number('gamma', 1, .5, 2);
      result.sharpness = number('sharpness', 0, 0, 2);
      result.denoise = json['denoise'] == true;
      result.autoSpeed = number('autoSpeed', 36, 10, maxAutoSpeed);
      result.volumeKeys = json['volumeKeys'] == true;
      result.autoLandscapeDouble = json['autoLandscapeDouble'] == true;
      result.autoNextChapter = json['autoNextChapter'] != false;
      result.circleTranslation = json['circleTranslation'] == true;
      result.grayscale = json['grayscale'] == true;
      result.inverted = json['inverted'] == true;
      if (json['toolbar'] is List) {
        result.toolbar = (json['toolbar'] as List)
            .whereType<String>()
            .where(
              (id) => ['auto', 'slider', 'thumbnails', 'chapters'].contains(id),
            )
            .toSet()
            .toList();
        if (!result.toolbar.contains('slider')) result.toolbar.add('slider');
      }
    } catch (_) {
      // A damaged optional preference never prevents opening a chapter.
    }
    return result;
  }

  void save(ReadingLibrary library) => library.setSetting(
    key,
    jsonEncode({
      'flow': flow,
      'tapZones': tapZones,
      'reverseZones': reverseZones,
      'showZones': showZones,
      'showZonesOnStart': showZonesOnStart,
      'zoomLocked': zoomLocked,
      'splitWide': splitWide,
      'cropRatio': cropRatio,
      'customZones': customZones,
      'orientation': orientation,
      'brightness': brightness,
      'warmth': warmth,
      'contrast': contrast,
      'gamma': gamma,
      'sharpness': sharpness,
      'denoise': denoise,
      'grayscale': grayscale,
      'inverted': inverted,
      'autoSpeed': autoSpeed,
      'volumeKeys': volumeKeys,
      'autoLandscapeDouble': autoLandscapeDouble,
      'autoNextChapter': autoNextChapter,
      'circleTranslation': circleTranslation,
      'toolbar': toolbar,
    }),
  );

  /// Filters affect the artwork only; reader controls keep their contrast.
  List<double> get colorMatrix {
    final c = contrast;
    final sign = inverted ? -1.0 : 1.0;
    final offset = inverted ? 255 - 128 * (1 - c) : 128 * (1 - c);
    final weights = grayscale ? [.2126, .7152, .0722] : null;
    return [
      for (var row = 0; row < 3; row++) ...[
        for (var col = 0; col < 3; col++)
          sign * c * (weights?[col] ?? (row == col ? 1.0 : 0.0)),
        0,
        offset +
            (row == 0
                ? warmth * 18
                : row == 2
                ? -warmth * 38
                : 0),
      ],
      0,
      0,
      0,
      1,
      0,
    ];
  }
}
