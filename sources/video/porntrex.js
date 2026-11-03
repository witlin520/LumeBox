// LumeSource: {"id":"porntrex_video","name":"PornTrex","version":"1.0.0","category":"video","mirrors":["https://www.porntrex.com","https://porntrex.com"]}
// 镜像：porntrex.com 会 302 到 www.porntrex.com

// 站点：https://www.porntrex.com （KVS 内核，kt_player；2026-10-25 逐页实测，本机直连被封，验证走本机代理出口）
//
// 结构：
//   列表     GET /latest-updates/<N>/、/most-popular/<N>/、/top-rated/<N>/（1 基，第 1 页省略序号也行）
//   分类     GET /categories/<slug>/ → /categories/<slug>/<N>/（首页与页脚导航里带全套分类链接）
//   标签     GET /tags/<slug>/<N>/（存在，未放进 categories，避免几百项把面板撑爆）
//   搜索     GET /search/<词>/<N>/（词在路径里，URL 编成分页形如 /search/teen/2/）
//   卡片     `<div class="video-preview-screen video-item thumb-item  " data-item-id="<id>">`，
//            首页另有一版 `<span class="video-item">` 包法；两种都靠“`/video/<id>/<slug>` 锚点 + 同块
//            `data-src` 封面 + `alt`/`p.inf>a` 标题”抽，不依赖具体外层 class。
//   播放    详情页内联 `var flashvars = { video_url: '…<hash>/<id>/<id>.mp4/', video_alt_url: …720p…,
//            video_alt_url2: …1080p… }`。get_file 路径带 md5 段，**每次播放现取详情页**。
//            实测 `GET /get_file/...` 直接 302 到 pcdn.cdntrex.com 的签名 mp4（200/206 video/mp4）。
//   分页判据 分页块里存在 `class="next"`。
//
// 需要 Referer（站点根或详情页都行）+ 移动/桌面 UA 都能过；播放地址是 CDN 直链，不额外要 Cookie。
var H = {
  name: 'PornTrex',
  defaultBase: 'https://www.porntrex.com',
  base: 'https://www.porntrex.com',
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
    var t = String(s == null ? '' : s)
      .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ');
    return this.entity(t).replace(/\s+/g, ' ').trim();
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
  /// 播放头：mp4 直链是整片（几百 MB 起），带 `Range: bytes=0-` 的探活/起播都更快；
  /// m3u8 不能带 Range，否则拿不到 `#EXTM3U`。播放器自己也会发 Range，这里给的是同一语义。
  mediaHeaders: function (pageUrl, url) {
    var h = { 'Referer': pageUrl, 'User-Agent': this.ua };
    if (/\.mp4[/?#]?$/i.test(url) || /\.mp4\//i.test(url)) h['Range'] = 'bytes=0-1023';
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
  get: async function (path) {
    var url = /^https?:\/\//i.test(path) ? path : this.base + path;
    return this.response(await LumeSource.http.get(url, { headers: this.headers() }));
  }
};

/// 取 `var xx = { … };` 里的视频字段（flashvars 是 JS 对象字面量，键名不加引号，正则逐个抠更稳）
function flashField(html, name) {
  var m = new RegExp(name + "\\s*:\\s*'([^']*)'").exec(html) || new RegExp(name + '\\s*:\\s*"([^"]*)"').exec(html);
  return m ? m[1] : '';
}

/// 从详情页 HTML 里抽出全部清晰度：[{label, url, quality}]
function qualities(html) {
  var rows = [];
  var pairs = [
    ['video_url', 'video_url_text', 0],
    ['video_alt_url', 'video_alt_url_text', 1],
    ['video_alt_url2', 'video_alt_url2_text', 2],
    ['video_alt_url3', 'video_alt_url3_text', 3]
  ];
  for (var i = 0; i < pairs.length; i++) {
    var url = flashField(html, pairs[i][0]);
    if (!url) continue;
    var label = flashField(html, pairs[i][1]) || '';
    var q = Number(String(label).replace(/[^\d]/g, '')) || 0;
    rows.push({ label: label || (q ? q + 'p' : '默认'), url: url, quality: q });
  }
  rows.sort(function (a, b) { return b.quality - a.quality; });
  return rows;
}

var LumeSource = {
  id: 'porntrex_video',
  name: 'PornTrex',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.porntrex.com'],

  async home() {
    H.useDomain();
    var page = await this.list({ categoryId: '/latest-updates/', page: 1 });
    if (!page.items.length) throw new Error('PornTrex：首页没认出条目（站点可能改版）');
    return [{ title: '最新更新', moreUrl: '/latest-updates/', items: page.items.slice(0, 24) }];
  },

  /// 分类＝页脚导航里的 `/categories/<slug>/`；外加四个排序入口。
  async categories() {
    H.useDomain();
    var rows = [
      { id: '/latest-updates/', title: '最新更新' },
      { id: '/most-popular/', title: '最多观看' },
      { id: '/top-rated/', title: '最高评分' }
    ];
    var seen = { '/latest-updates/': 1, '/most-popular/': 1, '/top-rated/': 1 };
    try {
      var html = await H.get('/');
      var re = /<a[^>]+href="(?:https?:\/\/[^"\/]+)?(\/categories\/[a-z0-9-]+\/)"[^>]*>([\s\S]{0,80}?)<\/a>/gi, m;
      while ((m = re.exec(html)) !== null) {
        var id = m[1];
        var title = H.clean(m[2]);
        if (!title || seen[id]) continue;
        seen[id] = 1;
        rows.push({ id: id, title: title });
      }
    } catch (error) {
      console.warn('[porntrex] 分类导航抓取失败：' + error);
    }
    return rows.slice(0, 80);
  },

  async list(argument) {
    H.useDomain();
    var args = argument || {};
    var page = Math.max(1, Number(args.page) || 1);
    var keyword = H.clean(args.keyword || '').trim();
    var category = String(args.categoryId == null ? '' : args.categoryId).trim() || '/latest-updates/';
    var path;
    if (keyword) {
      path = '/search/' + encodeURIComponent(keyword) + '/' + page + '/';
    } else if (/^https?:\/\//i.test(category)) {
      path = category;
    } else {
      var base = category.charAt(0) === '/' ? category : '/' + category;
      if (!/\/$/.test(base)) base += '/';
      path = page > 1 ? base + page + '/' : base;
    }
    var html = await H.get(path);
    var items = this.__items(html);
    if (!items.length) console.warn('[porntrex] 列表没解析出条目：' + path);
    return { items: items, hasMore: /<li class="next">|<li class='next'>|class="next"/i.test(html) };
  },

  /// 卡片解析：以 `data-item-id="<id>"` 切块；无该属性时退回“锚点 + 图片”窗口扫描（首页竖版卡）。
  __items: function (html) {
    var out = [], seen = {}, text = String(html);
    var chunks = text.split('video-item');
    var re = /\/video\/(\d+)\/([a-z0-9-]+)/i;
    var i, block, hit, id, title, cover, dur, m;
    for (i = 0; i < chunks.length; i++) {
      block = chunks[i].slice(0, 4000);
      hit = re.exec(block);
      if (!hit) continue;
      id = hit[1];
      if (seen[id]) continue;
      seen[id] = 1;
      title = (/alt="([^"]{2,300})"/.exec(block) || [])[1] || '';
      if (!title) title = (/<p class="inf">[\s\S]{0,300}?<a[^>]*>([\s\S]{0,200}?)<\/a>/.exec(block) || [])[1] || '';
      title = H.clean(title);
      if (!title) title = H.clean(hit[2].replace(/-/g, ' '));
      cover = (/data-src="([^"]+)"/.exec(block) || [])[1] || (/src="([^"]+\.jpe?g[^"]*)"/.exec(block) || [])[1] || '';
      dur = (/class="durations"[^>]*>([\s\S]{0,60}?)<\/div>/.exec(block) || [])[1] || '';
      dur = H.clean(dur);
      out.push({
        id: 'https://www.porntrex.com/video/' + id + '/' + hit[2],
        title: title,
        cover: cover ? H.abs(cover) : null,
        coverHeaders: H.headers(),
        subtitle: dur
      });
    }
    return out;
  },

  async detail(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var m = /\/video\/(\d+)\/([a-z0-9-]+)/i.exec(id);
    if (!m) return null;
    var pageUrl = H.base + '/video/' + m[1] + '/' + m[2];
    var html = await H.get(pageUrl);
    var title = (/<meta[^>]+property="og:title"[^>]+content="([^"]*)"/i.exec(html) || [])[1] || '';
    if (!title) {
      var t = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
      title = t ? H.clean(t[1]).replace(/\s*[-|]\s*PornTrex.*$/i, '') : '';
    }
    if (!title) title = H.clean(m[2].replace(/-/g, ' '));
    var cover = (/<meta[^>]+property="og:image"[^>]+content="([^"]*)"/i.exec(html) || [])[1] || '';
    var desc = '';
    var dm = /<div class="video-description[^"]*"[^>]*>([\s\S]{0,1200}?)<\/div>/i.exec(html) ||
             /<meta[^>]+name="description"[^>]+content="([^"]*)"/i.exec(html);
    desc = dm ? H.clean(dm[1]) : '';
    var qs = qualities(html);
    var dur = (/class="durations"[^>]*>([\s\S]{0,60}?)<\/div>/i.exec(html) || [])[1] || '';
    var bits = [];
    if (H.clean(dur)) bits.push(H.clean(dur));
    if (qs.length) bits.push(qs.map(function (r) { return r.label; }).join('/'));
    return {
      id: pageUrl,
      title: title,
      cover: cover ? H.abs(cover) : null,
      coverHeaders: H.headers(),
      subtitle: bits.join(' · '),
      description: desc
    };
  },

  /// KVS 一条视频有多档清晰度：一档一集，id 就是档位标签（content 按标签挑 URL）。
  async chapters(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var m = /\/video\/(\d+)\/([a-z0-9-]+)/i.exec(id);
    if (!m) return [];
    try {
      var html = await H.get(H.base + '/video/' + m[1] + '/' + m[2]);
      var rows = qualities(html);
      if (rows.length) {
        return rows.map(function (r) {
          var label = r.label || (r.quality ? r.quality + 'p' : 'MP4');
          return { id: label, title: label };
        });
      }
    } catch (error) {
      console.warn('[porntrex] chapters 解析清晰度失败，退回单集：' + error);
    }
    return [{ id: 'play', title: '正片' }];
  },

  async content(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var chapterId = String(argument && argument.chapterId ? argument.chapterId : '').trim();
    var m = /\/video\/(\d+)\/([a-z0-9-]+)/i.exec(id);
    if (!m) throw new Error('PornTrex：认不出视频地址（' + id + '）——id 应来自 list()');
    var pageUrl = H.base + '/video/' + m[1] + '/' + m[2];
    var html = await H.get(pageUrl);
    var rows = qualities(html);
    if (!rows.length) {
      return { kind: 'webplayer', pageUrl: pageUrl, headers: H.headers(pageUrl) };
    }
    var picked = null;
    for (var i = 0; i < rows.length; i++) {
      if (chapterId && rows[i].label === chapterId) { picked = rows[i]; break; }
    }
    if (!picked) picked = rows[0];
    return {
      kind: 'video',
      url: picked.url,
      headers: H.mediaHeaders(pageUrl, picked.url),
      qualities: rows.map(function (r) { return { label: r.label, url: r.url }; })
    };
  }
};

if (typeof module !== 'undefined' && module.exports) module.exports = LumeSource;
