/// Local mobile preview only: the normal lib/main.dart entry stays unchanged.
/// flutter run -d emulator-5580 -t tool/android_reader_preview.dart
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lume_box/core/media/media_library.dart';
import 'package:lume_box/core/reading/comic_image_tools.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/app_preferences.dart';
import 'package:lume_box/core/session/privacy_settings.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/shell/shell_settings.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/theme/appearance.dart';
import 'package:lume_box/core/theme/floating_modules.dart';
import 'package:lume_box/core/theme/frosted_settings.dart';
import 'package:lume_box/core/theme/interface_typography.dart';
import 'package:lume_box/core/theme/lume_theme.dart';
import 'package:lume_box/core/theme/user_fonts.dart';
import 'package:lume_box/features/comic/comic_reader_page.dart';
import 'package:lume_box/features/settings/settings_page.dart';
import 'package:lume_box/features/settings/tab_bar_settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.boot();
  await PrivacySettings.instance.boot();
  await MediaLibrary.instance.boot();
  await AppearanceController.instance.boot();
  await UserFonts.instance.boot();
  await UserFonts.instance.ensureLoaded(
    AppearanceController.instance.settings.fontId,
  );
  await ShellSettingsController.instance.boot();
  await FloatingModules.instance.boot();
  await FrostedSettings.instance.boot();
  await ComicImageToolsSettings.instance.boot();
  final source = await _LocalComicSource.create();
  final library = await ReadingLibrary.open(Section.comic);
  runApp(_PreviewApp(source: source, library: library));
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp({required this.source, required this.library});
  final _LocalComicSource source;
  final ReadingLibrary library;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AppearanceController.instance,
      UserFonts.instance,
    ]),
    builder: (context, _) {
      final appearance = AppearanceController.instance.settings;
      ThemeData theme(Brightness brightness) => LumeTheme.build(
        brightness: brightness,
        accent: appearance.accent,
        customAccent: appearance.customAccent,
        background: appearance.background,
        fontFamily: UserFonts.instance.familyFor(appearance.fontId),
        fontBold: appearance.fontBold,
        fontItalic: appearance.fontItalic,
      );
      return MaterialApp(
        title: 'LumeBox 移动端预览',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: appearance.mode,
        builder: (context, child) {
          LumeTheme.applyBrightness(Theme.of(context).brightness);
          LumeTheme.applyAccent(
            appearance.accent,
            customAccent: appearance.customAccent,
          );
          LumeTheme.applyBackground(appearance.background);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: InterfaceTextScaler(
                MediaQuery.textScalerOf(context),
                appearance.textScale,
              ),
            ),
            child: child!,
          );
        },
        home: _PreviewHome(source: source, library: library),
      );
    },
  );
}

class _PreviewHome extends StatelessWidget {
  const _PreviewHome({required this.source, required this.library});
  final _LocalComicSource source;
  final ReadingLibrary library;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('LumeBox · 移动端预览')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('本地演示素材', style: TextStyle(fontSize: 26)),
          const SizedBox(height: 12),
          const Text(
            '使用现有阅读器页面，检查触控、翻页、安全区、悬浮工具栏与玻璃效果。'
            '素材由本机生成，无需图源或网络。\n\niOS OCR、翻译、朗读、系统分享仍需 iPhone 验证。',
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('打开漫画阅读器'),
            onPressed: () => open(
              ComicReaderPage(
                library: library,
                dataSource: source,
                target: ReadingTarget(
                  sourceId: source.id,
                  itemId: 'mobile-preview',
                  title: '山间来信 · 本地演示',
                ),
                chapters: _LocalComicSource.chapterList,
                initialChapterIndex: 0,
                runtimeAvailable: true,
                pageBytes: source.bytesFor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.palette_outlined),
            label: const Text('打开现有设置页面'),
            onPressed: () => open(const SettingsPage(runtimeAvailable: true)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.tune_rounded),
            label: const Text('底部导航栏管理'),
            onPressed: () => open(const TabBarSettingsPage()),
          ),
        ],
      ),
    );
  }
}

class _LocalComicSource extends MockDataSource {
  _LocalComicSource(this.pages, this.server) : super(section: Section.comic);
  final List<Uint8List> pages;
  // Loopback also serves the reader's real preload/export image pipeline.
  final HttpServer server;
  static final chapterList = List.generate(
    24,
    (index) => SourceChapter(
      id: 'preview-chapter-${index + 1}',
      title:
          '第 ${index + 1} 话 · ${['午后的风', '远方的信', '穿过山谷', '雨后的晴空'][index % 4]}',
    ),
  );

  @override
  String get id => 'local.mobile.reader.preview';
  @override
  String get name => '本地演示素材';

  static Future<_LocalComicSource> create() async {
    final pages = <Uint8List>[
      for (var index = 0; index < 8; index++) await _paintPage(index),
    ];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final source = _LocalComicSource(pages, server);
    server.listen((request) async {
      final data = await source.bytesFor(request.uri.toString());
      if (data == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(data);
      }
      await request.response.close();
    });
    return source;
  }

  Future<Uint8List?> bytesFor(String url) async {
    final page = int.tryParse(Uri.parse(url).pathSegments.lastOrNull ?? '');
    return page == null || page < 0 || page >= pages.length
        ? null
        : pages[page];
  }

  @override
  Future<List<SourceChapter>> chapters(String itemId) async => chapterList;

  @override
  Future<ChapterContent?> content({
    required String itemId,
    required String chapterId,
  }) async => ImageContent([
    for (var page = 0; page < pages.length; page++)
      'http://127.0.0.1:${server.port}/$chapterId/$page',
  ]);
}

Future<Uint8List> _paintPage(int index) async {
  final width = index == 2 ? 1000 : 540;
  final height = index == 1
      ? 2200
      : index == 2
      ? 650
      : 1200;
  final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final tint = [
    const Color(0xFF9BBCC7),
    const Color(0xFFD2B5A5),
    const Color(0xFF9EBEB1),
    const Color(0xFFA6B0D3),
  ][index % 4];
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFF8F4ED), tint, const Color(0xFF527E75)],
      ).createShader(bounds),
  );
  canvas.drawCircle(
    Offset(width * .76, height * .32),
    width * .13,
    Paint()..color = const Color(0xFFF1C884),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, height * .72)
      ..lineTo(width * .22, height * .50)
      ..lineTo(width * .55, height * .72)
      ..lineTo(width * .82, height * .56)
      ..lineTo(width.toDouble(), height * .68)
      ..lineTo(width.toDouble(), height.toDouble())
      ..lineTo(0, height.toDouble())
      ..close(),
    Paint()..color = const Color(0xFF375F60),
  );
  final bubble = Rect.fromLTWH(36, height * .15, width * .70, 138);
  canvas.drawRRect(
    RRect.fromRectAndRadius(bubble, const Radius.circular(12)),
    Paint()..color = Colors.white,
  );
  final text = TextPainter(
    text: TextSpan(
      text: '山间来信  ${index + 1} / 8\n午后的风，带来远方的消息。',
      style: const TextStyle(
        color: Color(0xFF223B3C),
        fontSize: 26,
        height: 1.6,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: bubble.width - 36);
  text.paint(canvas, bubble.topLeft + const Offset(18, 20));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
