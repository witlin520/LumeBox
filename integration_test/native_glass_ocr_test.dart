import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lume_box/core/reading/comic_image_tools.dart';
import 'package:lume_box/core/reading/ocr_evaluation.dart';
import 'package:lume_box/features/shell/dock_native_glass.dart';
import 'package:lume_box/shared/widgets/frosted_glass_widget.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iPhone native glass keeps editor focus when keyboard and sheet appear',
    (tester) async {
      if (!Platform.isIOS) return;
      final focus = FocusNode();
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FrostedGlassWidget(
                      child: TextField(
                        key: const Key('native-editor'),
                        focusNode: focus,
                        controller: controller,
                      ),
                    ),
                    TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.viewInsetsOf(context).bottom,
                          ),
                          child: const FrostedGlassWidget(
                            child: TextField(
                              key: Key('sheet-editor'),
                              autofocus: true,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('打开弹窗'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DockNativeGlass), findsOneWidget);
      await tester.tap(find.byKey(const Key('native-editor')));
      await tester.enterText(find.byKey(const Key('native-editor')), '输入保持测试');
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(controller.text, '输入保持测试');
      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sheet-editor')), '弹窗输入保持');
      await tester.pumpAndSettle();
      expect(find.text('弹窗输入保持'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot('native-glass-sheet-keyboard');
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'iPhone OCR measures actual cold and warm runs against a known text fixture',
    (tester) async {
      if (!Platform.isIOS) return;
      const reference = '你好世界 Hello World 12345';
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      final painter = TextPainter(
        text: const TextSpan(
          text: reference,
          style: TextStyle(color: Colors.black, fontSize: 44),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 1100);
      painter.paint(canvas, const Offset(30, 60));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1200, 220);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      picture.dispose();
      painter.dispose();
      final settings = ComicImageToolsSettings()..source = 'auto';
      final tools = ComicImageTools(settings: settings);
      try {
        final runs = <Map<String, Object>>[];
        for (var i = 0; i < 2; i++) {
          final timer = Stopwatch()..start();
          final texts = await tools.recognize(bytes);
          final measurement = OcrEvaluation.compare(reference, texts.join());
          runs.add({
            'run': i == 0 ? 'cold' : 'warm',
            'ms': timer.elapsedMilliseconds,
            'recognized': texts,
            'characterErrorRate': measurement.errorRate,
          });
          expect(texts, isNotEmpty);
          expect(
            measurement.errorRate,
            lessThan(.2),
            reason: 'Synthetic baseline only; real manga must be checked separately.',
          );
        }
        binding.reportData = {...?binding.reportData, 'ocrBaseline': runs};
      } finally {
        tools.dispose();
      }
    },
  );
}
