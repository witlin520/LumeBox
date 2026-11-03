import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/reading/image_pipeline.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/js_data_source.dart';

void main() {
  test('预取只占两个通道，可见图片越过待预取队列，重复预取不重复请求', () async {
    final started = <String>[];
    final gates = <String, Completer<NetworkResponse>>{};
    final firstTwo = Completer<void>(), visibleStarted = Completer<void>();
    final pipeline = SectionImagePipeline(
      cacheDir: '',
      diskCache: false,
      maxConcurrent: 4,
      maxRetries: 0,
      requestSender: (request) {
        final path = Uri.parse(request.url).path;
        started.add(path);
        final gate = gates[path] = Completer<NetworkResponse>();
        if (started.length == 2) firstTwo.complete();
        if (path == '/visible') visibleStarted.complete();
        return gate.future;
      },
    );
    final urls = [for (var i = 0; i < 6; i++) 'https://images.example/$i'];
    pipeline.preload(urls);
    pipeline.preload(urls);
    await firstTwo.future.timeout(const Duration(seconds: 2));
    expect(started, ['/0', '/1']);
    final visible = pipeline.image('https://images.example/visible');
    await visibleStarted.future.timeout(const Duration(seconds: 2));
    expect(started, ['/0', '/1', '/visible']);
    pipeline.dispose();
    for (final gate in gates.values) {
      gate.complete(
        const NetworkResponse(statusCode: 404, body: [], headers: {}),
      );
    }
    await visible;
    await Future<void>.delayed(Duration.zero);
    expect(started, ['/0', '/1', '/visible'], reason: '退出后不再继续排队的预取');
  });

  test('home 和 filters 同时探测只读取一次源契约，失败后允许重试', () async {
    final runtime = _ContractRuntime();
    final source = JsDataSource(
      id: 'a',
      name: '源',
      section: Section.video,
      runtime: runtime,
    );
    final home = source.supportsHome(), filters = source.supportsFilters();
    expect(runtime.calls, 1);
    runtime.pending.complete({'home', 'filters'});
    expect(await home, isTrue);
    expect(await filters, isTrue);
    expect(await source.supportsHome(), isTrue);
    expect(runtime.calls, 1);

    final retry = _ContractRuntime();
    final other = JsDataSource(
      id: 'b',
      name: '源',
      section: Section.video,
      runtime: retry,
    );
    final failed = expectLater(other.supportsHome(), throwsStateError);
    retry.pending.completeError(StateError('temporary'));
    await failed;
    retry.pending = Completer<Set<String>>();
    final second = other.supportsHome();
    retry.pending.complete({'home'});
    expect(await second, isTrue);
    expect(retry.calls, 2);
  });
}

class _ContractRuntime implements JsSourceRuntime {
  int calls = 0;
  Completer<Set<String>> pending = Completer<Set<String>>();
  @override
  Future<Set<String>> contractMethods() {
    calls++;
    return pending.future;
  }

  @override
  Future<Object?> call(String method, [Object? argument]) async => null;
}
