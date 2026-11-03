import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/settings/diagnostic_export_tile.dart';
import 'package:lume_box/features/settings/diagnostic_exporter.dart';

void main() {
  testWidgets(
    'one tap collects and exports one ZIP; repeated taps while busy are ignored',
    (tester) async {
      final pending = Completer<bool>();
      var collected = 0;
      var exported = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticExportTile(
              collect: () async {
                collected++;
                return DiagnosticExporter.build(
                  created: DateTime(2026),
                  metadata: {'version': 'test'},
                  logs: [],
                );
              },
              save: (bundle) async {
                exported++;
                expect(bundle.name, endsWith('.zip'));
                expect(bundle.bytes, isNotEmpty);
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('一键导出诊断包'));
      await tester.pump();
      await tester.tap(find.text('一键导出诊断包'));
      await tester.pump();
      expect(collected, 1);
      expect(exported, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('诊断包已导出，可将 ZIP 文件发来排查'), findsOneWidget);
    },
  );
  testWidgets('cancel and collection failure return to retryable state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiagnosticExportTile(
            collect: () async => throw StateError('fixture'),
            save: (_) async => false,
          ),
        ),
      ),
    );
    await tester.tap(find.text('一键导出诊断包'));
    await tester.pumpAndSettle();
    expect(find.text('诊断包导出失败，请重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
