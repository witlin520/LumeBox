import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/video_source_metadata.dart';

void main() {
  test('网盘诊断压缩为数量和预览限制，不把三集可用资源当作总集数', () {
    const raw =
        '2 个网盘 · 夸克A 无限 OK 3 集（匿名 video_preview（无 Cookie，夸克限制：仅 120 秒预览），HTTP 200） / 百度A OK';
    expect(
      conciseVideoSubtitle(raw, availableEpisodes: 3),
      '2 个网盘 · 可用 3 集 · 含 120 秒预览线路',
    );
  });
  test('保留不可用及登录要求，不显示 HTTP 和接口名', () {
    expect(
      conciseVideoSubtitle(
        '1 个网盘 · HTTP 403 需要登录，video_preview',
        availableEpisodes: 0,
      ),
      '1 个网盘 · 含预览线路 · 部分线路不可用 · 部分线路需登录',
    );
  });
  test('普通影视资料和无诊断的网盘说明保持不变', () {
    for (final text in [
      '更新至13集 · 2026 · 剧情',
      '2 个网盘 · 4K',
      '2026 · OK Computer',
    ]) {
      expect(conciseVideoSubtitle(text, availableEpisodes: 13), text);
    }
  });
}
