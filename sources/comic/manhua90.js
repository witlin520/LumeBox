// LumeSource: {"id":"manhua90_comic","name":"90漫画","version":"1.0.0","category":"comic","mirrors":["https://www.90mh.cc"]}
//
// 站点：90漫画网（日本 / 韩国漫画在线，服务端渲染，Yii2 前端，2026-10-25 逐页实测）
//
// 为什么按「PC 版」解析：站点有 /js/phone.js 的 phone.check("https://m.90mh.cc")，
// 手机 UA 会被前端跳到 m.90mh.cc 另一套壳（DOM 完全不一样）。本源所有 HTML 请求
// 都显式带桌面 Chrome UA，服务端就吐 PC 版结构，不碰 ?device=phone。
//
// 反爬（关键坑，实测）：**每个新会话第一次请求必然 403**，返回一个约 110 字节的
//   <html><meta charset="utf-8" /><title></title><div></div></html>
//   <script> window.location.href ="/"; </script>
// 响应头里带 2 个 Set-Cookie（一个随机名字的十六进制 cookie + HttpOnly 的
// server_session_xxxx）。把那两个 cookie 回传再请求同一个地址就 200。之后同会话里
// 大概每 5～8 次请求会再抖一次 403，同样「收 cookie → 立刻重试」即可过。
// 所以本源所有 GET 都走 get()：收 Set-Cookie → 落本地 → 403 就再试，最多 4 次。
// 另外 520/521/522/524 是 Cloudflare 在喊「源站没正常回包」，站点自己会抖（同一条 URL
// 前一秒 520、十秒后 200，实测过好几次），get() 也会小幅退避重试，别把整页判死。
// 注意别把正常页面里的 /cdn-cgi/challenge-platform/scripts/jsd 当成被拦信号
// （首页正常带这段广告/统计脚本），只有 403/503 + "Just a moment" 才是真挑战页。
//
// 页面结构（2026-10-25 实测）：
//   · 首页      /                          4 个 tab：热门连载 / 经典完结 / 最新上架 / 2016新番，
//                                          每个 tab 是 <ul id="tabN" class="cover-list">
//   · 分类      /list/{slug}/               第 1 页省略页码，第 2 页起 /list/{slug}/{page}/
//                                          36 条/页；末页在第 164 页（日本）
//   · 分类表    /list/ 页面里的 filter-nav：按类型(ertong/shaonian/shaonv/qingnian)
//                                          按地区(riben/dalu/hongkong/taiwan/oumei/hanguo/qita)
//                                          后面还有 ~150 个「按剧情」标签，本源只取前两组，避免刷屏
//   · 更新      /update/                    · 排行 /comic/rank/ （/rank/ 是 520，别用）
//   · 详情      /manhua/{slug}/               <h1><span>标题</span></h1>、img.pic 封面、
//                                          #intro-all 简介、ul#chapter-list-N 章节
//   · 章节      /manhua/{slug}/{cid}.html     <script> var chapterImages = ["http:\/\/jspc.haotu90.top\/…"]
//                                          整章的图一次性给全（没有 ajax 分页），转义是 \/ 要还原
//   · 搜索      POST https://api.90mh.cc/comic/search  body: keywords=…&page=N
//                                          返回 Yii REST JSON：{items:[{name,uri,coverUrl,
//                                          last_chapter_name,serialise,…}],_meta:{pageCount,…}}
//                                          （站点前端 /js/common.js 里 search() 调的就是它）
//   · 卡片      <li class="item-lg" data-key="7891"><a class="cover" href="https://www.90mh.cc/manhua/yehuixu/" title="夜绘序">
//                 <img src="http://cover.haotu90.top/images/cover/202610/xxx.jpg" …>
//                 <span class="tt">更新至第02话</span></a>
//               <p class="ell"><a href="…">夜绘序</a></p></li>
//               ——首页 / 列表页 / 详情页的「还喜欢看」都用这一个形状，统一按 a.cover 认。
//   · 媒体      ！封面在 cover.haotu90.top，章节图在 jspc.haotu90.top，两个 CDN
//               **裸访问就是 200/206，不挑 Referer**（实测 curl -r 0-1023 带不带 -e 都过）。
//               保险起见 content() 里还是给了 Referer: https://www.90mh.cc/。
//
// App 侧：需要能出外网（本源走宿主 http，用户自备代理时 App 侧要配好）。

var DEFAULT_BASE = 'https://www.90mh.cc';
var API_BASE = 'https://api.90mh.cc';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var COOKIE_FILE = 'cookies.json';
// 实测站点会「成串」抽风：520 是随机出现的（连打 12 次中 2 次，偶尔连着几下），
// 403 是每几次请求一次的 cookie 闸门。两种都靠重试解决，所以给到 8 次 + 递增退避。
var MAX_RETRY = 8;

// 分类兜底表（/list/ 页面解析失败时用；id 就是 /list/{id}/ 里的 slug）
var FALLBACK_CATEGORIES = [
  { id: 'shaonian', title: '少年漫画' },
  { id: 'shaonv', title: '少女漫画' },
  { id: 'qingnian', title: '青年漫画' },
  { id: 'ertong', title: '儿童漫画' },
  { id: 'riben', title: '日本' },
  { id: 'hanguo', title: '韩国' },
  { id: 'oumei', title: '欧美' },
  { id: 'dalu', title: '大陆' },
  { id: 'hongkong', title: '香港' },
  { id: 'taiwan', title: '台湾' }
];

var cookieHeader = '';
var cookieLoaded = false;
// 单页缓存：detail() → chapters() 会连着要同一个详情页，content() 也可能要详情页；
// 站点本身就爱抽风，能少发一次请求就少一次踩 520 的机会。
var pageCache = { url: '', html: '' };

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  var value = domain || DEFAULT_BASE;
  return value.replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
  };
  if (cookieHeader) result.Cookie = cookieHeader;
  for (var key in extra || {}) if (extra[key] != null) result[key] = extra[key];
  return result;
}

function decode(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#(\d+);/g, function (all, code) {
      return String.fromCharCode(Number(code));
    })
    .replace(/&nbsp;/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// ------------------------------------------------------------------ Cookie 池
// 站点用「首访 403 + Set-Cookie」做闸门，cookie 是随机会话名，只能照抄。
function cookieMap() {
  var map = {};
  var parts = String(cookieHeader || '').split(';');
  for (var i = 0; i < parts.length; i++) {
    var piece = parts[i].trim();
    if (!piece) continue;
    var eq = piece.indexOf('=');
    if (eq <= 0) continue;
    map[piece.slice(0, eq)] = piece.slice(eq + 1);
  }
  return map;
}

async function loadCookies() {
  if (cookieLoaded) return cookieHeader;
  cookieLoaded = true;
  try {
    var raw = await LumeSource.fs.readText(COOKIE_FILE);
    if (raw) {
      var saved = JSON.parse(raw);
      if (saved && typeof saved.cookie === 'string') cookieHeader = saved.cookie;
    }
  } catch (error) {
    /* 没有缓存就从零开始，第一次 403 会把 cookie 发下来 */
  }
  return cookieHeader;
}

async function saveCookies(list) {
  if (!list || !list.length) return;
  var map = cookieMap();
  var changed = false;
  for (var i = 0; i < list.length; i++) {
    var first = String(list[i] || '').split(';')[0].trim();
    var eq = first.indexOf('=');
    if (eq <= 0) continue;
    var name = first.slice(0, eq);
    var value = first.slice(eq + 1);
    if (map[name] !== value) {
      map[name] = value;
      changed = true;
    }
  }
  if (!changed) return;
  var chunks = [];
  for (var key in map) chunks.push(key + '=' + map[key]);
  cookieHeader = chunks.join('; ');
  try {
    await LumeSource.fs.writeText(COOKIE_FILE, JSON.stringify({ cookie: cookieHeader, at: Date.now() }));
  } catch (error) {
    /* 落盘失败不影响本次会话 */
  }
}

// ------------------------------------------------------------------ 抓取
function needsWebview(text) {
  return /Just a moment|cf-chl-|challenge-platform\/scripts\/jsd/i.test(String(text || ''));
}

async function request(url, extra) {
  return LumeSource.http.request({
    url: url,
    method: 'GET',
    headers: headers(extra)
  });
}

function wait(ms) {
  return new Promise(function (resolve) {
    setTimeout(resolve, ms);
  });
}

async function get(target, extra) {
  var url = absolute(target);
  if (pageCache.url === url && pageCache.html) return pageCache.html;
  await loadCookies();
  var lastStatus = 0;
  for (var attempt = 0; attempt < MAX_RETRY; attempt++) {
    var response = await request(url, extra);
    var status = response ? response.status : 0;
    var text = String((response && response.body) || '');
    lastStatus = status;
    if (response && response.setCookie && response.setCookie.length) await saveCookies(response.setCookie);
    if (status === 200) {
      if (text.length > 4000) pageCache = { url: url, html: text };
      return text;
    }
    if (status === 403 || status === 503) {
      if (needsWebview(text)) {
        throw new Error('NEED_WEBVIEW_VERIFY：90漫画 被 Cloudflare 挑战页拦住（HTTP ' + status + '），请在源设置里走网页视图或给本源配代理');
      }
      // 首访闸门：cookie 已经在上面收下了，立刻重试
      continue;
    }
    if (status >= 500) {
      // 520/521/522/524 = Cloudflare 说「源站没正常回包」，站点自己抖一下很常见
      // （实测随机命中，同一条 URL 隔一两秒就 200），递增退避再试，别把整页判死。
      await wait(300 * (attempt + 1));
      continue;
    }
    throw new Error('90漫画 页面打不开：HTTP ' + status + ' ' + url);
  }
  throw new Error('90漫画 页面打不开：HTTP ' + lastStatus + '（已重试 ' + MAX_RETRY + ' 次，cookie 闸门或源站抖动没过）' + url);
}

// ------------------------------------------------------------------ 解析
// 卡片：<li class="item-…"><a class="cover" href="/manhua/{slug}/" title="…">
//         <img src="封面"><span class="tt">更新至第02话</span></a>
function parseCards(pageHtml) {
  var items = [];
  var seen = {};
  var pattern = /<a class="cover" href="([^"]+)"\s+title="([^"]*)">([\s\S]{0,700}?)<\/a>/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var href = decode(matched[1]);
    if (!/\/manhua\/[^\/"']+\/?$/i.test(href)) continue;
    if (seen[href]) continue;
    var body = matched[3];
    var coverMatch = /<img[^>]*src="([^"]+)"/i.exec(body);
    var cover = coverMatch ? decode(coverMatch[1]) : '';
    if (/default\/cover\.png|loading\.gif|blank\./i.test(cover)) cover = '';
    var subMatch = /<span class="tt">([\s\S]*?)<\/span>/i.exec(body);
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: decode(matched[2]),
      cover: cover ? absolute(cover) : '',
      subtitle: subMatch ? decode(subMatch[1]) : ''
    });
  }
  return items;
}

function parseCategories(pageHtml) {
  var groups = String(pageHtml).split('<div class="filter-item clearfix">');
  var out = [];
  var seen = {};
  // groups[1] = 按类型，groups[2] = 按地区；后面是 ~150 个剧情标签，不取。
  for (var g = 1; g <= 2 && g < groups.length; g++) {
    var chunk = groups[g];
    var pattern = /href="\/list\/([A-Za-z0-9_-]+)\/"[^>]*>([^<]+)</g;
    var matched;
    while ((matched = pattern.exec(chunk)) !== null) {
      var slug = matched[1];
      var title = decode(matched[2]);
      if (!slug || !title || seen[slug]) continue;
      if (/^(qita|unknown)$/i.test(slug) && seen['qita']) continue;
      seen[slug] = true;
      out.push({ id: slug, title: title });
    }
  }
  return out;
}

function parseTabs(pageHtml) {
  var titles = {};
  var titlePattern = /<a href="#tab(\d+)"[^>]*>([^<]+)<\/a>/g;
  var matched;
  while ((matched = titlePattern.exec(pageHtml)) !== null) {
    if (!titles[matched[1]]) titles[matched[1]] = decode(matched[2]);
  }
  var boards = [];
  var blockPattern = /<ul id="tab(\d+)" class="cover-list[^"]*">([\s\S]*?)<\/ul>/g;
  while ((matched = blockPattern.exec(pageHtml)) !== null) {
    var items = parseCards(matched[2]);
    if (!items.length) continue;
    boards.push({
      title: titles[matched[1]] || ('推荐 ' + matched[1]),
      moreUrl: '/list/',
      items: items.slice(0, 18)
    });
  }
  return boards;
}

function parseDescription(pageHtml) {
  var all = /<div id="intro-all"[^>]*>([\s\S]*?)<\/div>\s*<a class="intro-act"/i.exec(pageHtml) ||
    /<div id="intro-all"[^>]*>([\s\S]*?)<\/div>/i.exec(pageHtml) ||
    /<div id="intro-cut"[^>]*>([\s\S]*?)<\/div>/i.exec(pageHtml);
  if (all) {
    var text = decode(all[1]);
    if (text) return text;
  }
  var meta = /<meta name="description" content="([^"]*)"/i.exec(pageHtml);
  return meta ? decode(meta[1]) : '';
}

function parseChapters(pageHtml) {
  var chapters = [];
  var seen = {};
  var listPattern = /<ul id="chapter-list-[\d]+"[\s\S]*?<\/ul>/g;
  var listMatch;
  while ((listMatch = listPattern.exec(pageHtml)) !== null) {
    var pattern = /<a href="(\/manhua\/[^"]+\.html)"[^>]*>\s*<span>([\s\S]*?)<\/span>/g;
    var matched;
    while ((matched = pattern.exec(listMatch[0])) !== null) {
      var url = absolute(decode(matched[1]));
      if (seen[url]) continue;
      seen[url] = true;
      chapters.push({ id: url, title: decode(matched[2]) || ('第 ' + (chapters.length + 1) + ' 话') });
    }
  }
  return chapters;
}

function parseChapterImages(pageHtml) {
  var block = /var\s+chapterImages\s*=\s*(\[[\s\S]*?\])\s*;/.exec(pageHtml);
  if (!block) return [];
  var images = [];
  var seen = {};
  var pattern = /"([^"]+)"/g;
  var matched;
  while ((matched = pattern.exec(block[1])) !== null) {
    var url = matched[1].replace(/\\\//g, '/').replace(/\\u002F/gi, '/');
    if (!/^https?:\/\//i.test(url) || seen[url]) continue;
    seen[url] = true;
    images.push(url);
  }
  return images;
}

function imageHeaders() {
  return {
    Referer: base() + '/',
    'User-Agent': UA,
    Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
  };
}

function idOf(argument) {
  return argument && argument.id ? String(argument.id).trim() : '';
}

// ------------------------------------------------------------------ 搜索
async function searchItems(keyword, pageNo) {
  var response = await LumeSource.http.request({
    url: API_BASE + '/comic/search?page=' + pageNo,
    method: 'POST',
    headers: headers({
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'X-Requested-With': 'XMLHttpRequest',
      Accept: 'application/json, text/javascript, */*; q=0.01',
      Referer: base() + '/'
    }),
    body: 'keywords=' + encodeURIComponent(keyword)
  });
  var status = response ? response.status : 0;
  var text = String((response && response.body) || '');
  if (status !== 200) throw new Error('90漫画 搜索失败：HTTP ' + status);
  var data = JSON.parse(text);
  var rows = Array.isArray(data && data.items) ? data.items : [];
  var items = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i] || {};
    var uri = row.uri || (row.slug ? '/manhua/' + row.slug + '/' : '');
    if (!uri) continue;
    var parts = [];
    if (row.author) parts.push(decode(row.author));
    if (row.last_chapter_name) parts.push(decode(row.last_chapter_name));
    if (row.serialise === 1 || row.serialise === true) parts.push('连载中');
    items.push({
      id: absolute(uri),
      title: decode(row.name || row.title || ''),
      cover: row.coverUrl ? absolute(row.coverUrl) : '',
      subtitle: parts.join(' · ')
    });
  }
  var meta = data && data._meta ? data._meta : null;
  var hasMore = meta && meta.pageCount ? Number(meta.currentPage) < Number(meta.pageCount) : items.length >= 20;
  return { items: items, hasMore: hasMore };
}

var LumeSource = {
  id: 'manhua90_comic',
  name: '90漫画',
  version: '1.0.0',
  category: 'comic',
  mirrors: ['https://www.90mh.cc'],

  async categories() {
    // 首页 / 列表页 / 详情页都挂着同一套 filter-nav（按类型 / 按地区 / 按剧情 …），
    // 手上已经有页面就直接解析，省一次请求。
    try {
      if (pageCache.html) {
        var cached = parseCategories(pageCache.html);
        if (cached.length >= 4) return cached;
      }
      await loadCookies();
      var pageHtml = await get('/list/');
      var list = parseCategories(pageHtml);
      if (list.length >= 4) return list;
    } catch (error) {
      /* 落到兜底表 */
    }
    return FALLBACK_CATEGORIES.slice();
  },

  async home() {
    await loadCookies();
    var pageHtml = await get('/');
    var boards = parseTabs(pageHtml);
    if (!boards.length) {
      // 首页结构变了就退到「最新更新 / 分类首页」两条板，别让首页整块空掉
      var fallback = parseCards(await get('/list/'));
      if (fallback.length) boards.push({ title: '最新收录', moreUrl: '/list/', items: fallback.slice(0, 18) });
    }
    if (!boards.length) throw new Error('90漫画：首页没认出条目（站点可能改版）');
    return boards;
  },

  async list(argument) {
    await loadCookies();
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    if (keyword) return searchItems(keyword, pageNo);

    var slug = settings.categoryId ? String(settings.categoryId).trim() : '';
    if (!/^[A-Za-z0-9_-]+$/.test(slug)) slug = 'shaonian';
    var path = pageNo <= 1 ? '/list/' + slug + '/' : '/list/' + slug + '/' + pageNo + '/';
    var pageHtml = await get(path, { Referer: base() + '/list/' });
    var items = parseCards(pageHtml);
    var hasMore = false;
    if (items.length) {
      var maxPage = 0;
      var pattern = new RegExp('/list/' + slug + '/(\\d+)/', 'g');
      var matched;
      while ((matched = pattern.exec(pageHtml)) !== null) {
        var value = Number(matched[1]);
        if (value > maxPage) maxPage = value;
      }
      hasMore = maxPage > pageNo || /下一页|下页/.test(pageHtml);
    }
    return { items: items, hasMore: hasMore };
  },

  async detail(argument) {
    await loadCookies();
    var id = idOf(argument);
    if (!id) return null;
    var pageHtml = await get(id);
    var titleMatch = /<div class="book-title">[\s\S]{0,200}?<h1><span>([\s\S]*?)<\/span><\/h1>/i.exec(pageHtml) ||
      /<h1><span>([\s\S]*?)<\/span><\/h1>/i.exec(pageHtml) ||
      /<title>([\s\S]*?)<\/title>/i.exec(pageHtml);
    var title = titleMatch ? decode(titleMatch[1]) : '';
    if (!title) return null;
    title = title.replace(/\s*-\s*90漫画网\s*$/, '').trim();

    var coverMatch = /<img class="pic" src="([^"]+)"/i.exec(pageHtml) ||
      /<div class="book-cover[\s\S]{0,300}?<img[^>]*src="([^"]+)"/i.exec(pageHtml);
    var cover = coverMatch ? absolute(decode(coverMatch[1])) : '';

    var parts = [];
    var areaMatch = /漫画地区：<\/strong><a[^>]*>([^<]*)<\/a>/i.exec(pageHtml);
    if (areaMatch) parts.push(decode(areaMatch[1]));
    var authorMatch = /漫画作者：<\/strong><a[^>]*>([^<]*)<\/a>/i.exec(pageHtml);
    if (authorMatch) parts.push(decode(authorMatch[1]));
    var statusMatch = /漫画状态：<\/strong>\s*<a[^>]*>([^<]*)<\/a>/i.exec(pageHtml);
    if (statusMatch) parts.push(decode(statusMatch[1]));
    var chapters = parseChapters(pageHtml);
    if (chapters.length) parts.push(chapters.length + ' 话');

    return {
      id: absolute(id),
      title: title,
      cover: cover,
      subtitle: parts.join(' · '),
      description: parseDescription(pageHtml)
    };
  },

  async chapters(argument) {
    await loadCookies();
    var id = idOf(argument);
    if (!id) return [];
    // 已经是章节页就直接认
    if (/\/manhua\/[^\/]+\/\d+\.html$/i.test(id)) return [{ id: absolute(id), title: '本章' }];
    var pageHtml = await get(id);
    return parseChapters(pageHtml);
  },

  async content(argument) {
    await loadCookies();
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var target = chapterId || idOf(argument);
    if (!target) throw new Error('90漫画：缺少章节地址');
    // 传进来的是详情页（/manhua/{slug}/）就先拿第一章
    if (!/\.html$/i.test(target)) {
      var detailHtml = await get(target);
      var list = parseChapters(detailHtml);
      if (!list.length) throw new Error('90漫画：该条目没有章节');
      target = list[0].id;
    }
    var pageHtml = await get(target, { Referer: base() + '/' });
    var images = parseChapterImages(pageHtml);
    if (!images.length) {
      throw new Error('90漫画：章节页没有 chapterImages（可能被地区限制、或是会员话）' + absolute(target));
    }
    return { kind: 'images', images: images, headers: imageHeaders() };
  }
};
