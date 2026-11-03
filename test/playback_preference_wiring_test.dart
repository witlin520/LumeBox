import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/player/abstract_player.dart';
import 'package:lume_box/core/player/player_capabilities.dart';
import 'package:lume_box/core/player/player_experience.dart';
import 'package:lume_box/features/video/playback_preference_wiring.dart';

void main() {
  const preferences = PlayerExperience();

  test('UA 只在用户填写且媒体没有自带 User-Agent 时加入', () {
    final configured = preferences.update({
      'browserUA': 'Mozilla/5.0 LumeTest',
    });
    final media = PlayerMedia(
      uri: Uri.parse('https://example.com/a.m3u8'),
      headers: const {'Referer': 'https://example.com/'},
    );
    final applied = PlaybackPreferenceWiring.applyUserAgent(media, configured);
    expect(applied.headers, containsPair('User-Agent', 'Mozilla/5.0 LumeTest'));
    expect(applied.headers, containsPair('Referer', 'https://example.com/'));

    final sessionMedia = PlayerMedia(
      uri: media.uri,
      headers: const {'User-Agent': 'SessionVerified/1.0'},
    );
    final untouched = PlaybackPreferenceWiring.applyUserAgent(
      sessionMedia,
      configured,
    );
    expect(identical(untouched, sessionMedia), isTrue);
  });

  test('留空 UA 不改变媒体对象', () {
    final media = PlayerMedia(uri: Uri.parse('https://example.com/a.mp4'));
    expect(
      identical(
        PlaybackPreferenceWiring.applyUserAgent(media, preferences),
        media,
      ),
      isTrue,
    );
  });

  List<PlayerTrack> tracks() => const [
    PlayerTrack(id: '0', label: 'English', language: 'en'),
    PlayerTrack(id: '1', label: '简体中文', language: 'zh-Hans'),
    PlayerTrack(id: '2', label: '繁體中文', language: 'zh-Hant'),
    PlayerTrack(id: '3', label: '日本語', language: 'ja'),
  ];

  test('字幕语言按结构化语言字段优先匹配', () {
    expect(
      PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'zh-Hans'),
      '1',
    );
    expect(
      PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'zh-Hant'),
      '2',
    );
    expect(PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'ja'), '3');
    expect(PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'en'), '0');
  });

  test('跟随片源/关闭字幕不选择轨道，未知语言也不乱选', () {
    expect(
      PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'source'),
      isNull,
    );
    expect(
      PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'off'),
      isNull,
    );
    expect(
      PlaybackPreferenceWiring.chooseSubtitleTrack(tracks(), 'ko'),
      isNull,
    );
  });

  test('短语言码不会误匹配英文单词中的字母组合', () {
    const french = [PlayerTrack(id: 'fr', label: 'French', language: 'fr')];
    expect(PlaybackPreferenceWiring.chooseSubtitleTrack(french, 'en'), isNull);
    const chineseLabel = [PlayerTrack(id: 'zh', label: '中文字幕')];
    expect(
      PlaybackPreferenceWiring.chooseSubtitleTrack(chineseLabel, 'zh-Hans'),
      'zh',
    );
  });
}
