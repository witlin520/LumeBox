// LumeSource: {"id":"mwx43zd_video","name":"快猫镜像站 18+","version":"1.0.0","category":"video","mirrors":["https://www.mwx43zd.xyz","https://4dxzevb.xyz"]}
//
// 站点：mwx43zd.xyz/pc/index.html（Vue2 + hash 路由 SPA）。品牌是「快猫」——
//   播放页水印文案写死「未经快猫授权 禁止转载」，/api/domain/address 里的官方 APK 叫
//   newkm_official（新快猫），封面/切片 CDN 主机一律 xkm* 前缀（xkmcoverimgs.*、
//   xkm.m3.arvfiss.top、xkmts.djycmc.com）。
//   **但后端与 sources/video/yue5xi5.js（同叫快猫）不是一套**：本源是 ThinkPHP 后端
//   （错误页就是 ThinkPHP 的「系统发生错误」），接口全在 /api/video/*，与快猫那套
//   maomi_pass_xyz / 625202f9149maomi 完全无关。
//
// ── 加解密（本源的钥匙，2026-10-25 从主 bundle 抄出来的）
//   主 bundle：https://www.mwx43zd.xyz/pc/static/js/index.d019db7b.js
//   加解密模块在 webpack 模块 id "c71e"（导出 a=解密、b=加密）：
//     const key = CryptoJS.enc.Utf8.parse("x;j/6olSp})&{ZJD")   // 16 字节 → AES-128
//     const iv  = CryptoJS.enc.Utf8.parse("znbV%$JN5olCpt<c")
//     mode = CBC, padding = Pkcs7
//     加密：AES.encrypt(Utf8.parse(明文), key, {iv, CBC, Pkcs7}).ciphertext.toString().toUpperCase()
//           → **hex 大写字符串**
//     解密：Hex.parse(响应体) → Base64.stringify → AES.decrypt(...) → Utf8 → JSON.parse
//           （等价于：把响应体的 hex 当密文做 AES-128-CBC 解密）
//   响应体本身就是一串 hex（不是 JSON），解出来才是 {code,msg,data}。
//   签名模块在同一 bundle 的 axios 请求拦截器里：
//     query = 按 key 升序拼 `k=v&k=v`（k/v 各自 encodeURIComponent）
//     signature = MD5(query + 'ohI}-bFpD*z8)W7~REusVa]U`YKQ=[C1&XZ."n5:dl<{?@J6NkO+f%c^"$tevxB>j2M_9;G#y3Tw|gL/HS,Pqr0!Ami(49Y_.~Tan#z{5ZLO,_E(7!vJ^HC5_{Xq5$z*').toUpperCase()
//   请求体（Content-Type: application/x-www-form-urlencoded; charset=UTF-8）：
//     data = AES(JSON.stringify({...params, signature}))       // hex 大写
//     device_version=pc & device_type=pc & version_code=1.0 & device=pc
//     api_token=<登录态，游客空串> & c_name=<渠道名>
//   c_name 来自 bundle 模块 "c36a"：按 window.location.host 取值 ——
//     xkmamix.com → new_km_qd_jc1001 / kmvips.com → new_km_qd_short_url / 其它 → developer-default
//   本站域名走 default 分支，实测 developer-default 被服务端接受。
//   沙箱里没有 crypto / atob / Buffer，所以下面自带纯 JS 的 MD5 与 AES-128-CBC
//   （借自 sources/video/yue5xi5.js，SBOX 由 GF(2^8) 逆元现算，与 Node crypto 逐字节一致，
//    本源的 key/iv/salt 已换成本站常量，实测服务端认）。
//
// ── 接口（全部 POST，且**必须**走上面的加密 form；JSON body 会直接拿到 ThinkPHP 报错页）
//   baseURL: https://api.ikz66r8.xyz/（写死在 bundle 里，与页面域名无关，换镜像不用换 API）
//   POST /api/video/index   {type, page, perPage}            → data.video_list[]
//   POST /api/video/info    {video_id}                       → data.video_info / banner_list / newestComment
//   POST /api/banner/index  {type}                           → data.bannerList[]（全是推广位，本源不用）
//   POST /api/domain/address {}                              → 官方域名 / 官方 APK / TG 群（镜子旁证）
//   POST /api/vip/package   {}                               → data.packageList[]（会员价目表）
//   POST /api/vip/gold      {}                               → 匿名 403「登陆失效」
//   POST /api/app/recommend {}                               → 推的第三方 App（广告，不用）
//   POST /api/video/exclusive {}                             → VIP 专享分组（内容详情一律 401）
//
//   `type` 的含义是从 /video_list 页的 chunk-78d4770e 里对齐出来的（原站的 5 个 tab，
//   tab 下标 0..4 依次绑定 Original/Hot/Select/Charge/Square 组件）：
//     11 = 原创视频（ids ~1.5e6，2024 年的老片子）
//      3 = 热门视频（按点赞倒序）
//      1 = 精选视频（**服务端忽略 page**，永远是同一批，所以本源 page>1 直接返回空）
//      9 = 付费视频（gold>0，需要金币解锁）
//      2 = 视频广场（同样是付费条目，排序与 9 略不同）
//   video_list 里 `type:2` 的条目**不是视频**，是推广位（只有 title/android/ios/cover），
//   原站点击是 window.open(广告位)，本源按条目类型过滤掉。
//   `perPage` 服务端认（实测 perPage=100 回 110 条 = 100 条视频 + 10 条广告），
//   默认 20 条。
//
// ── 匿名能拿到什么（实测，不外推）
//   免费条目：匿名（api_token 空串）即可拿 /api/video/info，返回完整 m3u8_url + normal_url。
//   付费条目：/api/video/info → {"code":401,"msg":"此视频需要付费！"}，连标题都不给。
//   VIP 专享条目：/api/video/info → {"code":401,"msg":"此视频为VIP专享！"}。
//   搜索：/api/video/index {type:4, keyword} → {"code":401,"msg":"VIP用户专享！"}。
//   这四道都是**服务端**锁（不是前端灰按钮），脚本侧没有可解的东西，本源如实呈现：
//   付费/VIP 条目照常出现在列表（带「付费 · N 金币」标注），点开 detail 给可读原因，
//   content 抛可读错误，不伪造地址、不假装能播。搜索退化成本地标题过滤（见下）。
//
// ── VIP 到底锁在哪：不是「只发试看片段」，是直接不发
//   免一条目的 m3u8 是**完整 VOD**：`#EXT-X-PLAYLIST-TYPE:VOD` + `#EXT-X-ENDLIST`，
//   段列表从头到尾（实测 6~18 段，累加 47s~162s，与条目实际时长一致），
//   没有截断标记、也没有「试看 N 秒」字段。
//   /api/video/info 里 play_time / size 这两个「标称时长/体积」字段对免费条目恒为 "0"，
//   所以「m3u8 段数 × 每段时长 vs 标称时长」这条判据在本站**没有可比的左侧**——
//   能拿到的证据只有「有没有 ENDLIST」和「段数是否连续」。结论按证据写：
//   免费线路 = 完整片（不是试看）；付费/VIP = 服务端 401，一个字节都不给。
//   VIP 卖的其实是**无水印/高清线路**：info 里的 vip_url / vip_m3u8_url 对匿名恒为空串，
//   免费线路的文件名统一是 *_wm.mp4（带水印）。本源在 info 出现 non-empty vip_* 时
//   会把它作为额外清晰度线路给播放器（只有真 VIP 的 api_token 才会出现）。
//
// ── 内容类型
//   短视频，单集。chapters 恒返回一个「播放」；content 给 HLS（AES-128 加密的 m3u8，
//   key URI 是公网可取的 .../encryption.key，播放器自己解）。
//   info.normal_url 那个 mp4 直链的 CDN 主机（osnlpls.nkmwrw.xyz）**当前 DNS 都解析不了**，
//   所以只在探测到 2xx 时才作为额外线路给出去，不把死链丢给用户。
//
// ── 过滤（涉未成年）
//   本站列表里没有「萝莉/未成年」这类分区或标签字段（video_list 根本不带 tag），
//   但标题是站长自填的自由文本。按任务要求，本源把标题命中未成年指涉词的条目直接丢弃
//   （见 BLOCK_WORDS），宁可少一条也不放进列表。
//
// ── mirrors 证据
//   https://4dxzevb.xyz：与主站**同一个 bundle**（/pc/index.html 引用 index.d019db7b.js，
//     两份 index.html 都是 5433 字节、title 都是 home）；并且 /api/domain/address 里
//     official_url 就是它，info 里的 h5_video_play_link 也是它。
//   https://kmvips.com、https://fhi3rxc.xyz：**不是**本源镜像 —— 它们引用的是
//     index.b3dd6341.js，也就是 sources/video/yue5xi5.js 那套快猫后端的前端，
//     接口完全不同（那是另一份源），所以没写进 mirrors。
//   xkmamix.com（c_name 模块里出现的第三个域名）当前已打不开，同样没写进去。

var DEFAULT_BASE = 'https://www.mwx43zd.xyz';
var API_BASE = 'https://api.ikz66r8.xyz';
var UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// bundle 模块 "c71e" / 请求拦截器里的硬常量
var AES_KEY = 'x;j/6olSp})&{ZJD';
var AES_IV = 'znbV%$JN5olCpt<c';
var SIGN_SALT =
  'ohI}-bFpD*z8)W7~REusVa]U`YKQ=[C1&XZ."n5:dl<{?@J6NkO+f%c^"$tevxB>j2M_9;G#y3Tw|gL/HS,Pqr0!Ami(49Y_.~Tan#z{5ZLO,_E(7!vJ^HC5_{Xq5$z*';
// bundle 模块 "c36a"：非 xkmamix.com / kmvips.com 的域名一律 developer-default
var CHANNEL_NAME = 'developer-default';

var PAGE_SIZE = 20;
var HOME_SIZE = 12;

// type → 原站 tab（见文件头注释）；顺序即分类顺序
var TAB_LIST = [
  { id: '1', title: '精选视频', type: 1, paged: false },
  { id: '3', title: '热门视频', type: 3, paged: true },
  { id: '11', title: '原创视频', type: 11, paged: true },
  { id: '9', title: '付费视频', type: 9, paged: true },
  { id: '2', title: '视频广场', type: 2, paged: true }
];

// 涉未成年指涉词：命中即丢弃（本站没有分区可以过滤，只能按标题拦）
var BLOCK_WORDS = ['萝莉', '蘿莉', 'loli', '幼女', '幼齿', '未成年', '小学生', '中学生', '初中生', '儿童', '正太'];

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
  bytes.push(bitLength & 0xff, (bitLength >>> 8) & 0xff, (bitLength >>> 16) & 0xff, (bitLength >>> 24) & 0xff, 0, 0, 0, 0);

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  for (var offset = 0; offset < bytes.length; offset += 64) {
    var words = [];
    for (var w = 0; w < 16; w++) {
      var base = offset + w * 4;
      words[w] = (bytes[base] | (bytes[base + 1] << 8) | (bytes[base + 2] << 16) | (bytes[base + 3] << 24)) >>> 0;
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

  var state = [a0, b0, c0, d0];
  var digest = [];
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

function aesShiftRows(state) {
  for (var row = 1; row < 4; row++) {
    var rowValues = [state[row], state[row + 4], state[row + 8], state[row + 12]];
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
function site() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers() {
  return {
    'User-Agent': UA,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    Origin: site(),
    Referer: site() + '/pc/index.html'
  };
}

function mediaHeaders() {
  return { 'User-Agent': UA, Referer: site() + '/' };
}

function sortedQuery(params) {
  var keys = Object.keys(params || {}).sort();
  var parts = [];
  for (var index = 0; index < keys.length; index++) {
    var key = keys[index];
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]));
  }
  return parts.join('&');
}

// 明文 params → 站点的加密 form body（signature 藏在密文里，明文只有 data 一个参数）
function buildForm(params, token) {
  var signature = md5Hex(sortedQuery(params) + SIGN_SALT).toUpperCase();
  var payload = {};
  var keys = Object.keys(params);
  for (var index = 0; index < keys.length; index++) payload[keys[index]] = params[keys[index]];
  payload.signature = signature;
  var data = aesEncryptToHex(JSON.stringify(payload));
  return (
    'data=' + data +
    '&device_version=pc&device_type=pc&version_code=1.0&device=pc' +
    '&api_token=' + encodeURIComponent(String(token || '')) +
    '&c_name=' + encodeURIComponent(CHANNEL_NAME)
  );
}

function tokenFromConfig() {
  // 游客态：api_token 空串（实测服务端接受）。用户在源设置里填了账号也不自动登录——
  // 本站登录要手机号 + 验证码（/api/user/getVerificationCode），脚本不替用户过验证码。
  var config = LumeSource.config || {};
  return config.token ? String(config.token) : '';
}

async function rawPost(path, params) {
  var form = buildForm(params || {}, tokenFromConfig());
  var response = await LumeSource.http.post(API_BASE + path, form, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '').trim();
  if (status === 403 || status === 503) {
    throw new Error('NEED_WEBVIEW_VERIFY：站点触发了 Cloudflare 人机校验（HTTP ' + status + '）');
  }
  if (!body) throw new Error('接口没有返回内容：' + path + '（HTTP ' + status + '）');
  if (body.charAt(0) === '<') {
    // ThinkPHP 的「系统发生错误」页 = 加密 form 没按格式发（或服务端换了签名规则）
    throw new Error('接口回了服务端错误页（HTTP ' + status + '）：' + path + '，多半是签名/加密常量变了');
  }
  return body;
}

// 一次抖动重试：代理与 CDN 偶发抖动，重试一次比把错误丢给用户好
async function apiPost(path, params) {
  var body;
  try {
    body = await rawPost(path, params);
  } catch (error) {
    if (/NEED_WEBVIEW_VERIFY/.test(String(error && error.message))) throw error;
    body = await rawPost(path, params);
  }
  var plain;
  try {
    plain = aesDecryptFromHex(body);
  } catch (error) {
    throw new Error('响应解不开（AES 常量可能改了）：' + path);
  }
  var parsed;
  try {
    parsed = JSON.parse(plain);
  } catch (error) {
    throw new Error('响应不是 JSON：' + path + ' → ' + plain.slice(0, 80));
  }
  return parsed;
}

// code 200 = 成功；其余把服务端原话抛出去（401 的文案就是「此视频需要付费！」这类）
async function apiData(path, params) {
  var parsed = await apiPost(path, params);
  var code = parsed && parsed.code;
  if (String(code) !== '200') {
    var message = String((parsed && (parsed.msg || parsed.message)) || 'code ' + code);
    var error = new Error(message + '（' + path + '）');
    error.apiCode = String(code);
    error.apiMessage = message;
    throw error;
  }
  return (parsed && parsed.data) || {};
}

/* ========================== 数据整形 ========================== */
function blocked(title) {
  var text = String(title == null ? '' : title).toLowerCase();
  for (var index = 0; index < BLOCK_WORDS.length; index++) {
    if (text.indexOf(String(BLOCK_WORDS[index]).toLowerCase()) >= 0) return true;
  }
  return false;
}

function isAd(row) {
  return String(row && row.type) === '2' || (row && row.android != null && row.mv_id == null && row.id != null);
}

function goldOf(row) {
  var gold = Number((row && row.gold) || 0);
  return isFinite(gold) && gold > 0 ? gold : 0;
}

function itemOf(row) {
  if (!row || row.id == null) return null;
  if (isAd(row)) return null; // 推广位不是视频（原站点击就是 window.open(广告)）
  var title = String(row.title || '');
  if (!title) return null;
  if (blocked(title)) return null; // 涉未成年标题：直接不进列表
  var parts = [];
  if (row.nickname) parts.push(String(row.nickname));
  if (row.praise_num != null) parts.push('赞 ' + String(row.praise_num));
  var gold = goldOf(row);
  if (gold > 0) parts.push('付费 · ' + gold + ' 金币');
  if (String(row.vip_exclusive || 0) === '1') parts.push('VIP 专享');
  return {
    id: String(row.id),
    title: title,
    cover: String(row.cover || ''),
    subtitle: parts.join(' · ')
  };
}

var ROW_CACHE = {};

function itemsOf(rows) {
  var items = [];
  for (var index = 0; index < (rows || []).length; index++) {
    var row = rows[index];
    var item = itemOf(row);
    if (item) {
      ROW_CACHE[item.id] = row;
      items.push(item);
    }
  }
  return items;
}

function tabOf(categoryId) {
  var id = String(categoryId == null ? '' : categoryId);
  for (var index = 0; index < TAB_LIST.length; index++) {
    if (TAB_LIST[index].id === id) return TAB_LIST[index];
  }
  // 也认 type 数字与 tab 中文名，方便「更多」回来时任意写法都能落到同一个列表
  for (var j = 0; j < TAB_LIST.length; j++) {
    if (String(TAB_LIST[j].type) === id || TAB_LIST[j].title === id) return TAB_LIST[j];
  }
  return TAB_LIST[0];
}

async function fetchList(type, page, perPage) {
  var data = await apiData('/api/video/index', { type: Number(type), page: Number(page), perPage: Number(perPage) });
  return (data && data.video_list) || [];
}

async function fetchInfo(id) {
  var data = await apiData('/api/video/info', { video_id: String(id) });
  var info = data && data.video_info;
  if (!info) {
    var error = new Error('这条视频没有详情（源站返回空）：' + id);
    error.apiCode = 'EMPTY';
    throw error;
  }
  return info;
}

function absolute(url) {
  var text = String(url || '');
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.charAt(0) === '/') return site() + text;
  return text;
}

// 试看判定：m3u8 是不是完整片（`#EXT-X-ENDLIST` + 段列表从头到尾）
async function inspectPlaylist(url) {
  try {
    var response = await LumeSource.http.request({ url: url, method: 'GET', headers: mediaHeaders() });
    if (!response || response.status !== 200) return null;
    var text = String(response.body || '');
    if (text.indexOf('#EXTM3U') < 0) return null;
    var segments = 0;
    var seconds = 0;
    var matched;
    var pattern = /#EXTINF:([\d.]+),/g;
    while ((matched = pattern.exec(text)) !== null) {
      segments++;
      seconds += Number(matched[1]) || 0;
    }
    return {
      segments: segments,
      seconds: Math.round(seconds),
      complete: text.indexOf('#EXT-X-ENDLIST') >= 0,
      encrypted: /#EXT-X-KEY:/.test(text)
    };
  } catch (error) {
    return null;
  }
}

/* ========================== 图源契约 ========================== */
var LumeSource = {
  id: 'mwx43zd_video',
  name: '快猫镜像站 18+',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.mwx43zd.xyz', 'https://4dxzevb.xyz'],

  /// 分类 = 原站 /video_list 的 5 个 tab（id 用 type 数字，点「更多」回来也对得上）
  async categories() {
    var list = [];
    for (var index = 0; index < TAB_LIST.length; index++) {
      list.push({ id: TAB_LIST[index].id, title: TAB_LIST[index].title });
    }
    return list;
  },

  /// 首页三块：热门 / 精选 / 原创（原站首页也是这几个列表，各取 7 条；这里 12 条）。
  /// 三块并发抓，免得撞穿沙箱单次预算。
  async home() {
    var boards = [];
    var results = await Promise.all([
      fetchList(3, 1, HOME_SIZE).catch(function () { return []; }),
      fetchList(1, 1, HOME_SIZE).catch(function () { return []; }),
      fetchList(11, 1, HOME_SIZE).catch(function () { return []; })
    ]);
    var titles = ['热门视频', '精选视频', '原创视频'];
    var ids = ['3', '1', '11'];
    for (var index = 0; index < results.length; index++) {
      var items = itemsOf(results[index]);
      if (items.length) boards.push({ title: titles[index], moreUrl: ids[index], items: items });
    }
    if (!boards.length) throw new Error('快猫镜像站：首页三个列表都取不到条目（检查网络或站点是否换了接口）');
    return boards;
  },

  /// 列表：categoryId 是 tab id（'1'/'3'/'11'/'9'/'2'），原样映射成 /api/video/index 的 type。
  /// 搜索：源站的搜索接口是 VIP 专享（type=4 回 401「VIP用户专享！」），
  /// 所以关键词走「拉三个免费列表（各 50 条）→ 本地按标题过滤」。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';

    if (keyword) {
      if (page > 1) return { items: [], hasMore: false };
      var pools = await Promise.all([
        fetchList(1, 1, 50).catch(function () { return []; }),
        fetchList(3, 1, 50).catch(function () { return []; }),
        fetchList(11, 1, 50).catch(function () { return []; })
      ]);
      var needle = keyword.toLowerCase();
      var hits = [];
      var seen = {};
      for (var p = 0; p < pools.length; p++) {
        for (var r = 0; r < pools[p].length; r++) {
          var row = pools[p][r];
          if (!row || row.id == null) continue;
          if (String(row.title || '').toLowerCase().indexOf(needle) < 0) continue;
          var key = String(row.id);
          if (seen[key]) continue;
          seen[key] = 1;
          hits.push(row);
        }
      }
      return { items: itemsOf(hits), hasMore: false };
    }

    var tab = tabOf(settings.categoryId);
    // 精选（type=1）服务端忽略 page：翻页给同一批，所以直接不给「还有更多」
    if (!tab.paged && page > 1) return { items: [], hasMore: false };
    var rows = await fetchList(tab.type, page, PAGE_SIZE);
    var items = itemsOf(rows);
    var hasMore = tab.paged ? items.length >= Math.min(PAGE_SIZE, 10) : false;
    return { items: items, hasMore: hasMore };
  },

  /// 详情：匿名即可拿免费条目。付费 / VIP 专享条目服务端 401，
  /// 这时用列表里已抓到的行拼一个「只读说明」，并明确写清锁在服务端，不编造播放地址。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id || !/^\d+$/.test(id)) return null;

    var info = null;
    try {
      info = await fetchInfo(id);
    } catch (error) {
      var message = String((error && error.message) || '');
      if (/不存在|已下架|已删除/.test(message)) return null;
      var locked = /付费|VIP|专享/.test(message);
      if (!locked) throw error;
      var cached = ROW_CACHE[id];
      if (!cached) {
        // 没缓存（用户直接从别处切进来）：把服务端原话给出去，比编一个标题诚实
        throw new Error('源站服务端锁定了这条内容：' + String((error && error.apiMessage) || message));
      }
      return {
        id: id,
        title: String(cached.title || id),
        cover: String(cached.cover || ''),
        subtitle: goldOf(cached) > 0 ? '付费 · ' + goldOf(cached) + ' 金币' : 'VIP 专享',
        description:
          '源站提示：' + String((error && error.apiMessage) || message) + '\n' +
          '这条内容锁在服务端（/api/video/info 直接 401，连标题/地址都不返回），' +
          '本站的匿名接口拿不到播放地址，脚本侧也没有可绕的东西。'
      };
    }

    var parts = [];
    if (info.nickname) parts.push(String(info.nickname));
    if (info.width && info.height) parts.push(info.width + '×' + info.height);
    if (info.play_num != null) parts.push('播放 ' + String(info.play_num));
    if (info.praise_num != null) parts.push('赞 ' + String(info.praise_num));
    if (info.comment_num != null) parts.push('评论 ' + String(info.comment_num));

    var description = [];
    description.push('作者：' + String(info.nickname || '未知'));
    if (info.create_at) description.push('发布：' + new Date(Number(info.create_at) * 1000).toISOString().slice(0, 10));
    description.push(
      '播放 ' + String(info.play_num == null ? '-' : info.play_num) +
        ' · 点赞 ' + String(info.praise_num == null ? '-' : info.praise_num) +
        ' · 评论 ' + String(info.comment_num == null ? '-' : info.comment_num)
    );
    if (info.description) description.push('简介：' + String(info.description));
    if (String(info.vip_exclusive || 0) === '1') description.push('源站标注：VIP 专享（本条目匿名仍可取到线路）');
    if (String(info.is_original || 0) === '1') description.push('原创作品');
    description.push('免费线路是 *_wm.mp4 转出的 HLS（带站方水印）；无水印的 vip_* 线路只对 VIP 账号下发。');

    return {
      id: String(id),
      title: String(info.title || id),
      cover: absolute(info.cover),
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

  /// 播放：info 给的 m3u8_url（AES-128 加密的 HLS，完整 VOD）当主线路；
  /// normal_url（mp4 直链）主机 osnlpls.nkmwrw.xyz 当前 DNS 都解析不了，
  /// 只有探测到 2xx 才作为额外线路；vip_* 线路只有真 VIP 账号才会有值。
  async content(argument) {
    var settings = argument || {};
    var id = String(settings.id || settings.chapterId || '').replace(/#play$/, '').trim();
    if (!id || !/^\d+$/.test(id)) throw new Error('缺少视频 id');

    var info;
    try {
      info = await fetchInfo(id);
    } catch (error) {
      var message = String((error && error.message) || '');
      if (/付费|VIP|专享/.test(message)) {
        throw new Error(
          '源站服务端锁定：' + String((error && error.apiMessage) || message) + ' —— 这条要付费/开 VIP 才下发地址，脚本侧拿不到'
        );
      }
      throw error;
    }

    var playHeaders = mediaHeaders();
    var qualities = [];
    var primary = '';

    var hls = absolute(info.vip_m3u8_url || '') || absolute(info.m3u8_url || '');
    if (hls) {
      primary = hls;
      qualities.push({ label: String(info.vip_m3u8_url ? 'HLS · VIP 无水印' : 'HLS'), url: hls });
    }

    var vipMp4 = absolute(info.vip_url || '');
    if (vipMp4) qualities.push({ label: 'MP4 · VIP 无水印', url: vipMp4 });

    var plainMp4 = absolute(info.normal_url || '');
    if (plainMp4 && plainMp4 !== hls) {
      // 死链探测：这台 CDN 目前解析不了，探不到就不给（别把死链丢给播放器）
      var alive = false;
      try {
        var probe = await LumeSource.http.request({
          url: plainMp4,
          method: 'GET',
          headers: Object.assign({}, playHeaders, { Range: 'bytes=0-1023' })
        });
        alive = !!probe && probe.status >= 200 && probe.status < 400;
      } catch (error) {
        alive = false;
      }
      if (alive) qualities.push({ label: 'MP4 · 直链', url: plainMp4 });
      if (!primary) primary = plainMp4;
    }

    if (!primary) throw new Error('这条视频没有可播放地址（info 里 m3u8_url / normal_url 都是空）：' + id);

    // 完整片 / 试看：只在配置为空时补一句事实（不猜，按 playlist 自身证据）
    var verdict = await inspectPlaylist(primary);
    var extra = '';
    if (verdict) {
      extra = verdict.segments + ' 段 / 约 ' + verdict.seconds + ' 秒' + (verdict.complete ? '（VOD 完整片）' : '（无 ENDLIST，可能被截断）');
    }

    var result = { kind: 'video', url: primary, headers: playHeaders };
    if (qualities.length > 1) result.qualities = qualities;
    if (extra) result.subtitle = extra;
    return result;
  }
};
