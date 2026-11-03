import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/source_script_storage.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume-runtime-storage-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    await ReadingLibrary.open(Section.video);
    await ReadingLibrary.open(Section.comic);
  });
  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    root.deleteSync(recursive: true);
  });
  test('源存储跨实例保留JSON，按来源和板块隔离', () async {
    final store = SourceScriptStorage(Section.video, 'a/../../shared');
    await store.invoke({
      'operation': 'set',
      'key': 'state',
      'value': {'page': 3, 'enabled': true},
    });
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    final reopened = SourceScriptStorage(Section.video, 'a/../../shared');
    expect(await reopened.invoke({'operation': 'get', 'key': 'state'}), {
      'page': 3,
      'enabled': true,
    });
    for (final other in [
      SourceScriptStorage(Section.video, 'b'),
      SourceScriptStorage(Section.comic, 'a/../../shared'),
    ]) {
      expect(
        await other.invoke({
          'operation': 'get',
          'key': 'state',
          'defaultValue': 42,
        }),
        42,
      );
    }
    await reopened.invoke({'operation': 'remove', 'key': 'state'});
    expect(await reopened.invoke({'operation': 'get', 'key': 'state'}), isNull);
  });
  test('释放后未完成的写入不重新生成已清除的数据', () async {
    final store = SourceScriptStorage(Section.video, 'disposed');
    await store.invoke({'operation': 'set', 'key': 'state', 'value': 'before'});
    final pending = store.invoke({
      'operation': 'set',
      'key': 'state',
      'value': 'late',
    });
    store.dispose();
    await expectLater(pending, throwsStateError);
    final reopened = SourceScriptStorage(Section.video, 'disposed');
    expect(
      await reopened.invoke({'operation': 'get', 'key': 'state'}),
      'before',
    );
  });

  test('超额写入失败时保留原有值', () async {
    final store = SourceScriptStorage(Section.video, 'bounded');
    await store.invoke({'operation': 'set', 'key': 'saved', 'value': '原值'});
    await expectLater(
      store.invoke({'operation': 'set', 'key': 'saved', 'value': 'x' * 65537}),
      throwsException,
    );
    expect(await store.invoke({'operation': 'get', 'key': 'saved'}), '原值');
  });
}
