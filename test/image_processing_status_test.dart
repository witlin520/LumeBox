import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/reading/comic_image_tools.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/tmdb/tmdb.dart';
import 'package:lume_box/features/reading/poster_card.dart';
import 'package:lume_box/features/video/tmdb_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ComicImageTools tools;
  late SectionImagePipeline pipeline;
  var nativeCalls = 0, downloads = 0;
  final small = img.encodePng(img.Image(width: 40, height: 80));
  setUp(() {
    nativeCalls = downloads = 0;
    ComicImageTools.debugAutomaticSupported = true;
    tools = ComicImageTools(
      settings: ComicImageToolsSettings()
        ..automatic = true
        ..upscaleCovers = true
        ..upscaleVideoPosters = true,
    );
    messenger.setMockMethodCallHandler(ComicImageTools.channel, (call) async {
      if (call.method != 'superResolve') return null;
      nativeCalls++;
      final bytes = (call.arguments as Map)['bytes'] as Uint8List;
      final image = img.decodeImage(bytes)!;
      if (image.width >= 1080) {
        return {
          'bytes': bytes,
          'status': 'skipped',
          'width': image.width,
          'height': image.height,
          'reason': '原图已达到宽度阈值',
        };
      }
      return {
        'bytes': img.encodePng(
          img.copyResize(
            image,
            width: image.width * 2,
            height: image.height * 2,
          ),
        ),
        'status': 'processed',
        'width': image.width,
        'height': image.height,
        'outputWidth': image.width * 2,
        'outputHeight': image.height * 2,
      };
    });
    pipeline = SectionImagePipeline(
      cacheDir: '',
      diskCache: false,
      cacheOriginalBytes: true,
      decodeTransform: (bytes) =>
          tools.automatic(bytes, surface: UpscaleSurface.videoPoster),
      requestSender: (request) async {
        downloads++;
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
        return NetworkResponse(
          statusCode: 200,
          body: request.url.contains('large')
              ? img.encodePng(img.Image(width: 1200, height: 1))
              : small,
          headers: const {'content-type': 'image/png'},
        );
      },
    );
  });
  tearDown(() {
    tools.dispose();
    pipeline.dispose();
    ComicImageTools.debugAutomaticSupported = null;
    messenger.setMockMethodCallHandler(ComicImageTools.channel, null);
  });

  test('并发图片分别记录完成和跳过状态；取色与原图导出不会再超分', () async {
    const a = 'https://status-fixture.test/small.png',
        b = 'https://status-fixture.test/large.png';
    final images = await Future.wait([pipeline.image(a), pipeline.image(b)]);
    expect(images.first!.width, 80);
    expect(pipeline.processingReport(a)!.summary, contains('40×80 → 80×160'));
    expect(pipeline.processingReport(b)!.status, 'skipped');
    expect(pipeline.processingReport(b)!.width, 1200);
    expect(await pipeline.bytes(a), small);
    final sample = await pipeline.colorSample(a);
    sample!.dispose();
    expect(nativeCalls, 2);
    expect(downloads, 2);
    pipeline.release(a);
    pipeline.release(b);
  });

  testWidgets('TMDB 海报接入超分并可查看尺寸，评分简介和匹配结果保持原值', (tester) async {
    const url = 'https://tmdb-status-fixture.test/poster.png';
    const metadata = TmdbMetadata(
      overview: '原始简介',
      posters: [url],
      rating: 8.2,
      year: '2026',
      episodeCount: 24,
    );
    final controller = TmdbDetailController(
      '测试影片',
      settings: TmdbSettings()..enabled = true,
      autoLoad: false,
    )..metadata = metadata;
    addTearDown(controller.dispose);
    String? displayed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 200,
                height: 300,
                child: TmdbPosterGallery(
                  controller: controller,
                  imagePipeline: pipeline,
                  fallback: const Text('加载中'),
                  onArtworkDisplayed: (url) => displayed = url,
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showImageProcessingInfo(
                    context,
                    pipeline: pipeline,
                    url: url,
                    origin: 'TMDB 海报',
                    surface: UpscaleSurface.videoPoster,
                  ),
                  child: const Text('图片状态'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(displayed, url);
    expect(identical(controller.metadata, metadata), true);
    expect(nativeCalls, 1);
    await tester.tap(find.text('图片状态'));
    await tester.pumpAndSettle();
    expect(find.textContaining('40×80 → 80×160'), findsOneWidget);
    expect(find.textContaining('TMDB 海报'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
