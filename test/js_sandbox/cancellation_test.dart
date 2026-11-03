import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_box/core/js/sandbox/sandbox.dart';
import 'package:lume_box/core/net/network_cancellation.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/source/source.dart';
import 'package:lume_box/core/util/lume_log.dart';

import 'support/js_sandbox_support.dart';

class _HeldHost implements SandboxHost {
  final started = Completer<void>();
  final response = Completer<Object?>();

  @override
  Future<Object?> invoke(SandboxHostRequest request) {
    started.complete();
    return response.future;
  }
}

class _CancelledRuntime implements JsSourceRuntime {
  @override
  Future<Object?> call(String method, [Object? argument]) async =>
      throw const NetworkCancelled();

  @override
  Future<Set<String>> contractMethods() async => {'categories', 'list'};
}

void main() {
  test(
    'data source preserves navigation cancellation instead of source failure',
    () async {
      final source = JsDataSource(
        id: 'cancelled',
        name: 'Cancelled',
        section: Section.video,
        runtime: _CancelledRuntime(),
      );
      await expectLater(source.list(), throwsA(isA<NetworkCancelled>()));
      await expectLater(source.categories(), throwsA(isA<NetworkCancelled>()));
    },
  );
  final available = installBridge();
  test(
    'cancelled queued/in-flight calls keep cancellation type and queue usable',
    () async {
      final host = _HeldHost();
      final sandbox = LumeSandbox.create(
        id: 'cancellation',
        host: host,
        policy: SandboxPolicy.standard.copyWith(allowHostAccess: true),
      );
      addTearDown(sandbox.dispose);
      expect(
        (await sandbox.load('''
      var source = {
        wait: function () { return LumeBridge.invoke('held', null); },
        next: function () { return 42; },
        fail: function () { throw new Error('real script failure'); }
      };
    ''')).isOk,
        isTrue,
      );
      LumeLog.clear();
      final active = NetworkCancellation();
      final queued = NetworkCancellation();
      final first = active.run(() => sandbox.call('source.wait'));
      final firstError = expectLater(first, throwsA(isA<NetworkCancelled>()));
      await host.started.future;
      final second = queued.run(() => sandbox.call('source.next'));
      final secondError = expectLater(second, throwsA(isA<NetworkCancelled>()));
      queued.cancel();
      active.cancel();
      host.response.complete('finished');
      await Future.wait([firstError, secondError]);
      expect(LumeLog.snapshot, isEmpty);
      expect(sandbox.lastFailure, isNull);
      expect((await sandbox.call('source.next')).value, 42);
      final failed = await sandbox.call('source.fail');
      expect(failed.error?.kind, SandboxErrorKind.script);
      expect(
        LumeLog.snapshot.any(
          (entry) => entry.message.contains('real script failure'),
        ),
        isTrue,
      );
    },
    skip: available ? false : 'QuickJS native bridge unavailable',
  );
}
