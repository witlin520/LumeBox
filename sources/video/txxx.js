// LumeSource: {"id":"txxx_video","name":"TXXX","version":"1.0.0","category":"video","mirrors":["https://txxx.com","https://hclips.com","https://upornia.com","https://voyeurhit.com"]}

// 站点：TXXX 网络（https://txxx.com / https://hclips.com / https://upornia.com / https://voyeurhit.com ——
// 同一套 Vue SPA + JSON API 模板，接口路径逐字相同，实测四个域名都能直连 200）
// 覆盖范围：综合（latest-updates / most-popular / top-rated / longest）+ 偷拍（voyeur / hidden cam 分类）
// 源设置里换域名即可在四个站之间切（config.domain 优先，默认 txxx.com）
//
// 结构（2026-10-23 对着线上接口逐条核过；本机直连不通，验证走本机代理出口）：
//   分类      GET /api/json/categories/<lifetime>/str.all.en.json
//             → {categories:[{title, dir, total_videos}]}；dir 就是分类标识
//   首页      GET /api/json/main/<lifetime>/str.en.json（板块/模型/频道）
//   列表      GET /api/json/videos2/<lifetime>/<gender>/<sort>/<count>/
//               <section>.<object_id>.<page>.<type>.<duration>.<date>.json
//             实测：最新  `86400/str/latest-updates/60/..1.all...json`
//                   最热  `14400/str/most-popular/60/..1.all..day.json`
//                   分类  `86400/str/latest-updates/60/categories.<dir>.1.all...json`
//             返回 {videos:[…], pages, total_count}
//   搜索      GET /api/videos2.php?params=259200/str/relevance/60/search..<page>.all...&s=<关键词>
//   详情      GET /api/json/video/86400/<id/1e6 取整>/<id/1e3 取整>/<id>.json
//   播放      GET /api/videofile.php?video_id=<id>&lifetime=864000
//             → [{format:"_hq.mp4", video_url:"<被 Cyrillic 字母替换过的 base64>,<base64 查询串>"}]
//             把 А→A / Е→E / М→M / С→C 还原后分别 base64 解码，拼成
//             `https://<站点>/get_file/…/<id>_hq.mp4/?<d=&br=&ti=>`；实测 302 到 ahcdn，
//             带 Range 回 206 video/mp4。签名带 ti 过期时间，**每次播放现取**。
var H = {
  base: 'https://txxx.com', name: 'TXXX', defaultBase: 'https://txxx.com',
  ua: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
  clean: function (s) { return this.entity(String(s || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim(); },
  entity: function (s) { return String(s || '').replace(/&(?:amp|quot|apos|lt|gt|nbsp|#39);/gi, function (v) { var m = { '&amp;': '&', '&quot;': '"', '&apos;': "'", '&lt;': '<', '&gt;': '>', '&nbsp;': ' ', '&#39;': "'" }; return m[v] || v; }); },
  useDomain: function () { var c = (typeof LumeSource !== 'undefined' && LumeSource.config) || null; this.base = String((c && c.domain) || this.defaultBase).replace(/\/+$/, ''); return this.base; },
  response: function (r) { if (!r) throw new Error(this.name + '：没有网络响应'); var s = r.status; if (s === 403 || s === 503 || s === 521) throw new Error('NEED_WEBVIEW_VERIFY：' + this.name + ' 需要网页验证（HTTP ' + s + '）'); if (s === 404) throw new Error(this.name + '：页面不存在（HTTP 404）'); if (s !== 200) throw new Error(this.name + '：请求失败（HTTP ' + s + '）'); return String(r.body || ''); },
  get: async function (path, absolute) {
    var url = absolute ? path : this.base + path;
    return this.response(await LumeSource.http.get(url, { headers: { 'User-Agent': this.ua, 'Referer': this.base + '/' } }));
  },
  json: async function (path) {
    var text = await this.get(path);
    try { return JSON.parse(text); } catch (error) { throw new Error(this.name + '：接口返回的不是 JSON（站点可能改版）'); }
  }
};

/// 纯 JS base64 解码（沙箱里不保证有 atob / Buffer）。
/// 末尾不足 4 位时按实际字符数出字节——注意不能用 charAt 越界取到的空串去找下标
/// （`indexOf('')` 会回 0，凭空多解出一个 NUL）。
function fromBase64(text) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var s = String(text || '').replace(/[^A-Za-z0-9+/=]/g, '');
  var out = '';
  var at = function (i) { return i < s.length ? chars.indexOf(s.charAt(i)) : -1; };
  var i = 0;
  while (i < s.length) {
    var a = at(i), b = at(i + 1), c = at(i + 2), d = at(i + 3);
    i += 4;
    if (a < 0) break;
    var n = (a << 18) | ((b < 0 ? 0 : b) << 12) | ((c < 0 ? 0 : c) << 6) | (d < 0 ? 0 : d);
    out += String.fromCharCode((n >> 16) & 255);
    if (c >= 0) out += String.fromCharCode((n >> 8) & 255);
    if (d >= 0) out += String.fromCharCode(n & 255);
  }
  return out;
}

/// 站点把 base64 里的若干拉丁字母换成了西里尔同形字母（А/В/Е/М/С…）。
/// 逐字符还原；还原后仍不是 base64 字符的，丢掉（与站点播放器同一做法），
/// 最后校验解出来的必须是一条站内路径，否则报错——绝不把乱码地址交给播放器。
var HOMOGLYPHS = {
  '\u0410': 'A', '\u0412': 'B', '\u0415': 'E', '\u041a': 'K', '\u041c': 'M',
  '\u041d': 'H', '\u041e': 'O', '\u0420': 'P', '\u0421': 'C', '\u0422': 'T',
  '\u0423': 'Y', '\u0425': 'X', '\u0405': 'S', '\u0406': 'I', '\u0408': 'J',
  '\u0430': 'a', '\u0435': 'e', '\u043a': 'k', '\u043c': 'm', '\u043e': 'o',
  '\u0440': 'p', '\u0441': 'c', '\u0442': 't', '\u0443': 'y', '\u0445': 'x',
  '\u0455': 's', '\u0456': 'i', '\u0458': 'j'
};

function foldBase64(text) {
  var out = '';
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i);
    out += HOMOGLYPHS[ch] || ch;
  }
  return out;
}

// TXXX 网络里存在两种编码形态（实测）：
//   · voyeurhit 那套：<base64 路径>,<base64 查询串> 两段逗号分隔；
//   · txxx/hclips/upornia：**整条地址（含 ?d=&br=&ti=）编成一段 base64**，没有逗号。
// 所以两种都要认，解出来必须是以 /get_file/ 开头的站内路径才算数。
function decodeVideoUrl(raw) {
  var text = foldBase64(String(raw || '')).replace(/~/g, '');
  var comma = text.indexOf(',');
  if (comma >= 0) {
    var head = fromBase64(text.slice(0, comma)).replace(/\u0000/g, '');
    var tail = fromBase64(text.slice(comma + 1)).replace(/\u0000/g, '');
    if (head.charAt(0) === '/' && head.indexOf('/get_file/') === 0) return head + '?' + tail;
  }
  var whole = fromBase64(text).replace(/\u0000/g, '');
  if (whole.charAt(0) === '/' && whole.indexOf('/get_file/') === 0) return whole;
  return '';
}

var LumeSource = {
  id: 'txxx_video',
  name: 'TXXX',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://txxx.com', 'https://hclips.com', 'https://upornia.com', 'https://voyeurhit.com'],

  async home() {
    H.useDomain();
    var page = await this.list({ categoryId: '/latest-updates', page: 1 });
    if (!page.items.length) throw new Error('TXXX：首页没认出条目（站点可能改版）');
    return [{ title: '最新视频', moreUrl: '/latest-updates', items: page.items.slice(0, 24) }];
  },

  /// 分类＝站点 categories 接口（按热度排序），外加五个排序入口。
  async categories() {
    H.useDomain();
    var rows = [
      { id: '/latest-updates', title: '最新' },
      { id: '/most-popular', title: '最热' },
      { id: '/most-viewed', title: '最多观看' },
      { id: '/top-rated', title: '最高评分' },
      { id: '/longest', title: '最长' }
    ];
    var seen = {};
    try {
      var data = await H.json('/api/json/categories/14400/str.all.en.json');
      var list = (data && data.categories) || [];
      for (var i = 0; i < list.length && rows.length < 120; i++) {
        var dir = String(list[i].dir || '').trim();
        var title = H.clean(list[i].title || '');
        if (!dir || !title || seen[dir]) continue;
        seen[dir] = true;
        rows.push({ id: '/category/' + dir, title: title });
      }
    } catch (error) {
      console.warn('[txxx] 分类接口抓取失败：' + error);
    }
    return rows;
  },

  async list(argument) {
    H.useDomain();
    var args = argument || {};
    var page = Number(args.page) || 1;
    if (page < 1) page = 1;
    var keyword = H.clean(args.keyword || '').trim();
    var category = String(args.categoryId == null ? '' : args.categoryId).trim();
    var text;
    if (keyword) {
      text = await H.get('/api/videos2.php?params=259200/str/relevance/60/search..' + page + '.all...'
        + '&s=' + encodeURIComponent(keyword));
    } else if (category.indexOf('/category/') === 0) {
      var dir = category.slice('/category/'.length);
      if (!/^[a-z0-9-]+$/.test(dir)) throw new Error('TXXX：认不出分类（' + category + '）');
      text = await H.get('/api/json/videos2/86400/str/latest-updates/60/categories.' + dir + '.' + page + '.all...json');
    } else {
      var sort = category.replace(/^\//, '') || 'latest-updates';
      if (!/^[a-z-]+$/.test(sort)) sort = 'latest-updates';
      var lifetime = '86400';
      var date = '';
      if (sort === 'most-popular' || sort === 'most-viewed' || sort === 'top-rated') { lifetime = '14400'; date = 'day'; }
      text = await H.get('/api/json/videos2/' + lifetime + '/str/' + sort + '/60/..' + page + '.all..' + date + '.json');
    }
    var data;
    try { data = JSON.parse(text); } catch (error) { throw new Error('TXXX：列表接口返回的不是 JSON（站点可能改版）'); }
    var videos = (data && data.videos) || [];
    var items = videos.map(function (v) {
      var cover = String(v.scr || '');
      return {
        id: String(v.video_id || ''),
        title: H.clean(v.title || ''),
        cover: cover || null,
        coverHeaders: { 'User-Agent': H.ua, 'Referer': H.base + '/' },
        subtitle: [v.duration, v.file_dimensions].filter(function (x) { return !!x; }).join(' · ')
      };
    }).filter(function (item) { return item.id && item.title; });
    if (!items.length) console.warn('[txxx] 列表没解析出条目');
    var pages = Number(data && data.pages) || 0;
    return { items: items, hasMore: pages ? page < pages : items.length > 0 };
  },

  async detail(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    if (!/^\d+$/.test(id)) return null;
    var dirs = Math.floor(Number(id) / 1e6) + '/' + Math.floor(Number(id) / 1e3);
    var data = await H.json('/api/json/video/86400/' + dirs + '/' + id + '.json');
    var video = data && data.video;
    if (!video) return null;
    var stats = video.statistics || {};
    var tags = [];
    var cs = String(video.categories || '').split(',');
    for (var i = 0; i < cs.length; i++) { var t = H.clean(cs[i]); if (t) tags.push(t); }
    return {
      id: id,
      title: H.clean(video.title || ''),
      cover: String(video.thumbsrc || video.thumb || '') || null,
      coverHeaders: { 'User-Agent': H.ua, 'Referer': H.base + '/' },
      subtitle: [video.duration, stats.viewed ? stats.viewed + ' 次观看' : '', tags.slice(0, 3).join(' / ')]
        .filter(function (x) { return !!x; }).join(' · ')
    };
  },

  async chapters(argument) {
    if (!argument || !argument.id) return [];
    return [{ id: 'play', title: '播放' }];
  },

  async content(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    if (!/^\d+$/.test(id)) throw new Error('TXXX：认不出视频 id（' + id + '）——id 应当来自 list()');
    var text = await H.get('/api/videofile.php?video_id=' + encodeURIComponent(id) + '&lifetime=864000');
    var rows;
    try { rows = JSON.parse(text); } catch (error) { throw new Error('TXXX：播放接口返回的不是 JSON（站点可能改版）'); }
    if (!rows || !rows.length) throw new Error('TXXX：这个视频没有可用的播放地址（可能需要登录或已下架）');
    var qualities = [];
    for (var i = 0; i < rows.length; i++) {
      var path = decodeVideoUrl(rows[i].video_url);
      if (!path) continue;
      var format = String(rows[i].format || '');
      var label = /_tr\.mp4/.test(format) ? '预告片' : (/4k|2160/i.test(format) ? '4K' : 'HQ');
      qualities.push({ label: label, url: H.base + path });
    }
    if (!qualities.length) throw new Error('TXXX：播放地址解码失败（站点可能换了混淆方式）');
    return {
      kind: 'video',
      url: qualities[0].url,
      headers: { 'Referer': H.base + '/', 'User-Agent': H.ua },
      qualities: qualities
    };
  }
};

if (typeof module !== 'undefined' && module.exports) module.exports = LumeSource;
