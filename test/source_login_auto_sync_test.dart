import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:lume_box/core/reading/reading.dart';
import 'package:lume_box/core/session/section.dart';
import 'package:lume_box/core/session/section_scope.dart';
import 'package:lume_box/core/net/waf.dart';
import 'package:lume_box/features/source/source_login_page.dart';

class _Platform extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;
  bool loggedIn = false;
  String url = 'https://login.example/';
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params, this);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.owner) : super.implementation();
  final _Platform owner;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setUserAgent(String? agent) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    owner.url = params.uri.toString();
  }

  @override
  Future<String?> currentUrl() async => owner.url;
  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      jsonEncode({'loggedIn': owner.loggedIn, 'loginForm': !owner.loggedIn});
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback finished;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late Directory root;
  var reads = 0;
  var session = 'guest';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    root = Directory.systemTemp.createTempSync('login-auto-');
    platform = _Platform();
    WebViewPlatform.instance = platform;
    reads = 0;
    session = 'guest';
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('lumebox/webview'), (
      call,
    ) async {
      if (call.method != 'allCookies') return null;
      expectSync((call.arguments as Map)['url'], 'https://login.example/');
      reads++;
      return [
        {
          'name': 'session',
          'value': session,
          'domain': 'login.example',
          'path': '/',
        },
        {
          'name': 'foreign',
          'value': 'must-not-import',
          'domain': 'other.example',
          'path': '/',
        },
      ];
    });
  });
  tearDown(() async {
    ReadingLibrary.disposeAll();
    ReadingStore.disposeAll();
    await SectionScope.closeAll();
    WafSessions.resetForTesting();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('lumebox/webview'),
      null,
    );
    root.deleteSync(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    ValueChanged<SourceLoginCredentials>? onCredentialsChanged,
  }) async {
    await tester.runAsync(() => ReadingLibrary.open(Section.video));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SourceLoginPage(
                    section: Section.video,
                    sourceId: 'fixture',
                    name: '测试源',
                    url: 'https://login.example/',
                    credentials: const SourceLoginCredentials(
                      'saved-user',
                      'saved-password',
                    ),
                    onCredentialsChanged: onCredentialsChanged,
                  ),
                ),
              ),
              child: const Text('登录站点'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('登录站点'));
    await tester.pumpAndSettle();
  }

  testWidgets('网页加载和同页登录自动同步，直接返回取最终会话并停止轮询', (tester) async {
    await open(tester);
    expect(find.text('检查登录'), findsNothing);
    platform.delegate.finished(platform.url);
    await flush(tester);
    expect(WafSessions.cookiesFor(Section.video, 'fixture'), 'session=guest');
    platform.loggedIn = true;
    session = 'signed-in';
    await tester.pump(const Duration(seconds: 2));
    await flush(tester);
    expect(
      WafSessions.cookiesFor(Section.video, 'fixture'),
      'session=signed-in',
    );
    expect(find.textContaining('已检测到站点登录'), findsOneWidget);
    session = 'final-value';
    await tester.pageBack();
    await tester.pumpAndSettle();
    await flush(tester);
    expect(
      WafSessions.cookiesFor(Section.video, 'fixture'),
      'session=final-value',
    );
    final afterClose = reads;
    await tester.pump(const Duration(seconds: 5));
    expect(reads, afterClose);
  });
  testWidgets('第三方授权页不作为本站登录证据，只同步本站Cookie', (tester) async {
    await open(tester);
    platform.delegate.finished(platform.url);
    await flush(tester);
    final before = reads;
    platform.url = 'https://other.example/authorize';
    platform.loggedIn = true;
    await tester.pump(const Duration(seconds: 2));
    await flush(tester);
    expect(reads, before);
    expect(find.textContaining('请完成授权并返回原站点'), findsOneWidget);
    expect(
      WafSessions.cookiesFor(Section.video, 'fixture'),
      isNot(contains('foreign')),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await flush(tester);
  });
  testWidgets('同一登录页编辑账号资料，确定更新草稿、取消保留原值', (tester) async {
    final changes = <SourceLoginCredentials>[];
    await open(tester, onCredentialsChanged: changes.add);
    await tester.tap(find.byTooltip('账号资料'));
    await tester.pumpAndSettle();
    final account = find.widgetWithText(TextField, '账号');
    final password = find.widgetWithText(TextField, '密码');
    expect(tester.widget<TextField>(account).controller!.text, 'saved-user');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.enterText(account, 'new-user');
    await tester.enterText(password, 'new-password');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(changes.single.account, 'new-user');
    expect(changes.single.password, 'new-password');
    await tester.tap(find.byTooltip('账号资料'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(account).controller!.text, 'new-user');
    await tester.enterText(account, 'cancelled-user');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await flush(tester);
  });
}
