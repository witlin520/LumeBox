import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lume_box/core/reading/comic_image_tools.dart';
import 'package:lume_box/features/comic/comic_region_translation_page.dart';

class _Tools extends ComicImageTools {
  Uint8List? received;
  @override
  Future<List<ComicTextRegion>> translateSelectedRegion(Uint8List bytes) async {
    received = bytes;
    return const [
      ComicTextRegion(
        text: 'Hello',
        translation: '你好',
        x: 0,
        y: 0,
        width: 1,
        height: 1,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'only the selection is translated; apply returns a full page with the rest preserved',
    (tester) async {
      final image = img.Image(width: 200, height: 400);
      img.fill(image, color: img.ColorRgb8(120, 180, 210));
      final bytes = Uint8List.fromList(img.encodePng(image));
      final tools = _Tools();
      tools.preferences.serverTranslation = false;
      addTearDown(tools.dispose);
      ComicRegionTranslationResult? applied;
      Future<void> settleImage() async {
        for (var i = 0; i < 25; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
      }

      await tester.binding.setSurfaceSize(const Size(400, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  applied = await Navigator.push<ComicRegionTranslationResult>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComicRegionTranslationPage(
                        loadImage: () async => bytes,
                        tools: tools,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 350));
      await settleImage();
      await tester.pumpAndSettle();
      final canvas = tester.getTopLeft(
        find.byKey(const ValueKey('comic-region-canvas')),
      );
      await tester.dragFrom(
        canvas + const Offset(50, 50),
        const Offset(160, 180),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '翻译选区'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('翻译选区'));
      await settleImage();
      final crop = img.decodePng(tools.received!)!;
      expect(crop.width, lessThan(200));
      expect(crop.height, lessThan(400));
      expect(find.text('应用到当前页'), findsOneWidget);
      await tester.tap(find.text('应用到当前页'));
      await tester.pumpAndSettle();
      final output = img.decodePng(applied!.bytes)!;
      expect(output.width, 200);
      expect(output.height, 400);
      expect(output.getPixel(0, 0).r, 120);
      expect(output.getPixel(0, 0).g, 180);
    },
  );
}
