import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/source/source_order.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late ReadingLibrary library;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('lume-source-order');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    library = await ReadingLibrary.open(Section.video);
  });
  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    root.deleteSync(recursive: true);
  });
  test(
    'saved order precedes newly imported sources without duplicating IDs',
    () {
      library.setSetting(SourceOrder.key, jsonEncode(['b', 'a', 'b']));
      final rows = ['d', 'a', 'c', 'b'];
      rows.sort(SourceOrder.comparator(Section.video, ['a', 'b', 'c', 'd']));
      expect(rows, ['b', 'a', 'c', 'd']);
    },
  );
  test(
    'each sort uses one stable preference snapshot; later sorts see edits',
    () {
      library.setSetting(SourceOrder.key, jsonEncode(['b', 'a']));
      final snapshot = SourceOrder.comparator(Section.video, ['a', 'b', 'c']);
      library.setSetting(SourceOrder.key, jsonEncode(['a', 'b']));
      expect((['a', 'b', 'c']..sort(snapshot)), ['b', 'a', 'c']);
      expect(
        (['a', 'b', 'c']
          ..sort(SourceOrder.comparator(Section.video, ['a', 'b', 'c']))),
        ['a', 'b', 'c'],
      );
    },
  );
  test(
    'section order and filtered source reordering remain independent',
    () async {
      library.setSetting(SourceOrder.key, jsonEncode(['b', 'a', 'c', 'd']));
      await SourceOrder.move(
        Section.video,
        ['b', 'a', 'c', 'd'],
        ['b', 'c'],
        0,
        1,
      );
      expect(SourceOrder.read(Section.video), ['c', 'a', 'b', 'd']);
      expect(
        (['a', 'b']..sort(SourceOrder.comparator(Section.comic, ['a', 'b']))),
        ['a', 'b'],
      );
    },
  );
}
