import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/source_groups_preview.dart';

void main() {
  testWidgets(
    'cat preview stays one panel without a scrollbar during scrolling',
    (tester) async {
      await tester.pumpWidget(const SourceGroupsPreview());
      await tester.pumpAndSettle();
      expect(find.text('猫源 · 一体列表'), findsOneWidget);
      for (final kind in ['video', 'comic', 'novel', 'live']) {
        expect(find.byKey(ValueKey('cat-picker-group-$kind')), findsNothing);
      }
      expect(find.byType(Scrollable), findsOneWidget);
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      final left = tester.getTopLeft(find.text('站点 1'));
      final right = tester.getTopLeft(find.text('站点 2'));
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      final movedLeft = tester.getTopLeft(find.text('站点 1'));
      final movedRight = tester.getTopLeft(find.text('站点 2'));
      expect(movedLeft.dy, lessThan(left.dy));
      expect(movedLeft.dy - left.dy, movedRight.dy - right.dy);
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
}
