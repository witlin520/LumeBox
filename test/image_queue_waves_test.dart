import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/reading/image_pipeline.dart';

void main() {
  test('封面排队后完整释放名额，下一批及换源后的新图片继续加载', () async {
    var active = 0, peak = 0, count = 0;
    final pipeline = SectionImagePipeline(
      cacheDir: '',
      diskCache: false,
      maxConcurrent: 2,
      maxRetries: 0,
      requestSender: (_) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 3));
        active--;
        count++;
        return const NetworkResponse(
          statusCode: 200,
          body: [1, 2, 3],
          headers: {},
        );
      },
    );
    addTearDown(pipeline.dispose);
    for (var wave = 0; wave < 3; wave++) {
      final images = await Future.wait(
        List.generate(
          12,
          (index) => pipeline.fetch('https://example.com/$wave/$index.jpg'),
        ),
      ).timeout(const Duration(seconds: 1));
      expect(images.every((bytes) => bytes != null), isTrue);
    }
    expect(count, 36);
    expect(peak, 2);
    expect(active, 0);
  });
}
