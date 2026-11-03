// LumeSource: {"id":"v1024_video","name":"1024Videos","version":"1.0.0","category":"video","mirrors":["https://1024videos.com"]}

// 站点：https://1024videos.com （2026-10-25 逐页实测；本机直连被封，走本机代理出口）
//
// 一、外壳与真实接口（上一轮卡在「main.js 里没有 api/m3u8 常量」，这轮挖到根了）
//   首页    GET / → 5.7KB Angular+Ionic 空壳（<app-root>），脚本是
//           /runtime.14a7d1f50be1f9ad.js、/polyfills.*.js、/main.d050a29b3d324f52.js（2.25MB，type=module）。
//   **接口不在 main.js**，真正的数据在懒加载 chunk 里：runtime.js 有 149 个 chunk 的映射表，
//   路由表（main 内联）指向：
//     path:"video/:id"     → chunk 8061.5529bd13c55ab776.js（DetailPageModule，里面就是 m3u8）
//     path:"videos/:type"  → chunk 7517…（IndexPageModule）
//     path:"videos"        → chunk 9651.dc9873545b9a0a25.js（HomePageModule，列表请求在这）
//     path:"search/:keyword" → chunk 3375…/3523…
//   没有 /assets/config*.json、没有 environment 文件（Angular 的 environment 已编译进 bundle），
//   `ng://` 只是源码映射命名，没有额外入口。
//
// 二、协议：全部 POST + AES 信封
//   所有数据接口都是同一个入口：
//     POST https://v2.cdn199.com/js
//     Content-Type: application/json, Origin/Referer: https://1024videos.com
//     body = {
//       "url": "/sevenVideos?page=1&type=hot",           // 要的“虚拟路径”
//       "deviceInfo": {"platform":"web","operatingSystem":"web",…},
//       "app": "1024videos.com", "version": "260901",     // 版本取自 main 里的 M.version
//       "theLink": "novaluenull", "uuid": "novalue",      // localStorage 缺省值原样带
//       "isStandalone": false
//     }
//   少了 deviceInfo/app/version 这些字段 → **403 {"blocked":true}**（实测）。
//   返回 {"r":"U2FsdGVkX1…"} 是 CryptoJS 的 OpenSSL 信封：
//     base64("Salted__" + salt(8) + AES-256-CBC(PKCS7))，口令就是字面量 **"xxx"**
//     （main 里 decrypt(l){ AES.decrypt(l.r,"xxx") }），EVP_BytesToKey(MD5) 派生 key/iv。
//   镜像（main 的 M.httpNames，全部实测 200 且能解出同样 24 条）：
//     v2.cdn199.com / v2.kekecdn.net / v2.luchu.org / v2.madou.ws /
//     v2.papapa.biz / v2.tianmtv.com / v2.xiaoshuo.info / v2.xiaoshuo.la
//
// 三、端点（实测都通，返回解出来的明文）
//   列表  url:"/sevenVideos?page=<N>&type=<type>"   → 24 条/页（数组）
//         type 实测可用：hot / recent / high / japan / taiwan / west / swag / vip / c0 / c1
//   搜索  url:"/searchSevenVideos" + {page, keywords} → 24 条（keywords:"user_<up主>" 是站内“同作者”用法）
//   详情  url:"/sevenVideos/<vId>" + {url_search:""} → 单个对象，带 m3u8s 数组
//   其它  /retrieveGlobal（视频总数）、/sevenVideoFavs?page=N（收藏）、/increaseCount（埋点）
//   条目字段：{_id, id, vId, title, title_en, keywords_gem, duration, durationStr,
//             createdTime, time, views, size, user, thumbnails/thumbNails, videoType}
//   详情额外：{m3u8s:["https://tm.helloye.com/<sig>,<end>/<_id>/index.m3u8"], m3u8Type:"m3u8", downloadable}
//
// 四、播放
//   m3u8 在 tm.helloye.com（签名段 + end=<过期秒>，每次请求详情都现签，所以要现取不要缓存）。
//   实测 GET 该地址 + Referer: https://1024videos.com/ → **200，#EXTM3U**（content-type 是
//   application/octet-stream，但正文就是 m3u8；不带 Referer 的请求没验证过，本源统一带）。
//   封面在 tp.helloye.com/<vId>.jpg。
//
// 五、沙箱里没有 atob、也没有现成 AES —— 所以本源自带 base64 / MD5 / AES-256-CBC 解密
//   （纯 ES5 实现，MD5 与 Node crypto 逐条对齐、解密与 Node decipheriv 逐字节对齐，均自测过）。
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var SITE = 'https://1024videos.com';
var API_HOSTS = [
  'https://v2.cdn199.com',
  'https://v2.kekecdn.net',
  'https://v2.luchu.org',
  'https://v2.madou.ws',
  'https://v2.papapa.biz',
  'https://v2.tianmtv.com',
  'https://v2.xiaoshuo.info',
  'https://v2.xiaoshuo.la'
];
var PASS = 'xxx';
var VERSION = '260901';
var APP = '1024videos.com';
var HOST_KEY = 'v1024-host.json';
var TYPES = [
  { id: 'hot', title: '最热' },
  { id: 'recent', title: '最新' },
  { id: 'high', title: '高清' },
  { id: 'japan', title: '日本' },
  { id: 'taiwan', title: '台湾' },
  { id: 'west', title: '欧美' },
  { id: 'swag', title: 'SWAG' },
  { id: 'c0', title: '国产传媒' },
  { id: 'c1', title: '国产自拍' },
  { id: 'vip', title: 'VIP' }
];
var DETAIL_CACHE = {};

// ------------------------------------------------------------------ base64
function b64decode(str) {
  var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var clean = String(str == null ? '' : str).replace(/[^A-Za-z0-9+/=]/g, '');
  var out = [];
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < clean.length; i++) {
    var ch = clean.charAt(i);
    if (ch === '=') break;
    var v = chars.indexOf(ch);
    if (v < 0) continue;
    buffer = ((buffer << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return Uint8Array.from ? Uint8Array.from(out) : new Uint8Array(out);
}

function toBytes(str) {
  var s = String(str == null ? '' : str);
  var out = new Uint8Array(s.length);
  for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
  return out;
}

// ------------------------------------------------------------------ MD5
var MD5_S = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];
var MD5_K = (function () {
  var t = new Array(64);
  for (var i = 0; i < 64; i++) t[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) | 0;
  return t;
})();

function rotl32(x, n) {
  return ((x << n) | (x >>> (32 - n))) >>> 0;
}

function md5(bytes) {
  var len = bytes.length;
  var total = (((len + 8) >> 6) + 1) * 64;
  var buf = new Uint8Array(total);
  buf.set(bytes);
  buf[len] = 0x80;
  var bitsLo = (len * 8) >>> 0;
  var bitsHi = Math.floor((len * 8) / 4294967296) >>> 0;
  buf[total - 8] = bitsLo & 0xff;
  buf[total - 7] = (bitsLo >>> 8) & 0xff;
  buf[total - 6] = (bitsLo >>> 16) & 0xff;
  buf[total - 5] = (bitsLo >>> 24) & 0xff;
  buf[total - 4] = bitsHi & 0xff;
  buf[total - 3] = (bitsHi >>> 8) & 0xff;
  buf[total - 2] = (bitsHi >>> 16) & 0xff;
  buf[total - 1] = (bitsHi >>> 24) & 0xff;

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;
  var M = new Array(16);

  for (var off = 0; off < total; off += 64) {
    for (var i = 0; i < 16; i++) {
      var p = off + i * 4;
      M[i] = (buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16) | (buf[p + 3] << 24)) >>> 0;
    }
    var A = a0, B = b0, C = c0, D = d0;
    for (var r = 0; r < 64; r++) {
      var F, g;
      if (r < 16) { F = (B & C) | (~B & D); g = r; }
      else if (r < 32) { F = (D & B) | (~D & C); g = (5 * r + 1) % 16; }
      else if (r < 48) { F = B ^ C ^ D; g = (3 * r + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * r) % 16; }
      F = (F + A + MD5_K[r] + M[g]) >>> 0;
      A = D;
      D = C;
      C = B;
      B = (B + rotl32(F, MD5_S[r])) >>> 0;
    }
    a0 = (a0 + A) >>> 0;
    b0 = (b0 + B) >>> 0;
    c0 = (c0 + C) >>> 0;
    d0 = (d0 + D) >>> 0;
  }

  var out = new Uint8Array(16);
  var words = [a0, b0, c0, d0];
  for (var k = 0; k < 4; k++) {
    out[k * 4] = words[k] & 0xff;
    out[k * 4 + 1] = (words[k] >>> 8) & 0xff;
    out[k * 4 + 2] = (words[k] >>> 16) & 0xff;
    out[k * 4 + 3] = (words[k] >>> 24) & 0xff;
  }
  return out;
}

// ------------------------------------------------------------------ AES-256-CBC（仅解密）
function rev8(x, n) {
  return ((x << n) | (x >>> (8 - n))) & 0xff;
}

var SBOX = new Uint8Array(256);
var INV_SBOX = new Uint8Array(256);
(function buildSbox() {
  var p = 1, q = 1;
  do {
    p = (p ^ ((p << 1) & 0xff) ^ (p & 0x80 ? 0x1b : 0)) & 0xff;
    q ^= q << 1;
    q ^= q << 2;
    q ^= q << 4;
    q &= 0xff;
    if (q & 0x80) q ^= 0x09;
    var x = (q ^ rev8(q, 1) ^ rev8(q, 2) ^ rev8(q, 3) ^ rev8(q, 4)) & 0xff;
    SBOX[p] = x ^ 0x63;
  } while (p !== 1);
  SBOX[0] = 0x63;
  for (var i = 0; i < 256; i++) INV_SBOX[SBOX[i]] = i;
})();

function xtime(b) {
  return ((b << 1) ^ (b & 0x80 ? 0x1b : 0)) & 0xff;
}

function gmul(a, b) {
  var p = 0;
  for (var i = 0; i < 8; i++) {
    if (b & 1) p ^= a;
    var hi = a & 0x80;
    a = (a << 1) & 0xff;
    if (hi) a ^= 0x1b;
    b >>= 1;
  }
  return p & 0xff;
}

function expandKey256(key) {
  var Nk = 8, Nr = 14;
  var w = new Uint8Array(16 * (Nr + 1));
  w.set(key);
  var rcon = 1;
  for (var i = Nk; i < 4 * (Nr + 1); i++) {
    var t0 = w[(i - 1) * 4], t1 = w[(i - 1) * 4 + 1], t2 = w[(i - 1) * 4 + 2], t3 = w[(i - 1) * 4 + 3];
    if (i % Nk === 0) {
      var tmp = t0;
      t0 = SBOX[t1] ^ rcon;
      t1 = SBOX[t2];
      t2 = SBOX[t3];
      t3 = SBOX[tmp];
      rcon = xtime(rcon);
    } else if (i % Nk === 4) {
      t0 = SBOX[t0];
      t1 = SBOX[t1];
      t2 = SBOX[t2];
      t3 = SBOX[t3];
    }
    w[i * 4] = w[(i - Nk) * 4] ^ t0;
    w[i * 4 + 1] = w[(i - Nk) * 4 + 1] ^ t1;
    w[i * 4 + 2] = w[(i - Nk) * 4 + 2] ^ t2;
    w[i * 4 + 3] = w[(i - Nk) * 4 + 3] ^ t3;
  }
  return w;
}

function invShiftRows(state) {
  for (var r = 1; r < 4; r++) {
    var a = state[r], b = state[r + 4], c = state[r + 8], d = state[r + 12];
    state[r + 4 * ((0 + r) % 4)] = a;
    state[r + 4 * ((1 + r) % 4)] = b;
    state[r + 4 * ((2 + r) % 4)] = c;
    state[r + 4 * ((3 + r) % 4)] = d;
  }
}

function invCipher(state, w) {
  var Nr = 14;
  var i, round;
  for (i = 0; i < 16; i++) state[i] ^= w[Nr * 16 + i];
  for (round = Nr - 1; round >= 1; round--) {
    invShiftRows(state);
    for (i = 0; i < 16; i++) state[i] = INV_SBOX[state[i]];
    for (i = 0; i < 16; i++) state[i] ^= w[round * 16 + i];
    for (var c = 0; c < 4; c++) {
      var a0 = state[4 * c], a1 = state[4 * c + 1], a2 = state[4 * c + 2], a3 = state[4 * c + 3];
      state[4 * c] = gmul(a0, 14) ^ gmul(a1, 11) ^ gmul(a2, 13) ^ gmul(a3, 9);
      state[4 * c + 1] = gmul(a0, 9) ^ gmul(a1, 14) ^ gmul(a2, 11) ^ gmul(a3, 13);
      state[4 * c + 2] = gmul(a0, 13) ^ gmul(a1, 9) ^ gmul(a2, 14) ^ gmul(a3, 11);
      state[4 * c + 3] = gmul(a0, 11) ^ gmul(a1, 13) ^ gmul(a2, 9) ^ gmul(a3, 14);
    }
  }
  invShiftRows(state);
  for (i = 0; i < 16; i++) state[i] = INV_SBOX[state[i]];
  for (i = 0; i < 16; i++) state[i] ^= w[i];
}

function aesCbcDecrypt(key, iv, data) {
  var w = expandKey256(key);
  var out = new Uint8Array(data.length);
  var prev = iv;
  for (var off = 0; off < data.length; off += 16) {
    var block = data.subarray(off, off + 16);
    var state = new Uint8Array(16);
    state.set(block);
    invCipher(state, w);
    for (var i = 0; i < 16; i++) out[off + i] = state[i] ^ prev[i];
    prev = block;
  }
  return out;
}

function evpDerive(passBytes, salt) {
  var derived = new Uint8Array(0);
  var block = new Uint8Array(0);
  while (derived.length < 48) {
    var input = new Uint8Array(block.length + passBytes.length + salt.length);
    input.set(block);
    input.set(passBytes, block.length);
    input.set(salt, block.length + passBytes.length);
    block = md5(input);
    var next = new Uint8Array(derived.length + block.length);
    next.set(derived);
    next.set(block, derived.length);
    derived = next;
  }
  return { key: derived.subarray(0, 32), iv: derived.subarray(32, 48) };
}

function utf8(bytes) {
  var out = '';
  var i = 0;
  while (i < bytes.length) {
    var b = bytes[i++];
    if (b < 0x80) out += String.fromCharCode(b);
    else if (b < 0xe0) out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i++] & 0x3f));
    else if (b < 0xf0) out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f));
    else {
      var cp = ((b & 0x07) << 18) | ((bytes[i++] & 0x3f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f);
      var v = cp - 0x10000;
      out += String.fromCharCode(0xd800 + (v >> 10), 0xdc00 + (v & 0x3ff));
    }
  }
  return out;
}

/// CryptoJS AES.decrypt(r, "xxx") 等价物
function decryptEnvelope(cipher, pass) {
  var raw = b64decode(cipher);
  if (raw.length < 17) throw new Error('1024Videos：密文太短');
  var salt = raw.subarray(8, 16);
  var keys = evpDerive(toBytes(pass || PASS), salt);
  var clear = aesCbcDecrypt(keys.key, keys.iv, raw.subarray(16));
  var end = clear.length;
  var pad = clear[end - 1];
  if (pad > 0 && pad <= 16) end -= pad;
  return utf8(clear.subarray(0, end));
}

// ------------------------------------------------------------------ 网络
function base() {
  var c = typeof LumeSource !== 'undefined' && LumeSource.config ? LumeSource.config : null;
  return String((c && c.domain) || SITE).replace(/\/+$/, '');
}

function headers() {
  return {
    'User-Agent': UA,
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/plain, */*',
    'Origin': SITE,
    'Referer': SITE + '/'
  };
}

async function host() {
  try {
    var saved = JSON.parse(String((await LumeSource.fs.readText(HOST_KEY)) || ''));
    if (saved && saved.host) return String(saved.host);
  } catch (error) {
    /* 没缓存 */
  }
  return API_HOSTS[0];
}

async function rememberHost(h) {
  try {
    await LumeSource.fs.writeText(HOST_KEY, JSON.stringify({ host: h, at: Date.now() }));
  } catch (error) {
    /* 缓存失败不影响 */
  }
}

function payload(urlPath, extra) {
  var body = {
    url: urlPath,
    deviceInfo: {
      model: '',
      platform: 'web',
      operatingSystem: 'web',
      osVersion: '',
      manufacturer: '',
      isVirtual: false,
      webViewVersion: ''
    },
    app: APP,
    version: VERSION,
    theLink: 'novaluenull',
    uuid: 'novalue',
    isStandalone: false
  };
  for (var key in extra || {}) body[key] = extra[key];
  return body;
}

/// POST <host>/js → 解 AES 信封 → 明文 JSON
async function api(urlPath, extra) {
  var order = await host();
  var hosts = [order].concat(API_HOSTS.filter(function (h) { return h !== order; }));
  var lastError = '';
  for (var i = 0; i < hosts.length; i++) {
    var res;
    try {
      res = await LumeSource.http.request({
        url: hosts[i] + '/js',
        method: 'POST',
        headers: headers(),
        body: JSON.stringify(payload(urlPath, extra))
      });
    } catch (error) {
      lastError = String(error && error.message ? error.message : error);
      continue;
    }
    var status = Number((res && res.status) || 0);
    var body = String((res && res.body) || '');
    if (status === 403 || status === 503) {
      lastError = 'HTTP ' + status + '（' + hosts[i] + '）' + (body.indexOf('blocked') >= 0 ? ' blocked' : '');
      continue;
    }
    if (status !== 200) {
      lastError = 'HTTP ' + status + '（' + hosts[i] + '）';
      continue;
    }
    var json;
    try {
      json = JSON.parse(body);
    } catch (error) {
      lastError = '返回不是 JSON：' + body.slice(0, 80);
      continue;
    }
    if (json && typeof json.r === 'string') {
      try {
        var plain = decryptEnvelope(json.r, PASS);
        await rememberHost(hosts[i]);
        return JSON.parse(plain);
      } catch (error) {
        lastError = '解密失败：' + String(error && error.message ? error.message : error);
        continue;
      }
    }
    if (json && (Array.isArray(json) || typeof json === 'object')) {
      await rememberHost(hosts[i]);
      return json;
    }
    lastError = '空响应';
  }
  throw new Error('1024Videos：接口全部失败（' + lastError + '）');
}

// ------------------------------------------------------------------ 条目
function vIdOf(id) {
  var text = String(id == null ? '' : id).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) {
    var parts = text.replace(/[?#].*$/, '').split('/').filter(Boolean);
    return parts.length ? parts[parts.length - 1] : '';
  }
  return text.replace(/^\/+/, '').split('/').pop();
}

function coverOf(video) {
  var list = video.thumbnails || video.thumbNails || [];
  if (Array.isArray(list) && list.length) return String(list[0]);
  return video.vId ? 'https://tp.helloye.com/' + video.vId + '.jpg' : null;
}

function toItem(video) {
  var bits = [];
  if (video.durationStr) bits.push(String(video.durationStr));
  if (Number(video.views)) bits.push(Number(video.views) + ' 次播放');
  if (video.user) bits.push(String(video.user));
  var vid = String(video.vId || video.id || '');
  return {
    id: base() + '/video/' + vid,
    title: String(video.title || video.title_en || vid),
    cover: coverOf(video),
    subtitle: bits.join(' · ')
  };
}

async function detailOf(id) {
  var vid = vIdOf(id);
  if (!vid) throw new Error('1024Videos：认不出视频 id（' + id + '）');
  var cached = DETAIL_CACHE[vid];
  if (cached && cached.at && Date.now() - cached.at < 5 * 60 * 1000) return cached.video;
  var data = await api('/sevenVideos/' + encodeURIComponent(vid), { url_search: '' });
  if (!data || typeof data !== 'object') throw new Error('1024Videos：详情为空（' + vid + '）');
  DETAIL_CACHE[vid] = { at: Date.now(), video: data };
  return data;
}

var LumeSource = {
  id: 'v1024_video',
  name: '1024Videos',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://1024videos.com'],

  async home() {
    var page = await this.list({ categoryId: 'hot', page: 1 });
    if (!page.items.length) throw new Error('1024Videos：首页没解析出条目');
    var boards = [{ title: '最热', moreUrl: base() + '/videos?page=1&type=hot', items: page.items.slice(0, 24) }];
    try {
      var recent = await this.list({ categoryId: 'recent', page: 1 });
      if (recent.items.length) {
        boards.push({ title: '最新', moreUrl: base() + '/videos?page=1&type=recent', items: recent.items.slice(0, 24) });
      }
    } catch (error) {
      console.warn('[1024videos] 最新榜抓取失败：' + error);
    }
    return boards;
  },

  async categories() {
    return TYPES.map(function (row) {
      return { id: row.id, title: row.title };
    });
  },

  async list(argument) {
    var args = argument || {};
    var page = Math.max(1, Number(args.page) || 1);
    var keyword = String(args.keyword == null ? '' : args.keyword).trim();
    var type = String(args.categoryId == null ? '' : args.categoryId).trim() || 'hot';
    var data;
    if (keyword) {
      data = await api('/searchSevenVideos', { page: page, keywords: keyword });
    } else {
      if (!/^[a-z0-9_]+$/i.test(type)) type = 'hot';
      data = await api('/sevenVideos?page=' + page + '&type=' + type);
    }
    var rows = Array.isArray(data) ? data : data && Array.isArray(data.list) ? data.list : [];
    var items = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (!row) continue;
      var item = toItem(row);
      if (!vIdOf(item.id)) continue;
      items.push(item);
    }
    if (!items.length) console.warn('[1024videos] 列表为空：page=' + page + ' type=' + type);
    return { items: items, hasMore: items.length >= 12 };
  },

  async detail(argument) {
    var id = String(argument && argument.id ? argument.id : '').trim();
    var video = await detailOf(id);
    var bits = [];
    if (video.durationStr) bits.push(String(video.durationStr));
    if (video.user) bits.push(String(video.user));
    if (Number(video.views)) bits.push(Number(video.views) + ' 次播放');
    if (video.size) bits.push(String(video.size));
    var desc = [];
    if (video.title_en) desc.push(String(video.title_en));
    if (video.keywords_gem) desc.push('标签：' + String(video.keywords_gem));
    if (video.tags) desc.push(String(video.tags));
    return {
      id: id,
      title: String(video.title || video.title_en || vIdOf(id)),
      cover: coverOf(video),
      subtitle: bits.join(' · '),
      description: desc.join('\n')
    };
  },

  /// 详情里的 m3u8s 是“线路”数组（一般 1 条），一条一集；content 按 chapterId 下标取
  async chapters(argument) {
    var id = String(argument && argument.id ? argument.id : '').trim();
    var video = await detailOf(id);
    var list = Array.isArray(video.m3u8s) ? video.m3u8s.filter(Boolean) : [];
    if (!list.length && video.m3u8) list = [String(video.m3u8)];
    if (!list.length) return [{ id: '0', title: '正片' }];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      out.push({ id: String(i), title: list.length === 1 ? '正片' : '线路 ' + (i + 1) });
    }
    return out;
  },

  async content(argument) {
    var id = String(argument && argument.id ? argument.id : '').trim();
    var chapterId = String(argument && argument.chapterId ? argument.chapterId : '').trim();
    var video = await detailOf(id);
    var list = Array.isArray(video.m3u8s) ? video.m3u8s.filter(Boolean) : [];
    if (!list.length && video.m3u8) list = [String(video.m3u8)];
    if (!list.length) {
      return { kind: 'webplayer', pageUrl: base() + '/video/' + encodeURIComponent(vIdOf(id)), headers: headers() };
    }
    var index = Number(chapterId);
    if (!isFinite(index) || index < 0 || index >= list.length) index = 0;
    return {
      kind: 'video',
      url: list[index],
      headers: {
        'Referer': base() + '/',
        'User-Agent': UA
      },
      qualities: list.map(function (u, i) {
        return { label: list.length === 1 ? 'HLS' : '线路 ' + (i + 1), url: u };
      })
    };
  }
};

if (typeof module !== 'undefined' && module.exports) module.exports = LumeSource;
