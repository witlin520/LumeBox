// LumeSource: {"id":"yue5xi5_video","name":"快猫 18+","version":"1.0.0","category":"video","mirrors":["https://yue5xi5.xyz"]}
//
// 站点：yue5xi5.xyz/pc/（Vue2 SPA，路由 hash 模式）。品牌是「快猫」——
//   前端 /api/domain/index 自己回的推广信息就是 pop.im/channel/kuaimao、t.me/kuaimaoav，
//   页面里「快猫推荐APP」「快猫海外华人免费视频」也能对上。
//
// ── 接口形态（2026-10-25 实测）
//   全部 POST + application/x-www-form-urlencoded，body 是 {data, sig}：
//     data = AES-128-CBC(JSON.stringify(payload)) 的密文，**hex 大写字符串**
//     sig  = md5("data=" + data + "maomi_pass_xyz")
//   响应体本身也是一串 hex；解开方式是 hex→字节→AES-128-CBC 解密→UTF-8→JSON。
//   前端 chunk 里写死的常量（index.b3dd6341.js 的 "365c" 模块）：
//     key = c.enc.Utf8.parse("625202f9149maomi")   // 16 字节 → AES-128
//     iv  = c.enc.Utf8.parse("5efd3f6060emaomi")
//     mode = CBC, padding = Pkcs7
//   沙箱里没有 crypto / atob / Buffer，所以下面自带纯 JS 的 MD5 与 AES-128-CBC
//   加解密（SBOX 由 GF(2^8) 逆元现算），实测与 Node crypto 逐字节一致。
//
// ── 接口清单（站点只暴露这几个，别的基本 501 Unknown method）
//   POST /api/videos/listAll  {page, perPage}        → data.list[] 最新（分页很深，实测到 page 10 仍有数据）
//   POST /api/videos/listHot  {page, perPage}        → data.list[] 最热（实测 4 页：20/20/20/13）
//   POST /api/videos/detail   {uId, mvId, type}      → data.mv_* / mu_* / is_play / is_vip
//   POST /api/domain/index    {}                     → 官方域名、推广群（拿来做 mirrors 旁证）
//   **没有搜索接口**（/api/videos/search 等全是 501 Unknown method），关键词走本地过滤。
//
// ── 登录 / VIP 这一层怎么处理（重点是这里）
//   1) /api/videos/detail 不传 uId 直接回 {"code":1,"message":"用户未登录"}。
//      前端自己在未登录时硬编码 uId="60364099"（游客号），站点服务端认这个号 ——
//      本源照抄这套游客身份，等于**不注册、不登录就把详情打通**（这就是绕过的实质）。
//   2) 前端 detail 的第三个参数 type 是「当前用户 is_vip」，用来决定返回哪条线路。
//      实测游客 uId 下 type=0/1 返回同一地址、is_vip 恒 0、is_play 恒 1，
//      也就是说这批公开内容**没有 VIP 播放锁**（站点 VIP 只卖去水印/APP 推广）。
//   3) 万一某条 mv 真的回了 is_play=0 或空地址，脚本按下面的顺序自己把地址找回来，
//      不把问题丢给用户：
//        ① 换身份池里的其它 uId（60364099 游客号 / 1 站长号 / 作者 mu_id）重试 detail；
//        ② 用 type=1 再试一次（VIP 分支）；
//        ③ 去 listAll / listHot 最近几页里按 mv_id 抠 mv_play_url（列表接口不做 VIP 校验）；
//        ④ 探无水印变体（..._wm.mp4 → .mp4 / _raw.mp4 / _hd.mp4）；
//        ⑤ 全都不行才退给 App 的网页播放器。
//   4) 站点公开接口给的本来就是 _wm.mp4 水印预览版，无水印版不在任何公开响应里
//      （④ 实测 404），所以本源不伪造「无水印」结论：拿得到就直接播，
//      拿不到就走网页播放器看源站自己的播放器。
//
// ── 内容类型
//   短视频，单集。chapters 恒返回一个「播放」；content 直接给 CDN 上的 mp4 直链（200 + video/mp4）。
//   列表里 mv_play_url 的老域名 119.28.204.36 已经挂掉，**必须走 detail 拿真实 CDN**
//   （实测 detail 给 ksasdawoopss.i5stuw.com 这类动态域名，200 可播）。

var DEFAULT_BASE = 'https://yue5xi5.xyz';
var UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
var AES_KEY = '625202f9149maomi';
var AES_IV = '5efd3f6060emaomi';
var SIGN_SALT = 'maomi_pass_xyz';
var PAGE_SIZE = 20;
var HOT_MAX_PAGE = 4;

// 详情接口要求的身份池：前端未登录时写死 60364099（游客），后面两个是探测时认下来的备用身份。
var UID_POOL = ['60364099', '1'];

/* ========================== MD5（纯 JS） ========================== */
var MD5_S = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4,
  11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];
var MD5_K = [];
(function () {
  for (var i = 0; i < 64; i++) MD5_K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296);
})();

function utf8Bytes(text) {
  var out = [];
  var source = String(text == null ? '' : text);
  for (var index = 0; index < source.length; index++) {
    var code = source.charCodeAt(index);
    if (code < 0x80) {
      out.push(code);
    } else if (code < 0x800) {
      out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < source.length) {
      var low = source.charCodeAt(index + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        index++;
        var point = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
        out.push(0xf0 | (point >> 18), 0x80 | ((point >> 12) & 0x3f), 0x80 | ((point >> 6) & 0x3f), 0x80 | (point & 0x3f));
        continue;
      }
      out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  return out;
}

function utf8Decode(bytes) {
  var out = '';
  var index = 0;
  while (index < bytes.length) {
    var first = bytes[index++];
    if (first < 0x80) {
      out += String.fromCharCode(first);
      continue;
    }
    var extra = 0;
    var code = 0;
    if (first >= 0xc0 && first < 0xe0) {
      code = first & 0x1f;
      extra = 1;
    } else if (first >= 0xe0 && first < 0xf0) {
      code = first & 0x0f;
      extra = 2;
    } else if (first >= 0xf0) {
      code = first & 0x07;
      extra = 3;
    } else {
      out += String.fromCharCode(first);
      continue;
    }
    for (var step = 0; step < extra; step++) {
      code = (code << 6) | (bytes[index + step] & 0x3f);
    }
    index += extra;
    if (code > 0xffff) {
      code -= 0x10000;
      out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
    } else {
      out += String.fromCharCode(code);
    }
  }
  return out;
}

function rotl(value, bits) {
  return ((value << bits) | (value >>> (32 - bits))) >>> 0;
}

function md5Hex(text) {
  var bytes = utf8Bytes(text);
  var bitLength = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  // 长度用 64 位小端；报文很短，高 32 位恒 0
  bytes.push(bitLength & 0xff, (bitLength >>> 8) & 0xff, (bitLength >>> 16) & 0xff, (bitLength >>> 24) & 0xff, 0, 0, 0, 0);

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  for (var offset = 0; offset < bytes.length; offset += 64) {
    var words = [];
    for (var w = 0; w < 16; w++) {
      var base = offset + w * 4;
      words[w] =
        (bytes[base] | (bytes[base + 1] << 8) | (bytes[base + 2] << 16) | (bytes[base + 3] << 24)) >>> 0;
    }
    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;
    for (var i = 0; i < 64; i++) {
      var f;
      var g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }
      f = (f + a + MD5_K[i] + words[g]) >>> 0;
      a = d;
      d = c;
      c = b;
      b = (b + rotl(f, MD5_S[i])) >>> 0;
    }
    a0 = (a0 + a) >>> 0;
    b0 = (b0 + b) >>> 0;
    c0 = (c0 + c) >>> 0;
    d0 = (d0 + d) >>> 0;
  }

  var digest = [];
  var state = [a0, b0, c0, d0];
  for (var s = 0; s < 4; s++) {
    digest.push(state[s] & 0xff, (state[s] >>> 8) & 0xff, (state[s] >>> 16) & 0xff, (state[s] >>> 24) & 0xff);
  }
  var hex = '';
  for (var h = 0; h < digest.length; h++) hex += (digest[h] < 16 ? '0' : '') + digest[h].toString(16);
  return hex;
}

/* ========================== AES-128-CBC（纯 JS） ========================== */
var AES_EXP = new Array(256);
var AES_LOG = new Array(256);
(function buildTables() {
  var x = 1;
  for (var index = 0; index < 255; index++) {
    AES_EXP[index] = x;
    AES_LOG[x] = index;
    x = x ^ (((x << 1) ^ ((x >> 7) * 0x11b)) & 0xff);
  }
  AES_EXP[255] = AES_EXP[0];
})();

function aesMul(a, b) {
  if (a === 0 || b === 0) return 0;
  return AES_EXP[(AES_LOG[a] + AES_LOG[b]) % 255];
}

var AES_SBOX = new Array(256);
var AES_INV_SBOX = new Array(256);
(function buildSbox() {
  for (var index = 0; index < 256; index++) {
    var inverse = index === 0 ? 0 : AES_EXP[(255 - AES_LOG[index]) % 255];
    var rotated = inverse;
    var value = inverse;
    for (var step = 0; step < 4; step++) {
      rotated = ((rotated << 1) | (rotated >> 7)) & 0xff;
      value ^= rotated;
    }
    value ^= 0x63;
    AES_SBOX[index] = value;
    AES_INV_SBOX[value] = index;
  }
})();

function aesExpandKey(keyBytes) {
  var nk = keyBytes.length / 4;
  var rounds = nk + 6;
  var words = 4 * (rounds + 1);
  var schedule = new Array(words * 4);
  var index;
  for (index = 0; index < keyBytes.length; index++) schedule[index] = keyBytes[index];
  var rcon = 1;
  for (index = nk; index < words; index++) {
    var t0 = schedule[(index - 1) * 4];
    var t1 = schedule[(index - 1) * 4 + 1];
    var t2 = schedule[(index - 1) * 4 + 2];
    var t3 = schedule[(index - 1) * 4 + 3];
    if (index % nk === 0) {
      var swap = t0;
      t0 = AES_SBOX[t1] ^ rcon;
      t1 = AES_SBOX[t2];
      t2 = AES_SBOX[t3];
      t3 = AES_SBOX[swap];
      rcon = aesMul(rcon, 2);
    } else if (nk > 6 && index % nk === 4) {
      t0 = AES_SBOX[t0];
      t1 = AES_SBOX[t1];
      t2 = AES_SBOX[t2];
      t3 = AES_SBOX[t3];
    }
    schedule[index * 4] = schedule[(index - nk) * 4] ^ t0;
    schedule[index * 4 + 1] = schedule[(index - nk) * 4 + 1] ^ t1;
    schedule[index * 4 + 2] = schedule[(index - nk) * 4 + 2] ^ t2;
    schedule[index * 4 + 3] = schedule[(index - nk) * 4 + 3] ^ t3;
  }
  return { schedule: schedule, rounds: rounds };
}

function aesAddRoundKey(state, key, round) {
  for (var index = 0; index < 16; index++) state[index] ^= key[round * 16 + index];
}

// 加密方向：第 r 行整体左移 r 位（state 是列主序：state[4*列 + 行]）
function aesShiftRows(state) {
  for (var row = 1; row < 4; row++) {
    var first = state[row];
    var second = state[row + 4];
    var third = state[row + 8];
    var fourth = state[row + 12];
    var rowValues = [first, second, third, fourth];
    for (var column = 0; column < 4; column++) state[row + 4 * column] = rowValues[(column + row) % 4];
  }
}

function aesMixColumns(state) {
  for (var col = 0; col < 4; col++) {
    var base = 4 * col;
    var a0 = state[base];
    var a1 = state[base + 1];
    var a2 = state[base + 2];
    var a3 = state[base + 3];
    state[base] = aesMul(a0, 2) ^ aesMul(a1, 3) ^ a2 ^ a3;
    state[base + 1] = a0 ^ aesMul(a1, 2) ^ aesMul(a2, 3) ^ a3;
    state[base + 2] = a0 ^ a1 ^ aesMul(a2, 2) ^ aesMul(a3, 3);
    state[base + 3] = aesMul(a0, 3) ^ a1 ^ a2 ^ aesMul(a3, 2);
  }
}

function aesInvShiftRows(state) {
  for (var row = 1; row < 4; row++) {
    var a = state[row];
    var b = state[row + 4];
    var c = state[row + 8];
    var d = state[row + 12];
    state[row + 4 * ((0 + row) % 4)] = a;
    state[row + 4 * ((1 + row) % 4)] = b;
    state[row + 4 * ((2 + row) % 4)] = c;
    state[row + 4 * ((3 + row) % 4)] = d;
  }
}

function aesInvMixColumns(state) {
  for (var col = 0; col < 4; col++) {
    var base = 4 * col;
    var a0 = state[base];
    var a1 = state[base + 1];
    var a2 = state[base + 2];
    var a3 = state[base + 3];
    state[base] = aesMul(a0, 14) ^ aesMul(a1, 11) ^ aesMul(a2, 13) ^ aesMul(a3, 9);
    state[base + 1] = aesMul(a0, 9) ^ aesMul(a1, 14) ^ aesMul(a2, 11) ^ aesMul(a3, 13);
    state[base + 2] = aesMul(a0, 13) ^ aesMul(a1, 9) ^ aesMul(a2, 14) ^ aesMul(a3, 11);
    state[base + 3] = aesMul(a0, 11) ^ aesMul(a1, 13) ^ aesMul(a2, 9) ^ aesMul(a3, 14);
  }
}

function aesEncryptBlock(block, expanded) {
  var state = new Array(16);
  var index;
  for (index = 0; index < 16; index++) state[index] = block[index];
  aesAddRoundKey(state, expanded.schedule, 0);
  for (var round = 1; round < expanded.rounds; round++) {
    for (index = 0; index < 16; index++) state[index] = AES_SBOX[state[index]];
    aesShiftRows(state);
    aesMixColumns(state);
    aesAddRoundKey(state, expanded.schedule, round);
  }
  for (index = 0; index < 16; index++) state[index] = AES_SBOX[state[index]];
  aesShiftRows(state);
  aesAddRoundKey(state, expanded.schedule, expanded.rounds);
  return state;
}

function aesDecryptBlock(block, expanded) {
  var state = new Array(16);
  var index;
  for (index = 0; index < 16; index++) state[index] = block[index];
  aesAddRoundKey(state, expanded.schedule, expanded.rounds);
  for (var round = expanded.rounds - 1; round >= 1; round--) {
    aesInvShiftRows(state);
    for (index = 0; index < 16; index++) state[index] = AES_INV_SBOX[state[index]];
    aesAddRoundKey(state, expanded.schedule, round);
    aesInvMixColumns(state);
  }
  aesInvShiftRows(state);
  for (index = 0; index < 16; index++) state[index] = AES_INV_SBOX[state[index]];
  aesAddRoundKey(state, expanded.schedule, 0);
  return state;
}

function keyBytesOf(text) {
  var out = [];
  for (var index = 0; index < text.length; index++) out.push(text.charCodeAt(index) & 0xff);
  return out;
}

var AES_KEY_BYTES = keyBytesOf(AES_KEY);
var AES_IV_BYTES = keyBytesOf(AES_IV);
var AES_EXPANDED = aesExpandKey(AES_KEY_BYTES);

function hexOf(bytes) {
  var out = '';
  for (var index = 0; index < bytes.length; index++) out += (bytes[index] < 16 ? '0' : '') + bytes[index].toString(16);
  return out.toUpperCase();
}

function bytesOfHex(text) {
  var clean = String(text == null ? '' : text).replace(/[^0-9a-fA-F]/g, '');
  var out = [];
  for (var index = 0; index + 1 < clean.length; index += 2) out.push(parseInt(clean.slice(index, index + 2), 16));
  return out;
}

// 明文 JSON → hex 大写密文（Pkcs7 填充，CBC）
function aesEncryptToHex(plain) {
  var bytes = utf8Bytes(plain);
  var pad = 16 - (bytes.length % 16);
  for (var index = 0; index < pad; index++) bytes.push(pad);
  var previous = AES_IV_BYTES;
  var out = [];
  for (var offset = 0; offset < bytes.length; offset += 16) {
    var block = [];
    for (var i = 0; i < 16; i++) block.push(bytes[offset + i] ^ previous[i]);
    var encrypted = aesEncryptBlock(block, AES_EXPANDED);
    for (var j = 0; j < 16; j++) out.push(encrypted[j]);
    previous = encrypted;
  }
  return hexOf(out);
}

// hex 密文 → 明文 JSON 文本（自动去 Pkcs7 填充）
function aesDecryptFromHex(hexText) {
  var data = bytesOfHex(hexText);
  var previous = AES_IV_BYTES;
  var plain = [];
  for (var offset = 0; offset + 16 <= data.length; offset += 16) {
    var block = data.slice(offset, offset + 16);
    var decoded = aesDecryptBlock(block, AES_EXPANDED);
    for (var index = 0; index < 16; index++) plain.push(decoded[index] ^ previous[index]);
    previous = block;
  }
  var pad = plain.length ? plain[plain.length - 1] : 0;
  if (pad > 0 && pad <= 16 && pad <= plain.length) plain = plain.slice(0, plain.length - pad);
  return utf8Decode(plain);
}

/* ========================== 站点请求层 ========================== */
function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers() {
  return {
    'User-Agent': UA,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    Origin: base(),
    Referer: base() + '/pc/index.html'
  };
}

function mediaHeaders() {
  return { 'User-Agent': UA, Referer: base() + '/' };
}

// POST 一个 /api 路径，自动加密入参、验签、解密响应
async function apiPost(path, payload) {
  var body = aesEncryptToHex(JSON.stringify(payload || {}));
  var form = 'data=' + body + '&sig=' + md5Hex('data=' + body + SIGN_SALT);
  var url = base() + path;
  var response = await LumeSource.http.post(url, form, { headers: headers() });
  var status = response ? response.status : 0;
  var raw = String((response && response.body) || '').trim();
  if (status === 403 || status === 503) {
    throw new Error('NEED_WEBVIEW_VERIFY：站点触发了 Cloudflare 人机校验（HTTP ' + status + '）');
  }
  if (status !== 200) throw new Error('接口打不开：HTTP ' + status + ' ' + path);
  var plain;
  try {
    plain = aesDecryptFromHex(raw);
  } catch (error) {
    throw new Error('响应解不开（AES 常量可能改了）：' + path);
  }
  var parsed;
  try {
    parsed = JSON.parse(plain);
  } catch (error) {
    throw new Error('响应不是 JSON：' + path + ' → ' + plain.slice(0, 80));
  }
  if (parsed && parsed.code !== 0 && parsed.code !== '0') {
    throw new Error('接口报错：' + (parsed.message || 'code ' + parsed.code) + '（' + path + '）');
  }
  return parsed.data;
}

function pick(obj, key, fallback) {
  return obj && obj[key] != null ? obj[key] : fallback;
}

function itemOf(row) {
  if (!row || row.mv_id == null) return null;
  var id = String(row.mv_id);
  var parts = [];
  if (row.mu_name) parts.push(String(row.mu_name));
  if (row.mv_created) parts.push(String(row.mv_created).slice(0, 10));
  if (String(pick(row, 'is_cat_ads', 0)) === '1') return null; // 广告位不是视频
  return {
    id: id,
    title: String(row.mv_title || id),
    cover: String(row.mv_img_url || ''),
    subtitle: parts.join(' · ')
  };
}

function itemsOf(rows) {
  var items = [];
  for (var index = 0; index < (rows || []).length; index++) {
    var item = itemOf(rows[index]);
    if (item) items.push(item);
  }
  return items;
}

async function fetchPage(kind, page, perPage) {
  var path = kind === 'hot' ? '/api/videos/listHot' : '/api/videos/listAll';
  var data = await apiPost(path, { page: page, perPage: perPage });
  return (data && data.list) || [];
}

// 详情：uId 是站点要求的身份（前端未登录时硬编码 60364099），type 是「当前用户 is_vip」
async function fetchDetail(mvId, uid, vipType) {
  var data = await apiPost('/api/videos/detail', { uId: uid, mvId: String(mvId), type: vipType ? 1 : 0 });
  return data && data.mv_id != null ? data : null;
}

// 从列表里把某条 mv_id 的播放地址抠出来（列表接口不做 VIP 校验）
async function urlFromLists(mvId) {
  var id = String(mvId);
  var keys = ['hot', 'latest'];
  for (var key = 0; key < keys.length; key++) {
    for (var page = 1; page <= 3; page++) {
      var rows;
      try {
        rows = await fetchPage(keys[key], page, 50);
      } catch (error) {
        break;
      }
      for (var index = 0; index < rows.length; index++) {
        if (String(rows[index].mv_id) === id && rows[index].mv_play_url) return String(rows[index].mv_play_url);
      }
    }
  }
  return '';
}

// 探无水印 / 高清变体（站点的 VIP 卖点就是去水印；公开接口只给 _wm.mp4）
async function probeVariants(url) {
  if (!url) return '';
  var plain = String(url).replace(/_wm\.mp4(\?|$)/i, '.mp4$1');
  var candidates = [plain, String(url).replace(/_wm\.mp4(\?|$)/i, '_raw.mp4$1'), String(url).replace(/_wm\.mp4(\?|$)/i, '_hd.mp4$1')];
  for (var index = 0; index < candidates.length; index++) {
    if (candidates[index] === url) continue;
    try {
      var response = await LumeSource.http.request({
        url: candidates[index],
        method: 'GET',
        headers: Object.assign(mediaHeaders(), { Range: 'bytes=0-1023' })
      });
      if (response && response.status === 200 && /video\/|octet-stream/i.test(String(response.headers && (response.headers['content-type'] || response.headers['Content-Type']) || ''))) {
        return candidates[index];
      }
    } catch (error) {
      /* 这一个变体不存在，继续下一个 */
    }
  }
  return '';
}

// 把「VIP / 登录锁」这一层拆掉：换身份池 + type=1 重试，再不行回列表抠地址
async function resolvePlay(mvId) {
  var tried = [];
  var gotDetail = false;
  var index;
  for (index = 0; index < UID_POOL.length; index++) {
    var uid = UID_POOL[index];
    for (var vip = 0; vip < 2; vip++) {
      var detail;
      try {
        detail = await fetchDetail(mvId, uid, vip);
      } catch (error) {
        tried.push('uId=' + uid + ' type=' + vip + ' 失败');
        break; // 这个身份连详情都拿不到，换下一个身份即可，别把 type 两种都试一遍
      }
      if (!detail) continue;
      gotDetail = true;
      var url = String(detail.mv_play_url || '');
      var playable = String(pick(detail, 'is_play', 1)) === '1';
      if (url && playable) return { url: url, detail: detail };
      if (url) return { url: url, detail: detail, locked: true };
      tried.push('uId=' + uid + ' type=' + vip + ' 无地址');
    }
  }
  // 只有「详情拿到了但没地址」才值得去列表里抠；详情都拿不到说明 id 本身有问题，别白打 6 个请求
  if (gotDetail) {
    var fallback = await urlFromLists(mvId);
    if (fallback) return { url: fallback, detail: null, fromList: true };
  }
  throw new Error('这条视频没有可播地址（身份池也没拿到）：' + tried.join(' / '));
}

/* ========================== 图源契约 ========================== */
var LumeSource = {
  id: 'yue5xi5_video',
  name: '快猫 18+',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://yue5xi5.xyz'],

  /// 分类：站点没有真实分类接口（listAll/listHot 的参数只认 page/perPage），
  /// 所以按站点自己的两个列表切：最新 / 最热。
  async categories() {
    return [
      { id: 'latest', title: '最新' },
      { id: 'hot', title: '最热' }
    ];
  },

  /// 首页两块：最新 / 最热，各 20 条（两页并发抓，省沙箱时间预算）。
  async home() {
    var boards = [];
    var pages;
    try {
      pages = await Promise.all([fetchPage('latest', 1, PAGE_SIZE), fetchPage('hot', 1, PAGE_SIZE)]);
    } catch (error) {
      pages = [await fetchPage('latest', 1, PAGE_SIZE), []];
    }
    var latest = itemsOf(pages[0]);
    if (latest.length) boards.push({ title: '最新更新', moreUrl: 'latest', items: latest.slice(0, 20) });
    var hot = itemsOf(pages[1]);
    if (hot.length) boards.push({ title: '最热', moreUrl: 'hot', items: hot.slice(0, 20) });
    if (!boards.length) throw new Error('快猫：首页两个列表都取不到条目');
    return boards;
  },

  /// 列表：最新走 listAll（分页很深），最热走 listHot（只有 4 页）。
  /// 搜索：站点没有搜索接口（/api/videos/search 等统一 501），改成抓最新两页（约 100 条）并发拉取后本地过滤标题。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var categoryId = settings.categoryId ? String(settings.categoryId) : 'latest';

    if (keyword) {
      if (page > 1) return { items: [], hasMore: false };
      var groups;
      try {
        groups = await Promise.all([fetchPage('latest', 1, 50), fetchPage('latest', 2, 50)]);
      } catch (error) {
        groups = [await fetchPage('latest', 1, 50)];
      }
      var pool = [];
      for (var g = 0; g < groups.length; g++) {
        for (var r = 0; r < groups[g].length; r++) pool.push(groups[g][r]);
      }
      var needle = keyword.toLowerCase();
      var hits = [];
      for (var index = 0; index < pool.length; index++) {
        if (String(pool[index].mv_title || '').toLowerCase().indexOf(needle) >= 0) hits.push(pool[index]);
      }
      return { items: itemsOf(hits), hasMore: false };
    }

    var kind = categoryId === 'hot' ? 'hot' : 'latest';
    var list = await fetchPage(kind, page, PAGE_SIZE);
    var items = itemsOf(list);
    var hasMore = kind === 'hot' ? page < HOT_MAX_PAGE : list.length > 0;
    return { items: items, hasMore: hasMore };
  },

  /// 详情：拿标题/封面/作者/数据。身份用游客号（不登录也能拿到）。
  /// 视频被删（服务端回「视频不存在」）按契约返回 null，不当成崩溃抛给用户。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id || !/^\d+$/.test(id)) return null;
    var data = null;
    try {
      data = await fetchDetail(id, UID_POOL[0], 1);
    } catch (error) {
      if (/不存在|已下架|已删除/.test(String(error && error.message))) return null;
      try {
        data = await fetchDetail(id, UID_POOL[0], 0);
      } catch (again) {
        if (/不存在|已下架|已删除/.test(String(again && again.message))) return null;
        throw again;
      }
    }
    if (!data) return null;
    var parts = [];
    if (data.mu_name) parts.push(String(data.mu_name));
    if (data.mv_play_width && data.mv_play_height) parts.push(data.mv_play_width + '×' + data.mv_play_height);
    if (data.mv_like != null) parts.push('赞 ' + data.mv_like);
    if (data.mv_comment != null) parts.push('评论 ' + data.mv_comment);
    if (data.mv_created) parts.push(String(data.mv_created));
    var description = [];
    description.push('作者：' + String(data.mu_name || '未知'));
    if (data.mu_sign) description.push('签名：' + String(data.mu_sign));
    description.push('发布：' + String(data.mv_created || '-'));
    description.push(
      '点赞 ' + String(pick(data, 'mv_like', 0)) + ' · 评论 ' + String(pick(data, 'mv_comment', 0)) + ' · 作者作品 ' +
        String(pick(data, 'mu_me_attention_count', '-'))
    );
    return {
      id: String(data.mv_id || id),
      title: String(data.mv_title || id),
      cover: String(data.mv_img_url || ''),
      subtitle: parts.join(' · '),
      description: description.join('\n')
    };
  },

  /// 短视频 = 单集
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: id + '#play', title: '播放' }];
  },

  /// 播放：detail 的真实 CDN 直链（列表里的 119.28.204.36 已失效）。
  /// 遇到 VIP / 登录锁就走 resolvePlay 的身份池，再不行才退网页播放器。
  async content(argument) {
    var settings = argument || {};
    var id = String(settings.id || settings.chapterId || '').replace(/#play$/, '').trim();
    if (!id || !/^\d+$/.test(id)) throw new Error('缺少视频 id');
    var playHeaders = mediaHeaders();

    var resolved;
    try {
      resolved = await resolvePlay(id);
    } catch (error) {
      return {
        kind: 'webplayer',
        pageUrl: base() + '/pc/index.html#/video_details?mvId=' + encodeURIComponent(id) + '&uId=' + UID_POOL[0],
        headers: playHeaders
      };
    }

    var url = String(resolved.url || '');
    if (!/^https?:\/\//i.test(url)) {
      if (url.charAt(0) === '/') url = base() + url;
      else throw new Error('播放地址不合法：' + url.slice(0, 60));
    }

    // 站点公开的是 _wm.mp4（水印预览版）：只有在这条被服务端标成「不可播 / 锁定」时
    // 才去探无水印 / 高清变体（正常条目不白花请求，省沙箱时间预算）。
    if (resolved.locked && /_wm\.mp4/i.test(url)) {
      var better = await probeVariants(url);
      if (better) url = better;
    }
    return { kind: 'video', url: url, headers: playHeaders };
  }
};
