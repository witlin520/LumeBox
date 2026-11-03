import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source_subscription_sync.dart';
import 'package:lume_box/shared/widgets/source_update_badge.dart';

void main() {
  testWidgets(
    'site notices deduplicate, persist names, mark rows and acknowledge',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('source-notices-');
      final file = File('${root.path}/counts.txt');
      SourceSubscriptionSync.attachNoticeFile(Section.comic, file);
      SourceSubscriptionSync.recordChange(
        Section.comic,
        'site-a',
        '漫画站 A',
        '已新增',
      );
      SourceSubscriptionSync.recordChange(
        Section.comic,
        'site-a',
        '漫画站 A',
        '已更新',
      );
      SourceSubscriptionSync.recordChange(
        Section.comic,
        'site-b',
        '漫画站 B',
        '已移除',
      );
      expect(SourceSubscriptionSync.changeCount(Section.comic).value, 2);
      SourceSubscriptionSync.attachNoticeFile(
        Section.comic,
        File('${root.path}/other.txt'),
      );
      SourceSubscriptionSync.attachNoticeFile(Section.comic, file);
      expect(
        SourceSubscriptionSync.notice(Section.comic, 'site-a')?['name'],
        '漫画站 A',
      );
      expect(
        SourceSubscriptionSync.notice(Section.comic, 'site-b')?['status'],
        '已移除',
      );
      expect(SourceSubscriptionSync.changeCount(Section.comic).value, 2);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SourceUpdateBadge(section: Section.comic, sourceId: 'site-a'),
          ),
        ),
      );
      expect(find.text('已更新'), findsOneWidget);
      SourceSubscriptionSync.acknowledge(Section.comic);
      await tester.pump();
      expect(find.text('已更新'), findsNothing);
      SourceSubscriptionSync.attachNoticeFile(
        Section.comic,
        File('${root.path}/other.txt'),
      );
      SourceSubscriptionSync.attachNoticeFile(Section.comic, file);
      expect(SourceSubscriptionSync.notices(Section.comic), isEmpty);
      expect(SourceSubscriptionSync.changeCount(Section.comic).value, 0);
      await tester.pumpWidget(const SizedBox());
      root.deleteSync(recursive: true);
    },
  );
}
