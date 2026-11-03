// LumeSource: {"id":"horrorporn_video","name":"HorrorPorn","version":"1.0.0","category":"video","mirrors":["https://horrorporn.com"]}

// 站点：https://horrorporn.com （hqmediago 网络下的恐怖题材成人片站；2026-10-25 逐页实测，走本机代理出口）
//
// 结构（和普通 tube 不一样，站点**没有** /videos/ 这类列表页，实测 /videos/、/latest/、/pages/videos/
// 全是 404）：
//   着陆页    GET /                       → 只有 slider + 3 部精选（listing-hot），当“精选”用
//   搜索      GET /pages/search/?q=<词>    → 结果卡 `<div class="search-item grid…" data-gallery-id="…">`
//                                             内含 `<a class="media-wrapper" href="/video/<slug>/">` + `<img … alt="标题">`
//                                             （站点不给分页，一次把命中的都吐出来）
//   标签      GET /pages/tags/             → 每个标签就是一条 `/pages/search/?q=<词>&key=<n>` 链接
//   全量目录  GET /sitemap.xml             → 53 条 `<loc>https://horrorporn.com/video/<slug>/</loc>` +
//                                             `<video:title>` + `<video:thumbnail_loc>`（本站唯一“全量列表”）
//   详情      GET /video/<slug>/           → og:title / og:image / JSON-LD
//   播放      `<video … data-video-sources='[{"src":"https://cdn77.hqmediago.com/files/horrorporn.com/eNNN/sample-960x540.mp4?secure=…","type":"video/mp4","width":960,…}, …]'>`
//             同一个数组里 960x540 / 1280x720 / 1920x1080 / 3840x2160 四档，全部是 `sample-*.mp4`。
//
// **重要（如实说明）**：全片要订阅（sitemap 里 `<video:requires_subscription>yes</video:requires_subscription>`，
// 详情页 `<video data-play="False">`，页头只有 Login / Join now）。站点对外公开的直链只有上面这些
// `sample-*`（带 `secure=<sig>,<expires>` 签名，实测 206 + `Content-Type: video/mp4`，能直接播）。
// 所以 content() 返回的是**官方公开样片直链**，不编造全片地址；样片都拿不到时才退 webplayer。
var H = {
  name: 'HorrorPorn',
  defaultBase: 'https://horrorporn.com',
  base: 'https://horrorporn.com',
  ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',

  useDomain: function () {
    var c = (typeof LumeSource !== 'undefined' && LumeSource.config) || null;
    this.base = String((c && c.domain) || this.defaultBase).replace(/\/+$/, '');
    return this.base;
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
    return this.entity(String(s == null ? '' : s).replace(/<script\b[\s\S]*?<\/script>/gi, ' ').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
  },
  abs: function (u) {
    u = this.entity(String(u == null ? '' : u)).trim();
    if (!u) return '';
    if (u.indexOf('//') === 0) return 'https:' + u;
    if (/^https?:\/\//i.test(u)) return u;
    if (u.charAt(0) === '/') return this.base + u;
    return this.base + '/' + u;
  },
  headers: function (referer) {
    return { 'User-Agent': this.ua, 'Referer': referer || this.base + '/', 'Accept-Language': 'en-US,en;q=0.9' };
  },
  mediaHeaders: function (pageUrl, url) {
    var h = { 'Referer': pageUrl, 'User-Agent': this.ua };
    if (/\.mp4[/?#]?$/i.test(url) || /\.mp4\?/i.test(url)) h['Range'] = 'bytes=0-1023';
    return h;
  },
  response: function (r) {
    if (!r) throw new Error(this.name + '：没有网络响应');
    var s = Number(r.status);
    if (s === 403 || s === 503 || s === 521) throw new Error('NEED_WEBVIEW_VERIFY：' + this.name + ' 要求网页验证（HTTP ' + s + '）');
    if (s === 404) throw new Error(this.name + '：页面不存在（HTTP 404）');
    if (s !== 200) throw new Error(this.name + '：请求失败（HTTP ' + s + '）');
    return String(r.body || '');
  },
  get: async function (path, referer) {
    var url = /^https?:\/\//i.test(path) ? path : this.base + path;
    return this.response(await LumeSource.http.get(url, { headers: this.headers(referer) }));
  }
};

var LumeSource = {
  id: 'horrorporn_video',
  name: 'HorrorPorn',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://horrorporn.com'],

  async home() {
    H.useDomain();
    var html = await H.get('/');
    var items = this.__cards(html, true);
    if (!items.length) {
      var page = await this.list({ categoryId: 'sitemap', page: 1 });
      items = page.items;
    }
    if (!items.length) throw new Error('HorrorPorn：首页没认出条目（站点可能改版）');
    return [{ title: '精选', moreUrl: '/', items: items.slice(0, 24) }];
  },

  /// 站点是“搜索驱动”的：全量目录用 sitemap，其余入口都是 /pages/search/ 标签页。
  async categories() {
    H.useDomain();
    var rows = [
      { id: 'sitemap', title: '全部影片（sitemap）' },
      { id: '/pages/search/?q=horror', title: '搜索：horror' }
    ];
    var seen = {};
    rows.forEach(function (r) { seen[r.id] = 1; });
    try {
      var html = await H.get('/pages/tags/');
      var re = /<a[^>]+href="(https?:\/\/[^"]*\/pages\/search\/\?q=[^"]+)"[^>]*>([\s\S]{0,800}?)<\/a>/gi, m;
      while ((m = re.exec(html)) !== null) {
        var url = H.entity(m[1]);
        var span = /<span[^>]*>([\s\S]{0,120}?)<\/span>/i.exec(m[2]);
        var title = H.clean(span ? span[1] : m[2]);
        if (!title) title = H.clean(decodeURIComponent(url.replace(/^.*[?&]q=/, '').split('&')[0]).replace(/\+/g, ' '));
        if (!title || seen[url]) continue;
        seen[url] = 1;
        rows.push({ id: url, title: '标签：' + title });
        if (rows.length >= 48) break;
      }
    } catch (error) {
      console.warn('[horrorporn] 标签页抓取失败：' + error);
    }
    return rows;
  },

  async list(argument) {
    H.useDomain();
    var args = argument || {};
    var page = Math.max(1, Number(args.page) || 1);
    var keyword = H.clean(args.keyword || '').trim();
    var category = String(args.categoryId == null ? '' : args.categoryId).trim();
    var items, hasMore = false;
    if (keyword) {
      var html = await H.get('/pages/search/?q=' + encodeURIComponent(keyword));
      items = this.__cards(html, false);
    } else if (category && category !== 'sitemap') {
      var pageHtml = await H.get(category);
      items = this.__cards(pageHtml, false);
    } else {
      var rows = await this.__sitemap();
      var size = 24;
      var from = (page - 1) * size;
      items = rows.slice(from, from + size);
      hasMore = rows.length > from + size;
    }
    if (!items.length) console.warn('[horrorporn] 列表没解析出条目：' + (keyword || category || 'sitemap'));
    return { items: items, hasMore: hasMore };
  },

  /// sitemap.xml → 全量条目（含标题/封面）。按 `</url>` 切片逐条解析，
  /// 避免用一条跨块正则把后面的 `<loc>` 一起吞掉（描述长度不定）。
  __sitemap: async function () {
    var xml = await H.get('/sitemap.xml');
    var out = [], seen = {};
    var chunks = String(xml).split('</url>');
    for (var i = 0; i < chunks.length; i++) {
      var block = chunks[i];
      var loc = /<loc>\s*(https?:\/\/[^<]*\/video\/([^<\/]+)\/)\s*<\/loc>/.exec(block);
      if (!loc) continue;
      var url = loc[1];
      if (seen[url]) continue;
      seen[url] = 1;
      var title = (/<video:title>\s*(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?\s*<\/video:title>/.exec(block) || [])[1] || '';
      var cover = (/<video:thumbnail_loc>([^<]+)<\/video:thumbnail_loc>/.exec(block) || [])[1] || '';
      var desc = (/<video:description>\s*(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?\s*<\/video:description>/.exec(block) || [])[1] || '';
      out.push({
        id: url,
        title: H.clean(title) || H.clean(loc[2].replace(/-/g, ' ')),
        cover: cover ? H.entity(cover.trim()) : null,
        coverHeaders: H.headers(),
        subtitle: '',
        description: H.clean(desc)
      });
    }
    return out;
  },

  /// 结果卡解析：`search-item` 块里的 `<a class="media-wrapper" href="/video/<slug>/">` + `<img … alt="标题">`
  __cards: function (html, homeMode) {
    var text = String(html);
    var out = [], seen = {};
    var chunks = homeMode ? text.split('<a ') : text.split('data-gallery-id');
    var re = /href="(?:https?:\/\/[^"\/]+)?(\/video\/[^"\/]+\/)"/;
    var i, block, hit, alt, img, time;
    for (i = 0; i < chunks.length; i++) {
      block = chunks[i].slice(0, 2600);
      hit = re.exec(block);
      if (!hit) continue;
      var path = hit[1];
      if (seen[path]) continue;
      seen[path] = 1;
      img = /<img[^>]+alt="([^"]*)"[^>]*>/i.exec(block);
      alt = img ? img[1] : '';
      var src = (/<img[^>]+src="(https?:\/\/[^"]+)"/i.exec(block) || [])[1] || '';
      if (!src) src = (/data-thumbnail="([^"]+)"/i.exec(block) || [])[1] || '';
      time = (/<time[^>]*>([\s\S]{0,20}?)<\/time>/.exec(block) || [])[1] || '';
      out.push({
        id: H.base + path,
        title: H.clean(alt) || H.clean(path.replace(/^\/video\//, '').replace(/\/$/, '').replace(/-/g, ' ')),
        cover: src ? H.abs(src) : null,
        coverHeaders: H.headers(),
        subtitle: H.clean(time)
      });
    }
    return out;
  },

  async detail(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var m = /\/video\/([a-z0-9-]+)\/?/i.exec(id);
    if (!m) return null;
    var pageUrl = H.base + '/video/' + m[1] + '/';
    var html = await H.get(pageUrl);
    var title = (/<meta[^>]+property="og:title"[^>]+content="([^"]*)"/i.exec(html) || [])[1] || '';
    if (!title) {
      var t = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
      title = t ? H.clean(t[1]) : '';
    }
    if (!title) title = H.clean(m[1].replace(/-/g, ' '));
    var cover = (/<meta[^>]+property="og:image"[^>]+content="([^"]*)"/i.exec(html) || [])[1] || '';
    var desc = (/<meta[^>]+name="description"[^>]+content="([^"]*)"/i.exec(html) || [])[1] || '';
    if (!desc) desc = (/<meta[^>]+property="og:description"[^>]+content="([^"]*)"/i.exec(html) || [])[1] || '';
    var dur = (/"duration"\s*:\s*"PT([^"]+)"/.exec(html) || [])[1] || '';
    return {
      id: pageUrl,
      title: H.entity(title),
      cover: cover ? H.abs(cover) : null,
      coverHeaders: H.headers(),
      subtitle: dur ? '时长 ' + dur : '',
      description: H.clean(desc)
    };
  },

  async chapters(argument) {
    if (!argument || !argument.id) return [];
    return [{ id: 'play', title: '正片（官方样片）' }];
  },

  async content(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var m = /\/video\/([a-z0-9-]+)\/?/i.exec(id);
    if (!m) throw new Error('HorrorPorn：认不出视频地址（' + id + '）——id 应来自 list()');
    var pageUrl = H.base + '/video/' + m[1] + '/';
    var html = await H.get(pageUrl);
    var raw = '';
    var dm = /data-video-sources='([\s\S]*?)'/i.exec(html) || /data-video-sources="([\s\S]*?)"/i.exec(html);
    if (dm) raw = H.entity(dm[1]);
    var rows = [];
    if (raw) {
      try {
        var list = JSON.parse(raw);
        for (var i = 0; i < list.length; i++) {
          var src = String(list[i].src || '');
          if (!src) continue;
          rows.push({ url: H.abs(src), width: Number(list[i].width) || 0, height: Number(list[i].height) || 0 });
        }
      } catch (error) {
        console.warn('[horrorporn] data-video-sources 解析失败：' + error);
      }
    }
    if (!rows.length) {
      var re = /(https?:\/\/[^"'\s]+\.mp4\?secure=[^"'\s]+)/g, mm;
      while ((mm = re.exec(raw || html)) !== null) {
        var w = Number((/(\d{3,4})x(\d{3,4})/.exec(mm[1]) || [])[1]) || 0;
        rows.push({ url: mm[1], width: w, height: 0 });
      }
    }
    if (!rows.length) {
      return { kind: 'webplayer', pageUrl: pageUrl, headers: H.headers(pageUrl) };
    }
    rows.sort(function (a, b) { return b.width - a.width; });
    return {
      kind: 'video',
      url: rows[0].url,
      headers: H.mediaHeaders(pageUrl, rows[0].url),
      qualities: rows.map(function (r) { return { label: (r.width ? r.width + 'x' + (r.height || Math.round(r.width * 9 / 16)) : '样片'), url: r.url }; })
    };
  }
};

if (typeof module !== 'undefined' && module.exports) module.exports = LumeSource;
