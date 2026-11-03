import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/cat/cat_web_parse.dart';
import '../../core/js/source_web_runtime.dart';
import '../../core/net/site_session_pool.dart';
import '../../core/source/web_player_episode.dart';

Future<void> showSourceWebPlayer(
  BuildContext context,
  CatWebParseRequired request,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => SourceWebPlayerPage(request: request)),
);

/// Page-owned JS/WASM playback. This route never creates a native decoder,
/// danmaku service, PiP session or playback-history target.
class SourceWebPlayerPage extends StatefulWidget {
  const SourceWebPlayerPage({super.key, required this.request});
  final CatWebParseRequired request;
  static const limitations = '网页播放 · 不提供原生弹幕、手势、画中画、字幕样式或进度记忆';
  @override
  State<SourceWebPlayerPage> createState() => _SourceWebPlayerPageState();
}

class _SourceWebPlayerPageState extends State<SourceWebPlayerPage>
    with WidgetsBindingObserver {
  final _controller = WebViewController();
  bool _ready = false, _fullScreen = false;
  bool _booting = false;
  String? _error;
  Timer? _episodeTimer;
  int _document = 0;
  bool _selecting = false;
  bool _foreground = true;
  bool _episodePending = false;

  void _stopSelection() {
    _document++;
    _episodeTimer?.cancel();
    _episodeTimer = null;
    _selecting = false;
  }

  void _selectEpisode(String url) {
    final selector = widget.request.episodeSelector;
    final loaded = Uri.tryParse(url);
    if (selector == null ||
        loaded == null ||
        !['http', 'https'].contains(loaded.scheme) ||
        loaded.origin != widget.request.page.origin) {
      return;
    }
    _episodePending = true;
    if (!_foreground) return;
    _stopSelection();
    final document = _document;
    var attempts = 0;
    Future<void> attempt() async {
      if (!mounted || document != _document || _selecting) return;
      _selecting = true;
      String result;
      try {
        result =
            '${await _controller.runJavaScriptReturningResult(webPlayerEpisodeScript(widget.request.page, selector))}'
                .replaceAll('"', '');
      } catch (_) {
        result = 'waiting';
      }
      if (!mounted || document != _document) return;
      _selecting = false;
      if (result == 'selected') {
        _episodePending = false;
        setState(() => _error = null);
        return;
      }
      if (++attempts >= 60 || result == 'invalid') {
        setState(() => _error = '未能选中指定集数。完成网页验证后点击“重试选集”，或在网页中手动选集。');
        return;
      }
      _episodeTimer = Timer(
        const Duration(seconds: 1),
        () => unawaited(attempt()),
      );
    }

    unawaited(attempt());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (_booting) return;
    _booting = true;
    try {
      final uri = widget.request.page;
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('网页播放需要有效的 HTTP(S) 页面地址');
      }
      final headers = await SiteSessionPool.shared.synchronize(
        uri.toString(),
        widget.request.headers,
      );
      if (!mounted) return;
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      final ua = SiteSessionPool.shared.userAgentFor(uri.toString());
      if (ua != null) await _controller.setUserAgent(ua);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _stopSelection(),
          onPageFinished: _selectEpisode,
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url == null ||
                !['http', 'https', 'about', 'blob'].contains(url.scheme)) {
              return NavigationDecision.prevent;
            }
            if (request.isMainFrame &&
                ['http', 'https'].contains(url.scheme) &&
                url.origin != uri.origin) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = '网页播放加载失败，请重试或在浏览器打开');
            }
          },
        ),
      );
      if (!mounted) return;
      await _controller.loadRequest(uri, headers: headers);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = '网页播放初始化失败，请检查网络或更换线路');
    } finally {
      _booting = false;
    }
  }

  Future<void> _browser() async {
    try {
      final opened = await SourceWebRuntime.channel.invokeMethod<bool>(
        'openExternal',
        {'url': widget.request.page.toString()},
      );
      if (opened != true) throw StateError('浏览器未打开');
    } catch (_) {
      await Clipboard.setData(
        ClipboardData(text: widget.request.page.toString()),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开浏览器，已复制页面地址')));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _foreground = false;
      _stopSelection();
      unawaited(
        _controller
            .runJavaScript(
              'document.querySelectorAll("video,audio").forEach(function(media){media.pause();});',
            )
            .catchError((_) {}),
      );
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (_episodePending && mounted) {
        setState(() => _error = '已暂停自动选集，可点击“重试选集”继续。');
      }
    }
  }

  @override
  void dispose() {
    _stopSelection();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((_) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _fullScreen
        ? null
        : AppBar(
            title: const Text('网页播放'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: () => _ready ? _controller.reload() : _boot(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '在浏览器打开',
                onPressed: _browser,
                icon: const Icon(Icons.open_in_browser),
              ),
              IconButton(
                tooltip: '全屏',
                onPressed: () => setState(() => _fullScreen = true),
                icon: const Icon(Icons.fullscreen),
              ),
            ],
          ),
    body: SafeArea(
      child: Column(
        children: [
          if (!_fullScreen)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(SourceWebPlayerPage.limitations),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          if (_error != null && widget.request.episodeSelector != null)
            TextButton(
              onPressed: () => _selectEpisode(widget.request.page.toString()),
              child: const Text('重试选集'),
            ),
          Expanded(
            key: const ValueKey('web-playback-content'),
            child: Stack(
              children: [
                if (_ready)
                  Positioned.fill(child: WebViewWidget(controller: _controller))
                else
                  const Center(child: CircularProgressIndicator()),
                if (_fullScreen)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: IconButton.filledTonal(
                      tooltip: '退出全屏',
                      onPressed: () => setState(() => _fullScreen = false),
                      icon: const Icon(Icons.fullscreen_exit),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
