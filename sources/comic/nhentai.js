// LumeSource: {"id":"nhentai_comic","name":"nhentai","version":"1.0.0","category":"comic","mirrors":["https://nhentai.net"]}
//
// 站点：nhentai（https://nhentai.net，英文站，同人志 / 成人漫画，全站 18+）
//
// 结构（2026-10-25 逐页实测，全部走本机代理出口）：
//   · 首页/热门  GET /                       25 张卡片
//   · 语言分区   GET /language/{chinese|english|japanese}/[?page=N]
//   · 搜索       GET /search?q={关键词}[&page=N]
//   · 卡片       <div class="gallery …"><a href="/g/{id}/" class="cover" …>
//                  <img class="lazyload" src="https://t1.nhentai.net/galleries/{media}/thumb.webp" alt="标题">
//                  <div class="caption">标题</div>
//   · 详情       GET /g/{id}/   → <h2 class="title …">标题</h2>、og:image（封面）、og:description、
//                标签链接 /{tag|language|parody|artist|character|category}/{slug}/
//   · 正文       GET /api/v2/galleries/{id}  ← **优先用这个 JSON**（比抠 HTML 稳）：
//                { id, media_id, title:{english,pretty}, num_pages, tags:[{name,type}],
//                  pages:[{number, path:"galleries/{media}/1.webp", width, height}] }
//                图片地址 = https://i.nhentai.net/{path}（实测 206 image/webp，带不带 Referer 都能下）
//   · 旧接口     /api/gallery/{id} 已下线，返回 403「Use new API …/api/v2/docs」
//
// 两个坑：
// 1) **UA 必须用桌面 Chrome**。同一条链接用 iPhone Safari UA 会被 Cloudflare 判 403（Just a moment…），
//    桌面 UA 实测 200。所以本源不跟其它源统一用移动 UA。
// 2) 个别作品被站方屏蔽（lolicon 一类），/api/v2/galleries/{id} 会 404 —— 脚本抛明确错误，不假装能看。
var BASE_URL = 'https://nhentai.net';
var IMAGE_HOST = 'https://i.nhentai.net';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  return (domain || BASE_URL).replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
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

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/json;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function fetchPage(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var text = String((response && response.body) || '');
  // 正常页面里也有 Cloudflare 的 /cdn-cgi/challenge-platform/scripts/jsd 探针，不能拿它当被拦信号；
  // 只认挑战页自己的特征（短页面 + Just a moment / cf-chl- 一类文案）。
  if (status === 403 || status === 503 ||
      (text.length < 60000 && /Just a moment|Attention Required|cf-chl-|__cf_chl/i.test(text))) {
    // App 的 Dart HTTP 栈与 Node 一样吃 Cloudflare 挑战（TLS 指纹判的，不是 Cookie 与 UA 的问题）：
    // 退到宿主的网页渲染（受限 WebKit 能过 JS 挑战），并把「本源走渲染」记 1 小时。
    try {
      var rendered = await renderPage(url);
      await markRenderMode();
      return rendered;
    } catch (error) {
      throw new Error('NEED_WEBVIEW_VERIFY：nhentai 被 Cloudflare 拦住（HTTP ' + status + '），请在源设置里走网页视图完成校验、或给本源配代理');
    }
  }
  if (status !== 200) throw new Error('nhentai 页面打不开：HTTP ' + status + ' ' + url);
  return text;
}

// ---------------------------------------------------------------- 网页渲染兜底
var RENDER_TTL_MS = 3600 * 1000;

async function renderMode() {
  var cached = await LumeSource.fs.readText('mode.json');
  if (!cached) return false;
  try {
    var saved = JSON.parse(cached);
    return !!(saved && saved.render && saved.at && Date.now() - saved.at < RENDER_TTL_MS);
  } catch (error) {
    return false;
  }
}

async function markRenderMode() {
  await LumeSource.fs.writeText('mode.json', JSON.stringify({ render: true, at: Date.now() }));
}

async function renderPage(url) {
  var result = await LumeSource.web.render({
    url: url,
    headers: { 'User-Agent': UA, Accept: 'text/html,application/json;q=0.9,*/*;q=0.8' },
    timeoutMs: 6000
  });
  var body = result && result.html ? String(result.html) : '';
  if (!body) throw new Error('nhentai：网页渲染没有返回内容');
  return body;
}

// 列表卡片：<div class="gallery …"><a href="/g/{id}/" class="cover" …><img src="…/thumb.webp" alt="标题">
function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('<div class="gallery ');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 1400);
    var idMatch = /href="\/g\/(\d+)\/"/.exec(block);
    if (!idMatch) continue;
    var id = idMatch[1];
    if (seen[id]) continue;
    var titleMatch = /<div class="caption">([\s\S]*?)<\/div>/.exec(block) || /<img[^>]+alt="([^"]*)"/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /<img[^>]+(?:data-src|src)="([^"]+)"/.exec(block);
    seen[id] = true;
    items.push({
      id: absolute('/g/' + id + '/'),
      title: title,
      cover: absolute(coverMatch ? coverMatch[1] : ''),
      subtitle: ''
    });
  }
  return items;
}

function hasNextPage(html) {
  return /class="[^"]*next[^"]*"/.test(html) && /href="[^"]*page=\d+"/.test(html);
}

function digitsOf(value) {
  var matched = /\/g\/(\d+)/.exec(String(value || '')) || /galleries\/(\d+)/.exec(String(value || ''));
  if (matched) return matched[1];
  var raw = String(value || '').replace(/[^\d]/g, '');
  return raw;
}

var CATEGORIES = [
  { id: 'home', title: '首页热门', path: '/' },
  { id: 'lang-zh', title: '中文', path: '/language/chinese/' },
  { id: 'lang-en', title: '英文', path: '/language/english/' },
  { id: 'lang-ja', title: '日文', path: '/language/japanese/' }
];

var LumeSource = {
  id: 'nhentai_comic',
  name: 'nhentai',
  version: '1.0.0',
  category: 'comic',
  mirrors: ['https://nhentai.net'],

  async categories() {
    var list = [];
    for (var i = 0; i < CATEGORIES.length; i++) list.push({ id: CATEGORIES[i].id, title: CATEGORIES[i].title });
    return list;
  },

  async home() {
    var boards = [];
    var plans = [
      { path: '/', title: '热门' },
      { path: '/language/chinese/', title: '中文同人志' }
    ];
    for (var i = 0; i < plans.length; i++) {
      try {
        var html = await fetchPage(plans[i].path);
        var items = parseItems(html);
        if (items.length) boards.push({ title: plans[i].title, moreUrl: i === 0 ? 'home' : 'lang-zh', items: items.slice(0, 24) });
      } catch (error) {
        if (i === 0) throw error;
      }
    }
    if (!boards.length) throw new Error('nhentai：首页没认出卡片（站点可能改版，或 UA 被拦）');
    return boards;
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';
    var path = '/';
    for (var i = 0; i < CATEGORIES.length; i++) if (CATEGORIES[i].id === category) path = CATEGORIES[i].path;
    var query = '';
    if (keyword) {
      query = '/search?q=' + encodeURIComponent(keyword);
      if (pageNo > 1) query += '&page=' + pageNo;
      path = query;
    } else if (pageNo > 1) {
      path = path + '?page=' + pageNo;
    }
    var html = await fetchPage(path);
    var items = parseItems(html);
    return { items: items, hasMore: items.length > 0 && (pageNo < 1000) && hasNextPage(html) };
  },

  async detail(argument) {
    var id = digitsOf(argument && argument.id);
    if (!id) return null;
    var html = await fetchPage('/g/' + id + '/');
    var titleMatch = /<h2 class="title[^"]*">([\s\S]*?)<\/h2>/.exec(html) ||
      /<meta[^>]+property="og:title"[^>]+content="([^"]*)"/.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) return null;
    var coverMatch = /<meta[^>]+property="og:image"[^>]+content="([^"]*)"/.exec(html);
    var descMatch = /<meta[^>]+property="og:description"[^>]+content="([^"]*)"/.exec(html);
    var pagesMatch = /(\d+)\s*pages/i.exec(decode(html));
    var parts = [];
    var langMatch = /href="\/language\/([a-z]+)\/"/.exec(html);
    if (langMatch) parts.push(langMatch[1]);
    var tags = [];
    var tagPattern = /href="\/tag\/([^"\/]+)\/"/g;
    var tagMatch;
    while ((tagMatch = tagPattern.exec(html)) !== null && tags.length < 3) {
      var name = decode(String(tagMatch[1]).replace(/-/g, ' '));
      if (name && tags.indexOf(name) < 0) tags.push(name);
    }
    if (tags.length) parts.push(tags.join(' / '));
    if (pagesMatch) parts.push(pagesMatch[1] + ' 页');
    return {
      id: absolute('/g/' + id + '/'),
      title: title,
      cover: absolute(coverMatch ? coverMatch[1] : ''),
      subtitle: parts.join(' · '),
      description: decode(descMatch ? descMatch[1] : '')
    };
  },

  async chapters(argument) {
    var id = digitsOf(argument && argument.id);
    if (!id) return [];
    // 一部同人志就是一话：章节 id 直接用作品 id，content() 再走 API 取图片。
    return [{ id: id, title: '全一话' }];
  },

  async content(argument) {
    var id = digitsOf((argument && argument.chapterId) || (argument && argument.id));
    if (!id) throw new Error('缺少作品 id');
    var raw = await fetchPage('/api/v2/galleries/' + id);
    var data = null;
    try {
      data = JSON.parse(raw);
    } catch (error) {
      throw new Error('nhentai：/api/v2/galleries/' + id + ' 返回的不是 JSON（可能被拦或被屏蔽）');
    }
    var pages = data && data.pages ? data.pages : [];
    var images = [];
    for (var i = 0; i < pages.length; i++) {
      var path = pages[i] && pages[i].path ? String(pages[i].path) : '';
      if (!path) continue;
      images.push(IMAGE_HOST + '/' + path.replace(/^\/+/, ''));
    }
    if (!images.length) throw new Error('nhentai：作品 ' + id + ' 没有可用图片（可能被站方屏蔽）');
    return {
      kind: 'images',
      images: images,
      headers: { Referer: base() + '/', 'User-Agent': UA, Accept: 'image/avif,image/webp,image/*,*/*;q=0.8' }
    };
  }
};
