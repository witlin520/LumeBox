/// 封面圆角总览（开发期用，不参与常规测试）。
///
/// 运行：`flutter test tool/cover_radius_preview_test.dart`
/// 产物：`build/ui_snapshot/cover_radius_all_modes.png`
///
/// 用生产代码里的 [PosterCard] / [PosterCover] / [CompactSourceItemTile]
/// 渲染四个板块 × 四种布局。封面走同一套图片占位，圆角裁切看得最清楚。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/features/reading/poster_card.dart';

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
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'CJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'CJK'),
  );
}

enum _PreviewMode {
  grid3('三列网格', 3),
  grid2('双列网格', 2),
  list('单列列表', 0),
  list2('双列列表', 2);

  const _PreviewMode(this.label, this.columns);
  final String label;
  final int columns;
}

class _CoverMatrix extends StatelessWidget {
  const _CoverMatrix({required this.pipeline});

  final SectionImagePipeline pipeline;

  static const List<Section> _sections = <Section>[
    Section.video,
    Section.comic,
    Section.video,
    Section.cat,
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LumeTheme.base,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '封面圆角 · 四板块 × 四布局',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: LumeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '网格封面与单列 / 双列缩略图统一 10px；卡片裁切半径与图片一致。',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: LumeTheme.descriptionColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const SizedBox(width: 92),
                for (final section in _sections)
                  Expanded(
                    child: Center(
                      child: Text(
                        section.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: LumeTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 14),
            for (final mode in _PreviewMode.values)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: 92,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          mode.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: LumeTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    for (final section in _sections)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _ModeCell(
                            mode: mode,
                            section: section,
                            pipeline: pipeline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeCell extends StatelessWidget {
  const _ModeCell({
    required this.mode,
    required this.section,
    required this.pipeline,
  });

  final _PreviewMode mode;
  final Section section;
  final SectionImagePipeline pipeline;

  SourceItem _item(int index) => SourceItem(
    id: '${section.id}-$index',
    title: '${section.label}示例 $index',
    subtitle: '用于检查四角圆角',
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LumeTheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: switch (mode) {
          _PreviewMode.grid3 => _grid(context, 3, 158),
          _PreviewMode.grid2 => _grid(context, 2, 212),
          _PreviewMode.list => _list(context),
          _PreviewMode.list2 => _list2(context),
        },
      ),
    );
  }

  Widget _grid(BuildContext context, int columns, double cardHeight) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < columns; index++) ...<Widget>[
                if (index > 0) const SizedBox(width: gap),
                SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: PosterCard(
                    footnoteBelow: true,
                    onTap: () {},
                    footnote: Text(
                      '${section.label}示例 ${index + 1}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: LumeTheme.textPrimary,
                      ),
                    ),
                    child: PosterCover(
                      pipeline: pipeline,
                      url: '',
                      title: '${section.label}示例 ${index + 1}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var index = 0; index < 2; index++)
          SizedBox(
            height: 100,
            child: CompactSourceItemTile(
              item: _item(index + 1),
              pipeline: pipeline,
              onTap: () {},
              columns: 1,
              coverWidth: 64,
              coverHeight: 82,
              flat: true,
              showMenu: false,
            ),
          ),
      ],
    );
  }

  Widget _list2(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 6) / 2;
        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < 2; index++) ...<Widget>[
                if (index > 0) const SizedBox(width: 6),
                SizedBox(
                  width: width,
                  height: 96,
                  child: CompactSourceItemTile(
                    item: _item(index + 1),
                    pipeline: pipeline,
                    onTap: () {},
                    columns: 2,
                    coverWidth: 46,
                    coverHeight: 64,
                    uniformList: true,
                    showMenu: false,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheDir;
  late SectionImagePipeline pipeline;

  setUpAll(() async {
    await _loadFonts();
  });

  setUp(() {
    cacheDir = Directory.systemTemp.createTempSync('lume_box_cover_radius');
    pipeline = SectionImagePipeline(cacheDir: cacheDir.path);
  });

  tearDown(() {
    pipeline.dispose();
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  testWidgets('四板块 × 四布局的封面圆角总览', (tester) async {
    tester.view.physicalSize = const Size(1440, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _snapshotTheme(),
        home: Scaffold(body: _CoverMatrix(pipeline: pipeline)),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final renderView = tester.binding.renderViews.first;
      final layer = renderView.debugLayer! as OffsetLayer;
      final image = await layer.toImage(renderView.paintBounds);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final output = Directory('build/ui_snapshot')
        ..createSync(recursive: true);
      File('${output.path}/cover_radius_all_modes.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
