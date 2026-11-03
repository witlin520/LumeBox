// LumeSource: {"id":"thepornjoy_video","name":"ThePornJoy 18+","version":"1.0.0","category":"video","mirrors":["https://thepornjoy.org","https://www.thepornjoy.org"]}
//
// 站点：https://thepornjoy.org/ （KVS 内核 / kt_player 模板，2026-10-25 逐页实测，**直连可用**）
// 镜像：www.thepornjoy.org 实测 302 回主域（同一套内容，首页首条 id 一致）；thepornjoy.com 是
//       「Coming Soon」停放页，不是镜像。
//
// ── 结构（全部实测 200）
//   首页/最新   GET /latest-updates/                GET /latest-updates/{N}/
//   热门        GET /most-popular/{N}/
//   好评        GET /top-rated/{N}/
//   分类总表    GET /categories/  → <a class="item" href=".../categories/{slug}/" title="{名}">
//   分类列表    GET /categories/{slug}/{N}/
//   搜索        GET /search/{关键词}/  （第 2 页起用 ?from=24、?from=48…；**注意 /search/{词}/2/ 是 404**）
//   详情        GET /videos/{id}/{slug}/  （**只给 /videos/{id}/ 会 404，id 必须连 slug 一起带**）
//   播放       详情页内联对象 `<var 名> = { video_id: '…', video_url: '<get_file 签名地址>/<id>_720p.mp4/?v-acctoken=…' }`
//              。实测 206 + video/mp4，字节头是 `ftypisom`，直连可播（要 Referer）。
//   分页判据   分页块里存在 `<li class="next">`
//
// ── 卡面解析
//   `<div class="item "> <a href="https://thepornjoy.org/videos/{id}/{slug}/" title="{标题}"> … <img … data-original="{封面}">`
//   同一个 anchor 里标题、封面、时长、评分、播放量、上传时间都齐（懒加载图在 data-original）。
//
// ── VIP / 登录：站点有 signup/login（KVS 自带会员），但这些公开视频**不需要登录**
//   详情页里 loginUrl 只是给「收藏/评论」这类互动用的；播放地址（带 v-acctoken 的 mp4）
//   直接在未登录的详情页 HTML 里，实测直接 GET 就是 206。所以本源不伪造任何 VIP 身份，
//   也不把登录态当门槛：拿到详情页就能播。
var H = {
  name: 'ThePornJoy 18+',
  defaultBase: 'https://thepornjoy.org',
  ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
  base: function () {
    var c = typeof LumeSource !== 'undefined' && LumeSource.config ? LumeSource.config : null;
    return String((c && c.domain) || this.defaultBase).replace(/\/+$/, '');
  },
  entity: function (s) {
    return String(s == null ? '' : s).replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, function (all, code) {
      var map = { amp: '&', quot: '"', apos: "'", lt: '<', gt: '>', nbsp: ' ', '#39': "'", '#34': '"' };
      if (map[code] !== undefined) return map[code];
      if (code.charAt(0) === '#') {
        var n = code.charAt(1) === 'x' || code.charAt(1) === 'X' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
        if (isFinite(n) && n > 0 && n < 0x110000) return String.fromCharCode(n);
      }
      return all;
    });
  },
  clean: function (s) {
    var t = String(s == null ? '' : s)
      .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ');
    return this.entity(t).replace(/\s+/g, ' ').trim();
  },
  abs: function (u) {
    var text = this.entity(String(u == null ? '' : u)).trim();
    if (!text) return '';
    if (text.indexOf('//') === 0) return 'https:' + text;
    if (/^https?:\/\//i.test(text)) return text;
    if (text.charAt(0) === '/') return this.base() + text;
    return this.base() + '/' + text;
  },
  headers: function (referer) {
    return { 'User-Agent': this.ua, Referer: referer || this.base() + '/', 'Accept-Language': 'en-US,en;q=0.9' };
  },
  get: async function (path) {
    var url = /^https?:\/\//i.test(path) ? path : this.base() + path;
    var r = await LumeSource.http.get(url, { headers: this.headers() });
    var s = Number(r && r.status);
    if (s === 403 || s === 503 || s === 521) throw new Error('NEED_WEBVIEW_VERIFY：ThePornJoy 要求网页验证（HTTP ' + s + '）');
    if (s === 404) throw new Error('ThePornJoy：页面不存在（404）' + path);
    if (s !== 200) throw new Error('ThePornJoy：请求失败（HTTP ' + s + '）' + path);
    return String((r && r.body) || '');
  }
};

/// 从列表 HTML 里抽条目。返回 { items, hasMore }
function parseItems(html) {
  var items = [];
  var seen = {};
  // 只认「视频详情」锚点：/videos/{id}/{slug}/ 。span 到后续 2500 字符当卡片块
  // （整个 item 含 img/span/rating 后才会出现 </a>，用 `[\s\S]{0,1200}?</a>` 会漏）
  var re = /<a\s+href="(https?:\/\/[^"]*?\/videos\/(\d+)\/([^"\/]*))\/?"\s+title="([^"]*)"/gi;
  var matched;
  while ((matched = re.exec(html)) !== null) {
    var id = matched[2];
    var slug = matched[3];
    var title = H.entity(matched[4]).trim();
    var block = html.slice(matched.index, matched.index + 3000);
    var coverMatch =
      /data-original="([^"]+)"/i.exec(block) ||
      /data-webp="([^"]+)"/i.exec(block) ||
      /<img[^>]+src="(https?:[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"/i.exec(block);
    var duration = /<div class="duration">\s*([^<]+?)\s*<\/div>/i.exec(block);
    var added = /<div class="added">[\s\S]{0,40}?<em>([^<]+)<\/em>/i.exec(block);
    var views = /<div class="views">\s*([^<]+?)\s*<\/div>/i.exec(block);
    if (!title || seen[id]) continue;
    seen[id] = 1;
    var bits = [];
    if (duration) bits.push(duration[1].trim());
    if (views) bits.push(H.clean(views[1]) + ' 次');
    if (added) bits.push(H.clean(added[1]));
    items.push({
      id: id + '/' + slug,
      title: title,
      cover: coverMatch ? H.abs(coverMatch[1]) : '',
      subtitle: bits.join(' · ')
    });
  }
  return { items: items, hasMore: /<li class="next">/i.test(html) };
}

function pageSuffix(page) {
  return page > 1 ? String(page) + '/' : '';
}

/// 分类总表里的 slug 白名单（只认分类详情页真能开的）
async function loadCategories() {
  var html = await H.get('/categories/');
  var rows = [];
  var seen = {};
  var re = /<a class="item"\s+href="https?:\/\/[^"]*?\/categories\/([a-z0-9\-]+)\/?"\s+title="([^"]*)"/gi;
  var matched;
  while ((matched = re.exec(html)) !== null) {
    var slug = matched[1];
    var name = H.entity(matched[2]).trim();
    if (!slug || seen[slug] || !name) continue;
    seen[slug] = 1;
    rows.push({ id: slug, title: name });
    if (rows.length >= 40) break;
  }
  return rows;
}

var CATEGORY_CACHE = null;

var LumeSource = {
  id: 'thepornjoy_video',
  name: 'ThePornJoy',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://thepornjoy.org', 'https://www.thepornjoy.org'],

  /// 分类：/categories/ 实时抓（站点有 100+，取到 40 个就够面板用）。
  async categories() {
    if (!CATEGORY_CACHE) CATEGORY_CACHE = await loadCategories();
    if (!CATEGORY_CACHE.length) {
      return [
        { id: 'latest', title: '最新' },
        { id: 'popular', title: '最热' }
      ];
    }
    return [{ id: 'latest', title: '最新' }, { id: 'popular', title: '最热' }].concat(CATEGORY_CACHE);
  },

  /// 首页三块：最新 / 最热 / 好评
  async home() {
    var boards = [];
    var groups = [
      { title: '最新更新', path: '/latest-updates/', more: 'latest' },
      { title: 'Most Popular', path: '/most-popular/', more: 'popular' },
      { title: '最高评分', path: '/top-rated/', more: 'top' }
    ];
    for (var i = 0; i < groups.length; i++) {
      try {
        var page = parseItems(await H.get(groups[i].path));
        if (page.items.length) boards.push({ title: groups[i].title, moreUrl: groups[i].more, items: page.items.slice(0, 20) });
      } catch (error) {
        /* 某一块挂了不影响其它块 */
      }
    }
    if (!boards.length) throw new Error('ThePornJoy：首页三块都没解析出条目（站点可能改版）');
    return boards;
  },

  /// 列表 / 搜索
  async list(argument) {
    var arg = argument || {};
    var page = Number(arg.page || 1) || 1;
    var keyword = arg.keyword ? String(arg.keyword).trim() : '';
    var categoryId = arg.categoryId ? String(arg.categoryId) : 'latest';
    var path;
    if (keyword) {
      // 搜索分页是 ?from=N（每页 24），不是 /2/
      var offset = (page - 1) * 24;
      path = '/search/' + encodeURIComponent(keyword) + '/' + (offset > 0 ? '?from=' + offset : '');
    } else if (categoryId === 'popular') {
      path = '/most-popular/' + pageSuffix(page);
    } else if (categoryId === 'top') {
      path = '/top-rated/' + pageSuffix(page);
    } else if (categoryId && categoryId !== 'latest') {
      path = '/categories/' + encodeURIComponent(categoryId) + '/' + pageSuffix(page);
    } else {
      path = '/latest-updates/' + pageSuffix(page);
    }
    return parseItems(await H.get(path));
  },

  /// 详情：id 形如 `816577/he-fucks-me-...`（列表里直接给的 id+slug）
  async detail(argument) {
    var raw = String((argument && argument.id) || '').trim().replace(/^\/+|\/+$/g, '');
    if (!raw) return null;
    var idPart = raw.split('/')[0];
    if (!/^\d+$/.test(idPart)) return null;
    var html;
    try {
      html = await H.get('/videos/' + raw + '/');
    } catch (error) {
      if (/404/.test(String(error && error.message))) return null;
      throw error;
    }
    var titleMatch = /<h1[^>]*>([\s\S]{0,300}?)<\/h1>/i.exec(html) || /<title>([\s\S]{0,200}?)<\/title>/i.exec(html);
    var title = titleMatch ? H.clean(titleMatch[1]).replace(/^Watch the Video\s*-\s*/i, '') : idPart;
    var coverMatch =
      /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i.exec(html) ||
      /<img[^>]+class="[^"]*video-holder[^"]*"[^>]+src="([^"]+)"/i.exec(html) ||
      /data-original="([^"]+)"/i.exec(html);
    var cats = [];
    var catRe = /<a[^>]+href="https?:\/\/[^"]*\/categories\/[a-z0-9\-]+\/?"[^>]*>([^<]{1,40})<\/a>/gi;
    var catMatch;
    while ((catMatch = catRe.exec(html)) !== null) {
      var name = H.clean(catMatch[1]);
      if (name && cats.indexOf(name) < 0) cats.push(name);
      if (cats.length >= 6) break;
    }
    var models = [];
    var modelRe = /<a[^>]+href="https?:\/\/[^"]*\/models\/[a-z0-9\-]+\/?"[^>]*>([^<]{1,40})<\/a>/gi;
    var modelMatch;
    while ((modelMatch = modelRe.exec(html)) !== null) {
      var modelName = H.clean(modelMatch[1]);
      if (modelName && models.indexOf(modelName) < 0) models.push(modelName);
      if (models.length >= 6) break;
    }
    var duration = /<div class="duration">\s*([^<]+?)\s*<\/div>/i.exec(html);
    var views = /<div class="views">\s*([^<]+?)\s*<\/div>/i.exec(html);
    var desc = [];
    if (cats.length) desc.push('分类：' + cats.join(', '));
    if (models.length) desc.push('模特：' + models.join(', '));
    if (duration) desc.push('时长：' + duration[1].trim());
    if (views) desc.push('播放：' + H.clean(views[1]));
    var sub = [];
    if (duration) sub.push(duration[1].trim());
    if (models.length) sub.push(models[0]);
    if (views) sub.push(H.clean(views[1]) + ' 次');
    return {
      id: raw,
      title: title,
      cover: coverMatch ? H.abs(coverMatch[1]) : '',
      subtitle: sub.join(' · '),
      description: desc.join('\n')
    };
  },

  /// 单集
  async chapters(argument) {
    var raw = String((argument && argument.id) || '').trim();
    if (!raw) return [];
    return [{ id: raw + '#play', title: '播放' }];
  },

  /// 播放：详情页内联的 video_url（get_file 签名 mp4），实测 206 + video/mp4
  async content(argument) {
    var arg = argument || {};
    var raw = String(arg.id || arg.chapterId || '').replace(/#play$/, '').replace(/^\/+|\/+$/g, '');
    if (!raw) throw new Error('缺少视频 id');
    var pageUrl = H.base() + '/videos/' + raw + '/';
    var html = await H.get('/videos/' + raw + '/');
    var media = [];
    var re = /video_(?:alt_)?url[0-9]*\s*:\s*'([^']+)'/gi;
    var matched;
    while ((matched = re.exec(html)) !== null) {
      var u = H.entity(matched[1]).trim();
      if (/^https?:\/\//i.test(u) && u.indexOf('.mp4') > 0 && media.indexOf(u) < 0) media.push(u);
    }
    if (!media.length) {
      // 极少数页面用 JSON 转义（\/）或者相对路径，兜一下
      var quoted = /"video_url"\s*:\s*"([^"]+)"/i.exec(html);
      if (quoted) {
        var q = H.entity(quoted[1]).replace(/\\\//g, '/');
        if (/^https?:\/\//i.test(q)) media.push(q);
      }
    }
    if (!media.length) throw new Error('ThePornJoy：详情页里没找到播放地址（站点模板可能改了）');
    var headers = { Referer: pageUrl, 'User-Agent': H.ua };
    // mp4 是整片（几百 MB），探活/起播都带 Range 更快；同 porntrex.js 的做法
    headers.Range = 'bytes=0-1023';
    var qualities = [];
    for (var i = 0; i < media.length; i++) {
      var label = /_(\d{3,4})p\.mp4/i.exec(media[i]);
      qualities.push({ label: label ? label[1] + 'P' : '线路 ' + (i + 1), url: media[i] });
    }
    qualities.sort(function (a, b) {
      return (parseInt(String(b.label), 10) || 0) - (parseInt(String(a.label), 10) || 0);
    });
    return { kind: 'video', url: qualities[0].url, headers: headers, qualities: qualities.length > 1 ? qualities : undefined };
  }
};
