import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/source_script.dart';
import 'package:lume_box/core/source/source_site_config.dart';
import 'package:lume_box/core/source/source_extension_settings.dart';
import 'package:lume_box/core/source/source_result_routes.dart';

void main() {
  final metadata = SourceMetadata.parse({
    'id': 'routes',
    'name': '线路测试',
    'endpoints': {
      'site': ['https://main.example', 'https://mirror.example'],
      'images': [
        {'url': 'https://img-a.example/assets', 'title': '图床一'},
        'https://img-b.example/pics',
      ],
      'video': ['https://v-a.example/hls', 'https://v-b.example/media'],
    },
    'settings': [
      {
        'key': 'quality',
        'title': '画质',
        'type': 'select',
        'default': 'hd',
        'options': [
          {'value': 'hd', 'title': '高清'},
          {'value': 'sd', 'title': '标清'},
        ],
      },
      {'key': 'autoNext', 'title': '自动下一页', 'type': 'toggle', 'default': false},
      {'key': 'limit', 'title': '数量', 'type': 'number', 'default': 20},
    ],
  })!;
  SourceSiteConfig configured() => SourceSiteConfig(
    mirrors: metadata.mirrors,
    mirrorIndex: 1,
    domainOverride: 'custom.example',
    images: metadata.images.copyWith(selected: 'https://img-b.example/pics'),
    video: metadata.video.copyWith(custom: 'https://v-custom.example/live'),
    settingDefinitions: metadata.settings,
    settingValues: const {'quality': 'sd', 'autoNext': true},
  );

  test('独立线路按完整前缀替换，保留签名查询串，不替换未声明地址', () {
    final site = configured();
    expect(site.resolvedDomain, 'https://custom.example');
    expect(
      site.rewriteUrl(
        'https://img-a.example/assets/a.webp?sig=a%2Fb&x=1',
        kind: 'image',
      ),
      'https://img-b.example/pics/a.webp?sig=a%2Fb&x=1',
    );
    expect(
      site.rewriteUrl(
        'https://v-a.example/hls/1/index.m3u8?t=x',
        kind: 'video',
      ),
      'https://v-custom.example/live/1/index.m3u8?t=x',
    );
    for (final value in [
      'https://unknown.example/a.jpg',
      'https://img-a.example/assets-other/a.jpg',
      'blob:https://main.example/token',
    ]) {
      expect(site.rewriteUrl(value), value);
    }
    expect(
      site.rewriteUrl('https://main.example/detail/1', kind: 'site'),
      'https://custom.example/detail/1',
    );
    expect(
      site.rewriteUrl('https://main.example/cover.jpg', kind: 'image'),
      'https://custom.example/cover.jpg',
    );
    expect(
      site.rewriteUrl('https://img-a.example/assets/a.jpg', kind: 'video'),
      'https://img-a.example/assets/a.jpg',
    );
  });
  test('默认端口不会继承旧端口，同域多路径优先匹配最长声明', () {
    final route = SourceRoute.parse(['https://a.example:51000/img'])
        .copyWith(custom: 'https://b.example/cdn');
    expect(
      route.rewrite('https://a.example:51000/img/a.jpg'),
      'https://b.example/cdn/a.jpg',
    );
    final site = SourceSiteConfig(
      mirrors: const ['https://a.example'],
      domainOverride: 'https://site.example',
      images: SourceRoute.parse(['https://a.example/img'])
          .copyWith(custom: 'https://image.example'),
    );
    expect(
      site.rewriteUrl('https://a.example/detail'),
      'https://site.example/detail',
    );
    expect(
      site.rewriteUrl('https://a.example/img/a.jpg'),
      'https://image.example/a.jpg',
    );
  });
  test('源更新保留自定义地址、参数和按网址选中的镜像，已删除线路回到主站', () {
    final old = configured().copyWith(mirrorIndex: 1).normalized();
    final next = old.redeclare(
      mirrors: metadata.mirrors.reversed.toList(),
      images: SourceRoute.parse(metadata.images.urls.reversed.toList()),
      video: const SourceRoute(),
      settings: metadata.settings,
    );
    expect(next.selectedMirror, 'https://mirror.example');
    expect(next.safeMirrorIndex, 0);
    expect(next.domainOverride, 'custom.example');
    expect(next.images.selectedUrl, 'https://img-b.example/pics');
    expect(next.video.custom, 'https://v-custom.example/live');
    expect(next.resolvedSettings['quality'], 'sd');
    final removed = next.redeclare(
      mirrors: const ['https://new.example'],
      images: const SourceRoute(),
      video: const SourceRoute(),
      settings: const [],
    );
    expect(removed.selectedMirror, 'https://new.example');
    expect(removed.settingValues['quality'], 'sd');
  });
  test('配置 JSON 往返保留线路与用户值，源升级改选项后使用有效默认', () {
    final roundTrip = SourceSiteConfig.fromJson(
      configured().normalized().toJson(),
    );
    expect(roundTrip.images.labels['https://img-a.example/assets'], '图床一');
    expect(roundTrip.resolvedSettings, {
      'quality': 'sd',
      'autoNext': true,
      'limit': 20,
    });
    final invalid = roundTrip.copyWith(
      settingValues: {'quality': 'removed', 'autoNext': 'wrong'},
    );
    expect(invalid.resolvedSettings, {
      'quality': 'hd',
      'autoNext': false,
      'limit': 20,
    });
  });
  test('镜像支持二十项，非法设置声明拒绝而不是静默隐藏', () {
    expect(
      SourceSiteConfig.normalizeMirrors(
        List.generate(25, (i) => 'https://m$i.example'),
      ).length,
      20,
    );
    expect(
      () => SourceMetadata.parseHeader(
        '// LumeSource: {"id":"bad","name":"bad","settings":[{"key":"q","title":"画质","type":"select","options":[]}]}',
      ),
      throwsFormatException,
    );
    expect(
      () => SourceSetting.parseAll([
        {'key': 'x', 'title': 'x', 'type': 'eval'},
      ]),
      throwsFormatException,
    );
  });
  test('只改媒体字段，章节标识不变，图片头索引同步，换线路不携带旧凭据', () {
    final site = configured();
    String route(String s, {String? kind}) => site.rewriteUrl(s, kind: kind);
    final value = routeSourceResult({
      'id': 'https://main.example/work',
      'cover': 'https://img-a.example/assets/a.jpg',
      'coverHeaders': {'Cookie': 'private', 'Referer': 'https://main.example/'},
      'chapters': [
        {'id': 'unchanged'},
      ],
    }, route) as Map;
    expect(value['id'], 'https://main.example/work');
    expect(value['cover'], 'https://img-b.example/pics/a.jpg');
    expect((value['coverHeaders'] as Map).containsKey('Cookie'), false);
    expect(
      (value['coverHeaders'] as Map)['Referer'],
      'https://custom.example/',
    );
    final alias = routeSourceResult({
      'cover_url': 'https://img-a.example/assets/a.jpg',
      'cover_headers': {'Authorization': 'old'},
    }, route) as Map;
    expect(alias['cover_headers'], isEmpty);
    final content = routeSourceResult({
      'kind': 'video',
      'url': 'https://v-a.example/hls/a.m3u8',
      'headers': {'Authorization': 'old'},
      'qualities': [
        {'url': 'https://v-a.example/hls/b.m3u8'},
      ],
    }, route) as Map;
    expect(content['url'], 'https://v-custom.example/live/a.m3u8');
    expect(content['headers'], isEmpty);
    final images = routeSourceResult({
      'kind': 'images',
      'images': ['https://img-a.example/assets/a.jpg'],
      'imageHeaders': {
        'https://img-a.example/assets/a.jpg': {
          'Referer': 'https://main.example/',
        },
      },
    }, route) as Map;
    expect(
      (images['imageHeaders'] as Map).keys.single,
      'https://img-b.example/pics/a.jpg',
    );
  });
}
