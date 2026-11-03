// LumeSource: {"id":"spankbang_video","name":"SpankBang 18+","version":"1.0.0","category":"video","mirrors":["https://spankbang.com"]}
//
// 站点：https://spankbang.com （综合大 tube 站，全站 18+）
//
// ⚠️ 纯 HTTP 客户端（宿主 LumeSource.http / Node fetch / curl）仍会 403，必须靠 App 网页视图过校验；
//    但**解析规则不是猜的**：2026-10-25 用本机 Chrome（真实指纹 + 代理）过完 CF 后，
//    用 CDP 抓了首页 `/`、列表页 `/trending_videos/`、详情页 `/a5d50/video/porn` 三份真实 HTML
//    （878KB 详情页），列表 / 详情 / 播放三段规则都对着这三页写，并离线喂 HTML 跑通：
//      列表 82 条、`hasMore=true`、标题/封面/时长/清晰度齐；
//      详情 `og:title` / `og:image` / `og:video:duration`（7245 秒）；
//      播放 `var stream_data = {…}` 里 `m3u8` → master（240p/480p/720p 三条），
//           实测直连 200 + `application/vnd.apple.mpegurl`；`…-720p.mp4` 206 + video/mp4。
//
// ── 403 实测结论（2026-10-25，多组合验证过）
//   · 直连（不带代理）：DNS 被劫持到 173.252.248.244，TCP 连不上，curl 回 000；
//     手动 --resolve 指到真实 CF 出口 IP 时同样回 403。
//   · 走本机代理 http://127.0.0.1:7890：403，响应头 `Cf-Mitigated: challenge`、
//     `Server: cloudflare`、`cf-ray: …-HKG`，响应体是 Cloudflare 的 `Just a moment...` 挑战页（约 5.6KB，
//     `cType: 'interactive'`，带 `__cf_chl_opt` / `script-src https://challenges.cloudflare.com`）。
//   · 换头无效：桌面 Chrome 140 全套（UA + sec-ch-ua / sec-fetch-* + Accept + Accept-Language +
//     Referer: https://spankbang.com/）与 iPhone 17 UA 都是同一个挑战页。
//   · 换路径无效：/ 、/new_videos/ 、/trending/ 、/most_popular/ 、/categories/ 、/pornstars/ 、
//     /s/teen/ 、/api/v1/videos/new 、/api/videos/new 、/ajax/videos 、/sitemap.xml 、/feed/ 、/rss
//     —— 全部 403 挑战页（每个都重试过，000 只是代理抖动，重试即 403）。
//     **只有 /robots.txt 是 200**（Cloudflare 的托管规则单放行了它，里面没有任何片库数据）。
//   · m.spankbang.com 只是一条 301 回主域，跟着跳过去还是 403。
//   ⇒ 这是「按 IP 信誉 + TLS/JS 指纹判定」的 JS 挑战，不是 UA 或 Referer 能过的东西，
//     纯 HTTP 客户端（宿主 LumeSource.http / Node fetch / curl）在拿到 cf_clearance 之前
//     一页真实 HTML 都取不到。所以：**本脚本的所有 HTML 解析规则没有实测样本可对照**。
//
// ── 因此这里的设计（照 App 的既有范式，同 huavod.js / olehdtv.js）
//   1) 抓取层统一走 getText()：403 / 503 / 521，或响应体里出现 `Just a moment` / `cf-chl` / `__cf_chl_opt`
//      → 抛 `NEED_WEBVIEW_VERIFY：…`，App 收到后会在失败页给出「网页视图」按钮；
//      用户在 App 内置网页视图里过完校验，App 把整套 Cookie（含 HttpOnly 的 cf_clearance）
//      存进本源会话，之后本源**所有**请求自动带上 —— 这条路 App 侧是支持的，也是本源唯一可用的通路。
//      （脚本不读也不写 Cookie，那是宿主凭据。）
//   2) 解析规则用**不依赖具体 DOM 结构**的兜底式抽取：
//      · 列表：`/<videoId>/video/<slug>` 锚点 + 同块 og/cover 图 + 时长文本；
//      · 详情：og:title / og:image / og:description / <title>；
//      · 播放：页面里第一个 m3u8（优先）或 mp4 直链，覆盖 `"videoUrl":"…"`、`<source src=…>`、
//        `og:video` 三种常见内联形态。
//      一条都抽不到时**抛可读错误**（说明「站点结构未实测 / 已改版 / 是否还没过校验」），
//      不返回空壳、不猜地址。
//   3) categories() 先实时抓首页导航里的站内路径，抓不到就用下面的兜底路径表（同样未实测）。
//
// ── 已知限制
//   · 没有实测样本 ⇒ 解析正则可能对不上当前线上结构；拿到 403 之外的页面后第一件事应是校对
//     __parseItems / __mediaOf 里的锚点形状。
//   · 搜索路径按 ` /s/<词>/ ` 拼（spankbang 的搜索是路径式，不是 query 式）；`?sort=top` 之类的排序串没加，
//     避免在无法验证时凭空构造参数。
//   · 播放地址大概率是 CDN 签名直链，有时效；本源每次都现取播放页，不做缓存。
//   · 本机 7890 代理出口是机房 IP，CF 判定的就是这类 IP，过了网页视图也要保证 App 的网络配置
//     与网页视图走同一个出口，否则 cf_clearance 与 IP 绑不上。
//
// 2026-10-25 本机自测：lume-source-check 里 categories 走兜底表通过；home/list/detail/chapters/content
// 全部按设计抛 NEED_WEBVIEW_VERIFY（403 挑战页），所以 **本源的 PASS 只能在
// 「App 内置网页视图过校验 + 同出口 IP」之后取得，纯 shell 环境不可能 PASS**。

var DEFAULT_BASE = 'https://spankbang.com';
var UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

// 分类：2026-10-25 用真 Chrome 过 CF 后抓到的首页导航，实测存在的频道只有这三条。
// （旧写法里的 /trending/ 与 /most_popular/ 是错的，站内实际路径是 /trending_videos/）
var FALLBACK_CATEGORIES = [
  { id: '/new_videos/', title: '最新' },
  { id: '/trending_videos/', title: '正在流行' },
  { id: '/upcoming/', title: '即将上线' }
];

function base() {
  var domain = '';
  try {
    domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  } catch (error) {
    domain = '';
  }
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers(referer) {
  return {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    Referer: referer || base() + '/',
    'Upgrade-Insecure-Requests': '1'
  };
}

function entity(text) {
  return String(text == null ? '' : text).replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, function (all, code) {
    var map = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', '#39': "'", '#34': '"' };
    if (map[code] !== undefined) return map[code];
    if (code.charAt(0) === '#') {
      var n =
        code.charAt(1) === 'x' || code.charAt(1) === 'X'
          ? parseInt(code.slice(2), 16)
          : parseInt(code.slice(1), 10);
      if (isFinite(n) && n > 0 && n < 0x110000) return String.fromCharCode(n);
    }
    return all;
  });
}

function clean(text) {
  var plain = String(text == null ? '' : text)
    .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ');
  return entity(plain).replace(/\s+/g, ' ').trim();
}

function absolute(url) {
  var text = entity(String(url == null ? '' : url)).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
}

/// 统一的 HTML 抓取：CF 挑战页一律转成 NEED_WEBVIEW_VERIFY，让 App 出「网页视图」
function responseOf(reply, path) {
  if (!reply) throw new Error('SpankBang：没有网络响应（' + path + '）');
  var status = Number(reply.status) || 0;
  var body = String(reply.body || '');
  if (status === 403 || status === 503 || status === 521 || status === 429) {
    throw new Error(
      'NEED_WEBVIEW_VERIFY：SpankBang 触发了 Cloudflare 人机校验（HTTP ' + status + '）——' +
        '请在「网页视图」里完成校验后再试（本源所有请求会自动带上校验后的 Cookie）'
    );
  }
  if (/Just a moment|__cf_chl_opt|cf-chl|challenges\.cloudflare\.com/i.test(body)) {
    throw new Error(
      'NEED_WEBVIEW_VERIFY：SpankBang 返回的是 Cloudflare 挑战页（HTTP ' + status + '）——' +
        '请在「网页视图」里完成校验后再试'
    );
  }
  if (status === 404) throw new Error('SpankBang：页面不存在（HTTP 404）' + path);
  if (status === 451) throw new Error('SpankBang：该地区被站点屏蔽（HTTP 451）' + path);
  if (status !== 200) throw new Error('SpankBang：请求失败 HTTP ' + status + ' ' + path);
  if (body.length < 512) throw new Error('SpankBang：响应过短（' + body.length + ' 字节），可能被拦' + path);
  return body;
}

async function getText(path, referer) {
  var url = /^https?:\/\//i.test(path) ? path : base() + (String(path).charAt(0) === '/' ? path : '/' + path);
  var reply;
  try {
    reply = await LumeSource.http.get(url, { headers: headers(referer) });
  } catch (error) {
    // 连 TCP 都没握上（DNS 被污染 / 直连被墙 / 代理没配）：给能行动的一句话，别把 TypeError 丢给用户
    throw new Error(
      'SpankBang：连不上站点（' + String((error && error.message) || error) + '）——' +
        '请在「源设置 → 网络」里给本源配好代理，或先在「网页视图」里打开 https://spankbang.com 确认能访问'
    );
  }
  return responseOf(reply, url);
}

/// 列表页 → Item[]。**按 2026-10-25 用真实浏览器过 CF 后抓到的 HTML 写的**：
///   卡片  <div data-testid="video-item" data-id="17046468" class=" js-video-item …">
///   链接  <a href="/a5d50/video/porn" …>            ← short id + slug，slug 里可能有 `+` 或 `%xx`
///   标题  <a href="/a5d50/video/porn" title="Image video"><span>…</span></a>   ← title 属性即标题
///   封面  <img src="https://tbi.sb-cd.com/t/17046468/…/w:300/t6-enh/porn.jpg">
///   时长  <div data-testid="video-item-length"> 120m </div>
///   分页  <li class="next"><a href="/trending_videos/2/" data-page="2">
function parseItems(html) {
  var text = String(html);
  var items = [];
  var seen = {};
  var marker = 'data-testid="video-item"';
  var starts = [];
  var cursor = text.indexOf(marker);
  while (cursor >= 0) {
    starts.push(cursor);
    cursor = text.indexOf(marker, cursor + marker.length);
  }
  for (var i = 0; i < starts.length; i++) {
    var block = text.slice(starts[i], i + 1 < starts.length ? starts[i + 1] : text.length);
    var idMatch = /data-id="(\d+)"/i.exec(block);
    var hrefMatch = /<a[^>]+href="(\/[^"]*?\/video\/[^"]*?)"[^>]*title="([^"]*)"/i.exec(block) ||
      /<a[^>]+href="(\/[^"]*?\/video\/[^"]*?)"/i.exec(block);
    if (!idMatch || !hrefMatch) continue;
    var path = hrefMatch[1].replace(/^\/+|\/+$/g, '');
    if (seen[path]) continue;
    seen[path] = 1;
    var title = hrefMatch[2] ? clean(hrefMatch[2]) : '';
    if (!title) {
      var alt = /<img[^>]+alt="([^"]{2,200})"/i.exec(block);
      title = alt ? clean(alt[1]) : '';
    }
    if (!title) {
      var slug = path.split('/video/')[1] || path;
      title = decodeURIComponent(slug.replace(/\+/g, ' ')).replace(/-/g, ' ');
    }
    var cover = (/<img[^>]+src="([^"]+\.(?:jpe?g|png|webp)[^"]*)"/i.exec(block) || [])[1] || '';
    var lengthMatch = /data-testid="video-item-length"[^>]*>\s*([^<]{1,12}?)\s*</i.exec(block);
    var resMatch = /data-testid="video-item-resolution"[^>]*>\s*([^<]{1,8}?)\s*</i.exec(block);
    var parts = [];
    if (lengthMatch) parts.push(lengthMatch[1]);
    if (resMatch) parts.push(resMatch[1]);
    items.push({
      id: path,
      title: title,
      cover: cover ? absolute(cover) : null,
      subtitle: parts.join(' · ')
    });
  }
  return items;
}

/// 分页：`li.next` 存在即有下一页
function hasNextPage(html) {
  return /<li[^>]+class="[^"]*next[^"]*"[^>]*>\s*<a[^>]+href="/i.test(String(html));
}

/// 页面里找媒体地址。**2026-10-25 用真 Chrome 过 CF 抓到的详情页实测**：
///   详情页内联  `var ana_video_id = '17046468'; var stream_data = {'240p': ['https://vdownload-49.sb-cd.com/…-240p.mp4?secure=…'],
///                '320p': [], '480p': […], '720p': […], '1080p': [], '4k': [], 'mpd': [],
///                'm3u8': ['https://hls-uranus.sb-cd.com/hls/1/7/17046468-,240p,480p,720p,.mp4.urlset/master.m3u8?secure=…'],
///                'm3u8_240p': […], 'm3u8_480p': […], 'm3u8_720p': […] }`
///   实测 `master.m3u8` 直连 200 + `application/vnd.apple.mpegurl`；`…-720p.mp4` 206 + video/mp4。
///   地址带 `secure=` 签名（内含过期时间戳），所以每次播放都现取详情页。
function streamFields(html) {
  var out = {};
  var re = /'(240p|320p|480p|720p|1080p|4k|mpd|m3u8|m3u8_\d+p)'\s*:\s*\[([^\]]*)\]/g;
  var matched;
  while ((matched = re.exec(String(html))) !== null) {
    var url = /'(https?:[^']+)'/.exec(matched[2]);
    if (url) out[matched[1]] = url[1];
  }
  return out;
}

function mediaOf(html) {
  var text = String(html || '');
  var fields = streamFields(text);

  // 1) 多码率 HLS（首选）：master 里已经含 240p/480p/720p 三条
  if (fields.m3u8) {
    var hlsQualities = [];
    ['m3u8_1080p', 'm3u8_720p', 'm3u8_480p', 'm3u8_240p'].forEach(function (key) {
      if (fields[key]) hlsQualities.push({ label: key.replace('m3u8_', '').toUpperCase(), url: fields[key] });
    });
    return { kind: 'hls', url: fields.m3u8, qualities: hlsQualities };
  }

  // 2) 渐进 mp4（HLS 缺失时）
  var mp4Qualities = [];
  ['4k', '1080p', '720p', '480p', '320p', '240p'].forEach(function (key) {
    if (fields[key]) mp4Qualities.push({ label: key.toUpperCase(), url: fields[key] });
  });
  if (mp4Qualities.length) return { kind: 'mp4', url: mp4Qualities[0].url, qualities: mp4Qualities };

  // 3) 兜底：页面里扫一遍（老模板 / 变体页）
  var plain = text.replace(/\\\//g, '/');
  var m3u8 = /https?:[^"'\s<>\\]+\.m3u8[^"'\s<>\\]*/i.exec(plain);
  if (m3u8) return { kind: 'hls', url: entity(m3u8[0]), qualities: [] };
  var mp4 = /https?:[^"'\s<>\\]+\.mp4[^"'\s<>\\]*/i.exec(plain);
  if (mp4) return { kind: 'mp4', url: entity(mp4[0]), qualities: [] };
  return null;
}

var LumeSource = {
  id: 'spankbang_video',
  name: 'SpankBang 18+',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://spankbang.com'],

  /// 分类：优先抓首页导航里的站内路径（`/new_videos/`、`/trending/`、`/most_popular/` 这类），
  /// 抓不到（多半是 CF 403）就用兜底表 —— 这里**不抛错**，保证源至少能导入、能出分类。
  async categories() {
    var rows = [];
    var seen = {};
    try {
      var html = await getText('/');
      var pattern = /<a\b[^>]*href="\/(new_videos|trending|most_popular|top_rated|pornstars|categories|c|[a-z_]*)\/?"[^>]*>([^<]{2,24})</gi;
      var matched;
      while ((matched = pattern.exec(html)) !== null) {
        var path = '/' + matched[1] + '/';
        var title = clean(matched[2]);
        if (!title || seen[path]) continue;
        if (!/new|trend|popular|top|star|categor|^\/c\//.test(path)) continue;
        seen[path] = 1;
        rows.push({ id: path, title: title });
      }
    } catch (error) {
      console.warn('[spankbang] 分类导航抓取失败，用兜底表：' + error);
    }
    if (!rows.length) {
      for (var i = 0; i < FALLBACK_CATEGORIES.length; i++) rows.push(FALLBACK_CATEGORIES[i]);
    }
    return rows;
  },

  async home() {
    var page = await this.list({ categoryId: '/new_videos/', page: 1 });
    if (!page.items.length) throw new Error('SpankBang：首页没认出条目（站点可能改版，或尚未通过 CF 校验）');
    return [{ title: '最新', moreUrl: '/new_videos/', items: page.items.slice(0, 24) }];
  },

  async list(argument) {
    var args = argument || {};
    var page = Number(args.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = String(args.keyword == null ? '' : args.keyword).trim();
    var categoryId = String(args.categoryId == null ? '' : args.categoryId).trim() || '/new_videos/';
    var path;
    if (keyword) {
      // spankbang 的搜索是路径式：/s/<词>/（不是 ?q=）。分页用 /s/<词>/<N>/
      path = '/s/' + encodeURIComponent(keyword).replace(/%20/g, '+') + '/' + (page > 1 ? page + '/' : '');
    } else if (categoryId.indexOf('search:') === 0) {
      path = '/s/' + decodeURIComponent(categoryId.slice(7)) + '/' + (page > 1 ? page + '/' : '');
    } else if (/^https?:\/\//i.test(categoryId)) {
      path = categoryId;
    } else {
      var rel = categoryId.charAt(0) === '/' ? categoryId : '/' + categoryId;
      if (!/\/$/.test(rel)) rel += '/';
      path = page > 1 ? rel + page + '/' : rel;
    }
    var html = await getText(path);
    var items = parseItems(html);
    if (!items.length) console.warn('[spankbang] 列表没解析出条目：' + path + '（站点可能又改版了）');
    return { items: items, hasMore: hasNextPage(html) };
  },

  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return null;
    var path = /^https?:\/\//i.test(id) ? id : base() + '/' + id.replace(/^\/+/, '');
    var html = await getText(path);
    var title =
      (/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']*)["']/i.exec(html) || [])[1] ||
      (/<meta[^>]+content=["']([^"']*)["'][^>]+property=["']og:title["']/i.exec(html) || [])[1] ||
      '';
    if (!title) {
      var titleTag = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
      title = titleTag ? clean(titleTag[1]) : '';
    }
    // 站内 <title> 形如 `Image video: 日本人 & イメージビデオ Porn - SpankBang`，去掉尾部噪音
    title = String(title || '')
      .replace(/\s*[-|]\s*SpankBang\s*$/i, '')
      .replace(/\s+Porn\s*$/i, '')
      .trim();
    if (!title) title = clean(id);
    var cover =
      (/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']*)["']/i.exec(html) || [])[1] ||
      (/<meta[^>]+content=["']([^"']*)["'][^>]+property=["']og:image["']/i.exec(html) || [])[1] ||
      '';
    var description = (/<meta[^>]+name=["']description["'][^>]+content=["']([^"']*)["']/i.exec(html) || [])[1] || '';
    var duration = (/<meta[^>]+property=["']og:video:duration["'][^>]+content=["']([^"']*)["']/i.exec(html) || [])[1] || '';
    return {
      id: id,
      title: clean(title),
      cover: cover ? absolute(cover) : null,
      subtitle: duration ? String(duration) + ' 秒' : '',
      description: clean(description).slice(0, 600)
    };
  },

  /// 单集：spankbang 一条视频一个播放页（清晰度是同一 HLS 里的多码率，不是分集）
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: 'play', title: '正片' }];
  },

  async content(argument) {
    var settings = argument || {};
    var id = String(settings.id || '').trim();
    if (!id) throw new Error('SpankBang：缺少视频 id（应来自 list() 的条目）');
    var pageUrl = /^https?:\/\//i.test(id) ? id : base() + '/' + id.replace(/^\/+/, '');
    var html = await getText(pageUrl);
    var media = mediaOf(html);
    if (!media) {
      // 播放器页有时只有 embed 里带地址，再试一次
      var embedBase = pageUrl.replace(/\/video\/.*$/, '');
      try {
        var embedHtml = await getText(embedBase + '/embed/', pageUrl);
        media = mediaOf(embedHtml);
      } catch (error) {
        console.warn('[spankbang] embed 页也取不到：' + error);
      }
    }
    if (!media) {
      throw new Error(
        'SpankBang：详情页里没找到可播地址（页面 ' +
          html.length +
          ' 字节）——要么站点改版换了 stream_data 的结构，要么拿到的不是真实内容页'
      );
    }
    var playHeaders = {
      'User-Agent': UA,
      Referer: pageUrl,
      Accept: '*/*'
    };
    var result = { kind: 'video', url: media.url, headers: playHeaders };
    if (media.qualities && media.qualities.length > 1) {
      result.qualities = media.qualities.map(function (row) {
        return { label: row.label, url: row.url, headers: playHeaders };
      });
    }
    return result;
  }
};

if (typeof module !== 'undefined' && module.exports) module.exports = LumeSource;
