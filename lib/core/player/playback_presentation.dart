import 'package:flutter/foundation.dart';

enum HdrPolicy {
  automatic('自动'),
  prefer('优先 HDR'),
  sdr('兼容 SDR');

  const HdrPolicy(this.label);
  final String label;
}

enum EnhancementPreset {
  original('原画'),
  clear('清晰'),
  anime('动漫');

  const EnhancementPreset(this.label);
  final String label;
}

/// Preferences describe intent. Engines report applied state separately.
@immutable
class PlaybackPresentation {
  const PlaybackPresentation({
    this.hdrEnabled = true,
    this.hdrPolicy = HdrPolicy.automatic,
    this.dolbyVision = true,
    this.dolbyAudio = true,
    this.enhancementEnabled = false,
    this.preset = EnhancementPreset.clear,
    this.upscale = true,
    this.sharpen = true,
    this.deband = true,
    this.originalSubtitleStyle = true,
    this.subtitleLanguage = 'source',
    this.rememberSubtitle = true,
  });
  final bool hdrEnabled, dolbyVision, dolbyAudio;
  final HdrPolicy hdrPolicy;
  final bool enhancementEnabled, upscale, sharpen, deband;
  final EnhancementPreset preset;
  final bool originalSubtitleStyle, rememberSubtitle;
  final String subtitleLanguage;
  bool get wantsHdr => hdrEnabled && hdrPolicy != HdrPolicy.sdr;
  bool get enhances =>
      enhancementEnabled && preset != EnhancementPreset.original;

  PlaybackPresentation copyWith({
    bool? hdrEnabled,
    HdrPolicy? hdrPolicy,
    bool? dolbyVision,
    bool? dolbyAudio,
    bool? enhancementEnabled,
    EnhancementPreset? preset,
    bool? upscale,
    bool? sharpen,
    bool? deband,
    bool? originalSubtitleStyle,
    String? subtitleLanguage,
    bool? rememberSubtitle,
  }) => PlaybackPresentation(
    hdrEnabled: hdrEnabled ?? this.hdrEnabled,
    hdrPolicy: hdrPolicy ?? this.hdrPolicy,
    dolbyVision: dolbyVision ?? this.dolbyVision,
    dolbyAudio: dolbyAudio ?? this.dolbyAudio,
    enhancementEnabled: enhancementEnabled ?? this.enhancementEnabled,
    preset: preset ?? this.preset,
    upscale: upscale ?? this.upscale,
    sharpen: sharpen ?? this.sharpen,
    deband: deband ?? this.deband,
    originalSubtitleStyle: originalSubtitleStyle ?? this.originalSubtitleStyle,
    subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    rememberSubtitle: rememberSubtitle ?? this.rememberSubtitle,
  );

  Map<String, Object> toJson() => {
    'hdrEnabled': hdrEnabled,
    'hdrPolicy': hdrPolicy.name,
    'dolbyVision': dolbyVision,
    'dolbyAudio': dolbyAudio,
    'enhancementEnabled': enhancementEnabled,
    'preset': preset.name,
    'upscale': upscale,
    'sharpen': sharpen,
    'deband': deband,
    'originalSubtitleStyle': originalSubtitleStyle,
    'subtitleLanguage': subtitleLanguage,
    'rememberSubtitle': rememberSubtitle,
  };
  static PlaybackPresentation fromJson(Object? value) {
    if (value is! Map) return const PlaybackPresentation();
    bool flag(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    const languages = [
      'source',
      'zh-Hans',
      'zh-Hant',
      'en',
      'ja',
      'ko',
      'yue',
      'off',
    ];
    return PlaybackPresentation(
      hdrEnabled: flag('hdrEnabled', true),
      hdrPolicy:
          HdrPolicy.values
              .where((e) => e.name == value['hdrPolicy'])
              .firstOrNull ??
          HdrPolicy.automatic,
      dolbyVision: flag('dolbyVision', true),
      dolbyAudio: flag('dolbyAudio', true),
      enhancementEnabled: flag('enhancementEnabled', false),
      preset:
          EnhancementPreset.values
              .where((e) => e.name == value['preset'])
              .firstOrNull ??
          EnhancementPreset.clear,
      upscale: flag('upscale', true),
      sharpen: flag('sharpen', true),
      deband: flag('deband', true),
      originalSubtitleStyle: flag('originalSubtitleStyle', true),
      subtitleLanguage: languages.contains(value['subtitleLanguage'])
          ? value['subtitleLanguage'] as String
          : 'source',
      rememberSubtitle: flag('rememberSubtitle', true),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackPresentation && mapEquals(toJson(), other.toJson());
  @override
  int get hashCode => Object.hashAll(toJson().values);

  /// libmpv render API targets an SDR Flutter texture. Never claim HDR passthrough.
  Map<String, String> get mpvProperties => {
    'target-prim': 'bt.709',
    'target-trc': 'bt.1886',
    'tone-mapping': 'auto',
    'scale': enhances && upscale ? 'spline36' : 'bilinear',
    'cscale': enhances && upscale ? 'spline36' : 'bilinear',
    'deband': enhances && deband ? 'yes' : 'no',
    'deband-iterations': '1',
    'deband-threshold': preset == EnhancementPreset.anime ? '32' : '24',
    'deband-range': '16',
    'deband-grain': '0',
    'sharpen': enhances && sharpen
        ? (preset == EnhancementPreset.anime ? '0.15' : '0.25')
        : '0',
    'sub-ass': 'yes',
    'sub-visibility': 'yes',
    'sub-ass-override': originalSubtitleStyle ? 'no' : 'force',
  };
}

/// Optional engine interface keeps settings independent of a particular backend.
abstract interface class PresentationEngine {
  Future<void> applyPresentation(PlaybackPresentation settings);
  ValueListenable<List<String>> get presentationStatus;
}
