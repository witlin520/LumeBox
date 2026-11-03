import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/web/web_home_sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume_box_web_home');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? root.path
              : null,
        );
    await ReadingLibrary.open(Section.video);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  test('网页主页可以新增、编辑、删除并写入板块设置', () async {
    final store = await WebHomeStore.open();
    final id = store.nextId();
    store.upsert(
      WebHomeSource(id: id, name: '影视主页', url: 'https://example.com'),
    );
    expect(store.items.single.name, '影视主页');
    expect(store.byId(id)?.url, 'https://example.com');

    store.upsert(store.items.single.copyWith(name: '另一个主页'));
    expect(store.items.single.name, '另一个主页');

    final library = await ReadingLibrary.open(Section.video);
    expect(library.setting('video.web.homes.v1'), contains('另一个主页'));

    store.remove(id);
    expect(store.items, isEmpty);
  });

  test('网页主页地址只接受 http(s) 绝对地址', () {
    expect(isValidWebHomeUrl('https://example.com'), isTrue);
    expect(isValidWebHomeUrl('http://example.com/a?b=1'), isTrue);
    expect(isValidWebHomeUrl('example.com'), isFalse);
    expect(isValidWebHomeUrl('ftp://example.com'), isFalse);
    expect(isValidWebHomeUrl(''), isFalse);
  });

  test('损坏的配置不会让网页主页列表崩溃', () {
    expect(WebHomeSource.fromJson('bad'), isNull);
    expect(
      WebHomeSource.fromJson({'id': 'a', 'name': 'A', 'url': 'https://a.com'}),
      isA<WebHomeSource>(),
    );
  });
}
