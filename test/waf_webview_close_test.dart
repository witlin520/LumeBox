import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:lume_box/features/source/waf_webview_page.dart';

class _Platform extends WebViewPlatform {
  bool ready = true;
  bool urlThrows = false;
  bool cookieHangs = false;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params, this);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.owner) : super.implementation();
  final _Platform owner;
  _Delegate? delegate;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as _Delegate;
  }

  @override
  Future<void> setUserAgent(String? value) async {}
  @override
  Future<String?> getUserAgent() async =>
      'Mozilla/5.0 Version/17.0 Safari/605.1';
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    delegate?.progress?.call(100);
  }

  @override
  Future<String?> currentUrl() async {
    if (owner.urlThrows) throw StateError('WebView is unavailable');
    return 'https://fixture.invalid/api';
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    if (script == 'document.cookie') {
      if (owner.cookieHangs) return Completer<Object>().future;
      return '';
    }
    if (script == 'navigator.userAgent') {
      return 'Mozilla/5.0 Version/17.0 Safari/605.1';
    }
    return jsonEncode({
      'n': 'API route does not exist',
      'r': owner.ready ? 'complete' : 'loading',
      'c': false,
    });
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  ProgressCallback? progress;
  @override
  Future<void> setOnProgress(ProgressCallback callback) async {
    progress = callback;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late _Platform platform;
  setUp(() {
    platform = _Platform();
    WebViewPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('lumebox/webview'),
          (_) async => <Object?>[],
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lumebox/webview'), null);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (inner) => Scaffold(
              body: TextButton(
                onPressed: () => showWafWebView(
                  context: inner,
                  url: 'https://fixture.invalid/api',
                  sourceName: '测试源',
                ),
                child: const Text('打开验证'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开验证'));
    await tester.pumpAndSettle();
  }

  for (final failure in ['empty', 'url-error', 'cookie-timeout']) {
    testWidgets('$failure：知道了关闭提示与验证窗，保留宿主页并能再次打开', (tester) async {
      await open(tester);
      platform.urlThrows = failure == 'url-error';
      platform.cookieHangs = failure == 'cookie-timeout';
      await tester.tap(find.byTooltip('关闭'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (failure == 'cookie-timeout') {
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
      }
      expect(find.text('未能读取验证会话'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(WafWebViewPage), findsNothing);
      expect(find.text('打开验证'), findsOneWidget);
      await tester.tap(find.text('打开验证'));
      await tester.pumpAndSettle();
      expect(find.byType(WafWebViewPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('页面未加载时可继续验证，也可明确退出，快速重复点击不叠提示', (tester) async {
    platform.ready = false;
    await open(tester);
    await tester.tap(find.byTooltip('关闭'));
    await tester.tap(find.byTooltip('关闭'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('继续验证'));
    await tester.pumpAndSettle();
    expect(find.byType(WafWebViewPage), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('退出验证'));
    await tester.pumpAndSettle();
    expect(find.byType(WafWebViewPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('打开验证'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
