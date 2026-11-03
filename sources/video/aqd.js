// LumeSource: {"id":"aqd_video","name":"爱情岛","version":"1.0.0","category":"video","mirrors":["https://38.148.206.8:20955"]}
//
// 站点：爱情岛论坛 / AQDLT（aqd1.vip … 视频站本体「亚洲品质自拍视频网站」）
//
// ── 入口链路（2026-10-25 实测，走本机代理出口）
//   · http://38.148.206.8:30018/  → 302 → https://38.148.206.8:20955/（同一个 nginx，
//     所有子路径同样 302，例如 /videos/category/cn.html → https://…:20955/videos/category/cn.html）。
//   · aqd1.vip / www.aqd1.vip 现在**不再指向站点本身**：DNS 解析到 192.238.196.52:8443 的
//     广告停放页（4KB，title「如遇到打不开，请输入域名：aqd1.vip …」是站点标题，但内容是跳转壳），
//     所以 mirrors 只写实测能出内容的那个 https 入口。
//   · 证书：CN=38.148.206.9，但 SAN 里带 `IP Address:38.148.206.8`（另含 .7/.15/.16/.17/.23/.24/.25），
//     签发者是 SSL.com RSA SSL subCA（2027-04 到期）。**不需要跳过证书校验**：
//     curl 不带 -k、Node 原生 fetch 直接 GET https://38.148.206.8:20955/ 都是 200，
//     只有打到 SAN 之外的 IP（例如同段别的地址）才会 hostname mismatch。
//
// ── 混淆层：`<script id='crypt_html_js'>` + `crypt_eval_js`
//   页面 251KB，正文不是明文：`var html = 'A0%E3%lmthF2%C3%…';` 是完全百分号编码后
//   **整串字符反转**的 HTML。页面自己的脚本就一句
//   `document.write(decodeURIComponent(html.split('').reverse().join('')))`。
//   解码 = 取 `var html = '…'` 的字符串 → `split('').reverse().join('')` → `decodeURIComponent`
//   （反转后 `%3C…` 三元组恰好恢复原序，不需要额外修 %, 实测直接 decodeURIComponent 不抛错）。
//   251KB → 明文 99KB（首页）/ 58KB（播放页）。本源每次请求都过一遍 decode()。
//
// ── 站点结构（全部实测）
//   · 首页      GET /                     → 分段：「今日更新視頻 15 個」「今日推薦」「共 50,106 個視頻」
//   · 地区目录  GET /videos/category/{cn|west|jp|kr|hk|tw|southeast-asia}.html
//   · 标签目录  GET /videos/tag/{slug}.html   （uncensored / cartoon / zipai / toupai / caption / sm / cosplay / …）
//   · 分页      /videos/category/{slug}/{page}.html（第 2 页起；实测每页 18 条卡片）
//   · 搜索      GET /videos/search.html?key={关键词}（实测「学妹」→「共找到 592 個視頻」，同样每页 18 条）
//   · 卡片      <div class="thumbnail" node-type="video" data-video-id="{id}">
//                 <a href="/videos/play/{id}.html" alt="{标题}"> … <img data-original="{封面}">
//                 <span class="video-duration">{时长}</span>
//               封面在图床 https://img{0-14}.fuqiu1688.com:606/thumbs/…（实测直连 200 image/jpeg，无 Referer 也行）
//   · 详情页    GET /videos/play/{id}.html：og:title / og:image、.video-player-title h3、
//               .detail-video-cate（分類）、.detail-video-views（次觀看）、.detail-video-date（上傳時間）、
//               .video-metas-tag（標籤按钮）
//   · 播放地址  **在详情页 HTML 里明文**：`let video_url = 'https://cdn.aqd-tv.com/video/{hash}/playlist/{hash}.m3u8';`
//               实测 GET → 200 + `application/vnd.apple.mpegurl` + `#EXTM3U`（媒体播放列表，.ts 分片），
//               带不带 Referer 都能播；页面播放器是 artplayer + hls.js。
//               页码/播放地址是「每帖现取」，所以 content() 每次都重新抓详情页（不缓存）。
//
// 说明：这不是论坛帖图站，落地页就是视频站本体（论坛版块在 /permalink.html 那套跳转里已经 404 化），
// 所以本源按「视频列表 → 详情 → m3u8」做，不做图片源。
var DEFAULT_BASE = 'https://38.148.206.8:20955';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

// 地区（实测 7 个都有内容）
var AREAS = [
  { id: 'category/cn.html', title: '中國・大陸' },
  { id: 'category/west.html', title: 'West・歐美' },
  { id: 'category/jp.html', title: 'Japan・日本' },
  { id: 'category/kr.html', title: '韓國・대한' },
  { id: 'category/hk.html', title: '中國・香港' },
  { id: 'category/tw.html', title: '中國・台灣' },
  { id: 'category/southeast-asia.html', title: 'Asia・東南亞' }
];

// 标签（都实测有 18 条卡片；没验证过的 slug 不写，免得点开空白）
var TAGS = [
  { id: 'tag/zipai.html', title: '自拍' },
  { id: 'tag/toupai.html', title: '偷拍' },
  { id: 'tag/uncensored.html', title: '無碼' },
  { id: 'tag/caption.html', title: '中文字幕' },
  { id: 'tag/cartoon.html', title: 'H動畫' },
  { id: 'tag/woman.html', title: '少婦' },
  { id: 'tag/student.html', title: '學生' },
  { id: 'tag/teacher.html', title: '老師' },
  { id: 'tag/model.html', title: '嫩模' },
  { id: 'tag/celebrity.html', title: '網紅' },
  { id: 'tag/anchor.html', title: '主播' },
  { id: 'tag/big-breast.html', title: '巨乳' },
  { id: 'tag/beauty-leg.html', title: '美腿' },
  { id: 'tag/stockings.html', title: '絲襪' },
  { id: 'tag/uniform.html', title: '制服誘惑' },
  { id: 'tag/cosplay.html', title: 'Cosplay' },
  { id: 'tag/hotel.html', title: '酒店' },
  { id: 'tag/car.html', title: '車震' },
  { id: 'tag/outside.html', title: '野外' },
  { id: 'tag/sm.html', title: 'SM' },
  { id: 'tag/homosexual.html', title: '同性' },
  { id: 'tag/other.html', title: '另類' }
];

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

// crypt_html_js 解码：取 var html = '…' → 反转 → decodeURIComponent。
function decodeCrypt(raw) {
  var text = String(raw == null ? '' : raw);
  if (text.indexOf('crypt_html_js') < 0) return text; // 已经是明文
  var match = /var\s+html\s*=\s*'([\s\S]*?)';/.exec(text);
  if (!match) return text;
  var reversed = match[1].split('').reverse().join('');
  try {
    return decodeURIComponent(reversed);
  } catch (error) {
    // 极端情况：反转后有孤立 %xx（不该出现），退化成手工解 %XX，非 %XX 段原样保留
    var out = '';
    for (var index = 0; index < reversed.length; index++) {
      var ch = reversed.charAt(index);
      if (ch === '%' && /^[0-9a-fA-F]{2}$/.test(reversed.substr(index + 1, 2))) {
        out += String.fromCharCode(parseInt(reversed.substr(index + 1, 2), 16));
        index += 2;
      } else {
        out += ch;
      }
    }
    return out;
  }
}

async function getHtml(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + path;
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  if (status !== 200) throw new Error('爱情岛页面打不开：HTTP ' + status + ' ' + url);
  return decodeCrypt(body);
}

function decode(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#(\d+);/g, function (all, code) {
      return String.fromCharCode(Number(code));
    })
    .replace(/\\\//g, '/')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[ \t\r\n]+/g, ' ')
    .trim();
}

// 卡片切分：每个 <div class="thumbnail" node-type="video" 一块，取 id / 标题 / 封面 / 时长。
function parseCards(html) {
  var chunks = String(html).split('<div class="thumbnail" node-type="video"');
  var items = [];
  for (var index = 1; index < chunks.length; index++) {
    var chunk = chunks[index].slice(0, 2400);
    var idMatch = /data-video-id="(\d+)"/.exec(chunk);
    if (!idMatch) continue;
    var hrefMatch = /href="(\/videos\/play\/\d+\.html)"/.exec(chunk);
    var altMatch = /<a[^>]*alt="([^"]*)"/.exec(chunk) || /<img[^>]*alt="([^"]*)"/.exec(chunk);
    var coverMatch = /data-original="([^"]+)"/.exec(chunk) || /src="([^"]*fuqiu1688[^"]*)"/.exec(chunk);
    var durationMatch = /class="video-duration">([^<]*)</.exec(chunk);
    var title = altMatch ? decode(altMatch[1]) : '';
    if (!title) continue;
    var parts = [];
    if (durationMatch && durationMatch[1].trim()) parts.push(durationMatch[1].trim());
    if (hrefMatch) parts.push('play/' + idMatch[1]);
    items.push({
      id: idMatch[1],
      title: title,
      cover: coverMatch ? decode(coverMatch[1]) : '',
      subtitle: parts[0] || ''
    });
  }
  return items;
}

function pagePath(categoryId, page) {
  var id = String(categoryId || '').trim().replace(/^\/+/, '');
  if (!id) id = AREAS[0].id;
  // 只允许本站已知的两类目录，别处传进来的脏值退回第一类
  if (!/^(category|tag)\/[a-z-]+\.html$/.test(id)) {
    var known = false;
    for (var index = 0; index < AREAS.length; index++) if (AREAS[index].id === id) known = true;
    for (var index2 = 0; index2 < TAGS.length; index2++) if (TAGS[index2].id === id) known = true;
    if (!known) id = AREAS[0].id;
  }
  var stem = id.replace(/\.html$/, '');
  if (!page || page <= 1) return '/videos/' + id;
  return '/videos/' + stem + '/' + page + '.html';
}

var LumeSource = {
  id: 'aqd_video',
  name: '爱情岛',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://38.148.206.8:20955'],

  /// 分类：7 个地区 + 22 个标签（全部实测有卡片）。
  async categories() {
    var rows = [];
    for (var index = 0; index < AREAS.length; index++) rows.push({ id: AREAS[index].id, title: AREAS[index].title });
    for (var index2 = 0; index2 < TAGS.length; index2++) rows.push({ id: TAGS[index2].id, title: TAGS[index2].title });
    return rows;
  },

  /// 首页：直接切首页的三个分段（今日更新 / 今日推薦 / 最新视频）。
  async home() {
    var html = await getHtml('/');
    var parts = String(html).split('<div class="page-result">');
    var boards = [];
    for (var index = 1; index < parts.length; index++) {
      var chunk = parts[index];
      // 分段标题就是 page-result 之后到第一个标签前的那几个字：
      // 「今日更新視頻 <span>15</span> 個」/「今日推薦」/「共 50,106 個視頻」
      var labelMatch = /^([^<]{1,40})/.exec(chunk);
      var label = labelMatch ? decode(labelMatch[1]) : '';
      if (/^共/.test(label)) label = '最新上線';
      if (!label) label = '爱情岛';
      var items = parseCards(chunk).slice(0, 18);
      if (!items.length) continue;
      boards.push({ title: label || '爱情岛', moreUrl: AREAS[0].id, items: items });
      if (boards.length >= 3) break;
    }
    if (!boards.length) {
      // 首页结构变了也别整个空手：退回第一个地区目录
      var fallback = parseCards(await getHtml(pagePath(AREAS[0].id, 1))).slice(0, 18);
      if (fallback.length) boards.push({ title: AREAS[0].title, moreUrl: AREAS[0].id, items: fallback });
    }
    if (!boards.length) throw new Error('爱情岛：首页没解析出任何视频卡片（站点可能改版）');
    return boards;
  },

  /// 列表 / 搜索。categoryId = 'category/cn.html' 或 'tag/zipai.html'；page 从 1 起。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var path;
    if (keyword) {
      // 搜索结果同样分页：/videos/search.html?key=…（第 2 页起参数是否被认没验证，所以只给第一页）
      path = '/videos/search.html?key=' + encodeURIComponent(keyword);
      if (page > 1) return { items: [], hasMore: false };
    } else {
      path = pagePath(settings.categoryId, page);
    }
    var html = await getHtml(path);
    var items = parseCards(html);
    return { items: items, hasMore: items.length > 0 };
  },

  /// 详情：og:title / og:image + 分類/观看/上传时间/标签。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return null;
    var html = await getHtml('/videos/play/' + encodeURIComponent(id) + '.html');
    var ogTitle = /<meta[^>]+property="og:title"[^>]+content="([^"]*)"/i.exec(html);
    var ogImage = /<meta[^>]+property="og:image"[^>]+content="([^"]*)"/i.exec(html);
    var h3 = /<div class="video-player-title">[\s\S]{0,200}?<h3>([\s\S]{0,300}?)<\/h3>/i.exec(html);
    var cate = /<span class="detail-video-cate">([\s\S]{0,200}?)<\/span>/i.exec(html);
    var views = /<span class="detail-video-views">([\s\S]{0,80}?)<\/span>/i.exec(html);
    var date = /<span class="detail-video-date">([\s\S]{0,80}?)<\/span>/i.exec(html);
    var tagBlock = /<div class="video-metas video-metas-tag">([\s\S]{0,2000}?)<\/div>/i.exec(html);
    var tags = [];
    if (tagBlock) {
      var tagMatches = tagBlock[1].match(/<button[^>]*>([\s\S]{0,40}?)<\/button>/gi) || [];
      for (var index = 0; index < tagMatches.length; index++) {
        var name = decode(tagMatches[index]);
        if (name) tags.push(name);
      }
    }
    var title = (ogTitle && decode(ogTitle[1])) || (h3 && decode(h3[1])) || id;
    var parts = [];
    if (cate) parts.push(decode(cate[1]));
    if (views) parts.push(decode(views[1]));
    if (date) parts.push(decode(date[1]));
    return {
      id: id,
      title: title,
      cover: ogImage ? decode(ogImage[1]) : '',
      subtitle: parts.join(' · '),
      description: tags.length ? '標籤：' + tags.join(' / ') : '爱情岛论坛 · 视频 ' + id
    };
  },

  /// 单个视频就是一个「章节」，标题用详情页标题（取不到就编号）。
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: id, title: '播放' }];
  },

  /// 播放：详情页里 `let video_url = '…m3u8'` 现取现用（页面自带 artplayer+hls.js）。
  async content(argument) {
    var settings = argument || {};
    var id = String(settings.chapterId || settings.id || '').trim();
    if (!id) throw new Error('缺少视频 id');
    var mediaHeaders = { 'User-Agent': UA, Referer: base() + '/', Accept: '*/*' };
    var html = await getHtml('/videos/play/' + encodeURIComponent(id) + '.html');
    var matched = /video_url\s*=\s*'([^']+)'/.exec(html) || /video_url\s*=\s*"([^"]+)"/.exec(html);
    var url = matched ? matched[1] : '';
    if (url && /^https?:\/\//i.test(url)) {
      return { kind: 'video', url: url, headers: mediaHeaders };
    }
    // 兜底：有些帖子只有播放器 iframe / 广告流，交给 App 的网页播放器开详情页
    return {
      kind: 'webplayer',
      pageUrl: base() + '/videos/play/' + encodeURIComponent(id) + '.html',
      headers: { 'User-Agent': UA, Referer: base() + '/' }
    };
  }
};
