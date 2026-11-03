// LumeSource: {"id":"xhamsterlive_video","name":"xHamsterLive","version":"1.0.0","category":"video","mirrors":["https://zh.xhamsterlive.com"]}
//
// 站点：xHamsterLive（= StripChat / strpst 网络的 xHamster 白标直播站；`/couples`、`/men`、
// `/trans`、`/girls` 是四个一级目录）
//
// 结构（2026-10-25 逐条核过；本机直连不通，全部实测走本机代理出口）：
//   · 页面外壳：SSR HTML + 客户端按需拉 JSON。**列表不在 HTML 里**（`window.__PRELOADED_STATE__`
//     的 tagPage.models / allModels 全是空数组），要直接打下面的 JSON 接口。
//   · 移动端 UA 会被拒（HTTP 406 Not Acceptable）→ 本源固定用桌面 UA，别换成 iPhone UA。
//   · 列表      GET /api/front/models?primaryTag={girls|couples|men|trans}&limit=N&offset=M
//               → {models:[…], totalCount, filteredCount}。实测 limit 上限 60（120 → HTTP 400），
//               offset 可以翻到 2000+（没有 1000 条的截断）。primaryTag 必须给，缺了 → 400。
//   · 节目对象  每个 model 自带 hlsPlaylist（例：https://edge-hls.doppiocdn.media/hls/{id}/master/{id}_240p.m3u8）、
//               streamName（实测恒等于数字 id）、previewUrlThumbSmall（封面）、viewersCount、status。
//   · 搜索      GET /search/models/{关键词}（SSR，整页 ~1MB，结果在 __PRELOADED_STATE__ 的
//               modelSearch.models，实测 300 条）。**注意：`/api/front/models?...&search=`、
//               `&searchString=`、`&q=`、`&username=` 全部被服务端忽略（回同一批数据），只有这个
//               SSR 路由真的会过滤；而且搜索结果的 model 不带 hlsPlaylist，所以播放地址只能现拼。
//   · 详情      GET /api/front/models/{数字id} → {id, username, avatarUrl, isLive, isOnline, status}
//               （很小，~250B；房间页 /{username} 是 300KB SSR，没必要）
//   · 播放      不需要 hlsPlaylist 也能拼：https://edge-hls.doppiocdn.media/hls/{id}/master/{id}_{档位}.m3u8
//               档位后缀实测为 720p / 480p / 240p / 160p_blurred（模板来自站内 configV3.initialCommon.hlsStreamUrlTemplate
//               = https://edge-hls.{cdnHost}/hls/{streamName}/master/{streamName}{suffix}.m3u8，
//               defaultHlsStreamHost = doppiocdn.media）。
//               实测：带不带 Referer 都回 200 + #EXTM3U；缺档位回 404（1080p 机器可能只有 720p/480p）。
//               所以 content() 依次试 720p → 480p → 240p，第一个拿到 #EXTM3U 的就用。
//   · 房间页     https://zh.xhamsterlive.com/{username}（根路径，不是 /girls/{username}；后者 404）
//               给 webplayer 兜底用。
//
// 已知限制（写清楚，不美化）：
//   1) 只有四个一级目录有真正的服务端筛选；标签页（tagLanguageChinese 之类）的参数没找到，
//      `/couples/asian` 这类 slug 路由直接 404 → 不编造标签分类。
//   2) 关键词搜索走的是 SSR 整页（~1MB / ~1.1s），比列表接口重；搜索结果按 60 条一页切片。
//   3) 私密 / 票制群秀的房间 m3u8 会拒播，content() 会退成 webplayer。
var DEFAULT_BASE = 'https://zh.xhamsterlive.com';
// 移动端 UA 会被 406，这里固定桌面 UA（站点自己的 SSR 也按 UA 分设备）。
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
var PAGE_SIZE = 60;
var HLS_TEMPLATE = 'https://edge-hls.doppiocdn.media/hls/{id}/master/{id}_{res}.m3u8';
var HLS_PRESETS = ['720p', '480p', '240p'];

var PRIMARY_TAGS = [
  { id: 'girls', title: '女主播' },
  { id: 'couples', title: '情侣' },
  { id: 'men', title: '男主播' },
  { id: 'trans', title: '跨性别' }
];

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function getJson(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + path;
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  if (status !== 200) {
    throw new Error('xHamsterLive 接口打不开：HTTP ' + status + ' ' + url);
  }
  if (/cf-chl-|Just a moment|challenge-platform/i.test(body)) {
    throw new Error('NEED_WEBVIEW_VERIFY：xHamsterLive 触发了 Cloudflare 人机校验，请给本源配代理');
  }
  try {
    return JSON.parse(body);
  } catch (error) {
    throw new Error('xHamsterLive 返回的不是 JSON：' + body.slice(0, 120));
  }
}

async function getHtml(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + path;
  var response = await LumeSource.http.get(url, { headers: headers({ Accept: 'text/html,application/xhtml+xml' }) });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  if (status !== 200) throw new Error('xHamsterLive 页面打不开：HTTP ' + status + ' ' + url);
  return body;
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
    .replace(/\\u002F/gi, '/')
    .replace(/\\u002D/gi, '-')
    .replace(/\\u003D/gi, '=')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[ \t\r\n]+/g, ' ')
    .trim();
}

function numOf(value) {
  var number = Number(value);
  return isFinite(number) && number > 0 ? number : 0;
}

// 从 startIndex 处的 '[' 起做括号配平，返回整段 JSON 数组文本（字符串内的括号不算）。
function jsonArrayAt(html, startIndex) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = startIndex; index < html.length; index++) {
    var ch = html.charAt(index);
    if (inString) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') {
      inString = true;
      continue;
    }
    if (ch === '[') depth++;
    else if (ch === ']') {
      depth--;
      if (depth === 0) return html.slice(startIndex, index + 1);
    }
  }
  return '';
}

function itemOf(model) {
  var id = String(model && model.id != null ? model.id : '').trim();
  if (!id) return null;
  var title = String(model.username || model.displayName || model.display_name || id).trim();
  var cover = String(model.previewUrlThumbSmall || model.previewUrlThumbSmallPath || model.avatarUrl || '').trim();
  if (cover && cover.charAt(0) === '/') cover = 'https://static-proxy.strpst.com' + cover;
  var parts = [];
  if (model.viewersCount) parts.push(Number(model.viewersCount) + ' 人观看');
  if (model.status) parts.push(String(model.status));
  if (model.isHd) parts.push('HD');
  return { id: id, title: title, cover: cover, subtitle: parts.join(' · ') };
}

function itemsOf(models) {
  var items = [];
  for (var index = 0; index < (models || []).length; index++) {
    var item = itemOf(models[index]);
    if (item) items.push(item);
  }
  return items;
}

var LumeSource = {
  id: 'xhamsterlive_video',
  name: 'xHamsterLive',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://zh.xhamsterlive.com'],

  /// 四个一级目录（stripchat 路由正则里就这四段：girls|couples|men|trans），实测都能筛出不同结果集。
  async categories() {
    return PRIMARY_TAGS.slice();
  },

  /// 首页：四个目录各取 24 条（并发）。
  async home() {
    var boards = await Promise.all(
      PRIMARY_TAGS.map(async function (tag) {
        try {
          var data = await getJson('/api/front/models?primaryTag=' + encodeURIComponent(tag.id) + '&limit=24&offset=0');
          return { title: tag.title, moreUrl: tag.id, items: itemsOf(data.models).slice(0, 24) };
        } catch (error) {
          return { title: tag.title, moreUrl: tag.id, items: [] };
        }
      })
    );
    return boards.filter(function (board) {
      return board.items.length > 0;
    });
  },

  /// 列表 / 搜索：目录走 JSON 接口（limit 上限 60），关键词走 SSR 的 /search/models/{kw}。
  async list(argument) {
    var settings = argument || {};
    var page = numOf(settings.page) || 1;
    var keyword = settings.keyword ? decode(settings.keyword) : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'girls';

    if (keyword) {
      var html = await getHtml('/search/models/' + encodeURIComponent(keyword));
      // 页面里 `"modelSearch":` 出现两次：先是全局开关（models 为空数组），后面才是真结果。
      // 用带 id 的数组头定位，避免解析到空的那个。
      var arrayStart = html.indexOf('"models":[{"id":');
      var models = [];
      if (arrayStart >= 0) {
        var raw = jsonArrayAt(html, arrayStart + 9);
        if (raw) {
          try {
            models = JSON.parse(raw);
          } catch (error) {
            models = [];
          }
        }
      }
      var from = (page - 1) * PAGE_SIZE;
      var slice = models.slice(from, from + PAGE_SIZE);
      return { items: itemsOf(slice), hasMore: from + PAGE_SIZE < models.length };
    }

    var known = false;
    for (var index = 0; index < PRIMARY_TAGS.length; index++) {
      if (PRIMARY_TAGS[index].id === category) known = true;
    }
    if (!known) category = 'girls';
    var offset = (page - 1) * PAGE_SIZE;
    var data = await getJson(
      '/api/front/models?primaryTag=' + encodeURIComponent(category) + '&limit=' + PAGE_SIZE + '&offset=' + offset
    );
    var list = itemsOf(data.models);
    return { items: list, hasMore: list.length >= PAGE_SIZE };
  },

  /// 详情：/api/front/models/{数字id}（约 250B）。不拿 300KB 的房间页。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return null;
    var numeric = id.replace(/[^0-9].*$/, '');
    if (!numeric) return null;
    var data;
    try {
      data = await getJson('/api/front/models/' + numeric);
    } catch (error) {
      return { id: numeric, title: numeric, cover: '', subtitle: '', description: '' };
    }
    var parts = [];
    if (data.isLive) parts.push('直播中');
    else if (data.isOnline) parts.push('在线');
    else parts.push('离线');
    if (data.status) parts.push(String(data.status));
    return {
      id: String(data.id || numeric),
      title: String(data.username || numeric),
      cover: String(data.avatarUrl || ''),
      subtitle: parts.join(' · '),
      description: 'xHamsterLive 直播间 / ' + String(data.username || numeric)
    };
  },

  /// 直播站：一个「直播间」章节，播放地址现拼（每次播放都重新探一次档位）。
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    return [{ id: id, title: '进入直播间' }];
  },

  /// 播放：拼 HLS 直链（720p → 480p → 240p），拿不到就退 webplayer（房间页 /{username}）。
  async content(argument) {
    var raw = String((argument && (argument.chapterId || argument.id)) || '').trim();
    var numeric = raw.replace(/[^0-9].*$/, '');
    if (!numeric) throw new Error('缺少直播间数字 id');
    var mediaHeaders = { 'User-Agent': UA, Referer: base() + '/', Accept: '*/*' };
    for (var index = 0; index < HLS_PRESETS.length; index++) {
      var url = HLS_TEMPLATE.replace(/\{id\}/g, numeric).replace(/\{res\}/g, HLS_PRESETS[index]);
      try {
        var response = await LumeSource.http.get(url, { headers: mediaHeaders });
        var body = String((response && response.body) || '');
        if (response && response.status === 200 && body.indexOf('#EXTM3U') >= 0) {
          return { kind: 'video', url: url, headers: mediaHeaders };
        }
      } catch (error) {
        /* 缺档位就试下一档 */
      }
    }
    // 所有档位都没开（离线 / 私密 / 票制群秀）：交给 App 的网页播放器开房间页。
    var username = '';
    try {
      var detail = await getJson('/api/front/models/' + numeric);
      username = String((detail && detail.username) || '');
    } catch (error) {
      username = '';
    }
    return {
      kind: 'webplayer',
      pageUrl: username ? base() + '/' + encodeURIComponent(username) : base() + '/',
      headers: { 'User-Agent': UA, Referer: base() + '/' }
    };
  }
};
