import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/danmaku/danmaku_models.dart';

void main() {
  test('本机发送与已有弹幕合并时保留对象和排序', () {
    const existing = DanmakuItem(time: Duration(seconds: 10), text: '已有弹幕');
    const posted = DanmakuItem(time: Duration(seconds: 20), text: '刚发送');
    final track = DanmakuTrack.parse([posted, existing, {'time': 15000, 'text': '源弹幕'}]);
    expect(track.items.map((item) => item.text), ['已有弹幕', '源弹幕', '刚发送']);
    expect(track.items.last, same(posted));
  });
}
