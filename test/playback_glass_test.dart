import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/playback_glass.dart';

void main() {
  testWidgets('系统模糊能力查询失败时安全降级，关闭后去除所有效果层', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('lumebox/playback_effects'),
          (_) async => throw PlatformException(code: 'unsupported'),
        );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlaybackGlass(
            enabled: true,
            child: SizedBox(width: 300, height: 80, child: Text('控制栏')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('控制栏'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlaybackGlass(
            enabled: false,
            child: SizedBox(width: 300, height: 80, child: Text('控制栏')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ClipRRect), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
