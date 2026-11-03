import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/startup_gate.dart';

void main() {
  test('startup tasks report names for failures and timeouts without blocking successful tasks', () async {
    var completed = false;
    final issues = await initializeAppTasks([
      StartupTask('good', () async {
        completed = true;
      }),
      StartupTask(
        'privacy',
        () async => throw StateError('bad'),
        required: true,
      ),
      StartupTask('hung', () => Completer<void>().future),
    ], timeout: const Duration(milliseconds: 15));
    expect(completed, true);
    expect(issues.map((i) => i.name), containsAll(['privacy', 'hung']));
    expect(issues.singleWhere((i) => i.name == 'privacy').required, true);
  });
  testWidgets(
    'required startup failure blocks application routes and retries successfully',
    (tester) async {
      var count = 0, ready = 0;
      await tester.pumpWidget(
        StartupGate(
          initialize: () async =>
              ++count == 1 ? [const StartupIssue('privacy', true)] : [],
          onReady: () => ready++,
          child: const MaterialApp(home: Text('private content')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('privacy'), findsOneWidget);
      expect(find.text('private content'), findsNothing);
      expect(find.text('继续使用'), findsNothing);
      await tester.tap(find.text('重新加载'));
      await tester.pumpAndSettle();
      expect(find.text('private content'), findsOneWidget);
      expect(ready, 1);
    },
  );
  testWidgets(
    'optional startup failure can continue and unexpected initialization errors remain recoverable',
    (tester) async {
      await tester.pumpWidget(
        StartupGate(
          initialize: () async => [const StartupIssue('appearance', false)],
          child: const MaterialApp(home: Text('home')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续使用'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      await tester.pumpWidget(
        StartupGate(
          key: const Key('new'),
          initialize: () async => throw StateError('unexpected'),
          child: const MaterialApp(home: Text('must stay hidden')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('启动初始化'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('must stay hidden'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
