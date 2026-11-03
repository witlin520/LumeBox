import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/cat/cat_web_parse.dart';
import 'package:lume_box/core/source/data_source.dart';

void main() {
  test('网页解析只接受 http(s) 的媒体地址', () {
    expect(CatMediaSniffer.isMediaUrl('https://a.com/v/index.m3u8'), isTrue);
    expect(CatMediaSniffer.isMediaUrl('https://a.com/v/a.mp4?token=1'), isTrue);
    expect(
      CatMediaSniffer.isMediaUrl('https://a.com/live/playlist?format=m3u8'),
      isTrue,
    );
    expect(CatMediaSniffer.isMediaUrl('https://a.com/player.html'), isFalse);
    expect(CatMediaSniffer.isMediaUrl('blob:https://a.com/123'), isFalse);
    expect(CatMediaSniffer.isMediaUrl('data:video/mp4;base64,AAAA'), isFalse);
    expect(CatMediaSniffer.isMediaUrl('//a.com/v/a.mp4'), isFalse);
    expect(CatMediaSniffer.isMediaUrl(''), isFalse);
  });

  test('候选地址去重且保持页面请求顺序', () {
    final values = CatMediaSniffer.filter([
      'https://a.com/1.m3u8',
      'https://a.com/player.html',
      'https://a.com/2.mp4',
      'https://a.com/1.m3u8',
    ]);
    expect(values, ['https://a.com/1.m3u8', 'https://a.com/2.mp4']);
  });

  test('网页解析异常携带页面与请求头，并属于源异常', () {
    final request = CatWebParseRequired(
      Uri.parse('https://a.com/play/1'),
      const {'Referer': 'https://a.com/'},
    );
    expect(request, isA<SourceException>());
    expect(request.page.toString(), 'https://a.com/play/1');
    expect(request.headers['Referer'], 'https://a.com/');
    expect('$request', contains('网页解析'));
  });
}
