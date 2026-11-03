import 'package:flutter_test/flutter_test.dart';

/// Let real file I/O finish alongside widget animations under the fake clock.
Future<void> pumpIoAndSettle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (!tester.binding.hasScheduledFrame) break;
  }
  await tester.pumpAndSettle();
}
