import 'package:flutter/material.dart';

import '../../core/player/player_settings.dart';
import 'playback_preference_wiring.dart';

class PresentationSettingsCard extends StatelessWidget {
  const PresentationSettingsCard({
    super.key,
    required this.settings,
    required this.onChanged,
    this.showPicture = true,
    this.showSubtitles = true,
    this.showAudio = true,
  });
  final bool showPicture, showSubtitles, showAudio;
  final PlayerSettings settings;
  final ValueChanged<PlayerSettings> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = settings.presentation;
    void update(PlaybackPresentation next) =>
        onChanged(settings.copyWith(presentation: next));
    Widget toggle(
      String title,
      bool value,
      ValueChanged<bool> change,
      String help,
    ) => SwitchListTile.adaptive(
      title: Text(title),
      subtitle: Text(help),
      value: value,
      onChanged: change,
    );
    return Column(
      children: [
        if (showPicture)
          ExpansionTile(
            title: const Text('HDR 与杜比'),
            subtitle: const Text('独立开关 · 按片源与设备能力生效'),
            children: [
              toggle(
                '启用 HDR',
                p.hdrEnabled,
                (v) => update(p.copyWith(hdrEnabled: v)),
                '关闭时使用 SDR 兼容显示；AVPlayer 使用原生显示层',
              ),
              for (final policy in HdrPolicy.values)
                ListTile(
                  title: Text(policy.label),
                  leading: Icon(
                    p.hdrPolicy == policy
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  enabled: p.hdrEnabled,
                  onTap: () => update(p.copyWith(hdrPolicy: policy)),
                ),
              toggle(
                '优先杜比视界',
                p.dolbyVision,
                (v) => update(p.copyWith(dolbyVision: v)),
                '有兼容线路时优先选择；关闭不会转换单一杜比片源',
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'MPV 当前使用 SDR 纹理与色调映射；MDK 的 HDR 输出待验证。偏好开启不等于 HDR 或 Atmos 已输出。线路偏好在下次加载时生效。',
                ),
              ),
            ],
          ),
        if (showPicture)
          ExpansionTile(
            title: const Text('画质增强'),
            subtitle: Text(
              p.enhancementEnabled ? p.preset.label : '已关闭 · 保留原画',
            ),
            children: [
              toggle(
                '启用画质增强',
                p.enhancementEnabled,
                (v) => update(p.copyWith(enhancementEnabled: v)),
                '目前由 MPV 提供；AVPlayer / MDK 保留原画',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in EnhancementPreset.values)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected: p.preset == preset,
                      onSelected: (_) => update(p.copyWith(preset: preset)),
                    ),
                ],
              ),
              toggle(
                '高质量缩放',
                p.upscale,
                (v) => update(p.copyWith(upscale: v)),
                '改善低分辨率画面的放大效果',
              ),
              toggle(
                '轻度锐化',
                p.sharpen,
                (v) => update(p.copyWith(sharpen: v)),
                '增强轮廓；动漫档强度更低',
              ),
              toggle(
                '去色带',
                p.deband,
                (v) => update(p.copyWith(deband: v)),
                '平滑渐变中的色阶；总开关关闭时以上处理均停止',
              ),
            ],
          ),
        if (showAudio) ...[
          toggle(
            '优先杜比音频',
            p.dolbyAudio,
            (v) => update(p.copyWith(dolbyAudio: v)),
            '优先 Dolby 音轨；关闭时优先普通音轨。空间音频由系统与输出设备控制',
          ),
        ],
        if (showSubtitles)
          ExpansionTile(
            title: const Text('字幕偏好'),
            subtitle: const Text('语言 · 同剧记忆 · ASS 原始样式'),
            children: [
              DropdownButtonFormField<String>(
                initialValue: p.subtitleLanguage,
                decoration: const InputDecoration(labelText: '优先字幕语言'),
                items: [
                  for (final e
                      in PlaybackPreferenceWiring
                          .subtitleLanguageLabels
                          .entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  if (v != null) update(p.copyWith(subtitleLanguage: v));
                },
              ),
              toggle(
                '记住同剧字幕选择',
                p.rememberSubtitle,
                (v) => update(p.copyWith(rememberSubtitle: v)),
                '按作品保存语言或关闭状态；有匹配语言时后续各集自动沿用',
              ),
              toggle(
                '保留 ASS 原始样式',
                p.originalSubtitleStyle,
                (v) => update(p.copyWith(originalSubtitleStyle: v)),
                'MPV 使用 libass 保留排版和特效；关闭后统一字幕样式。字体缺失时由系统回退',
              ),
            ],
          ),
      ],
    );
  }
}
