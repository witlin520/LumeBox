import '../util/lume_log.dart';

/// 「每个图源最近请求过的地址 / 请求过的域名」——网页视图的地址兜底来源，
/// 以及「源站会话能发给谁」的判定依据。
///
/// **为什么需要它**：脚本抛 `NEED_WEBVIEW_VERIFY` 时，App 要拿站点 origin 去弹
/// 验证窗。地址有两个来源：脚本把 URL 写进报错文案（新脚本有，**老脚本没有**）、
/// 或者图源的订阅地址（粘贴导入的源没有）。两个都没有时，按钮点了只能给一句
/// 「拿不到源站地址」——用户看到的就是「点了没反应」（真机反馈过两轮）。
///
/// 但有一件事是确定的：**能报 WAF 错误，就说明刚发过一次请求**。网络层每次请求
/// 都记一条（按图源 id），弹窗时取最近的那条即可——与脚本怎么写、怎么导入的都无关。
///
/// 域名集合（[_hosts]）服务于另一条链路：图片请求要不要带源站会话。
/// 判定口径是「脚本自己请求过的域名」——脚本请过的域名就是源站（含镜像），
/// 脚本从不请求的域名（独立图床）永远不在集合里，会话 Cookie 也就发不出去。
///
/// 只存内存里（不落盘）：它是「这一次会话」的上下文，不是配置。
class SourceRequestLog {
  SourceRequestLog._();

  /// 图源 id → 最近一次请求的完整地址。
  static final Map<String, String> _last = <String, String>{};

  /// 图源 id → 脚本请求过的域名（小写，按首次请求先后排序）。
  static final Map<String, Set<String>> _hosts = <String, Set<String>>{};

  /// 同一图源最多记多少个域名：镜像站会换域名，但不会换出一屏来。
  static const int hostLimit = 12;

  /// 记录一次请求（由 [LumeHttp] 在发请求前调用）。
  static void record(String sourceId, String url) {
    final id = sourceId.trim();
    final text = url.trim();
    if (id.isEmpty || text.isEmpty) return;
    // 只记 http(s)：本地 file / data 之类的地址对网页视图没意义。
    if (!text.startsWith('http://') && !text.startsWith('https://')) return;
    _last[id] = text;
    final host = Uri.tryParse(text)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return;
    final set = _hosts.putIfAbsent(id, () => <String>{});
    set.add(host);
    if (set.length > hostLimit) set.remove(set.first);
  }

  /// 取某图源最近请求过的地址；没有则 null。
  ///
  /// [quiet] 不写日志：界面为了显示「将打开哪个站」这类提示文案会在 build 里
  /// 问一次，那种查询刷日志没有意义（真正的兜底发生在用户点击时）。
  static String? lastFor(String sourceId, {bool quiet = false}) {
    final value = _last[sourceId.trim()];
    if (value == null) return null;
    if (!quiet) LumeLog.info('[waf] 用最近请求过的地址兜底：$value');
    return value;
  }

  /// 这个地址是不是**源站自己的**：域名与脚本自己请求过的域名一致。
  ///
  /// 图片请求据此决定要不要带源站会话（`cf_clearance` 这类）：
  /// 源站自己的图（页面上的封面）必须带——不带就是「正文能看、封面全裂」；
  /// 独立图床绝不带——那是把源站会话泄漏给第三方域名。
  static bool ownsHost(String sourceId, String url) {
    final wanted = _bareHost(Uri.tryParse(url.trim())?.host ?? '');
    if (wanted.isEmpty) return false;
    final set = _hosts[sourceId.trim()];
    if (set == null || set.isEmpty) return false;
    for (final host in set) {
      if (_bareHost(host) == wanted) return true;
    }
    return false;
  }

  /// 去掉 `www.` 前缀：`www.example.com` 与 `example.com` 视为同一个站。
  static String _bareHost(String host) {
    final text = host.trim().toLowerCase();
    return text.startsWith('www.') ? text.substring(4) : text;
  }

  /// 仅测试用：清空记录。
  static void resetForTesting() {
    _last.clear();
    _hosts.clear();
  }
}
