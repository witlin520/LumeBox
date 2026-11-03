/// 猫源站点选择卡片预览（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/cat_picker_cards_snapshot_test.dart`
/// 产物：`build/ui_snapshot/cat_picker_cards.png`
///
/// 用生产 [CatGroupedSourceList] / [CatSiteTile] 渲染单列与双列，顶部保留
/// 「加载或刷新包内站点」的 ListTile，以便人眼核对 16pt 左基线与卡片高度。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/cat/cat_service.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/cat/cat_page.dart';
import 'package:lume_box/shared/widgets/cat_site_tile.dart';
import 'package:lume_box/shared/widgets/source_swipe_tile.dart';

const String _fontRoot = r'C:\flutter\bin\cache\artifacts\material_fonts';
const String _cjkFont = r'C:\Windows\Fonts\Deng.ttf';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final path = '$_fontRoot\\$file';
      if (!File(path).existsSync()) continue;
      loader.addFont(
        File(path).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
      );
    }
    await loader.load();
  }

  await load('Roboto', <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await load('MaterialIcons', <String>['materialicons-regular.otf']);
  final cjk = FontLoader('CJK');
  if (File(_cjkFont).existsSync()) {
    cjk.addFont(
      File(_cjkFont).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
    );
  }
  await cjk.load();
}

ThemeData _snapshotTheme() {
  final base = LumeTheme.build();
  final textTheme = base.textTheme.apply(fontFamily: 'CJK');
  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
    // ListTile 会注入自己的 title/subtitle 样式；不补 CJK 族，
    // 顶部「加载或刷新包内站点」会画成方块。
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle:
          (base.listTileTheme.titleTextStyle ?? textTheme.titleMedium)
              ?.copyWith(fontFamily: 'CJK'),
      subtitleTextStyle:
          (base.listTileTheme.subtitleTextStyle ?? textTheme.bodyMedium)
              ?.copyWith(fontFamily: 'CJK'),
    ),
  );
}

const List<String> _names = <String>[
  '猫源站点一',
  '猫源站点二 · 长名称',
  '猫源站点三',
  '猫源站点四',
  '猫源站点五',
  '猫源站点六',
];

List<CatSite> _sites() => <CatSite>[
  for (var i = 0; i < _names.length; i++)
    CatSite(
      subscriptionId: 'preview',
      key: 'site-$i',
      name: _names[i],
      api: '/spider/site-$i',
    ),
];

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    final double cardHeight = CatSiteTile.compactHeight;
    return SizedBox(
      width: 320,
      child: Material(
        color: LumeTheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ListTile(
              title: const Text('包内站点订阅'),
              subtitle: const Text('加载或刷新包内站点'),
              trailing: const Icon(Icons.refresh),
              onTap: () {},
            ),
            CatGroupedSourceList(
              columns: columns,
              sites: _sites(),
              itemBuilder: (context, site) => SourceSwipeTile(
                height: cardHeight,
                actions: <SourceSwipeAction>[
                  SourceSwipeAction(
                    label: '设置',
                    color: LumeTheme.accent,
                    onTap: () {},
                  ),
                ],
                child: CatSiteTile(
                  height: cardHeight,
                  label: site.name,
                  selected: site.key == 'site-1',
                  onTap: () {},
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                columns > 1 ? '双列 · 51pt 高 · 文字绝对居中' : '单列 · 51pt 高 · 文字绝对居中',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: LumeTheme.descriptionColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  testWidgets('猫源选择：单列 / 双列卡片高度与对齐', (tester) async {
    tester.view.physicalSize = const Size(700, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(),
        home: Scaffold(
          backgroundColor: LumeTheme.base,
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PickerPanel(columns: 1),
                const SizedBox(width: 20),
                const _PickerPanel(columns: 2),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final renderView = tester.binding.renderViews.first;
      final layer = renderView.debugLayer! as OffsetLayer;
      final image = await layer.toImage(renderView.paintBounds);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final output = Directory('build/ui_snapshot')
        ..createSync(recursive: true);
      File('${output.path}/cat_picker_cards.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
