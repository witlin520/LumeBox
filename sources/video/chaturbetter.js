// LumeSource: {"id":"chaturbetter_video","name":"Chaturbetter","version":"1.0.0","category":"video","mirrors":["https://chaturbetter.com"]}
//
// 站点：Chaturbetter（https://chaturbetter.com）—— 第三方 Chaturbate 搜索/过滤器前端
// （SvelteKit SSR + Supabase；房间页 `/c/{主播名}`，播放器是 `auth.chaturbetter.com/embed/…` 的 iframe）
//
// 结构（2026-10-25 逐条核过；本机直连不通，全部实测走本机代理出口）：
//   · 首页/列表  GET /                        → 服务端渲染的房间卡片（实测 100 张 / 386KB）
//                GET /?tags={标签}            → 标签筛选（asian / ebony / latina / milf / teen / bbw /
//                                               squirt / anal / bigboobs / trans / blonde / 18 实测都有结果；
//                                               hd / new / couples 返回 0 张，所以没放进分类表）
//                GET /search?search={关键词}  → 站内搜索（实测 asian → 100 张）
//                卡片：<div class="col room_list_room" data-room="{主播}" data-status="public" …
//                       <a class="thumb-box" href="/c/{主播}"><img src="https://thumb.live.mmcdn.com/minifwap/{主播}.jpg?time=">
//   · 无分页     `/?page=2`、`/page/2` 都是同一批数据（前者内容完全相同，后者 404）→ hasMore 恒 false。
//   · 详情      GET /c/{主播}  → og:image（快照）、og:description（房间标题）、<title>{主播} Live Cam …
//   · 播放      **有直链**：房间页 iframe → auth.chaturbetter.com/embed/{主播}/?…，那一页里有一坨
//               双重转义 JSON，字段 `hls_source` 就是
//               https://edge12-sin.live.mmcdn.com/v1/edge/streams/origin.{主播}.{流ID}/llhls.m3u8?token=eyJ…
//               （JS 里写作 `https:\u002F\u002Fedge12\u002Dsin…token\u003DeyJ…`，要把 \u002D → -、
//                \u003D → = 、\u002F → / 解一遍才是真地址）。
//               实测：解出来后直接 GET → 200 + `application/vnd.apple.mpegurl` + `#EXTM3U`，
//               带 `Referer: https://chaturbetter.com/` 播放正常（token 是限时的，所以每次播放都现取 embed）。
//   · 兜底      主播离线 / 私密时 embed 页里没有 hls_source → 退 {kind:'webplayer', pageUrl:'/c/{主播}'}。
var DEFAULT_BASE = 'https://chaturbetter.com';
var EMBED_BASE = 'https://auth.chaturbetter.com/embed/';
var UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
var MAX_CARDS = 120;

// 实测有结果的标签（hd / new / couples 是 0 张，没写进来，免得分类点开是空的）。
var TAGS = [
  { id: '', title: '全部在线' },
  { id: 'asian', title: '亚洲' },
  { id: 'ebony', title: '黑珍珠' },
  { id: 'latina', title: '拉美' },
  { id: 'milf', title: '熟女' },
  { id: 'teen', title: '18+' },
  { id: 'bbw', title: '丰满' },
  { id: 'bigboobs', title: '大胸' },
  { id: 'squirt', title: '潮吹' },
  { id: 'anal', title: '肛' },
  { id: 'blonde', title: '金发' },
  { id: 'trans', title: '跨性别' }
];

var GENDERS = { female: '女', male: '男', couple: '情侣', transgender: '跨性别', trans: '跨性别' };

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function fetchPage(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + path;
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  // 注意：页面正常也带 Turnstile 的 `/cdn-cgi/challenge-platform/…` 脚本，不能拿 challenge-platform 当校验特征。
  if (status === 403 || status === 503 || status === 429 || /Just a moment|cf-mitigated|<title>Attention Required/i.test(body)) {
    throw new Error('NEED_WEBVIEW_VERIFY：Chaturbetter 触发了 Cloudflare 人机校验（HTTP ' + status + '）');
  }
  if (status !== 200) throw new Error('Chaturbetter 页面打不开：HTTP ' + status + ' ' + url);
  return { html: body, url: url };
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
    .replace(/<[^>]+>/g, ' ')
    .replace(/[ \t\r\n]+/g, ' ')
    .trim();
}

// 卡片切分：`data-room="{主播}"` 起头，向后 2600 字符内拿到封面、性别、状态。
function parseRooms(html) {
  var chunks = String(html).split('data-room="');
  var items = [];
  var seen = {};
  for (var index = 1; index < chunks.length && items.length < MAX_CARDS; index++) {
    var chunk = chunks[index].slice(0, 2600);
    var quote = chunk.indexOf('"');
    if (quote <= 0) continue;
    var username = chunk.slice(0, quote).trim();
    if (!username || seen[username]) continue;
    var coverMatch = /<a[^>]+href="\/c\/[^"]+"[^>]*>\s*<img[^>]+src="([^"]+)"/i.exec(chunk);
    if (!coverMatch) continue;
    seen[username] = true;
    var cover = decode(coverMatch[1]).replace(/\?time=$/, '');
    var statusMatch = /data-status="([^"]*)"/i.exec(chunk);
    var genderMatch = /bi-gender-([a-z]+)/i.exec(chunk);
    var parts = [];
    if (genderMatch && GENDERS[genderMatch[1]]) parts.push(GENDERS[genderMatch[1]]);
    if (statusMatch && statusMatch[1]) parts.push(statusMatch[1]);
    items.push({ id: username, title: username, cover: cover, subtitle: parts.join(' · ') });
  }
  return items;
}

// embed 页里的 `hls_source` 是双重转义 JSON：先解 \uXXXX，再找 m3u8。
function unescapeUnicode(text) {
  return String(text).replace(/\\+u([0-9a-fA-F]{4})/g, function (all, hex) {
    return String.fromCharCode(parseInt(hex, 16));
  });
}

function hlsFromEmbed(html) {
  var source = String(html);
  var at = source.indexOf('hls_source');
  var region = at >= 0 ? source.slice(at, at + 3000) : source;
  var decoded = unescapeUnicode(region).replace(/\\\//g, '/');
  var matched = /(https?:\/\/[^"'\s\\]+\.m3u8[^"'\s\\]*)/.exec(decoded);
  return matched ? matched[1] : '';
}

function mediaHeaders() {
  return { 'User-Agent': UA, Referer: base() + '/', Accept: '*/*' };
}

var LumeSource = {
  id: 'chaturbetter_video',
  name: 'Chaturbetter',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://chaturbetter.com'],

  async categories() {
    var rows = [];
    for (var index = 0; index < TAGS.length; index++) {
      rows.push({ id: TAGS[index].id, title: TAGS[index].title });
    }
    return rows;
  },

  /// 首页：全部在线 + 亚洲，两块。
  async home() {
    var boards = [];
    try {
      var all = await fetchPage('/');
      var allItems = parseRooms(all.html).slice(0, 24);
      if (allItems.length) boards.push({ title: '全部在线', moreUrl: '', items: allItems });
    } catch (error) {
      /* 首页挂了就只剩下面那块 */
    }
    try {
      var asian = await fetchPage('/?tags=asian');
      var asianItems = parseRooms(asian.html).slice(0, 24);
      if (asianItems.length) boards.push({ title: '亚洲', moreUrl: 'asian', items: asianItems });
    } catch (error) {
      /* 单个标签失败不影响首页 */
    }
    if (!boards.length) throw new Error('Chaturbetter：首页没认出任何房间卡片（站点可能改版）');
    return boards;
  },

  /// 列表 / 搜索。站点没有分页（实测 ?page=2 同一批），所以 page>1 直接返回空 + hasMore=false。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    if (page > 1) return { items: [], hasMore: false };
    var keyword = settings.keyword ? decode(settings.keyword) : '';
    var category = settings.categoryId == null ? '' : String(settings.categoryId).trim();
    var path;
    if (keyword) {
      path = '/search?search=' + encodeURIComponent(keyword);
    } else if (category) {
      path = '/?tags=' + encodeURIComponent(category);
    } else {
      path = '/';
    }
    var page1 = await fetchPage(path);
    var items = parseRooms(page1.html);
    if (!items.length) console.warn('[chaturbetter] 列表没解析出房间：' + path);
    return { items: items, hasMore: false };
  },

  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return null;
    var page = await fetchPage('/c/' + encodeURIComponent(id));
    var coverMatch = /<meta[^>]+property="og:image"[^>]+content="([^"]*)"/i.exec(page.html) ||
      /<meta[^>]+content="([^"]*)"[^>]+property="og:image"/i.exec(page.html);
    var descMatch = /<meta[^>]+property="og:description"[^>]+content="([^"]*)"/i.exec(page.html) ||
      /<meta[^>]+name="description"[^>]+content="([^"]*)"/i.exec(page.html);
    return {
      id: id,
      title: id,
      cover: coverMatch ? decode(coverMatch[1]) : 'https://thumb.live.mmcdn.com/minifwap/' + id + '.jpg',
      subtitle: 'Chaturbetter 直播间',
      description: descMatch ? decode(descMatch[1]).replace(/\s*·\s*Watch[\s\S]*$/i, '') : ''
    };
  },

  /// 一个直播间 = 一个章节。
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: id, title: '进入直播间' }];
  },

  /// 播放：现取 embed 页 → 从 hls_source 解出 llhls.m3u8（限时 token）；解不到就退 webplayer。
  async content(argument) {
    var id = String((argument && (argument.chapterId || argument.id)) || '').trim();
    if (!id) throw new Error('缺少直播间名');
    var embedUrl =
      EMBED_BASE +
      encodeURIComponent(id) +
      '/?embed_video_only=0&join_overlay=1&disable_sound=0&mobileRedirect=auto&room=' +
      encodeURIComponent(id);
    var playHeaders = mediaHeaders();
    try {
      var response = await LumeSource.http.get(embedUrl, {
        headers: headers({ Referer: base() + '/c/' + encodeURIComponent(id) })
      });
      var body = String((response && response.body) || '');
      var hls = hlsFromEmbed(body);
      if (hls && /^https?:\/\//i.test(hls)) {
        return { kind: 'video', url: hls, headers: playHeaders };
      }
    } catch (error) {
      /* 落到 webplayer */
    }
    // 离线 / 私密 / embed 改版：交给 App 的网页播放器开房间页（页内有 iframe 播放器）。
    return { kind: 'webplayer', pageUrl: base() + '/c/' + encodeURIComponent(id), headers: playHeaders };
  }
};
