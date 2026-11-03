import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/cat/cat_web_parse.dart';
import '../../core/player/player_experience_store.dart';
import '../../core/theme/lume_theme.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/lume_icon.dart';
import '../video/source_web_player_page.dart';
import '../../core/net/site_session_pool.dart';

Future<Uri?> showCatWebParsePage(
  BuildContext context,
  CatWebParseRequired request,
) => Navigator.push<Uri>(
  context,
  MaterialPageRoute(builder: (_) => CatWebParsePage(request: request)),
);

/// Loads a `parse=1` page in a real WebView and collects media URLs the page
/// requests. The user taps one candidate to hand it to the player.
class CatWebParsePage extends StatefulWidget {
  const CatWebParsePage({super.key, required this.request});

  final CatWebParseRequired request;

  @override
  State<CatWebParsePage> createState() => _CatWebParsePageState();
}

class _CatWebParsePageState extends State<CatWebParsePage> {
  final WebViewController _controller = WebViewController();
  final List<String> _candidates = [];
  int _progress = 0;
  String? _error;
  bool _ready = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final ua = PlayerExperienceStore.current.browserUA;
    if (ua.isNotEmpty) await _controller.setUserAgent(ua);
    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.addJavaScriptChannel(
      'LumeMedia',
      onMessageReceived: (message) {
        final values = CatMediaSniffer.filter([message.message]);
        if (values.isEmpty || !mounted) return;
        setState(() {
          for (final value in values) {
            if (!_candidates.contains(value)) _candidates.add(value);
          }
        });
      },
    );
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _error = null);
        },
        onPageFinished: (_) => _installSniffer(),
        onWebResourceError: (failure) {
          if (mounted && failure.isForMainFrame == true) {
            setState(() => _error = '解析页加载失败，请检查网络后重试');
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (const {
            'http',
            'https',
            'about',
            'data',
            'blob',
          }.contains(uri.scheme)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ),
    );
    final headers = await SiteSessionPool.shared.synchronize(
      widget.request.page.toString(),
      widget.request.headers,
    );
    await _controller.loadRequest(widget.request.page, headers: headers);
    if (!mounted) return;
    setState(() => _ready = true);
    _hintTimer = Timer(const Duration(seconds: 14), () {
      if (mounted && _candidates.isEmpty) setState(() {});
    });
  }

  Future<void> _installSniffer() async {
    try {
      await _controller.runJavaScript(r'''
(function(){
  if (window.__lumeMediaSniffer) { return; }
  window.__lumeMediaSniffer = true;
  function send(u) {
    try { if (u) LumeMedia.postMessage(String(u)); } catch (e) {}
  }
  function scan() {
    try {
      performance.getEntriesByType('resource').forEach(function(e){ send(e.name); });
    } catch (e) {}
    try {
      document.querySelectorAll('video,source,audio').forEach(function(v){
        send(v.currentSrc || v.src);
      });
    } catch (e) {}
    try {
      document.querySelectorAll('iframe').forEach(function(f){ send(f.src); });
    } catch (e) {}
  }
  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function() {
      var result = originalFetch.apply(this, arguments);
      try { send(result && result.url); } catch (e) {}
      return result;
    };
  }
  var originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    send(url);
    return originalOpen.apply(this, arguments);
  };
  document.addEventListener('play', function(event) {
    var target = event.target;
    if (target) send(target.currentSrc || target.src);
  }, true);
  scan();
  setInterval(scan, 1200);
})();
''');
    } catch (_) {
      // A page that blocks script injection can still be played manually.
    }
  }

  void _choose(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) Navigator.pop(context, uri);
  }

  @override
  Widget build(BuildContext context) => GlassScaffold(
    effectModule: GlassModule.cat,
    title: '网页解析',
    leading: IconButton(
      tooltip: '返回',
      icon: const LumeIcon(Icons.arrow_back, slot: 'cat_web_parse.back'),
      onPressed: () => Navigator.maybePop(context),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          await showSourceWebPlayer(context, widget.request);
          if (context.mounted) Navigator.of(context).pop();
        },
        child: const Text('改用网页播放'),
      ),
      IconButton(
        tooltip: '刷新',
        icon: const LumeIcon(Icons.refresh, slot: 'cat_web_parse.refresh'),
        onPressed: _ready ? () => _controller.reload() : null,
      ),
    ],
    child: Column(
      children: [
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
        Expanded(
          child: _ready
              ? WebViewWidget(controller: _controller)
              : const Center(child: CircularProgressIndicator()),
        ),
        Material(
          color: LumeTheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '识别到以下播放地址，点一个开始播放：',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_candidates.isEmpty)
                        TextButton(
                          onPressed: () => Navigator.maybePop(context),
                          child: const Text('取消'),
                        ),
                    ],
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (_candidates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '正在等待页面请求视频地址；如果页面有播放按钮，先点一下播放。'
                        '超过十几秒仍没有结果，可以返回并换一条直连线路。',
                        style: TextStyle(color: LumeTheme.textSecondary),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 170),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _candidates.length,
                        itemBuilder: (context, index) {
                          final url = _candidates[index];
                          final short = url.length > 72
                              ? '${url.substring(0, 69)}…'
                              : url;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(short),
                            subtitle: _candidates.length > 1
                                ? Text('候选 ${index + 1}')
                                : null,
                            trailing: const Text('播放'),
                            onTap: () => _choose(url),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
