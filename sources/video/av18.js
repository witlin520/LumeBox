// LumeSource: {"id":"av18_video","name":"18AV","version":"1.0.0","category":"video","mirrors":["https://18av.mm-cg.com"]}

// 站点：https://18av.mm-cg.com （繁中，18AV / mm-cg；2026-10-25 逐页实测，走本机代理出口）
//
// 结构：
//   列表     GET /zh/<分类>_list/all/<N>.html        例：/zh/chinese_list/all/1.html（N 从 1 起）
//   分类导航 GET /zh/  → 站内链接形如 /zh/<分类>_random/all/index.html，
//            换成 <分类>_list/all/1.html 就是该分类的分页列表（实测 chinese/censored/uncensored/
//            amateurjav/reducing-mosaic/animation/dt…/ 全部 200）。cg / cwp / novel 是写真与小说，剔掉。
//   搜索     GET /zh/fc_search/all/<词>/<N>.html      （fc＝全部影片；另有 chineseonly 等前缀，取值见站内下拉）
//   卡片     `<div class='post video_9s'>` 块：`<a href="…/zh/<分类>_content/<id>/<番号>.html">`、
//            封面 `<img src='https://xxxs.imgstream2.com/…jpg'>`、悬停预览 `<video data-src='…9smv_….mp4'>`（只是预览动图）、
//            标题 `<h3 itemprop='name headline'><a …>标题</a>`、日期 `<div class='meta'>YYYY/MM/DD</div>`
//   详情     GET /zh/<分类>_content/<id>/<番号>.html → h1 标题、播放器海报、JSON-LD(VideoObject) 的
//            name/description/keywords/thumbnailUrl/uploadDate
//   播放     页面里没有 <video>/m3u8，播放器是 **AES 加密的 iframe 串**：
//            `mvarr['<清晰度>_<服务器>']=[['a_iframe_id_x','<ENC>','<iframe 前半>','//18av.mm-cg.com/js/player/play.php?numresolution=<清晰度>&id=','<后半>'],];`
//            浏览器端 content_mv_protect.js 用 decrypto() + CryptoJS.AES 解出 id 再塞进 iframe：
//              decrypto(ENC): 按分隔符（= String.fromCharCode(base+97)）切串 → parseInt(tok, base) ^ xorMask → fromCharCode
//                             得到一段 base64；
//              AES:            AES-128-CBC / PKCS7，key = 页面里 `var argdeqweqweqwe`，iv = `var hdddedg252`
//                             （实测固定 '164aa8d2da404649' / '3d3a4ff9ece0fc5e'，本文件仍从页面读，读不到才落回常量）
//            解出的 id 拼成 → GET /js/player/play.php?numresolution=<清晰度>&id=<id>
//            该页里 `const videoSources = [{src:'https://cdn-*.streamfastpro.com/<hash>/19/2/<key>/<key>.m3u8',
//            type:'application/x-mpegURL', size:1080}, …]`，实测直接 200 + `application/vnd.apple.mpegurl` + `#EXTM3U`。
//            本文件把 AES-128-CBC 解密用纯 JS 移植进来（沙箱无 atob 依赖、无 CryptoJS）。
// 需要 Referer（站点根或详情页）+ 普通 UA；m3u8 是 CDN 直链，不额外要 Cookie。
var H = {
  name: '18AV',
  defaultBase: 'https://18av.mm-cg.com',
  base: 'https://18av.mm-cg.com',
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
    return this.entity(String(s == null ? '' : s).replace(/<script\b[\s\S]*?<\/script>/gi, ' ').replace(/<style\b[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
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
    return { 'User-Agent': this.ua, 'Referer': referer || this.base + '/', 'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8' };
  },
  mediaHeaders: function (pageUrl, url) {
    var h = { 'Referer': pageUrl, 'User-Agent': this.ua };
    if (/\.mp4[/?#]?$/i.test(url)) h['Range'] = 'bytes=0-1023';
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

// ---------------------------------------------------------------- 纯 JS AES-128-CBC 解密
// tiny-AES-c 的字节实现（GF(2^8) 乘 + 程序生成 S 盒），只为解 18AV 的播放 id。
var AES_T = null;
function aesTables() {
  var sbox = new Array(256), rsbox = new Array(256), inv = new Array(256), i, x, y;
  function gmul(a, b) {
    var r = 0, k, hi;
    for (k = 0; k < 8; k++) {
      if (b & 1) r ^= a;
      hi = a & 0x80;
      a = (a << 1) & 0xff;
      if (hi) a ^= 0x1b;
      b >>= 1;
    }
    return r & 0xff;
  }
  inv[0] = 0;
  for (i = 1; i < 256; i++) {
    for (x = 1; x < 256; x++) { if (gmul(i, x) === 1) { inv[i] = x; break; } }
  }
  for (i = 0; i < 256; i++) {
    var b = inv[i], r = b;
    for (y = 1; y <= 4; y++) r ^= ((b << y) | (b >> (8 - y))) & 0xff;
    sbox[i] = r ^ 0x63;
  }
  for (i = 0; i < 256; i++) rsbox[sbox[i]] = i;
  return { sbox: sbox, rsbox: rsbox, mul: gmul };
}
function aesT() { if (!AES_T) AES_T = aesTables(); return AES_T; }
function aesExpandKey(key) {
  var T = aesT(), rk = new Array(176), i, j, tmp, rcon = 1;
  for (i = 0; i < 16; i++) rk[i] = key[i];
  for (i = 16; i < 176; i += 4) {
    tmp = [rk[i - 4], rk[i - 3], rk[i - 2], rk[i - 1]];
    if (i % 16 === 0) {
      tmp = [tmp[1], tmp[2], tmp[3], tmp[0]];
      tmp[0] = T.sbox[tmp[0]] ^ rcon;
      tmp[1] = T.sbox[tmp[1]]; tmp[2] = T.sbox[tmp[2]]; tmp[3] = T.sbox[tmp[3]];
      rcon = T.mul(rcon, 2) || 0x1b;
    }
    for (j = 0; j < 4; j++) rk[i + j] = rk[i - 16 + j] ^ tmp[j];
  }
  return rk;
}
function aesDecryptBlock(block, rk) {
  var T = aesT(), s = block.slice(0), i, a0, a1, a2, a3, t, round;
  function addKey(r) { for (var k = 0; k < 16; k++) s[k] ^= rk[r * 16 + k]; }
  addKey(10);
  for (round = 9; round >= 1; round--) {
    // InvShiftRows
    t = s[13]; s[13] = s[9]; s[9] = s[5]; s[5] = s[1]; s[1] = t;
    t = s[2]; s[2] = s[10]; s[10] = t;
    t = s[6]; s[6] = s[14]; s[14] = t;
    t = s[3]; s[3] = s[7]; s[7] = s[11]; s[11] = s[15]; s[15] = t;
    // InvSubBytes
    for (i = 0; i < 16; i++) s[i] = T.rsbox[s[i]];
    addKey(round);
    // InvMixColumns
    var m = T.mul;
    for (i = 0; i < 4; i++) {
      a0 = s[i * 4]; a1 = s[i * 4 + 1]; a2 = s[i * 4 + 2]; a3 = s[i * 4 + 3];
      s[i * 4] = m(a0, 14) ^ m(a1, 11) ^ m(a2, 13) ^ m(a3, 9);
      s[i * 4 + 1] = m(a0, 9) ^ m(a1, 14) ^ m(a2, 11) ^ m(a3, 13);
      s[i * 4 + 2] = m(a0, 13) ^ m(a1, 9) ^ m(a2, 14) ^ m(a3, 11);
      s[i * 4 + 3] = m(a0, 11) ^ m(a1, 13) ^ m(a2, 9) ^ m(a3, 14);
    }
  }
  t = s[13]; s[13] = s[9]; s[9] = s[5]; s[5] = s[1]; s[1] = t;
  t = s[2]; s[2] = s[10]; s[10] = t;
  t = s[6]; s[6] = s[14]; s[14] = t;
  t = s[3]; s[3] = s[7]; s[7] = s[11]; s[11] = s[15]; s[15] = t;
  for (i = 0; i < 16; i++) s[i] = T.rsbox[s[i]];
  addKey(0);
  return s;
}
function strToBytes(s) {
  var out = [], i, c;
  for (i = 0; i < s.length; i++) {
    c = s.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | c >> 6, 0x80 | c & 0x3f);
    else out.push(0xe0 | c >> 12, 0x80 | c >> 6 & 0x3f, 0x80 | c & 0x3f);
  }
  return out;
}
function bytesToStr(bytes) {
  var out = '', i = 0, b, c;
  while (i < bytes.length) {
    b = bytes[i++];
    if (b < 0x80) out += String.fromCharCode(b);
    else if (b > 0xbf && b < 0xe0) out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i++] & 0x3f));
    else out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f));
  }
  return out;
}
function b64ToBytes(b64) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var map = {}, i, out = [], acc = 0, bits = 0, ch;
  for (i = 0; i < chars.length; i++) map[chars.charAt(i)] = i;
  b64 = String(b64 || '').replace(/[^A-Za-z0-9+/=]/g, '');
  for (i = 0; i < b64.length; i++) {
    ch = b64.charAt(i);
    if (ch === '=') break;
    acc = ((acc << 6) | map[ch]) & 0xffffff;
    bits += 6;
    if (bits >= 8) { bits -= 8; out.push((acc >> bits) & 0xff); }
  }
  return out;
}
function aes128CbcDecrypt(ctB64, keyStr, ivStr) {
  var rk = aesExpandKey(strToBytes(keyStr));
  var data = b64ToBytes(ctB64);
  var prev = strToBytes(ivStr), out = [], i, j, plain;
  if (data.length < 16) return '';
  data = data.slice(0, data.length - data.length % 16);
  for (i = 0; i < data.length; i += 16) {
    plain = aesDecryptBlock(data.slice(i, i + 16), rk);
    for (j = 0; j < 16; j++) out.push(plain[j] ^ prev[j]);
    prev = data.slice(i, i + 16);
  }
  var pad = out[out.length - 1];
  if (pad > 0 && pad <= 16) out = out.slice(0, out.length - pad);
  return bytesToStr(out);
}

var LumeSource = {
  id: 'av18_video',
  name: '18AV',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://18av.mm-cg.com'],

  async home() {
    H.useDomain();
    var page = await this.list({ categoryId: '/zh/chinese_list/all/1.html', page: 1 });
    if (!page.items.length) throw new Error('18AV：首页没认出条目（站点可能改版）');
    return [{ title: '中文字幕 最新', moreUrl: '/zh/chinese_list/all/1.html', items: page.items.slice(0, 24) }];
  },

  /// 分类从 /zh/ 的导航里现场读（`<分类>_random/all/index.html` → `<分类>_list/all/1.html`）；
  /// 抓不到就用内置清单。cg / cwp / novel / doujin 是写真与小说，不是视频，剔除。
  async categories() {
    H.useDomain();
    var fallback = [
      ['chinese', '中文字幕'], ['censored', '有碼AV'], ['uncensored', '無碼AV'],
      ['reducing-mosaic', '無碼破解'], ['amateurjav', '素人AV'], ['animation', 'H動畫'],
      ['dt', '國產自拍']
    ];
    var rows = [], seen = {};
    try {
      var html = await H.get('/zh/');
      var re = /<a[^>]+href=['"](?:https?:)?\/\/(?:www\.)?18av\.mm-cg\.com\/zh\/([A-Za-z-]+)_random\/all\/index\.html['"][^>]*>([\s\S]{0,80}?)<\/a>/gi, m;
      while ((m = re.exec(html)) !== null) {
        var slug = m[1];
        var title = H.clean(m[2]);
        if (!title || seen[slug]) continue;
        if (/^(cg|cwp|novel|doujin)$/i.test(slug)) continue;
        seen[slug] = 1;
        rows.push({ id: '/zh/' + slug + '_list/all/1.html', title: title });
      }
    } catch (error) {
      console.warn('[18av] 分类导航抓取失败：' + error);
    }
    if (!rows.length) {
      for (var i = 0; i < fallback.length; i++) {
        rows.push({ id: '/zh/' + fallback[i][0] + '_list/all/1.html', title: fallback[i][1] });
      }
    }
    return rows;
  },

  async list(argument) {
    H.useDomain();
    var args = argument || {};
    var page = Math.max(1, Number(args.page) || 1);
    var keyword = H.clean(args.keyword || '').trim();
    var category = String(args.categoryId == null ? '' : args.categoryId).trim() || '/zh/chinese_list/all/1.html';
    var path;
    if (keyword) {
      path = '/zh/fc_search/all/' + encodeURIComponent(keyword) + '/' + page + '.html';
    } else if (/^https?:\/\//i.test(category)) {
      path = category;
    } else {
      path = category.charAt(0) === '/' ? category : '/' + category;
      path = path.replace(/\/(\d+)\.html$/i, '/' + page + '.html');
      if (!/\/(\d+)\.html$/i.test(path)) path = path.replace(/\/+$/, '') + '/' + page + '.html';
    }
    var html = await H.get(path);
    var items = this.__items(html);
    if (!items.length) console.warn('[18av] 列表没解析出条目：' + path);
    var hasMore = /<a[^>]+href=['"][^'"]*\/'?\s*\+?\s*['"]?>/.test(html) && /下一頁|Next/i.test(html);
    return { items: items, hasMore: hasMore };
  },

  __items: function (html) {
    var text = String(html), out = [], seen = {};
    var chunks = text.split("class='post video_9s'");
    if (chunks.length < 2) chunks = text.split('class="post video_9s"');
    for (var i = 1; i < chunks.length; i++) {
      var block = chunks[i].slice(0, 2200);
      var hit = /href=['"]((?:https?:)?\/\/(?:www\.)?18av\.mm-cg\.com)?(\/zh\/[A-Za-z0-9_-]+_content\/\d+\/[^'"]+\.html)['"]/i.exec(block);
      if (!hit) continue;
      var path = hit[2];
      if (seen[path]) continue;
      seen[path] = 1;
      var title = (/<h3[^>]*>[\s\S]{0,200}?<a[^>]*>([\s\S]{0,300}?)<\/a>/.exec(block) || [])[1] || '';
      var cover = (/<img[^>]+src=['"]([^'"]+)['"]/i.exec(block) || [])[1] || '';
      var date = (/<div class='meta'>([\s\S]{0,30}?)<\/div>/.exec(block) || [])[1] || '';
      out.push({
        id: H.base + path,
        title: H.clean(title) || H.clean(path.split('/').pop().replace(/\.html$/i, '')),
        cover: cover ? H.abs(cover) : null,
        coverHeaders: H.headers(),
        subtitle: H.clean(date)
      });
    }
    return out;
  },

  async detail(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var m = /(\/zh\/[A-Za-z0-9_-]+_content\/\d+\/[^"'?#]+\.html)/i.exec(id);
    if (!m) return null;
    var pageUrl = H.base + m[1];
    var html = await H.get(pageUrl);
    var title = (/<h1[^>]*>([\s\S]{0,400}?)<\/h1>/i.exec(html) || [])[1] || '';
    title = H.clean(title.replace(/<\/?b>/gi, ''));
    var ld = /<script[^>]+application\/ld\+json[^>]*>([\s\S]*?)<\/script>/i.exec(html);
    var obj = null;
    if (ld) { try { obj = JSON.parse(ld[1]); } catch (error) { obj = null; } }
    if (!title && obj) title = H.clean(obj.name || '');
    if (!title) {
      var t = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
      title = t ? H.clean(t[1]).replace(/\s*18AV.*$/i, '') : '';
    }
    var cover = (obj && obj.thumbnailUrl) || (/<div id="player-wrap"[\s\S]{0,400}?<img[^>]+src=['"]?([^'"\s>]+)/i.exec(html) || [])[1] || '';
    var desc = (obj && obj.description) || '';
    var keys = (obj && obj.keywords) || '';
    var date = (obj && obj.uploadDate) || '';
    return {
      id: pageUrl,
      title: title || '18AV',
      cover: cover ? H.abs(cover) : null,
      coverHeaders: H.headers(),
      subtitle: [date, H.clean(keys).slice(0, 80)].filter(Boolean).join(' · '),
      description: H.clean(desc)
    };
  },

  async chapters(argument) {
    if (!argument || !argument.id) return [];
    return [{ id: 'play', title: '正片' }];
  },

  async content(argument) {
    H.useDomain();
    var id = String(argument && argument.id ? argument.id : '').trim();
    var m = /(\/zh\/[A-Za-z0-9_-]+_content\/\d+\/[^"'?#]+\.html)/i.exec(id);
    if (!m) throw new Error('18AV：认不出视频地址（' + id + '）——id 应来自 list()');
    var pageUrl = H.base + m[1];
    var html = await H.get(pageUrl);

    var entries = this.__mvarr(html);
    if (!entries.length) {
      return { kind: 'webplayer', pageUrl: pageUrl, headers: H.headers(pageUrl) };
    }
    var secret = this.__secret(html);
    var best = entries[0];
    var enc = best.enc;
    var ct = '';
    try {
      ct = this.__decrypto(enc, secret);
    } catch (error) {
      console.warn('[18av] 编码串解码失败：' + error);
    }
    if (!ct) return { kind: 'webplayer', pageUrl: pageUrl, headers: H.headers(pageUrl) };
    var videoId = '';
    try {
      videoId = aes128CbcDecrypt(ct, secret.key, secret.iv);
    } catch (error) {
      console.warn('[18av] AES 解密失败：' + error);
    }
    if (!/^[\x21-\x7e]{8,}$/.test(videoId)) {
      return { kind: 'webplayer', pageUrl: pageUrl, headers: H.headers(pageUrl) };
    }

    var playerUrl = 'https://18av.mm-cg.com/js/player/play.php?numresolution=' + best.res + '&id=' + encodeURIComponent(videoId);
    var player = await H.get(playerUrl, pageUrl);
    var rows = [];
    var re = /\{src:\s*'([^']+)'\s*,\s*type:\s*'([^']*)'\s*,\s*size:\s*(\d+)\}/g, mm;
    while ((mm = re.exec(player)) !== null) {
      rows.push({ url: mm[1].replace(/\\\//g, '/'), type: mm[2], size: Number(mm[3]) || 0 });
    }
    if (!rows.length) {
      var re2 = /(https?:\/\/[^"'\s]+\.m3u8[^"'\s]*)/g;
      while ((mm = re2.exec(player)) !== null) rows.push({ url: mm[1], type: 'application/x-mpegURL', size: 0 });
    }
    if (!rows.length) {
      return { kind: 'webplayer', pageUrl: playerUrl, headers: H.headers(pageUrl) };
    }
    rows.sort(function (a, b) { return b.size - a.size; });
    return {
      kind: 'video',
      url: rows[0].url,
      headers: H.mediaHeaders(pageUrl, rows[0].url),
      qualities: rows.map(function (r) { return { label: (r.size ? r.size + 'p' : 'HLS'), url: r.url }; })
    };
  },

  /// 抠 `mvarr['<清晰度>_<服务器>']=[[elemId,'<ENC>',<iframe 头>,<前缀>,<后缀>]];`
  __mvarr: function (html) {
    var out = [];
    var re = /mvarr\['([^']+)'\]\s*=\s*\[\[([\s\S]{0,20000}?)\]\s*,\s*\]/g, m;
    while ((m = re.exec(html)) !== null) {
      var key = m[1];
      var tokens = [], q = /'((?:[^'\\]|\\.)*)'/g, t;
      while ((t = q.exec(m[2])) !== null) tokens.push(t[1].replace(/\\'/g, "'"));
      if (tokens.length < 2 || !tokens[1]) continue;
      // 前缀里带真正要传给 play.php 的清晰度：`…play.php?numresolution=1080&id=`；
      // 键名（'10_1' / '11_1'）只是服务器的档位序号，别拿它当 numresolution。
      var prefix = tokens[3] || '';
      var res = Number((/numresolution=(\d+)/.exec(prefix) || [])[1]) || Number(String(key).replace(/_.*$/, '')) || 0;
      out.push({ res: res, enc: tokens[1], prefix: prefix });
    }
    out.sort(function (a, b) { return b.res - a.res; });
    return out;
  },

  /// xor 掩码 / 进制 / 分隔符 / AES key+iv 全部从页面读（读不到用实测常量兜底）
  __secret: function (html) {
    function pick(re, fallback) {
      var m = re.exec(html);
      return m ? m[1] : fallback;
    }
    var xor = Number(pick(/hadeedg\d+\s*=\s*(\d+)/, '25'));
    var dbase = Number(pick(/hcdeedg\d+\s*=\s*0*(\d+)/, '2'));
    var key = pick(/var\s+argdeqweqweqwe\s*=\s*'([0-9a-fA-F]{16})'/, '') ||
              pick(/var\s+hdddedd252\s*=\s*'([0-9a-fA-F]{16})'/, '164aa8d2da404649');
    var iv = pick(/var\s+argdeqweqweqww\s*=\s*'([0-9a-fA-F]{16})'/, '') ||
             pick(/var\s+hdddedg252\s*=\s*'([0-9a-fA-F]{16})'/, '3d3a4ff9ece0fc5e');
    return { xor: isFinite(xor) ? xor : 25, base: dbase > 1 && dbase < 37 ? dbase : 2, key: key, iv: iv };
  },

  /// 站点 decrypto()：按 fromCharCode(base+97) 切串 → parseInt(tok, base) ^ xor → 字符（得到 base64）
  __decrypto: function (enc, secret) {
    var sep = String.fromCharCode(secret.base + 97);
    var parts = String(enc).split(sep);
    var out = '';
    for (var i = 0; i < parts.length; i++) {
      var v = parseInt(parts[i], secret.base);
      if (!isFinite(v)) continue;
      out += String.fromCharCode((v ^ secret.xor) & 0xff);
    }
    return out;
  }
};

if (typeof module !== 'undefined' && module.exports) module.exports = LumeSource;
