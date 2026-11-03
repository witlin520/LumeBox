import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lume_box/core/net/lume_net.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/net/network_cancellation.dart';
import 'package:lume_box/core/net/network_queue.dart';
import 'package:lume_box/core/net/network_settings.dart';

const ok = NetworkResponse(statusCode: 200, body: [1], headers: {'a': 'b'});
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('同一在途 GET 合并，响应不允许消费者互相修改；结束后重新发送', () async {
    final held = Completer<NetworkResponse>();
    var calls = 0;
    final queue = NetworkQueue(
      settings: const NetworkSettings(),
      sender: (_) {
        calls++;
        return held.future;
      },
    );
    const request = NetworkRequest(url: 'https://a.example/page');
    final a = queue.send(request), b = queue.send(request);
    await tick();
    expect(calls, 1);
    held.complete(ok);
    final responses = await Future.wait([a, b]);
    expect(() => responses[0].body.add(2), throwsUnsupportedError);
    expect(() => responses[0].headers['a'] = 'changed', throwsUnsupportedError);
    expect(responses[1].body, [1]);
    await queue.send(request);
    expect(calls, 2);
  });

  test('一个页面退出不取消另一个消费者，最后一个退出才停止物理请求', () async {
    final a = NetworkCancellation(), b = NetworkCancellation();
    final held = Completer<NetworkResponse>();
    late NetworkCancellation physical;
    var calls = 0;
    final queue = NetworkQueue(
      settings: const NetworkSettings(),
      sender: (r) {
        calls++;
        physical = r.cancellation!;
        return held.future;
      },
    );
    final first = queue.send(
      NetworkRequest(url: 'https://a.example', cancellation: a),
    );
    final second = queue.send(
      NetworkRequest(url: 'https://a.example', cancellation: b),
    );
    final firstError = expectLater(first, throwsA(isA<NetworkCancelled>()));
    final secondError = expectLater(second, throwsA(isA<NetworkCancelled>()));
    await tick();
    a.cancel();
    await firstError;
    expect(physical.isCancelled, false);
    expect(calls, 1);
    b.cancel();
    await secondError;
    await tick();
    expect(physical.isCancelled, true);
    expect(queue.activeGlobal, 0);
    expect(queue.failuresForHost('a.example'), 0);
    held.complete(ok);
  });

  test('不同 Cookie、源、读取范围和非幂等请求不合并', () async {
    var calls = 0;
    final held = Completer<NetworkResponse>();
    final queue = NetworkQueue(
      settings: const NetworkSettings(
        globalConcurrency: 12,
        perHostConcurrency: 12,
      ),
      sender: (_) {
        calls++;
        return held.future;
      },
    );
    final requests = [
      const NetworkRequest(
        url: 'https://a.example',
        headers: {'Cookie': 'a=1'},
      ),
      const NetworkRequest(
        url: 'https://a.example',
        headers: {'Cookie': 'a=2'},
      ),
      const NetworkRequest(url: 'https://a.example', source: 'other'),
      const NetworkRequest(url: 'https://a.example', maxBytes: 4),
      const NetworkRequest(url: 'https://a.example', method: 'POST'),
      const NetworkRequest(url: 'https://a.example', method: 'POST'),
    ];
    final pending = requests.map(queue.send).toList();
    await tick();
    expect(calls, requests.length);
    held.complete(ok);
    await Future.wait(pending);
  });

  test('排队取消立即移出等待队列，且从未发送', () async {
    final held = Completer<NetworkResponse>();
    final calls = <String>[];
    final queue = NetworkQueue(
      settings: const NetworkSettings(
        globalConcurrency: 1,
        perHostConcurrency: 1,
      ),
      sender: (r) {
        calls.add(r.url);
        return held.future;
      },
    );
    final first = queue.send(const NetworkRequest(url: 'https://a.example/1'));
    final token = NetworkCancellation();
    final second = queue.send(
      NetworkRequest(url: 'https://a.example/2', cancellation: token),
    );
    final error = expectLater(second, throwsA(isA<NetworkCancelled>()));
    await tick();
    expect(queue.waitingCount, 1);
    token.cancel();
    await error;
    await tick();
    expect(queue.waitingCount, 0);
    held.complete(ok);
    await first;
    expect(calls, ['https://a.example/1']);
  });

  test('开始前取消不会发送，总预算到期会取消发送端', () async {
    var calls = 0;
    late NetworkCancellation physical;
    final held = Completer<NetworkResponse>();
    final queue = NetworkQueue(
      settings: const NetworkSettings(),
      sender: (r) {
        calls++;
        physical = r.cancellation!;
        return held.future;
      },
    );
    final token = NetworkCancellation()..cancel();
    await expectLater(
      queue.send(NetworkRequest(url: 'https://a.example', cancellation: token)),
      throwsA(isA<NetworkCancelled>()),
    );
    expect(calls, 0);
    await expectLater(
      queue.send(
        const NetworkRequest(
          url: 'https://a.example',
          retryOn: false,
          timeout: Duration(milliseconds: 20),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(physical.isCancelled, true);
    expect(queue.activeGlobal, 0);
    held.complete(ok);
  });

  test('真实 HTTP 传输可以中断，不只是让页面停止等结果', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    final listener = server.listen((request) {
      received.complete();
    });
    addTearDown(() async {
      LumeNet.closeSharedClientForTesting();
      await server.close(force: true);
      await listener.cancel();
    });
    final token = NetworkCancellation();
    final pending = LumeNet.sendDirect(
      NetworkRequest(
        url: 'http://127.0.0.1:${server.port}/held',
        cancellation: token,
      ),
    );
    final error = expectLater(
      pending,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await received.future.timeout(const Duration(seconds: 2));
    token.cancel();
    await error.timeout(const Duration(seconds: 2));
  });

  test('页面总超时会取消底层 token，晚到响应被吸收且同槽新任务不受旧计时器影响', () async {
    final owner = NetworkRequestOwner();
    addTearDown(owner.dispose);
    final held = Completer<int>();
    late NetworkCancellation token;
    final run = owner.run('home', () {
      token = NetworkCancellation.current!;
      return held.future;
    }, timeout: const Duration(milliseconds: 20));
    final error = expectLater(run, throwsA(isA<TimeoutException>()));
    await error;
    expect(token.isCancelled, isTrue);
    held.completeError(StateError('late'));
    await tick();
    expect(await owner.run('home', () async => 7), 7);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await owner.run('home', () async => 8), 8);
  });

  test('页面替换任务与 dispose 取消各自 Zone，晚到错误被吸收', () async {
    final owner = NetworkRequestOwner();
    final firstHeld = Completer<int>(), secondHeld = Completer<int>();
    late NetworkCancellation firstToken, secondToken;
    final first = owner.run('list', () {
      firstToken = NetworkCancellation.current!;
      return firstHeld.future;
    });
    final firstError = expectLater(first, throwsA(isA<NetworkCancelled>()));
    final second = owner.run('list', () {
      secondToken = NetworkCancellation.current!;
      return secondHeld.future;
    });
    final secondError = expectLater(second, throwsA(isA<NetworkCancelled>()));
    await firstError;
    expect(firstToken.isCancelled, true);
    expect(secondToken.isCancelled, false);
    owner.dispose();
    await secondError;
    expect(secondToken.isCancelled, true);
    firstHeld.completeError(StateError('late'));
    secondHeld.complete(2);
    await tick();
    await expectLater(
      owner.run('list', () async => 3),
      throwsA(isA<NetworkCancelled>()),
    );
  });
}
