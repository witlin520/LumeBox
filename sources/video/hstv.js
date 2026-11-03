// LumeSource: {"id":"hstv_video","name":"HSTV","version":"1.0.0","category":"video","mirrors":["https://d1nu1x3tadacmt.cloudfront.net","https://d30zcqlpvg6j0s.cloudfront.net"]}
//
// ════════════════════════════════════════════════════════════════════════════
// 一、先说「hstv.fun 与 d1nu1x3tadacmt.cloudfront.net 是不是同一个站」
// ════════════════════════════════════════════════════════════════════════════
// **不是同一个站**（2026-10-25 实测，逐项比对如下）：
//
//   ┌─────────────┬──────────────────────────────┬──────────────────────────────┐
//   │             │ hstv.fun                     │ d1nu1x3tadacmt.cloudfront.net│
//   ├─────────────┼──────────────────────────────┼──────────────────────────────┤
//   │ 前端框架    │ Angular + Ionic（本文件同目录  │ Vue3 + Vite（/js/main-…js）  │
//   │             │ 的 main.d050a29b…js）         │                              │
//   │ 接口形态    │ **单一 RPC** POST /js，body 是 │ **REST** /api/app/<资源路径> │
//   │             │ {url:"/sevenVideos?page=1",   │ GET/POST 分离，路径即语义    │
//   │             │  app,version,deviceInfo,…}    │                              │
//   │ 接口域      │ v2.cdn199.com / v2.kekecdn.net│ d30zcqlpvg6j0s.cloudfront.net│
//   │             │ /v2.luchu.org/…（8 台）        │ /d3ea5bf3…/haoasd.rlkfus.cn   │
//   │ 响应加密    │ crypto-js AES.encrypt(json,   │ 自研派生：32B interfaceKey   │
//   │             │ "xxx") → {"r":"U2FsdGVkX1…"}  │ →SHA256 拼 AES-256-CBC 密钥  │
//   │ 内容域      │ sevenVideos / 邀请码 / 付费码  │ 短视频 + 短剧 + ACG + AI 换装 │
//   │ 支付        │ pandashop.one / mshop.one     │ 站内金币 + vipProductList    │
//   │ 运营方信标  │ 1024videos@gmail.com 等        │ mrchaose2027@gmail.com /     │
//   │             │                              │ @mrhaose（/ping/check 里自报）│
//   └─────────────┴──────────────────────────────┴──────────────────────────────┘
//
// 结论：两套互相独立的系统（最多算同一灰产生态的两个牌子）。所以本源**只接 CF 那套**，
// mirrors 里放的是 CF 的页面宿主 + 它的探活接口主机；hstv.fun **不放**（原因见下）。
//
// ▍为什么放弃 hstv.fun（实测废掉，不是没挖）
//   · 它的接口我已完全挖出：POST {httpNames}/js，body {url:"/sevenVideos?page=1&type=hot",
//     app:<域名>, version:"260901", deviceInfo:{}, theLink, uuid, isStandalone}，响应是
//     crypto-js AES.encrypt(json,"xxx")（OpenSSL salted，EVP_BytesToKey+MD5+AES-256-CBC），
//     接口表：/sevenVideos?page=N&type=hot|home_hot|home_japan|home_high、/sevenVideos/{id}、
//     /searchSevenVideos、/sevenVideoUserLogin、/vipProductDetails/{id}、/getPayList …
//   · 但 `/js` 对**我们这台机器**被 WAF 挡死：一律 `403 {"blocked":true}`。已排除请求写法问题——
//     换 8 台 API 主机、换 app（hstv.fun/hstv.life/91porn.coach/xchina.tube/yaoporn.com…）、
//     换 UA/Origin/Referer/全套 sec-fetch 头、换 uuid/theLink、带 cookie、CN 直连 vs HK 代理，
//     全部 blocked；而同一主机的 `/va` 永远 200（解出 {"value":"s"}）。
//   · 决定性证据：用真 Chrome headless（--proxy-server 走 7890）打开 hstv.fun，SPA 自己落到
//     站内拦截页「抱歉，您的访问已被拦截 / 参考编号 7c215088058c18a9」——是平台按 IP 拦，不是我们写错。
//   · 站点无 SSR（Googlebot UA 也只回 5.7KB 空壳）、无 sitemap。→ 片库数据一个字节都拿不到。
//   顺带纠正一个误读：`MAX_CVIDEO_PREVIEW_TIME=120` 是 videojs 前端
//   `C.currentTime() >= N && C.pause()` 的本地截断，服务端给的是整片 m3u8。
//
// ════════════════════════════════════════════════════════════════════════════
// 二、本源接的这套（CF / Vue3）接口清单 —— 全部实测 200
// ════════════════════════════════════════════════════════════════════════════
//  接口 base：前端 `eu` 数组里三台，任选一台探活（GET /api/app/ping/check 回 {"response":"pong"}）：
//    https://d30zcqlpvg6j0s.cloudfront.net   https://d3ea5bf3mxqaxz.cloudfront.net
//    https://haoasd.rlkfus.cn
//  **注意**：页面宿主 d1nu1x3tadacmt.cloudfront.net 只是静态托管，`/api/...` 它不接，
//  所以「接口未必同域」——本源把两者分开处理（mirrors[0] 是给人看的站点地址，API_BASES 是真接口）。
//
//  ▍鉴权：有个**匿名设备登录**，不注册、不填手机号就能拿 token（关键发现）
//     POST /api/app/mine/login/h5  body {"devID":"<32位十六进制>","sysType":"ios","isAppStore":false}
//     → data 解密后是一张 JWT（{type:0,uid:717439,...}），**这就是「无账号可用」的实质**。
//     除 /ping/check 与这张登录接口外，其余接口不带 token 一律 {"code":5005,"msg":"no token"}。
//     token 用法：`Authorization: <JWT 原文>`（不是 "Bearer xxx"，加了 Bearer 会 5009 invalid token）。
//
//  ▍接口（前缀 /api/app）
//     GET  /ping/check                         探活
//     POST /mine/login/h5                      匿名设备登录 → token
//     GET  /ping/domain/h5                     站点配置：VID 线路（视频 CDN）、IMAGE 图床、eKey、广告位
//     GET  /vid/recommend/list?pageNumber&pageSize&newsType=SP   推荐流（分类「推荐」）
//     GET  /search/hotVid/list?pageNumber&pageSize               热门流（分类「热门」）
//     POST /search/list  {pageNumber,pageSize,keyWords:[词],realm:"SP",sortType:7}   站内搜索
//     GET  /vid/info?videoID=<24位hex>          详情（sourceURL/freeTime/coins/tags/seriesCover…）
//     POST /video/play   {videoID,videoType:0,supportH265:false,scene:"detail"}
//                                               → playPolicy{result,source,previewTime,access{reason,price}}
//     GET  /vid/h5/m3u8/<playPolicy.source>?token=<JWT>    **真正的播放地址**（服务端把 CDN m3u8 代理出来）
//
// ════════════════════════════════════════════════════════════════════════════
// 三、播放地址怎么来（重点）
// ════════════════════════════════════════════════════════════════════════════
//  ① 详情/列表里的 `sourceURL` 是**相对路径**（`JHA-210/tk1/xxxx.m3u8`），直接拼 VID CDN
//     （sjljsla.lkkwip.cn 等）会 **403**；列表里那种明文路径 `bktappupdata/sp/…m3u8` 直连 CDN 同样 403。
//  ② 唯一可行路径是站点自己的代理端点（前端播放器源码原文）：
//        `${baseUrl}/api/app/vid/h5/m3u8/${playPolicy.source}?token=${token}&c=${线路}`
//     实测 200 + `application/octet-stream` + `#EXTM3U`；`c`（线路）可省，默认走线路 1。
//     播放列表里的分片是**带签名**的绝对地址（`…0.ts?md=1792932903-0-0-0ab56c32…&c=210&v=1702`），
//     有效期约 10 分钟，所以每集播放前重新取一次 playPolicy 即可。
//  ③ 播放列表里有 `#EXT-X-KEY:METHOD=AES-128,URI="/api/app/vid/sec"`；
//     该 URI 是站内绝对路径，**不带 token 也 200**（返回 16 字节密钥），标准播放器能自己取到。
//  ④ 封面：`IMAGE` 线路 https://zzzznnn.lkkwip.cn/ + cover（如 cf230705/image/…jpg，实测 200）。

// ════════════════════════════════════════════════════════════════════════════
// 四、VIP / 付费 / 金币锁 —— 实测结论（不粉饰）
// ════════════════════════════════════════════════════════════════════════════
//  ① 普通内容**不需要登录**就能看：匿名设备登录（第 21 行那条）就够，token 里 type:0、uid 是
//     按 devID 派生的固定号，**没有注册/邮箱/手机号/验证码**——这就是绕过的方式。
//  ② 哪些内容免费由服务端字段决定，`coins` 是价格：
//       - `/vid/info` 里每个条目带 `coins`（0 = 免费）、`freeTime`（试看秒数，默认 15）；
//       - `/video/play` 的 `playPolicy.result` 只有两种实测值：
//           `FULL`    → 完整播放列表（实测 77 段 / 781 秒、409 段 / 1648 秒，整片）
//           `PREVIEW` → **服务端把播放列表截断成 15 秒**（实测 4 段 / 18.48 秒 + #EXT-X-ENDLIST）
//         伴随 `access.reason:"LOCKED"`、`access.price.coins:68`、`needCoin:true`。
//  ③ 免费内容占比：推荐流每页 20 条里 7~11 条是 coins=0（三页实测 7/20、11/20、9/20），
//     这些**匿名身份直接给整片**，不需要 VIP、不需要金币。
//  ④ 金币/VIP 锁定那部分**破不了，如实报告**。已逐一试过并失败：
//        · 拿 /vid/info 里的 sourceURL、列表里的明文 sourceURL 直连代理端点 → 仍只回 4 段（或 403）；
//        · /video/play 换 scene("short"/"detail")、videoType(0/1) → 仍 PREVIEW 或参数错误；
//        · 直连 VID CDN（sjljsla.lkkwip.cn / rs2sts.pjrwfe.cn）→ 一律 403（无签名不放行）；
//        · 换身份（重新登录换 devID）→ 新号 coinBalance 恒 0，锁不打开。
//     也就是说**截断发生在服务端生成播放列表这一步**，不是前端限制，拿不到那 4 段之后的任何字节。
//  ⑤ 所以本源对 PREVIEW 条目照样返回可播地址（那 15 秒是真能播的），并在详情里标明「试看 15 秒」，
//     不伪造「已解锁」，也不因为锁就整条不显示——用户点进去至少知道自己看到了什么。

var DEFAULT_BASES = [
  'https://d30zcqlpvg6j0s.cloudfront.net',
  'https://d3ea5bf3mxqaxz.cloudfront.net',
  'https://haoasd.rlkfus.cn'
];
var INTERFACE_KEY = '65dc07d1b7915c6b2937432b091837a7';
var UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
var IMAGE_HOST = 'https://zzzznnn.lkkwip.cn';
var PAGE_SIZE = 20;
// 匿名设备号：32 位十六进制，服务端拿它派生 uid。换一个就等于换一个游客账号。
var DEVICE_ID = 'a1b2c3d4e5f64a1b9c8d7e6f5a4b3c2d';

/* ══════════════════════════ 纯 JS 基础工具（沙箱无 crypto / atob / Buffer） ══════════════════════════ */

var B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function b64ToBytes(text) {
  var source = String(text == null ? '' : text).replace(/[^A-Za-z0-9+/=]/g, '');
  var out = [];
  var buffer = 0;
  var bits = 0;
  for (var index = 0; index < source.length; index++) {
    var ch = source.charAt(index);
    if (ch === '=') break;
    var value = B64_CHARS.indexOf(ch);
    if (value < 0) continue;
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  return out;
}

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
    for (var step = 0; step < extra; step++) code = (code << 6) | ((bytes[index + step] || 0) & 0x3f);
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

/* ───────────────────────── SHA-256（站点密钥派生要用） ───────────────────────── */
var SHA256_K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr32(value, bits) {
  return ((value >>> bits) | (value << (32 - bits))) >>> 0;
}

function sha256Bytes(bytes) {
  var data = bytes.slice();
  var bitLength = data.length * 8;
  data.push(0x80);
  while (data.length % 64 !== 56) data.push(0);
  // 高位 32 位（本站报文远小于 2^32 字节，恒 0）
  data.push(0, 0, 0, 0, (bitLength >>> 24) & 0xff, (bitLength >>> 16) & 0xff, (bitLength >>> 8) & 0xff, bitLength & 0xff);

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  var w = new Array(64);
  for (var offset = 0; offset < data.length; offset += 64) {
    var t;
    for (t = 0; t < 16; t++) {
      var base = offset + t * 4;
      w[t] = ((data[base] << 24) | (data[base + 1] << 16) | (data[base + 2] << 8) | data[base + 3]) >>> 0;
    }
    for (t = 16; t < 64; t++) {
      var s0 = (rotr32(w[t - 15], 7) ^ rotr32(w[t - 15], 18) ^ (w[t - 15] >>> 3)) >>> 0;
      var s1 = (rotr32(w[t - 2], 17) ^ rotr32(w[t - 2], 19) ^ (w[t - 2] >>> 10)) >>> 0;
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) >>> 0;
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;
    for (t = 0; t < 64; t++) {
      var S1 = (rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)) >>> 0;
      var ch = ((e & f) ^ (~e & g)) >>> 0;
      var temp1 = (h + S1 + ch + SHA256_K[t] + w[t]) >>> 0;
      var S0 = (rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)) >>> 0;
      var maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      var temp2 = (S0 + maj) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
    h5 = (h5 + f) >>> 0;
    h6 = (h6 + g) >>> 0;
    h7 = (h7 + h) >>> 0;
  }

  var digest = [];
  var state = [h0, h1, h2, h3, h4, h5, h6, h7];
  for (var s = 0; s < 8; s++) {
    digest.push((state[s] >>> 24) & 0xff, (state[s] >>> 16) & 0xff, (state[s] >>> 8) & 0xff, state[s] & 0xff);
  }
  return digest;
}

/* ───────────────────────── AES CBC 解密（纯 JS，GF(2^8) 现算 SBOX） ───────────────────────── */
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

function aesAddRoundKey(state, key, round) {
  for (var index = 0; index < 16; index++) state[index] ^= key[round * 16 + index];
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

// CBC 解密（PKCS7 去填充），key/iv 是字节数组
function aesCbcDecrypt(data, keyBytes, ivBytes) {
  var expanded = aesExpandKey(keyBytes);
  var previous = ivBytes;
  var plain = [];
  for (var offset = 0; offset + 16 <= data.length; offset += 16) {
    var block = data.slice(offset, offset + 16);
    var decoded = aesDecryptBlock(block, expanded);
    for (var index = 0; index < 16; index++) plain.push(decoded[index] ^ previous[index]);
    previous = block;
  }
  var pad = plain.length ? plain[plain.length - 1] : 0;
  if (pad > 0 && pad <= 16 && pad <= plain.length) plain = plain.slice(0, plain.length - pad);
  return plain;
}

/* ───────────── 站点响应解密：cf 前端 `Fa(data, interfaceKey)` 的逐行复刻 ───────────── */
//   i = key || nonce(12B)
//   o = len(i)/2 ; r = SHA256(i)[8:24]
//   s = r || i[0:o] ; c = i[o:] || r
//   d = SHA256(s) ; f = SHA256(c)
//   aesKey = d[0:8] || f[8:24] || d[24:]      (32B → AES-256)
//   aesIv  = f[0:4] || d[12:20] || f[28:]     (16B)
//   plain  = AES-256-CBC-decrypt(base64decode(data)[12:])
function faDecrypt(payloadB64) {
  var keyBytes = utf8Bytes(INTERFACE_KEY);
  var raw = b64ToBytes(payloadB64);
  var nonce = raw.slice(0, 12);
  var i = keyBytes.concat(nonce);
  var half = i.length >> 1;
  var r = sha256Bytes(i).slice(8, 24);
  var s = r.concat(i.slice(0, half));
  var c = i.slice(half).concat(r);
  var d = sha256Bytes(s);
  var f = sha256Bytes(c);
  var aesKey = d.slice(0, 8).concat(f.slice(8, 24)).concat(d.slice(24));
  var aesIv = f.slice(0, 4).concat(d.slice(12, 20)).concat(f.slice(28));
  var plain = aesCbcDecrypt(raw.slice(12), aesKey, aesIv);
  var text = utf8Decode(plain);
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error('响应解开了但不是 JSON：' + text.slice(0, 80));
  }
}

/* ══════════════════════════ 站点请求层 ══════════════════════════ */

// 接口 base：默认三台轮，选了哪台记在 fs 里；用户手填的域名优先（换网址时可以直接填接口主机）
var baseCache = '';
var pickPromise = null;

function customBase() {
  var config = LumeSource.config || {};
  var custom = String(config.customDomain || '').trim().replace(/\/+$/, '');
  if (custom) return custom;
  return '';
}

var token = '';

function headers(extra) {
  var result = {
    'User-Agent': UA,
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    // 站点前端自己发的那两个标记（缺一个都可能被网关当成裸请求）
    temp: 'test',
    'X-User-Agent': 'uid=&device=PC&device_brand=&device_model=&sid=&device_id=' + DEVICE_ID + '&version=1'
  };
  if (token) result.Authorization = token;
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

// 发一个 /api/app 请求并解出明文 data。
// 返回 { code, msg, data }；网络层失败抛可读错误（403/5xx 会点名让用户换线路）。
async function call(base, path, options) {
  var settings = options || {};
  var url = base + '/api/app' + path;
  var requestHeaders = headers(settings.body ? { 'Content-Type': 'application/json' } : {});
  var response;
  try {
    if (settings.body) {
      response = await LumeSource.http.post(url, JSON.stringify(settings.body), { headers: requestHeaders });
    } else {
      response = await LumeSource.http.get(url, { headers: requestHeaders });
    }
  } catch (error) {
    throw new Error('连不上接口（' + base + '）：' + ((error && error.message) || '网络错误'));
  }
  var status = response ? response.status : 0;
  if (status === 403 || status === 521) {
    throw new Error('NEED_WEBVIEW_VERIFY：接口主机 ' + base + ' 返回 HTTP ' + status);
  }
  if (status !== 200) throw new Error('接口打不开：HTTP ' + status + ' ' + path);

  var parsed;
  try {
    parsed = JSON.parse(String((response && response.body) || ''));
  } catch (error) {
    throw new Error('接口返回的不是 JSON：' + path);
  }
  var code = parsed && parsed.code != null ? Number(parsed.code) : 0;
  var data = parsed ? parsed.data : null;
  if (parsed && parsed.hash && typeof data === 'string') {
    try {
      data = faDecrypt(data);
    } catch (error) {
      throw new Error('响应解不开（interfaceKey 可能换了）：' + path);
    }
  }
  return { code: code, msg: String((parsed && (parsed.msg || parsed.tip)) || ''), data: data, raw: parsed };
}

// 选一台能通的接口主机。
// 省预算的做法：内存命中就直接用；fs 里有上次选中的主机也直接信它，只有真失败才去逐台 ping。
async function pingOne(base) {
  var reply = await call(base, '/ping/check');
  return reply.code === 200;
}

async function pickBase(force) {
  if (!force && baseCache) return baseCache;
  if (!force && pickPromise) return pickPromise;
  var task = (async function () {
    var custom = customBase();
    var candidates = custom ? [custom].concat(DEFAULT_BASES.filter(function (item) { return item !== custom; })) : DEFAULT_BASES;
    var cached = '';
    try {
      cached = (await LumeSource.fs.readText('base.txt')) || '';
    } catch (error) {
      cached = '';
    }
    if (cached && cached.indexOf('http') === 0) {
      candidates = [cached].concat(candidates.filter(function (item) { return item !== cached; }));
    }
    var lastError = '';
    for (var index = 0; index < candidates.length; index++) {
      var base = candidates[index];
      // 上次选中的那台先不 ping，直接赌一把（失败会在 api() 里翻牌重选）
      if (!force && index === 0 && cached && base === cached) {
        baseCache = base;
        return base;
      }
      try {
        if (await pingOne(base)) {
          baseCache = base;
          try {
            await LumeSource.fs.writeText('base.txt', base);
          } catch (error) {
            /* 缓存写不进去不影响本次 */
          }
          return base;
        }
        lastError = 'ping 没有回 pong';
      } catch (error) {
        lastError = (error && error.message) || '未知错误';
      }
    }
    throw new Error('三条接口线路都打不通（' + lastError + '）');
  })();
  if (!force) pickPromise = task;
  try {
    return await task;
  } finally {
    if (pickPromise === task) pickPromise = null;
  }
}

// 匿名设备登录：站点自己也是这么干的（POST /mine/login/h5），不注册、不要验证码。
// 并发调用共用同一次登录（home() 里两个请求会同时来要 token）。
var loginPromise = null;

async function ensureToken(base, force) {
  if (!force) {
    if (token) return token;
    try {
      var cached = await LumeSource.fs.readText('token.txt');
      if (cached && String(cached).length > 32) {
        token = String(cached).trim();
        return token;
      }
    } catch (error) {
      /* 没有缓存就登录 */
    }
    if (loginPromise) return loginPromise;
  }
  loginPromise = (async function () {
    var reply = await call(base, '/mine/login/h5', {
      body: { devID: DEVICE_ID, sysType: 'ios', isAppStore: false }
    });
    if (reply.code !== 200 || !reply.data || !reply.data.token) {
      throw new Error('匿名设备登录失败：' + (reply.msg || 'code ' + reply.code));
    }
    token = String(reply.data.token);
    try {
      await LumeSource.fs.writeText('token.txt', token);
    } catch (error) {
      /* 无所谓，本次内存里有 */
    }
    return token;
  })();
  try {
    return await loginPromise;
  } finally {
    loginPromise = null;
  }
}

// 带 token 的请求：网络层失败就换一台接口主机重试一次；token 过期（5009）自动重登一次。
async function api(path, options) {
  var base = await pickBase(false);
  await ensureToken(base, false);
  var reply;
  try {
    reply = await call(base, path, options);
  } catch (error) {
    var next = await pickBase(true);
    if (next !== base) reply = await call(next, path, options);
    else throw error;
  }
  if (reply.code === 5009) {
    await ensureToken(base, true);
    reply = await call(base, path, options);
  }
  if (reply.code !== 200) {
    throw new Error('接口报错：' + (reply.msg || 'code ' + reply.code) + '（' + path + '）');
  }
  return reply.data;
}

/* ══════════════════════════ 数据整形 ══════════════════════════ */

function absoluteImage(path) {
  var text = String(path || '').trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  return IMAGE_HOST + '/' + text.replace(/^\/+/, '');
}

function tagNames(row) {
  var names = [];
  var tags = (row && row.tags) || [];
  for (var index = 0; index < tags.length && index < 5; index++) {
    if (tags[index] && tags[index].name) names.push(String(tags[index].name));
  }
  return names;
}

function itemOf(row) {
  if (!row || !row.id) return null;
  var parts = [];
  var tags = tagNames(row);
  if (tags.length) parts.push(tags.join('·'));
  var coins = Number(row.coins || 0);
  parts.push(coins > 0 ? coins + ' 金币' : '免费');
  if (row.playTime) parts.push(Math.round(Number(row.playTime) / 60) + ' 分钟');
  if (row.playCount) parts.push('播放 ' + String(row.playCount));
  return {
    id: String(row.id),
    title: String(row.title || row.id),
    cover: absoluteImage(row.cover || row.coverThumb || ''),
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

// 三种列表渠道（实测都活）
async function fetchFeed(kind, page, pageSize) {
  var size = pageSize || PAGE_SIZE;
  if (kind === 'hot') {
    var hot = await api('/search/hotVid/list?pageNumber=' + page + '&pageSize=' + size);
    return { rows: (hot && hot.data) || [], hasNext: !!(hot && (hot.hasNext || (hot.data || []).length >= size)) };
  }
  var rec = await api('/vid/recommend/list?pageNumber=' + page + '&pageSize=' + size + '&newsType=SP');
  return { rows: (rec && rec.list) || [], hasNext: !!(rec && rec.hasNext) };
}

/* ══════════════════════════ 图源契约 ══════════════════════════ */

var LumeSource = {
  id: 'hstv_video',
  name: 'HSTV',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://d1nu1x3tadacmt.cloudfront.net', 'https://d30zcqlpvg6j0s.cloudfront.net'],

  /// 分类：站点没有公开的分类树（/tag/list 只有标签云），所以按它自己的两条流切。
  async categories() {
    return [
      { id: 'recommend', title: '推荐' },
      { id: 'hot', title: '热门' }
    ];
  },

  /// 首页：推荐 + 热门，各 20 条（两个请求并发，省沙箱预算）。
  async home() {
    var boards = [];
    var results;
    try {
      results = await Promise.all([fetchFeed('recommend', 1, 20), fetchFeed('hot', 1, 20)]);
    } catch (error) {
      results = [await fetchFeed('recommend', 1, 20), { rows: [] }];
    }
    var recommend = itemsOf(results[0].rows);
    if (recommend.length) boards.push({ title: '推荐', moreUrl: 'recommend', items: recommend });
    var hot = itemsOf(results[1].rows);
    if (hot.length) boards.push({ title: '热门', moreUrl: 'hot', items: hot });
    if (!boards.length) throw new Error('首页：推荐与热门都取不到条目（站点可能改版）');
    return boards;
  },

  /// 列表 / 搜索。搜索走站点自己的 /search/list（realm=SP 就是短视频），不是本地过滤。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';

    if (keyword) {
      var found = await api('/search/list', {
        body: { pageNumber: page, pageSize: PAGE_SIZE, keyWords: [keyword], realm: 'SP', sortType: 7 }
      });
      var hitRows = (found && found.list) || [];
      return { items: itemsOf(hitRows), hasMore: !!(found && found.hasNext) };
    }

    var kind = String(settings.categoryId || 'recommend') === 'hot' ? 'hot' : 'recommend';
    var feed = await fetchFeed(kind, page, PAGE_SIZE);
    return { items: itemsOf(feed.rows), hasMore: feed.hasNext };
  },

  /// 详情：/vid/info。金币价与试看秒数照实写进描述（不替站点许诺「免费」）。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return null;
    var data;
    try {
      data = await api('/vid/info?videoID=' + encodeURIComponent(id));
    } catch (error) {
      if (/不存在|已删除|参数错误|code 4001/i.test(String(error && error.message))) return null;
      throw error;
    }
    if (!data || !data.id) return null;
    var coins = Number(data.coins || 0);
    var parts = [];
    var tags = tagNames(data);
    if (tags.length) parts.push(tags.join(' / '));
    parts.push(coins > 0 ? '金币 ' + coins : '免费');
    if (data.resolution) parts.push(String(data.resolution));
    if (data.playTime) parts.push(Math.round(Number(data.playTime) / 60) + ' 分钟');
    if (data.playCount) parts.push('播放 ' + String(data.playCount));

    var lines = [];
    lines.push('标题：' + String(data.title || id));
    lines.push('价格：' + (coins > 0 ? coins + ' 金币' : '免费（匿名身份直接整片）'));
    lines.push('试看：' + (data.freeTime ? data.freeTime + ' 秒（服务端只发这段）' : '-'));
    if (data.resolution) lines.push('分辨率：' + data.resolution + (data.size ? ' · ' + Math.round(Number(data.size) / 1048576) + 'MB' : ''));
    if (data.createdAt) lines.push('发布：' + String(data.createdAt).slice(0, 10));
    lines.push('数据：播放 ' + String(data.playCount || 0) + ' · 点赞 ' + String(data.likeCount || 0) + ' · 评论 ' + String(data.commentCount || 0));
    if (tags.length) lines.push('标签：' + tags.join(' / '));
    if (String(data.content || '').trim()) lines.push('简介：' + String(data.content).slice(0, 300));

    return {
      id: String(data.id),
      title: String(data.title || id),
      cover: absoluteImage(data.cover || data.coverThumb || ''),
      subtitle: parts.join(' · '),
      description: lines.join('\n')
    };
  },

  /// 短视频 = 单集（chapterId 里带上 newsType，content 时不用再猜）
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: id, title: '播放' }];
  },

  /// 播放：POST /video/play 拿 playPolicy.source，再拼站内的 m3u8 代理端点。
  /// 免费条目 playPolicy.result=FULL（整片）；金币/VIP 条目 result=PREVIEW，服务端只发 15 秒
  /// —— 这里照样把那段地址给播放器（它是真能播的），并在提示里说清楚，不假装解锁。
  async content(argument) {
    var settings = argument || {};
    var id = String(settings.chapterId || settings.id || '').trim();
    if (!id) throw new Error('缺少视频 id');
    var base = await pickBase(false);
    await ensureToken(base, false);

    var policy = await api('/video/play', {
      body: { videoID: id, videoType: 0, supportH265: false, scene: 'detail' }
    });
    var playPolicy = policy && policy.playPolicy;
    if (!playPolicy || !playPolicy.source) {
      throw new Error('这条没有给播放地址（playPolicy 为空），可能是下架或需要更高等级');
    }
    var source = String(playPolicy.source).replace(/^\/+/, '');
    var url = base + '/api/app/vid/h5/m3u8/' + source + '?token=' + encodeURIComponent(token);
    // 播放列表里的分片是带签名（md=…，约 10 分钟）的绝对地址；#EXT-X-KEY 指向 /api/app/vid/sec，
    // 那个端点不带 token 也回 16 字节密钥，所以标准播放器自己就能取到。
    // PREVIEW 条目（金币/VIP 锁）地址同样有效，只是列表被服务端截断成 15 秒——见文件头第四节。
    return {
      kind: 'video',
      url: url,
      headers: { 'User-Agent': UA, Referer: base + '/', Authorization: token }
    };
  }
};
