import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/danmaku/dandanplay_client.dart';
import 'package:lume_box/features/video/danmaku/danmaku_sources_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const legacy = MethodChannel('lumebox/danmaku_credentials');
  late Map<String, String> stored;
  late Map<String, String> old;
  late int legacyReads;
  setUp(() {
    stored = {};
    old = {};
    legacyReads = 0;
    messenger.setMockMethodCallHandler(DanmakuSourcesStore.channel, (
      call,
    ) async {
      if (call.method == 'read') return stored;
      if (call.method == 'write') {
        stored = Map<String, String>.from(call.arguments as Map);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(legacy, (call) async {
      if (call.method == 'read') legacyReads++;
      return old;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(DanmakuSourcesStore.channel, null);
    messenger.setMockMethodCallHandler(legacy, null);
  });

  test('设置页保存的当前源就是播放器读取的凭证，忽略旧平铺缓存', () async {
    await DanmakuSourcesStore.save([
      {
        'id': 'official',
        'type': 'official',
        'url': DandanplayCredentials.officialBase,
        'appId': 'app',
        'appSecret': 'key',
      },
    ], 'official');
    stored['baseUrl'] = DandanplayCredentials.defaultBase;
    stored['appId'] = '';
    stored['appSecret'] = '';
    old = {'baseUrl': 'https://legacy.example'};
    final config = await DandanplayCredentials.load();
    expect(config.official, isTrue);
    expect(config.appId, 'app');
    expect(config.appSecret, 'key');
    expect(legacyReads, 0);
  });

  test('移除旧弹1至弹14并保留CF服务，播放器不回到已删除的预设', () async {
    const cf = 'https://danmaku.example.workers.dev/access-prefix';
    stored = {
      'profilesJson': jsonEncode([
        {
          'id': 'preset-1',
          'name': '弹1',
          'type': 'logvar',
          'url': 'https://dm.999.team/87654321',
        },
        {'id': 'cf', 'name': '外置CF服务器', 'type': 'logvar', 'url': cf},
      ]),
      'activeId': 'preset-1',
    };
    final config = await DandanplayCredentials.load();
    expect(config.baseUrl, cf);
    expect(stored['activeId'], 'cf');
    expect(DanmakuSourcesStore.profiles(stored), hasLength(1));
    expect((await DandanplayCredentials.load()).baseUrl, cf);
  });

  testWidgets('全局添加的CF服务在管理页直接显示，不再显示十四个预设', (tester) async {
    stored = {
      'profilesJson': jsonEncode([
        {
          'id': 'cf',
          'name': '外置CF服务器',
          'type': 'logvar',
          'url': 'https://danmaku.example.workers.dev/path',
        },
      ]),
      'activeId': 'cf',
    };
    await tester.pumpWidget(const MaterialApp(home: DanmakuSourcesPage()));
    await tester.pumpAndSettle();
    expect(find.text('外置CF服务器'), findsOneWidget);
    expect(find.textContaining('弹1 ·'), findsNothing);
    expect(find.textContaining('兼容服务 · 点击选择'), findsNothing);
    expect(
      (await DandanplayCredentials.load()).baseUrl,
      'https://danmaku.example.workers.dev/path',
    );
  });

  test('旧 iOS 单服务凭证可读，保存后进入统一存储', () async {
    old = {
      'appId': 'app',
      'appSecret': 'key',
      'baseUrl': DandanplayCredentials.officialBase,
    };
    final config = await DandanplayCredentials.load();
    expect(config.official, isTrue);
    expect(config.configured, isTrue);
    await config.save();
    expect(jsonDecode(stored['profilesJson']!), hasLength(1));
    expect((await DandanplayCredentials.load()).appSecret, 'key');
  });

  test('播放页修改服务保留其它配置并通知当前播放器重载', () async {
    await DanmakuSourcesStore.save([
      {
        'id': 'a',
        'name': '官方',
        'url': DandanplayCredentials.officialBase,
        'appId': 'app',
        'appSecret': 'old',
      },
      {'id': 'b', 'url': 'https://other.example/prefix'},
    ], 'a');
    final revision = DanmakuSourcesStore.revision.value;
    await const DandanplayCredentials(
      ' app ',
      ' key ',
      baseUrl: DandanplayCredentials.officialBase,
    ).save();
    final profiles = DanmakuSourcesStore.profiles(stored);
    expect(profiles, hasLength(2));
    expect(
      profiles.firstWhere((s) => s['id'] == 'b')['url'],
      'https://other.example/prefix',
    );
    expect(stored['activeId'], 'a');
    expect((await DandanplayCredentials.load()).appSecret, 'key');
    expect(DanmakuSourcesStore.revision.value, revision + 1);
  });

  test('删除全部源后不复活旧凭证，选择兼容源不带官方凭证', () async {
    old = {
      'appId': 'old-app',
      'appSecret': 'old-key',
      'baseUrl': DandanplayCredentials.officialBase,
    };
    await DanmakuSourcesStore.save([], '');
    expect((await DandanplayCredentials.load()).official, isFalse);
    expect((await DandanplayCredentials.load()).configured, isFalse);
    await DanmakuSourcesStore.save([
      {'id': 'b', 'url': 'https://other.example'},
    ], 'b');
    expect((await DandanplayCredentials.load()).appSecret, isEmpty);
    expect(legacyReads, 0);
  });

  test('存储写入失败不通知播放器也不误报成功', () async {
    final revision = DanmakuSourcesStore.revision.value;
    messenger.setMockMethodCallHandler(DanmakuSourcesStore.channel, (
      call,
    ) async {
      if (call.method == 'write') throw PlatformException(code: 'keychain');
      return {};
    });
    await expectLater(
      const DandanplayCredentials('app', 'key').save(),
      throwsA(isA<PlatformException>()),
    );
    expect(DanmakuSourcesStore.revision.value, revision);
  });

  test('官方鉴权只允许正确的 HTTPS 主机与端口', () {
    for (final url in [
      'http://api.dandanplay.net',
      'https://api.dandanplay.net:8443',
      'https://api.dandanplay.net.example',
      'https://user@api.dandanplay.net',
    ]) {
      expect(
        DandanplayCredentials('app', 'key', baseUrl: url).official,
        isFalse,
      );
    }
    expect(
      const DandanplayCredentials(
        'app',
        'key',
        baseUrl: DandanplayCredentials.officialBase,
      ).official,
      isTrue,
    );
  });

  testWidgets('内置服务不用添加地址，保存选择后播放器读到稳定标识', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DanmakuSourcesPage()));
    await tester.pumpAndSettle();
    expect(find.text('内置本机服务'), findsOneWidget);
    await tester.tap(find.byTooltip('使用内置本机服务'));
    await tester.pumpAndSettle();
    final config = await DandanplayCredentials.load();
    expect(config.builtin, true);
    expect(config.baseUrl, DandanplayCredentials.builtinBase);
    expect(config.appId, isEmpty);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('从弹幕源管理页添加官方 ID 和密钥后播放器能直接读到', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DanmakuSourcesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加弹幕源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('弹弹play 开放平台'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'AppId'), ' app ');
    await tester.enterText(
      find.widgetWithText(TextField, 'AppSecret'),
      ' key ',
    );
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final config = await DandanplayCredentials.load();
    expect(config.official, isTrue);
    expect(config.appId, 'app');
    expect(config.appSecret, 'key');
    expect(DanmakuSourcesStore.profiles(stored), hasLength(1));
  });
}
