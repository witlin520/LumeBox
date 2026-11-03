import '../net/lume_net.dart';

import 'dart:async';

import '../net/network_cancellation.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import '../net/site_session_pool.dart';
import '../net/source_request_log.dart';
import '../net/verified_bridge_policy.dart';
import '../net/web_session_lifecycle.dart';

class SourceWebVerificationException implements Exception {
  @override
  String toString() => 'NEED_WEBVIEW_VERIFY：网页需要人工验证，请在网页视图完成后重试';
}

class SourceWebFailure extends StateError {
  SourceWebFailure(this.code, String message) : super('$code：$message');
  final String code;
}

/// Shared by JS and embedded Python. Native WebKit and SwiftSoup run on-device.
class SourceWebRuntime {
  SourceWebRuntime(this.scope);
  final String scope;
  static const channel = MethodChannel('lumebox/source_web');
  bool _disposed = false;
  final Set<String> _pending = {};
  final _lifetime = NetworkCancellation();
  static int _sequence = 0;
  static final Map<String, String> _retained = {};
  static final Map<String, String> _retainedRevisions = {};
  final Set<String> _ownedRetained = {};
  VerifiedBridgePolicy? _bridgePolicy;
  String? _bridgeRevision;
  String? _origin;
  int _bridgeActive = 0;
  Future<Object?> bridge(String method, Map<String, dynamic> payload) async {
    if (_disposed) throw StateError('源已释放');
    if (method == 'configure') {
      final policy = VerifiedBridgePolicy(payload);
      final revision = WebSessionLifecycle.revision(policy.origin);
      final token = NetworkCancellation.current;
      token?.check();
      final operation = channel
          .invokeMethod<Object?>('bridge.configure', {
            'scope': scope,
            'origin': policy.origin,
            'paths': policy.paths.toList(),
          })
          .timeout(const Duration(seconds: 5));
      Object? result;
      try {
        result = await _lifetime.guard(
          token == null ? operation : token.guard(operation),
        );
      } on PlatformException catch (error) {
        throw PlatformException(
          code: error.code,
          message: bridgeErrorMessage(error.code),
        );
      }
      if (_disposed) throw StateError('源已释放');
      if (revision != WebSessionLifecycle.revision(policy.origin)) {
        throw SourceWebFailure('bridge_unverified', '会话已失效，请重新验证');
      }
      if (result != true) throw StateError('请求桥配置未获验证页面接受');
      _bridgePolicy = policy;
      _bridgeRevision = revision;
      _origin = policy.origin;
      return result;
    }
    if (method != 'request' || _bridgePolicy == null) {
      throw StateError('请求桥尚未声明白名单或验证未通过');
    }
    if (_bridgeActive >= 2) throw StateError('请求桥最多同时执行两个请求');
    if (_bridgeRevision !=
        WebSessionLifecycle.revision(_bridgePolicy!.origin)) {
      _bridgePolicy = null;
      throw SourceWebFailure('bridge_unverified', '会话已失效，请重新验证');
    }
    final request = _bridgePolicy!.validate(payload);
    final revision = _bridgeRevision;
    final origin = _bridgePolicy!.origin;
    final token = NetworkCancellation.current;
    token?.check();
    final remove = token?.onCancel(() {
      _bridgePolicy = null;
      unawaited(
        channel
            .invokeMethod<void>('bridge.close', {'scope': scope})
            .catchError((_) {}),
      );
    });
    _bridgeActive++;
    try {
      final operation = channel
          .invokeMethod<Object?>('bridge.request', {'scope': scope, ...request})
          .timeout(
            Duration(milliseconds: (request['timeoutMs'] as int) + 1000),
          );
      final result = await _lifetime.guard(
        token == null ? operation : token.guard(operation),
      );
      if (revision != WebSessionLifecycle.revision(origin)) {
        throw SourceWebFailure('bridge_unverified', '会话已失效，请重新验证');
      }
      if (result is Map && result['status'] is num) {
        final status = (result['status'] as num).toInt();
        return {
          ...result,
          if (status >= 400)
            'failureKind': switch (status) {
              401 => 'session_expired',
              403 => 'source_rejected',
              429 => 'rate_limited',
              _ => 'upstream_http',
            },
        };
      }
      return result;
    } on PlatformException catch (error) {
      if ([
        'bridge_unverified',
        'bridge_timeout',
        'cancelled',
      ].contains(error.code)) {
        _bridgePolicy = null;
      }
      throw SourceWebFailure(error.code, bridgeErrorMessage(error.code));
    } finally {
      remove?.call();
      _bridgeActive--;
    }
  }

  static bool hasRetained(String url) =>
      _retained.containsKey(Uri.tryParse(url)?.host) &&
      _retainedRevisions[Uri.tryParse(url)?.host] ==
          WebSessionLifecycle.revision(url);
  static Future<Map<String, dynamic>?> verifyRetained(String url) async {
    final token = NetworkCancellation.current;
    token?.check();
    final id = _retained.remove(Uri.parse(url).host);
    if (id == null) return null;
    final revision = _retainedRevisions.remove(Uri.parse(url).host);
    if (revision != WebSessionLifecycle.revision(url)) {
      await channel.invokeMethod<void>('cancel', {'requestId': id});
      return null;
    }
    final remove = token?.onCancel(
      () => unawaited(
        channel
            .invokeMethod<void>('cancel', {'requestId': id})
            .catchError((_) {}),
      ),
    );
    Map<String, dynamic>? reply;
    try {
      final operation = channel.invokeMapMethod<String, dynamic>('verify', {
        'requestId': id,
      });
      reply = await (token == null ? operation : token.guard(operation));
    } on TimeoutException {
      await channel.invokeMethod<void>('cancel', {'requestId': id});
      rethrow;
    } finally {
      remove?.call();
    }
    if (revision != WebSessionLifecycle.revision(url)) return null;
    if (reply?['verified'] == true) {
      if (reply?['verificationSession'] is Map) {
        SiteSessionPool.shared.importVerification(
          url,
          reply!['verificationSession'] as Map,
        );
      }
      SiteSessionPool.shared.rememberPage(
        url,
        userAgent: reply?['userAgent'] as String?,
      );
      await SiteSessionPool.shared.synchronize(url, {});
      LumeNet.queue.clearInvalidLinks();
    }
    return reply;
  }

  Future<Object?> invoke(String method, Map<String, dynamic> payload) async {
    if (_disposed) throw StateError('源已释放');
    final id = '$scope:${_sequence++}';
    final args = Map<String, dynamic>.of(payload);
    if (method == 'render') {
      final url = Uri.tryParse('${args['url'] ?? ''}');
      if (url == null ||
          !['http', 'https'].contains(url.scheme) ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty) {
        throw const FormatException('网页地址必须是完整的 http(s) 地址');
      }
      final method = '${args['method'] ?? 'GET'}'.toUpperCase();
      if (!['GET', 'POST'].contains(method)) {
        throw const FormatException('网页导航只支持 GET／POST');
      }
      args['method'] = method;
      if (args['body'] != null &&
          (args['body'] is! String ||
              utf8.encode(args['body'] as String).length > 128 * 1024)) {
        throw const FormatException('网页表单正文无效或超过 128KB');
      }
      final timeout = args['timeoutMs'] ?? 6000;
      if (timeout is! num || !timeout.isFinite) {
        throw const FormatException('网页超时参数无效');
      }
      args['timeoutMs'] = timeout.round().clamp(100, 8000);
      for (final key in ['pageTimeoutMs', 'elementTimeoutMs', 'apiTimeoutMs']) {
        final value = args[key] ?? args['timeoutMs'];
        if (value is! num || !value.isFinite) throw FormatException('$key 无效');
        args[key] = value.round().clamp(100, args['timeoutMs'] as int);
      }
      final steps = args['steps'] ?? const [];
      if (steps is! List || steps.length > 16) {
        throw const FormatException('网页交互最多 16 步');
      }
      for (final step in steps) {
        if (step is! Map ||
            !['wait', 'click', 'fill', 'evaluate'].contains(step['type'])) {
          throw const FormatException('网页交互步骤类型无效');
        }
        if (step['type'] != 'evaluate' &&
            (step['selector'] is! String ||
                (step['selector'] as String).trim().isEmpty)) {
          throw const FormatException('网页交互步骤缺少 selector');
        }
      }
      args['steps'] = steps;
    } else if (method == 'extract') {
      if (args['html'] is! String ||
          utf8.encode(args['html'] as String).length > 2 * 1024 * 1024) {
        throw const FormatException('HTML 正文为空或超过 2MB');
      }
      final fields = args['fields'];
      if (fields is! Map || fields.isEmpty || fields.length > 32) {
        throw const FormatException('HTML 提取需要 1–32 个字段');
      }
      for (final field in fields.values) {
        if (field is! Map) throw const FormatException('HTML 字段规则必须是对象');
      }
    } else {
      throw const FormatException('不支持的网页宿主接口');
    }
    final token = NetworkCancellation.current;
    token?.check();
    _pending.add(id);
    final stopCancel = token?.onCancel(() => unawaited(_cancel(id)));
    try {
      if (method == 'render') {
        final url = args['url'] as String;
        final origin = Uri.parse(url).origin;
        if (_origin != null && _origin != origin) {
          _bridgePolicy = null;
          await channel.invokeMethod<void>('bridge.close', {'scope': scope});
        }
        _origin = origin;
        SourceRequestLog.record(scope, url);
        final headers = (args['headers'] as Map? ?? {}).map(
          (k, v) => MapEntry('$k', '$v'),
        );
        args['headers'] = await SiteSessionPool.shared.synchronize(
          url,
          headers,
          forceCookies: args['forceCookies'] == true,
        );
        if (_disposed) throw StateError('源已释放');
        args['userAgent'] =
            SiteSessionPool.shared.userAgentFor(url) ?? args['userAgent'];
        args['inspectable'] = SiteSessionPool.shared.inspectable;
        args['verificationStorage'] = SiteSessionPool.shared.storageFor(url);
      }
      token?.check();
      final result = await channel
          .invokeMethod<Object?>(method, {
            ...args,
            'requestId': id,
            'scope': scope,
          })
          .timeout(
            Duration(
              milliseconds: method == 'render'
                  ? (args['timeoutMs'] as int) + 500
                  : 5000,
            ),
          );
      if (_disposed) throw StateError('源已释放');
      token?.check();
      if (method == 'render' && result is Map) {
        if (result['requiresVerification'] == true) {
          throw SourceWebVerificationException();
        }
        if (result['status'] == 429) {
          throw SourceWebFailure('rate_limited', '网站请求过于频繁（HTTP 429），请稍后重试');
        }
        if (result['status'] == 401 || result['status'] == 403) {
          final blocked = RegExp(
            r'(error.?1020|ip (?:address )?(?:has been )?(?:banned|blocked))',
            caseSensitive: false,
          ).hasMatch('${result['html']}');
          throw SourceWebFailure(
            blocked ? 'ip_blocked' : 'http_${result['status']}',
            blocked ? '站点明确提示 IP 访问受限' : '网页拒绝访问，请检查登录或防盗链设置',
          );
        }
      }
      if ((method == 'render' &&
              (result is! Map || result['html'] is! String)) ||
          (method == 'extract' &&
              (result is! List || result.any((row) => row is! Map)))) {
        throw const FormatException('网页宿主返回格式无效');
      }
      if (method == 'render' && result is Map) {
        final url = '${result['url'] ?? args['url']}';
        SiteSessionPool.shared.rememberPage(
          url,
          userAgent: args['userAgent'] as String?,
        );
        await SiteSessionPool.shared.synchronize(url, {});
      }
      if (_disposed) throw StateError('源已释放');
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'verification') {
        if (_disposed || token?.isCancelled == true) {
          unawaited(_cancel(id));
          token?.check();
          throw StateError('源已释放');
        }
        _retained.clear();
        _retainedRevisions.clear();
        _retained[Uri.parse(args['url'] as String).host] = id;
        _retainedRevisions[Uri.parse(args['url'] as String)
            .host] = WebSessionLifecycle.revision(
          args['url'] as String,
        );
        _ownedRetained.add(id);
        throw SourceWebVerificationException();
      }
      rethrow;
    } on MissingPluginException {
      throw UnsupportedError('此能力需要包含 WebKit／SwiftSoup 的 iOS 安装包');
    } on TimeoutException {
      unawaited(_cancel(id));
      throw TimeoutException('网页操作超时');
    } finally {
      stopCancel?.call();
      _pending.remove(id);
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await channel.invokeMethod<void>('cancel', {'requestId': id});
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lifetime.cancel();
    _bridgePolicy = null;
    unawaited(
      channel
          .invokeMethod<void>('bridge.close', {'scope': scope})
          .catchError((_) {}),
    );
    for (final id in _pending.toList()) {
      unawaited(_cancel(id));
    }
    _pending.clear();
    for (final host in _retained.keys.toList()) {
      if (_ownedRetained.contains(_retained[host])) {
        unawaited(_cancel(_retained.remove(host)!));
        _retainedRevisions.remove(host);
      }
    }
    _ownedRetained.clear();
  }

  static String bridgeErrorMessage(String code) => switch (code) {
    'bridge_unverified' => '验证会话已失效，请重新完成验证',
    'bridge_timeout' => '页面请求超时，请检查网络后重试',
    'bridge_scope' || 'bridge_headers' => '源请求超出请求桥允许范围，请更新源配置',
    'cancelled' => '网页请求已取消',
    'bridge_request' => '页面请求失败，请检查网络或源签名；不会自动判为验证失败',
    _ => '页面请求失败，请检查源配置',
  };
}
