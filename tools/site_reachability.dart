// 站点可达性自检：用 App 同一套 Dart HTTP 栈（dart:io HttpClient）分别测「直连」与
// 「经本机代理」，判断某个据源在真机上是否会先被 WAF 拦住。
//
// 为什么需要它：Cloudflare 一类 WAF 拦的是客户端 TLS/HTTP 指纹，Node 的 fetch、
// curl、App 的 Dart 客户端可能给出三种不同结果——**只有 Dart 的结果代表 App 行为**。
//
// 用法：
//   dart run tools/site_reachability.dart                 # 内置 8 个目标
//   dart run tools/site_reachability.dart https://x.com/  # 只测给定地址
//   LUME_PROXY=127.0.0.1:7890 dart run tools/site_reachability.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

const ua =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const targets = <List<String>>[
  ['播剧网 ysxq', 'https://ysxq.cc/api.php/provide/vod/?ac=list&pg=1'],
  ['A123TV', 'https://a123tv.com/t/10.html'],
  ['饭搭子 fdzys', 'https://fdzys.com/movie/all'],
  ['飞流 flixflop', 'https://www.flixflop.com/'],
  ['短剧网 duanju2', 'https://www.duanju2.com/'],
  ['欧乐 olehdtv', 'https://www.olehdtv.com/index.php/vod/show/id/1.html'],
  ['华视 huavod', 'https://huavod.com/vodtype/1.html'],
  ['懂片帝 dongpian12', 'https://dongpian12.com/'],
];

Future<String> probe(String url, String proxyHost) async {
  final client = HttpClient()
    ..userAgent = ua
    ..connectionTimeout = const Duration(seconds: 15);
  if (proxyHost.isNotEmpty) {
    client.findProxy = (_) => 'PROXY $proxyHost';
  }
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    request.headers.set('Accept', 'text/html,application/xhtml+xml,*/*;q=0.8');
    request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
    final response = await request.close().timeout(const Duration(seconds: 25));
    final bytes = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    // 顺便报一下是不是被 WAF 挡了（Cloudflare 的拦截页有特征串）。
    final text = utf8.decode(bytes, allowMalformed: true);
    final blocked =
        text.contains('Attention Required') ||
        text.contains('Just a moment') ||
        text.contains('cf-error-details');
    return '${response.statusCode} ${bytes.length}b${blocked ? ' [WAF]' : ''}';
  } on Object catch (error) {
    return 'ERR ${error.runtimeType}';
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  final host = Platform.environment['LUME_PROXY'] ?? '127.0.0.1:7890';
  final rows = args.isEmpty
      ? targets
      : [
          for (final url in args) [url, url],
        ];
  print('代理地址：$host（LUME_PROXY 可改）');
  print('${'站点'.padRight(20)}${'Dart 直连'.padRight(18)}Dart 经代理');
  for (final row in rows) {
    final direct = await probe(row[1], '');
    final proxied = await probe(row[1], host);
    print(row[0].padRight(20) + direct.padRight(18) + proxied);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}
