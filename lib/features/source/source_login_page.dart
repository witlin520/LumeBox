import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/net/ios_verified_webview.dart';
import '../../core/net/lume_http.dart';
import '../../core/net/site_session_pool.dart';
import '../../core/net/web_session_lifecycle.dart';
import '../../core/net/waf.dart';
import '../../core/session/section.dart';
import '../../core/cache/section_memory_cache.dart';

class SourceLoginCredentials {
  const SourceLoginCredentials(this.account, this.password);
  final String account, password;
}

/// 一个站点登录流程：网页登录自动同步，源所需账号资料也在此编辑。
class SourceLoginPage extends StatefulWidget {
  const SourceLoginPage({
    super.key,
    required this.section,
    required this.sourceId,
    required this.name,
    required this.url,
    this.userAgent,
    this.loginMode = true,
    this.title,
    this.credentials,
    this.onCredentialsChanged,
  });
  final Section section;
  final String sourceId, name, url;
  final String? userAgent;
  final bool loginMode;

  /// 自定义标题（例如「打开发布页」）；为空时按登录/作品网页自动生成。
  final String? title;
  final SourceLoginCredentials? credentials;
  final ValueChanged<SourceLoginCredentials>? onCredentialsChanged;
  static String status(Map evidence, Map<String, String> cookies) {
    if (evidence['blocked'] == true) return '站点拒绝访问或等待验证，请先在网页中处理';
    if (evidence['loggedIn'] == true) {
      return '已检测到站点登录，会话已同步；章节购买权限仍由站点决定';
    }
    if (evidence['loginForm'] == true) return '尚未登录，请在下方站点页面登录';
    if (cookies.keys.any((k) => k.startsWith('wordpress_logged_in_'))) {
      return '已同步登录凭据；请在站点个人中心核实会话是否有效';
    }
    return '会话已同步；本站未提供可识别的登录标志，请在个人中心核对';
  }

  @override
  State<SourceLoginPage> createState() => _SourceLoginPageState();
}

class _SourceLoginPageState extends State<SourceLoginPage>
    with WidgetsBindingObserver {
  late final controller = WebViewController();
  String status = '正在打开站点…';
  bool checking = false;
  bool _ready = false;
  Timer? _autoSync;
  String? _lastSession;
  Future<void> _sessionQueue = Future.value();
  late SourceLoginCredentials _credentials =
      widget.credentials ?? const SourceLoginCredentials('', '');

  Future<void> _editCredentials() async {
    final account = TextEditingController(text: _credentials.account);
    final password = TextEditingController(text: _credentials.password);
    final route = DialogRoute<SourceLoginCredentials>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('本站账号资料'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仅在源要求保存账号资料时填写。网页登录仍在本站网页完成，返回源设置后点保存生效。'),
              const SizedBox(height: 12),
              TextField(
                controller: account,
                decoration: const InputDecoration(labelText: '账号'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '密码'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              SourceLoginCredentials(account.text.trim(), password.text),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    unawaited(
      route.completed.then((_) {
        account.dispose();
        password.dispose();
      }),
    );
    if (!mounted || result == null) return;
    _credentials = result;
    widget.onCredentialsChanged?.call(result);
  }

  void _startAutoSync() {
    _autoSync?.cancel();
    _autoSync = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_ready && mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_check());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoSync();
      if (_ready) unawaited(_check());
    } else {
      _autoSync?.cancel();
    }
  }

  @override
  void dispose() {
    _autoSync?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<Map<String, String>> _synchronizeSession() {
    final task = _sessionQueue.then((_) async {
      final native = await IosVerifiedWebView.channel
          .invokeMethod<List<Object?>>('allCookies', {'url': widget.url})
          .timeout(const Duration(seconds: 3));
      final cookies = webViewCookiesForUrl(native ?? [], widget.url);
      await SiteSessionPool.shared.synchronize(widget.url, {'User-Agent': ua});
      final identity = jsonEncode({
        for (final key in cookies.keys.toList()..sort()) key: cookies[key],
      });
      if (identity != _lastSession) {
        WafSessions.save(widget.section, widget.sourceId, cookies);
        WafSessions.saveUserAgent(widget.section, widget.sourceId, ua);
        SectionMemoryCache.instance.removeSource(
          widget.section,
          widget.sourceId,
        );
        _lastSession = identity;
      }
      return cookies;
    });
    _sessionQueue = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return task;
  }

  late final ua =
      SiteSessionPool.shared.userAgentFor(widget.url) ??
      (widget.userAgent?.trim().isNotEmpty == true
          ? widget.userAgent!
          : WafSessions.userAgentFor(widget.section, widget.sourceId) ??
                LumeHttp.defaultUserAgent);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoSync();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(ua);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (request.isMainFrame &&
                uri?.host == Uri.parse(widget.url).host &&
                RegExp(
                  r'logout|log-out|signout|customer-logout',
                  caseSensitive: false,
                ).hasMatch('${uri?.path}?${uri?.query}')) {
              WebSessionLifecycle.invalidate(
                hosts: {Uri.parse(widget.url).host},
              );
              WafSessions.storeOf(widget.section)?.clear(widget.sourceId);
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) => unawaited(_check()),
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true) {
              setState(() => status = '网页加载失败，可刷新重试');
            }
          },
        ),
      );
      final uri = Uri.parse(widget.url);
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException();
      }
      await controller.loadRequest(uri);
      _ready = true;
    } catch (_) {
      if (mounted) setState(() => status = '站点网页无法打开，请检查地址与网络');
    }
  }

  Future<void> _check() async {
    if (checking || !mounted) return;
    setState(() => checking = true);
    try {
      final current = Uri.tryParse(
        await controller.currentUrl().timeout(const Duration(seconds: 3)) ?? '',
      );
      if (current?.host != Uri.parse(widget.url).host) {
        if (mounted) setState(() => status = '请完成授权并返回原站点，App 会自动同步登录状态');
        return;
      }
      final raw = await controller
          .runJavaScriptReturningResult('''JSON.stringify({
        loggedIn:document.body.classList.contains('logged-in') || !!document.querySelector('a[href*="action=logout"],a[href*="customer-logout"]'),
        loginForm:!!document.querySelector('input[type="password"]'),
        blocked:/Sorry, you have been blocked|Just a moment|Attention Required/i.test(document.title+' '+document.body.innerText.slice(0,500))
      })''')
          .timeout(const Duration(seconds: 3));
      var parsed = jsonDecode('$raw');
      if (parsed is String) parsed = jsonDecode(parsed);
      final cookies = await _synchronizeSession();
      if (mounted) {
        setState(
          () => status = SourceLoginPage.status(
            parsed is Map ? parsed : {},
            cookies,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => status = '暂未同步登录状态，App 会自动重试');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop || !_ready) return;
      // Native cookies outlive the page. Collect the final state on every back
      // path, including swipe-back, without adding another user action.
      _autoSync?.cancel();
      unawaited(
        _synchronizeSession().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? '${widget.name} · ${widget.loginMode ? '登录' : '作品网页'}',
        ),
        actions: [
          if (widget.loginMode && widget.onCredentialsChanged != null)
            IconButton(
              tooltip: '账号资料',
              onPressed: _editCredentials,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          IconButton(
            tooltip: '刷新网页',
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [Expanded(child: Text(status))]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              widget.loginMode
                  ? '在下方网页登录，App 会自动同步登录状态，完成后直接返回即可。'
                  : '可在本站网页中选择章节阅读；若仍显示拒绝访问，说明站点也拦截了当前网页连接。',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ),
  );
}
