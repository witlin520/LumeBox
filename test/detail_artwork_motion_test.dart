import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/features/video/detail_artwork_motion.dart';

void main() {
  Future<ScrollController> preview(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 400,
                    child: DetailArtworkMotion(
                      scroll: scroll,
                      height: 400,
                      child: const ColoredBox(
                        key: Key('artwork'),
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1800, width: double.infinity),
                  const Positioned(
                    top: 300,
                    child: SizedBox(
                      key: Key('content'),
                      width: 100,
                      height: 50,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return scroll;
  }

  testWidgets('封面滚动慢于正文，保持正文尺寸与布局', (tester) async {
    final scroll = await preview(tester);
    final content = tester.getRect(find.byKey(const Key('content')));
    scroll.jumpTo(120);
    await tester.pump();
    final moved = tester.getRect(find.byKey(const Key('content')));
    expect(moved.size, content.size);
    expect(moved.top, content.top - 120);
    expect(tester.getTopLeft(find.byKey(const Key('artwork'))).dy, -72);
  });

  testWidgets('下拉封面顶部固定并拉伸，减少动态效果时禁用额外变换', (tester) async {
    var scroll = await preview(tester);
    scroll.jumpTo(-40);
    await tester.pump();
    final artwork = tester.getRect(find.byKey(const Key('artwork')));
    expect(artwork.top, closeTo(0, .01));
    expect(artwork.height, closeTo(440, .01));
    await tester.pumpWidget(const SizedBox());
    scroll = await preview(tester, reduceMotion: true);
    scroll.jumpTo(120);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const Key('artwork'))).dy, -120);
  });
}
