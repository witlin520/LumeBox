// LumeSource: {"id":"s618208_video","name":"618208","version":"1.0.0","category":"video","mirrors":["https://618208.xyz"]}
//
// 站点：618208（https://618208.xyz，苹果CMS 改的成人短视频站，18+）
// 快照：.tmp_probe/cf/s618208.html（18KB，无 <title>，浏览器抓的）
//
// ── 入口实测（2026-10-25，127.0.0.1:7890 代理，桌面 Chrome UA）────────────────
//   · 首页 `/`                → **506 字节空壳**（只有一个 #table-container + 外站 JS），
//                               浏览器里由 https://donk666.duokkq.com/…js 填内容。
//                               所以本源**不拿首页**，home() 用分类页拼板块。
//   · 分类 `/index.php/vod/type/id/{N}.html`              → 200，13.9KB，20 条/页
//   · 翻页 `/index.php/vod/type/id/{N}/page/{P}.html`     → 200（N=1 时 totalPages=1359）
//   · 搜索 `/index.php/vod/type/id/1/wd/{关键词}/page/{P}.html` → 200，20 条/页（totalPages=13）
//       路由规则来自站内 JS：g=(i,w,p)=> w ? `/index.php/vod/type/id/${i}/wd/${encodeURIComponent(w)}/page/${p}.html`
//       : `/index.php/vod/type/id/${i}/page/${p}.html`，站点级搜索固定 id=1（JS 里 `tota=1`）。
//   · 卡片   <a class="vodbox" href="/html/dcdc/{乱码}.html?m={vodId}&amp;b={封面}">
//              <div class="picbox"><img class="lazy" data-original="封面"></div>
//              <p class="km-script">{乱码标题}</p></a>
//
// ── **标题是 128 异或混淆**（本站最大的坑）──────────────────────────────────
//   全站文字带 class="km-script"，站内 JS（goldlike.uutoper.com/…/b8f8108….js）用一个字符
//   回路还原：`s += String.fromCharCode(128 ^ t.charCodeAt(i))`。
//   实测：凨遨襆頑 → 全部视频；ゐ餙藉祀ゑ箬¸´³枟­犱竿… → 【香蕉秀】第843期-爱穿丝袜的小妈被操的淫叫连连！
//   连 **详情页 URL 的路径段本身**都是这样混淆的（/html/dcdc/{乱码}.html）——但**服务端照样
//   认这个乱码路径**（HTTP 200），所以本源原样保留 href，只在展示时解码。
//
// ── 播放 ─────────────────────────────────────────────────────────────────────
//   详情页 `/html/dcdc/{乱码}.html?m={vodId}` 只有 4KB，真正的播放地址走 XPlayer + 一个接口：
//     const mk = searchParams.get('m');
//     fetch('https://h5.xxoo475.org/api/v2/vod/reqplay/' + mk)
//       → { retcode, data: { httpurl, httpurls:[…] } }
//       retcode===3 时用 data.httpurl_preview，否则用 data.httpurl；最后 .replace('?300','')
//   实测 m=85973 → httpurl = https://8u3m21v0.krwwy.com/20261019/gKKgXsQq/index.m3u8（#EXTM3U 正常）。
//   接口域名在详情页脚本里是写死的，本源从详情页里正则抽出来（抽不到才用默认），避免换域名就废。
//
// ── 兜底 ─────────────────────────────────────────────────────────────────────
//   按 niacg.js 的做法留了一条「直连被拦（403/503/空壳）就改走 LumeSource.web.render」的路，
//   并记 1 小时标记，省掉反复 403 的往返。实测目前所有需要的页面直连都是 200，这条不会触发。
var DEFAULT_BASE = 'https://618208.xyz';
var DEFAULT_API = 'https://h5.xxoo475.org/api/v2/vod/reqplay/';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var SEARCH_TYPE_ID = '1';
var RENDER_TTL_MS = 3600 * 1000;

// 分类表（从 /index.php/vod/type/id/1.html 的 .mycates 逐条异或解出来的，2026-10-25）
var CATEGORIES = [
  { id: '1', title: '全部视频' },
  { id: '13', title: '香蕉精品' },
  { id: '22', title: '制服诱惑' },
  { id: '6', title: '国产视频' },
  { id: '8', title: '清纯少女' },
  { id: '9', title: '辣妹大奶' },
  { id: '10', title: '女同专属' },
  { id: '11', title: '素人出演' },
  { id: '12', title: '角色扮演' },
  { id: '20', title: '人妻熟女' },
  { id: '23', title: '日韩剧情' },
  { id: '21', title: '经典伦理' },
  { id: '7', title: '成人动漫' },
  { id: '14', title: '精品二区' },
  { id: '40', title: '精品三区' }
];

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
}

// 站点自己的解码：每个字符 128 异或。字符串里所有字符都是 BMP，逐 UTF-16 码元处理即可。
function unxor(text) {
  var raw = String(text == null ? '' : text);
  var out = '';
  for (var index = 0; index < raw.length; index++) {
    out += String.fromCharCode(128 ^ raw.charCodeAt(index));
  }
  return out;
}

function decodeEntities(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, function (all, hex) {
      return String.fromCharCode(parseInt(hex, 16));
    })
    .replace(/&#(\d+);/g, function (all, code) {
      return String.fromCharCode(Number(code));
    })
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function decode(text) {
  return decodeEntities(unxor(text));
}

function plain(text) {
  return decodeEntities(String(text == null ? '' : text).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim());
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,application/json,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Referer: base() + '/'
  };
  for (var key in extra || {}) {
    if (Object.prototype.hasOwnProperty.call(extra, key)) result[key] = extra[key];
  }
  return result;
}

function looksBlocked(status, body) {
  var text = String(body || '');
  return status === 403 || status === 503 || status === 521 ||
    /Just a moment|Attention Required|cf-chl-|challenge-platform\/scripts\/jsd\/main/i.test(text) && text.length < 6000;
}

function looksShell(body) {
  var text = String(body || '');
  return text.length < 800 && text.indexOf('vodbox') < 0 && text.indexOf('mycates') < 0;
}

async function renderMode() {
  try {
    var cached = await LumeSource.fs.readText('mode.json');
    if (!cached) return false;
    var saved = JSON.parse(cached);
    return !!(saved && saved.render && saved.at && Date.now() - saved.at < RENDER_TTL_MS);
  } catch (error) {
    return false;
  }
}

async function markRenderMode() {
  try {
    await LumeSource.fs.writeText('mode.json', JSON.stringify({ render: true, at: Date.now() }));
  } catch (error) {
    /* 缓存写不进去不影响主流程 */
  }
}

async function renderPage(target) {
  var result = await LumeSource.web.render({
    url: absolute(target),
    headers: {
      'User-Agent': UA,
      Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9'
    },
    timeoutMs: 8000
  });
  var body = result && result.html ? String(result.html) : '';
  if (!body || looksShell(body)) {
    throw new Error('NEED_WEBVIEW_VERIFY：618208 需要网页视图完成校验，请在源设置里点「网页视图」打开本站后重试');
  }
  return body;
}

async function html(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  if (await renderMode()) return renderPage(url);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  if (looksBlocked(status, body) || looksShell(body)) {
    try {
      var rendered = await renderPage(url);
      await markRenderMode();
      return rendered;
    } catch (error) {
      throw new Error('618208 被拦/只拿到空壳（HTTP ' + status + '，' + body.length + ' 字节）：' + url);
    }
  }
  if (status !== 200) throw new Error('618208 页面打不开：HTTP ' + status + ' ' + url);
  return body;
}

// ---------------------------------------------------------------- 列表解析
function listPath(typeId, pageNo) {
  var n = Number(typeId);
  if (!n) n = 1;
  var p = Number(pageNo || 1);
  if (!p || p < 1) p = 1;
  return p === 1 ? '/index.php/vod/type/id/' + n + '.html' : '/index.php/vod/type/id/' + n + '/page/' + p + '.html';
}

function searchPath(keyword, pageNo) {
  var p = Number(pageNo || 1);
  if (!p || p < 1) p = 1;
  return '/index.php/vod/type/id/' + SEARCH_TYPE_ID + '/wd/' + encodeURIComponent(keyword) + '/page/' + p + '.html';
}

function parseCards(pageHtml) {
  var items = [];
  var seen = {};
  var pattern = /<a class="vodbox" href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var href = decodeEntities(matched[1]);
    if (!href || seen[href]) continue;
    var chunk = matched[2];

    var coverMatch = /<img[^>]+(?:data-original|data-src|src)="([^"]+)"/i.exec(chunk);
    var cover = coverMatch ? decodeEntities(coverMatch[1]) : '';
    if (!/^https?:\/\//i.test(cover)) {
      var bannerMatch = /[?&]b=([^&"]+)/.exec(href);
      cover = bannerMatch ? decodeURIComponent(bannerMatch[1]) : '';
    }

    var titleMatch = /<p[^>]*class="km-script"[^>]*>([\s\S]{0,400}?)<\/p>/i.exec(chunk);
    var title = titleMatch ? decode(titleMatch[1]) : '';
    if (!title) {
      var idMatch = /m=(\d+)/.exec(href);
      title = idMatch ? '视频 ' + idMatch[1] : '';
    }
    if (!title) continue;

    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: cover,
      subtitle: ''
    });
  }
  return items;
}

function totalPagesOf(pageHtml) {
  var matched = /totalPages\s*=\s*['"](\d+)['"]/.exec(pageHtml);
  return matched ? Number(matched[1]) : 0;
}

// ---------------------------------------------------------------- 详情解析
// 详情页 4KB 且标题是客户端算的（location.pathname.slice(11,-5) 再异或），
// 所以标题直接从 URL 路径段解，不依赖页面内容。
function pathSegmentOf(url) {
  var text = String(url || '').split('?')[0].split('#')[0];
  var matched = /\/([^\/]+)\.html$/.exec(text);
  if (!matched) return '';
  var segment = matched[1];
  try {
    segment = decodeURIComponent(segment);
  } catch (error) {
    /* 原样用 */
  }
  return segment;
}

function vodIdOf(url) {
  var matched = /[?&]m=(\d+)/.exec(String(url || ''));
  return matched ? matched[1] : '';
}

function coverOf(url) {
  var matched = /[?&]b=([^&]+)/.exec(String(url || ''));
  if (!matched) return '';
  try {
    return decodeURIComponent(matched[1]);
  } catch (error) {
    return matched[1];
  }
}

function categoryNameOf(typeId) {
  for (var index = 0; index < CATEGORIES.length; index++) {
    if (CATEGORIES[index].id === String(typeId)) return CATEGORIES[index].title;
  }
  return '';
}

function idOf(argument) {
  return argument && argument.id ? String(argument.id).trim() : '';
}

var LumeSource = {
  id: 's618208_video',
  name: '618208',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://618208.xyz'],

  async categories() {
    return CATEGORIES.slice();
  },

  async home() {
    var order = ['13', '22', '9'];
    var boards = [];
    for (var index = 0; index < order.length; index++) {
      try {
        var pageHtml = await html(listPath(order[index], 1));
        var items = parseCards(pageHtml);
        if (items.length) {
          boards.push({ title: categoryNameOf(order[index]) || '推荐', moreUrl: order[index], items: items.slice(0, 18) });
        }
      } catch (error) {
        if (index === 0) throw error;
      }
    }
    if (!boards.length) throw new Error('618208：分类页没认出条目（站点可能改版）');
    return boards;
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var typeId = settings.categoryId ? String(settings.categoryId).trim() : '1';
    if (!/^\d+$/.test(typeId)) typeId = '1';

    var path = keyword ? searchPath(keyword, pageNo) : listPath(typeId, pageNo);
    var pageHtml = await html(path);
    var items = parseCards(pageHtml);
    var total = totalPagesOf(pageHtml);
    return { items: items, hasMore: total ? pageNo < total : items.length >= 20 };
  },

  async detail(argument) {
    var id = idOf(argument);
    if (!id) return null;
    var url = /^https?:\/\//i.test(id) ? id : absolute(id);
    var title = decode(pathSegmentOf(url));
    if (!title) {
      var pageHtml = await html(url);
      var titleMatch = /<title[^>]*>([\s\S]{0,200}?)<\/title>/i.exec(pageHtml);
      title = titleMatch ? decode(plain(titleMatch[1])) : '';
    }
    if (!title) return null;
    var parts = [];
    var vodId = vodIdOf(url);
    if (vodId) parts.push('视频 #' + vodId);
    var segment = pathSegmentOf(url);
    if (segment && segment.length > 8) parts.push('视频页');
    return {
      id: url,
      title: title,
      cover: coverOf(url),
      subtitle: parts.join(' · '),
      description: title
    };
  },

  async chapters(argument) {
    var id = idOf(argument);
    if (!id) return [];
    var url = /^https?:\/\//i.test(id) ? id : absolute(id);
    var title = decode(pathSegmentOf(url));
    return [{ id: url, title: title ? title.slice(0, 40) : '播放' }];
  },

  async content(argument) {
    var target = (argument && (argument.chapterId || argument.id)) || '';
    var url = String(target).trim();
    if (!url) throw new Error('缺少播放页地址');
    if (!/^https?:\/\//i.test(url)) url = absolute(url);

    var vodId = vodIdOf(url);
    var apiBase = DEFAULT_API;
    if (!vodId) {
      var pageHtml = await html(url);
      var apiMatch = /(https?:\/\/[^'"\s]+\/api\/v2\/vod\/reqplay\/)/.exec(pageHtml);
      if (apiMatch) apiBase = apiMatch[1];
      var idMatch = /[?&]m=(\d+)/.exec(pageHtml);
      if (idMatch) vodId = idMatch[1];
      if (!vodId) throw new Error('618208：播放页里没找到 m 参数（' + url + '）');
    }

    var response = await LumeSource.http.get(apiBase + vodId, {
      headers: headers({ Accept: 'application/json, text/plain, */*', Referer: base() + '/' })
    });
    var status = response ? response.status : 0;
    var body = String((response && response.body) || '');
    if (status !== 200) throw new Error('618208 播放接口打不开：HTTP ' + status);
    var data;
    try {
      data = JSON.parse(body);
    } catch (error) {
      throw new Error('618208 播放接口返回的不是 JSON：' + body.slice(0, 120));
    }
    var payload = data && data.data ? data.data : {};
    var stream = Number(data && data.retcode) === 3 && payload.httpurl_preview ? payload.httpurl_preview : payload.httpurl;
    if (!stream && payload.httpurls && payload.httpurls.length) stream = payload.httpurls[0].httpurl;
    if (!stream) throw new Error('618208 播放接口没给地址：' + body.slice(0, 160));
    stream = String(stream).replace(/\?300$/, '');
    return {
      kind: 'video',
      url: stream,
      headers: { 'User-Agent': UA, Referer: base() + '/', Accept: '*/*' }
    };
  }
};
