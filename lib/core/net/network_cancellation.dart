import 'dart:async';

class NetworkCancelled implements Exception {
  const NetworkCancelled([this.message = '请求已取消']);
  final String message;
  @override
  String toString() => message;
}

/// One consumer's lifetime. Cancelling a consumer never cancels another one.
class NetworkCancellation {
  static final _zoneKey = Object();
  static NetworkCancellation? get current =>
      Zone.current[_zoneKey] as NetworkCancellation?;
  final _listeners = <void Function()>{};
  final _signal = Completer<void>();
  Object? _reason;
  bool get isCancelled => _reason != null;
  Future<void> get signal => _signal.future;
  void check() {
    if (_reason case final reason?) throw reason;
  }

  void cancel([Object reason = const NetworkCancelled()]) {
    if (isCancelled) return;
    _reason = reason;
    _signal.complete();
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  T run<T>(T Function() action) => runWith(this, action);
  static T runWith<T>(NetworkCancellation? token, T Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: token});
  Future<T> guard<T>(Future<T> operation) {
    final done = Completer<T>();
    final remove = onCancel(() {
      if (!done.isCompleted) done.completeError(_reason!);
    });
    operation.then(
      (value) {
        if (!done.isCompleted) done.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    return done.future.whenComplete(remove);
  }

  Future<void> delay(Duration duration) {
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    final remove = onCancel(() {
      timer.cancel();
      if (!done.isCompleted) done.completeError(_reason!);
    });
    return done.future.whenComplete(remove);
  }
}

/// Separate slots allow a page to replace a search without cancelling its images.
class NetworkRequestOwner {
  final _slots = <String, NetworkCancellation>{};
  bool _disposed = false;
  Future<T> run<T>(
    String slot,
    Future<T> Function() operation, {
    Duration? timeout,
    Object Function()? timeoutError,
  }) {
    if (_disposed) return Future.error(const NetworkCancelled());
    _slots.remove(slot)?.cancel();
    final token = NetworkCancellation();
    _slots[slot] = token;
    final timer = timeout == null
        ? null
        : Timer(
            timeout,
            () => token.cancel(
              timeoutError?.call() ?? TimeoutException('请求超时', timeout),
            ),
          );
    return token.run(() => token.guard(Future.sync(operation))).whenComplete(
      () {
        timer?.cancel();
        if (identical(_slots[slot], token)) _slots.remove(slot);
      },
    );
  }

  void cancelAll() {
    for (final token in _slots.values.toList()) {
      token.cancel();
    }
    _slots.clear();
  }

  void cancel(String slot) => _slots.remove(slot)?.cancel();

  void dispose() {
    _disposed = true;
    cancelAll();
  }
}
