// LumeSource: {"id":"hu4_video","name":"四虎","version":"1.0.0","category":"video","mirrors":["https://www.4hu.tv"]}
//
// 站点：4hu.tv（页面 <title> 是「鍥涜檸 - 4hu.tv」，UTF-8 被当 GBK 显示出来的乱码，真名就是**四虎**；
// 不是「4虎」。所以 name 按真站名写成四虎。）
//
// ── 入口链路（2026-10-25 实测，全部走本机代理出口）
//   · https://www.4hu.tv/ 只有 4.6KB：一个 `#cc_pwe_tent` 空壳 + `/indexaKo.js?V2.3`。
//     那个 JS 是 sojson 混淆（base64 串表 + 数组旋转 + 反调试），我用 Node 打桩 DOM 跑过一遍：
//     它**不是**站点跳转逻辑，只是「本站最新網址」提示页 —— 往 #cc_pwe_tent 里塞一张 base64 PNG
//     （logo + 二维码）、把 `WebUrl` 的 textContent 写成全角「ＷＷＷ．４ＨＵ．ＴＶ」、
//     logo1..4 写 www.4hu.tv、最后再拼一个 <a href="https://www.4hu.tv">。
//     也就是说 www.4hu.tv 本身就是正站入口，没有隐藏镜像域（找过 /permalink、/help、/json 索引都没别的域）。
//   · 真内容在 **/home/**（7KB，Nuxt3 SPA，`__NUXT_DATA__` 里 ssr:false，靠 fetch 拉数据）。
//     内联配置：`cdn_url:"//www.4hu.tv", search_url:"", json_url:"/json", api_change_json:!0`
//     → 数据全部来自**静态 JSON 目录 /json/**，`/api/v2/*` 这类后端接口在这个镜像上是死的（全返回 SPA 壳）。
//
// ── 解密：/json/*.json 的 body 是 {"status":1,"data":"<base64url>"}
//   data = base64url( AES-256-CBC( JSON ) )，key = "22946bc50fd63164b79df55070a85a92"（32 字节 → AES-256），
//   iv = "kaixin1234567890"（16 字节），PKCS7 padding。这三个常量就是站点前端 `$crypto` 里的明文常量
//   （chunk L9tOrg0d3LeVqd-e.js 里 `U.AES.decrypt(...{iv:i,mode:CBC,padding:Pkcs7})`）。
//   **本脚本自带纯 JS 的 AES-256-CBC 解密**（SBOX 由 GF(2^8) 逆元现算，不依赖 atob / Buffer / tools.aes，
//   因为 App 沙箱里 tools.aes 是原生能力、离线跑测工具里没实现）。实测与 Node crypto 输出逐字节一致
//   （latest.json 解出 22014 字符）。
//
// ── 接口（全部实测 200 + 可解）
//   · 分类树   GET /json/category-list.json → {"0".."4"} 五个一级组，每组 .items[] 是二级分类
//              {classid,classname,classpath,tbname,listtempid}。tbname==='movie' 才是视频（news 是图集/小说，
//              它的 /json/category/{id}-1.json 直接 404，所以本源只用 movie 分类）。
//   · 列表     GET /json/category/{classid}-{page}.json → {data:[{id,classid,title,titlepic,yulan,m3u8,newstime}],
//              per_page:28, total, current_page, last_page, category_name}（实测 4/30/42/64/142 都有货）
//   · 首页     GET /json/latest.json → {latest:[20], latest2:[20], movie:[20]}
//   · 详情     GET /json/video/{id}.json → 比列表多 `mp4`（https://d1.xia12345.com/.../720.mp4，实测 206）、
//              `category_name`、`breadcrumb`、`keyboard`（关键词串）、`maybe`、`prev_and_next`
//   · 封面     titlepic 给的是 `.../cover.txt`（text/plain，内容是 `data:image/jpg;base64,…` 的**数据 URI 文本**，
//              专门用来挡盗链）。前端自己就是 `titlepic.replace('.txt','.jpg')` 取图 —— 实测那个 .jpg 是
//              200 + image/jpeg（1407B），本源照抄这个替换。
//   · 播放     m3u8 字段是**站内相对路径** `/newhd/{y}/{hash}/hls/index.m3u8`，必须拼 CDN 主机才播：
//              前端随机从 ["https://m3u8.41cdn.com","…44…","…46…","…47…","…48…","…34…"] 取 3 个试。
//              实测 6 台全部 200 + `application/vnd.apple.mpegurl` + `#EXTM3U`（VOD 播放列表）。
//              mp4 直链同样可用，作为 m3u8 全挂时的兜底。
//   · 搜索     前端走 `search_url + /api/v2/search?keyword=&classid=&page=`，而这个镜像 search_url 是空串、
//              /api/v2/search 返回 SPA 壳（不是 JSON）→ **服务端搜索在这台镜像上不可用**。
//              本源不装死：关键词走「本地过滤」——把 /json/latest.json 的三组（60 条）按标题过滤后按 28 条
//              切片返回；命中为空就如实返回空列表（不编造结果）。
//
// ── Cloudflare：直连会被「TLS 指纹」判死，走宿主网页渲染
//   同一台机器、同一个代理出口、同一个桌面 Chrome UA：curl 打 /json/latest.json → 200 / 29377B；
//   Node 原生 fetch（undici）→ **403 + "Just a moment..."**（UA / Referer / Cookie 全试过，一样 403），
//   App 侧 Dart HttpClient 同样是这个下场。所以 fetchJsonText() 先直连，认出挑战页就改走
//   LumeSource.web.render（受限 WebKit 能过 JS 挑战，结果按 1 小时缓存「本源走渲染」标记），
//   两步都失败才抛 NEED_WEBVIEW_VERIFY。
//   **注意：离线跑测工具 tools/lume-source-check.mjs 不实现 web.render（直接 harnessUnsupported），
//   所以本源在检查器里的输出必然是 FAIL —— 那是工具边界，不是站点不可用。**
//   播放链路不受影响：m3u8.*cdn.com 与封面图床 pppp.642p.com 没有 Cloudflare，
//   Node fetch 直连就是 200 + #EXTM3U / image/jpeg（都实测过）。
var DEFAULT_BASE = 'https://www.4hu.tv';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var PAGE_SIZE = 28;

// 站内前端写死的 m3u8 CDN 主机（实测全部可用，同一个播放列表）
var HLS_HOSTS = [
  'https://m3u8.41cdn.com',
  'https://m3u8.44cdn.com',
  'https://m3u8.46cdn.com',
  'https://m3u8.47cdn.com',
  'https://m3u8.48cdn.com',
  'https://m3u8.34cdn.com'
];

/* ============================ 纯 JS AES-256-CBC 解密 ============================ */
var AES_EXP = new Array(256);
var AES_LOG = new Array(256);
(function buildLogTables() {
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

// base64url → 字节数组（自己实现：沙箱未必有 atob，也不引入 Buffer）
var B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function b64urlToBytes(text) {
  var source = String(text == null ? '' : text).replace(/-/g, '+').replace(/_/g, '/');
  var out = [];
  var buffer = 0;
  var bits = 0;
  for (var index = 0; index < source.length; index++) {
    var value = B64_CHARS.indexOf(source.charAt(index));
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

// 自己解 UTF-8（不依赖 TextDecoder）
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
    for (var step = 0; step < extra; step++) code = (code << 6) | (bytes[index + step] & 0x3f);
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

var AES_KEY = '22946bc50fd63164b79df55070a85a92';
var AES_IV = 'kaixin1234567890';

function aesCbcDecode(text) {
  var key = [];
  var iv = [];
  var index;
  for (index = 0; index < AES_KEY.length; index++) key.push(AES_KEY.charCodeAt(index) & 0xff);
  for (index = 0; index < AES_IV.length; index++) iv.push(AES_IV.charCodeAt(index) & 0xff);
  var data = b64urlToBytes(text);
  var expanded = aesExpandKey(key);
  var previous = iv;
  var plain = [];
  for (var offset = 0; offset + 16 <= data.length; offset += 16) {
    var block = data.slice(offset, offset + 16);
    var decoded = aesDecryptBlock(block, expanded);
    for (index = 0; index < 16; index++) plain.push(decoded[index] ^ previous[index]);
    previous = block;
  }
  var pad = plain.length ? plain[plain.length - 1] : 0;
  if (pad > 0 && pad <= 16) plain = plain.slice(0, plain.length - pad);
  return utf8Decode(plain);
}
/* ========================== AES 结束 ========================== */

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Referer: base() + '/home/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

function mediaHeaders() {
  return { 'User-Agent': UA, Referer: base() + '/', Accept: '*/*' };
}

// ------------------------------------------------ Cloudflare 挑战 → 网页渲染兜底
// 实测差异（同一台机器、同一个代理出口、同一个桌面 Chrome UA）：
//   curl 打 /json/latest.json → 200 / 29377B；
//   Node 原生 fetch（undici）打同一个 URL → **403 + "Just a moment..."**（Cloudflare JS 挑战）。
// 差别不在 UA / Referer / Cookie（全试过，都一样 403），是 TLS 指纹被判的（App 侧 Dart HttpClient 同样会被判）。
// 所以这里照 niacg.js 的做法：先直连，认出挑战页就改走宿主的受限 WebKit 渲染
// （LumeSource.web.render 能过 JS 挑战），并把「本源走渲染」记 1 小时，省掉每次 403 往返；
// 渲染也过不去才抛 NEED_WEBVIEW_VERIFY 让用户在网页视图里手点校验。
// 注：离线跑测工具 tools/lume-source-check.mjs **不实现 web.render**，所以它的输出一定是 FAIL，
// 这是工具边界，不是站点不可用（curl 实测列表/详情/播放都通）。
var RENDER_TTL_MS = 3600 * 1000;

function looksBlocked(status, body) {
  return (
    status === 403 ||
    status === 503 ||
    status === 521 ||
    /cf-chl-|Just a moment|challenge-platform|Attention Required/i.test(String(body || ''))
  );
}

async function renderMode() {
  var cached = await LumeSource.fs.readText('render_mode.json');
  if (!cached) return false;
  try {
    var saved = JSON.parse(cached);
    return !!(saved && saved.render && saved.at && Date.now() - saved.at < RENDER_TTL_MS);
  } catch (error) {
    return false;
  }
}

async function markRenderMode() {
  await LumeSource.fs.writeText('render_mode.json', JSON.stringify({ render: true, at: Date.now() }));
}

// 从渲染结果里抠出 JSON 文本（WebKit 打开 application/json 会包一层 <pre>/<html>）
function jsonTextFrom(body) {
  var text = String(body || '');
  var start = text.indexOf('{');
  var end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return '';
  return text.slice(start, end + 1).replace(/&quot;/g, '"').replace(/&amp;/g, '&');
}

async function renderJson(url) {
  var result = await LumeSource.web.render({
    url: url,
    headers: { 'User-Agent': UA, Accept: 'application/json, text/plain, */*', 'Accept-Language': 'zh-CN,zh;q=0.9' },
    timeoutMs: 8000
  });
  var body = result && result.html ? String(result.html) : '';
  var json = jsonTextFrom(body);
  if (!json || looksBlocked(200, body)) {
    throw new Error('NEED_WEBVIEW_VERIFY：四虎被 Cloudflare 拦住（TLS 指纹判的，curl 能过、App/Node 的 HTTP 栈不能），请在源设置里走网页视图打开本站完成校验后重试');
  }
  return json;
}

// 拉一个 /json/*.json 的原文：先直连，403/挑战页改走渲染
async function fetchJsonText(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + path;
  if (await renderMode()) return renderJson(url);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  if (looksBlocked(status, body)) {
    // 先记「本源要走网页渲染」，再试一次渲染；渲染也失败就把原因抛给 UI
    var rendered;
    try {
      rendered = await renderJson(url);
    } catch (error) {
      throw new Error('NEED_WEBVIEW_VERIFY：四虎 /json 被 Cloudflare 拦（HTTP ' + status + '），请走网页视图完成校验或给本源配代理');
    }
    await markRenderMode();
    return rendered;
  }
  if (status === 404) throw new Error('四虎接口 404：' + url);
  if (status !== 200) throw new Error('四虎接口打不开：HTTP ' + status + ' ' + url);
  return body;
}

// 拉一个 /json/*.json 并解出明文对象
async function fetchJson(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + path;
  var body = await fetchJsonText(path);
  var parsed;
  try {
    parsed = JSON.parse(body);
  } catch (error) {
    // /api/v2/* 会回 SPA 壳（HTML），这里如实报出来，不假装有数据
    throw new Error('四虎返回的不是 JSON（可能是 /api 路由的 SPA 壳）：' + url);
  }
  if (!parsed || !parsed.data) throw new Error('四虎接口没有 data 字段：' + url);
  var plain = aesCbcDecode(String(parsed.data));
  try {
    return JSON.parse(plain);
  } catch (error) {
    throw new Error('四虎数据解不出来（AES 常量可能变了）：' + plain.slice(0, 80));
  }
}

function coverOf(url) {
  var text = String(url || '').trim();
  if (!text) return '';
  // titlepic 给的是 .../cover.txt（内容是 data URI 文本），前端自己 replace 成 .jpg
  return text.replace(/\.txt$/i, '.jpg');
}

function itemOf(row) {
  if (!row || row.id == null) return null;
  var id = String(row.id);
  var parts = [];
  if (row.newstime) {
    try {
      var date = new Date(Number(row.newstime) * 1000);
      var month = String(date.getMonth() + 1);
      var day = String(date.getDate());
      if (month.length < 2) month = '0' + month;
      if (day.length < 2) day = '0' + day;
      parts.push(date.getFullYear() + '-' + month + '-' + day);
    } catch (error) {
      /* 时间坏了就不显示 */
    }
  }
  return { id: id, title: String(row.title || id), cover: coverOf(row.titlepic), subtitle: parts.join(' · ') };
}

function itemsOf(rows) {
  var items = [];
  for (var index = 0; index < (rows || []).length; index++) {
    var item = itemOf(rows[index]);
    if (item) items.push(item);
  }
  return items;
}

// 分类树缓存：一次会话里只解一遍
var categoryCache = null;

async function loadCategories() {
  if (categoryCache) return categoryCache;
  var tree = await fetchJson('/json/category-list.json');
  var rows = [];
  var groups = [];
  var keys = [];
  for (var key in tree) keys.push(key);
  keys.sort();
  for (var index = 0; index < keys.length; index++) {
    var group = tree[keys[index]];
    if (!group || !group.items) continue;
    groups.push({ id: 'group/' + group.classid, title: group.classname });
    for (var child = 0; child < group.items.length; child++) {
      var entry = group.items[child];
      // tbname==='news' 是图集 / 小说（它的 /json/category/{id}-1.json 直接 404），视频源只收 movie
      if (!entry || entry.tbname !== 'movie' || entry.classid == null) continue;
      rows.push({ id: String(entry.classid), title: String(entry.classname || '') + (group.classname ? ' · ' + group.classname : '') });
    }
  }
  categoryCache = rows;
  return rows;
}

function knownCategory(value) {
  var id = String(value == null ? '' : value).trim();
  if (!id || id.indexOf('group/') === 0) return '4'; // 一级组没有列表接口，退回「自拍视频」
  return /^\d+$/.test(id) ? id : '4';
}

var LumeSource = {
  id: 'hu4_video',
  name: '四虎',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.4hu.tv'],

  /// 分类：/json/category-list.json 里 tbname==='movie' 的二级分类（实测 78 个，包含国产/女优/电影三大组）。
  async categories() {
    var rows = await loadCategories();
    if (!rows.length) throw new Error('四虎：分类树解出来是空的（AES 常量可能变了）');
    return rows;
  },

  /// 首页：latest.json 的三组（最新更新 / 更多推荐 / 影视精选），各 20 条。
  async home() {
    var data = await fetchJson('/json/latest.json');
    var boards = [];
    var groups = [
      { key: 'latest', title: '最新更新' },
      { key: 'latest2', title: '更多推荐' },
      { key: 'movie', title: '影视精选' }
    ];
    for (var index = 0; index < groups.length; index++) {
      var rows = itemsOf(data[groups[index].key]);
      if (!rows.length) continue;
      boards.push({ title: groups[index].title, moreUrl: '4', items: rows.slice(0, 20) });
    }
    if (!boards.length) throw new Error('四虎：首页三组都解析不出条目（站点可能改版）');
    return boards;
  },

  /// 列表：/json/category/{classid}-{page}.json（每页 28 条）。关键词走本地过滤（服务端搜索在这台镜像上死了）。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';

    if (keyword) {
      if (page > 1) return { items: [], hasMore: false };
      // /api/v2/search 在这台镜像上返回 SPA 壳，所以退成「把 latest.json 的 60 条按标题过滤」
      var latest = await fetchJson('/json/latest.json');
      var pool = [];
      var buckets = ['latest', 'latest2', 'movie'];
      for (var bucket = 0; bucket < buckets.length; bucket++) {
        var rows = latest[buckets[bucket]] || [];
        for (var index = 0; index < rows.length; index++) pool.push(rows[index]);
      }
      var needle = keyword.toLowerCase();
      var hits = [];
      for (var cursor = 0; cursor < pool.length; cursor++) {
        if (String(pool[cursor].title || '').toLowerCase().indexOf(needle) >= 0) hits.push(pool[cursor]);
      }
      var sliced = hits.slice(0, PAGE_SIZE);
      return { items: itemsOf(sliced), hasMore: sliced.length < hits.length };
    }

    var classid = knownCategory(settings.categoryId);
    var data = await fetchJson('/json/category/' + classid + '-' + page + '.json');
    var items = itemsOf(data.data);
    var lastPage = Number(data.last_page || 0);
    return { items: items, hasMore: lastPage ? page < lastPage : items.length >= PAGE_SIZE };
  },

  /// 详情：/json/video/{id}.json（比列表多 mp4 / breadcrumb / keyboard / maybe）。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id || !/^\d+$/.test(id)) return null;
    var data = await fetchJson('/json/video/' + id + '.json');
    var path = [];
    var breadcrumb = data.breadcrumb || [];
    for (var index = 0; index < breadcrumb.length; index++) {
      if (breadcrumb[index] && breadcrumb[index].title) path.push(String(breadcrumb[index].title));
    }
    var parts = [];
    if (data.category_name) parts.push(String(data.category_name));
    if (data.keyboard) parts.push(String(data.keyboard));
    var maybe = data.maybe || [];
    if (maybe.length) parts.push('相關 ' + maybe.length + ' 部');
    return {
      id: String(data.id || id),
      title: String(data.title || id),
      cover: coverOf(data.titlepic),
      subtitle: parts.join(' · '),
      description: path.length ? path.join(' / ') : '四虎 · 视频 ' + id
    };
  },

  /// 单个视频 = 一个章节。
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: id, title: '播放' }];
  },

  /// 播放：m3u8 相对路径拼 CDN 主机（6 台都实测通，逐台探一次 #EXTM3U），全挂就回 mp4 直链。
  async content(argument) {
    var settings = argument || {};
    var id = String(settings.chapterId || settings.id || '').trim();
    if (!id || !/^\d+$/.test(id)) throw new Error('缺少视频 id');
    var data = await fetchJson('/json/video/' + id + '.json');
    var playHeaders = mediaHeaders();
    var hlsPath = String(data.m3u8 || '');
    if (hlsPath) {
      for (var index = 0; index < HLS_HOSTS.length; index++) {
        var url = HLS_HOSTS[index] + (hlsPath.charAt(0) === '/' ? hlsPath : '/' + hlsPath);
        try {
          var response = await LumeSource.http.get(url, { headers: playHeaders });
          var body = String((response && response.body) || '');
          if (response && response.status === 200 && body.indexOf('#EXTM3U') >= 0) {
            return { kind: 'video', url: url, headers: playHeaders };
          }
        } catch (error) {
          /* 这台 CDN 不通就试下一台 */
        }
      }
    }
    var mp4 = String(data.mp4 || '');
    if (mp4 && /^https?:\/\//i.test(mp4)) {
      return { kind: 'video', url: mp4, headers: playHeaders };
    }
    // 图文/小说类（tbname=news）或资源下架：交给 App 的网页播放器
    return { kind: 'webplayer', pageUrl: base() + '/video/' + encodeURIComponent(id), headers: playHeaders };
  }
};
