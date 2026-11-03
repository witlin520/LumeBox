// LumeSource: {"id":"zoosexfarm_video","name":"Zoo Sex Farm","version":"1.0.0","category":"video","mirrors":["https://zoosexfarm.com"]}
//
// 站点：Zoo Sex Farm（https://zoosexfarm.com，农场 zoo sex / 兽交题材，全站 18+）
// 结构：纯静态 HTML 老模板（同一套模板也用在 aboutporno.net，只是翻页写法不同）。实测 2026-10-25：
//   · 首页       /index.html                      → 卡片网格
//   · 翻页       /1/index.html、/2/index.html …    → **第 N 页 = /{N-1}/index.html**（0 基）
//   · 卡片       <a href="/{id}-{slug}.html" data-thumb-id="…">
//                  <img src="https://media.zoosexfarm.com/…/10000.jpg">
//                  <span data-length="3:43">3:43</span> <p>标题</p>
//                广告位是 href="/out.cgi?gId=…" 且 <span data-length="AD">，脚本按这两条过滤。
//   · 详情页     <h1>标题</h1> 与
//                <video … poster="…/content/10000.jpg" src="…/content/full.mp4?ahk=…">
//   · 播放       上面那条 mp4 会 **302** 到 st5.mediacnt.com/zoosexfarm.com/…?ahk=…，
//                跟随后 206 + video/mp4（已用 Range 请求实测）。ahk 是带时间戳的签名
//                （…kkkl<epoch>），所以每次播放都重新拉详情页取新地址，不要缓存播放串。
//   · 搜索       站点**没有**搜索：/search/、/search?q=、/?search= 全是 404 或原样返回首页。
//                list({keyword}) 老老实实返回空列表，不编造地址。
//   · 分类       /top/{n}/ 是**友链页**（best FREE PORN sites），点开的条目一律 HTTP 410，
//                不能当分类用；本源因此只提供「最新」一路（靠 /{n}/index.html 翻页）。
//   · 代理       国内直连 TCP 不通（curl 25s 超时），需要给本源配代理。
var BASE_URL = 'https://zoosexfarm.com';
var UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  return (domain || BASE_URL).replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
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
    .replace(/&nbsp;/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function fetchPage(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  if (status === 403 || status === 503 || status === 521) {
    throw new Error('NEED_WEBVIEW_VERIFY：Zoo Sex Farm 被源站 WAF 拦住（HTTP ' + status + '），请给本源配代理或在源设置里走网页视图');
  }
  if (status === 410) throw new Error('这条内容已被源站下架（HTTP 410）：' + url);
  if (status !== 200) throw new Error('Zoo Sex Farm 页面打不开：HTTP ' + status + ' ' + url);
  return { html: String(response.body || ''), url: url };
}

// 第 N 页地址：1 = /index.html，2 = /1/index.html，3 = /2/index.html …
function listPath(pageNo) {
  if (pageNo <= 1) return '/index.html';
  return '/' + (pageNo - 1) + '/index.html';
}

// 卡片：只认 /{数字id}[-slug].html 的详情链接，且时长不是 "AD"（广告位的标记）。
function parseItems(html) {
  var items = [];
  var seen = {};
  var pattern = /<a\b([^>]*)>([\s\S]*?)<\/a>/g;
  var matched;
  while ((matched = pattern.exec(html)) !== null) {
    var attrs = matched[1];
    if (attrs.indexOf('data-thumb-id') < 0) continue;
    var hrefMatch = /href="([^"]+)"/i.exec(attrs);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (!/^\/\d{4,}(?:[-_][^\/]*)?\.html$/.test(href)) continue;
    if (seen[href]) continue;
    var body = matched[2];
    var lengthMatch = /data-length="([^"]*)"/i.exec(body);
    var length = lengthMatch ? decode(lengthMatch[1]) : '';
    if (/^ad$/i.test(length)) continue;
    var titleMatch = /<p>([\s\S]*?)<\/p>/i.exec(body) || /<img[^>]+alt="([^"]*)"/i.exec(body);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /<img[^>]+src="([^"]+)"/i.exec(body);
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: absolute(coverMatch ? coverMatch[1] : ''),
      subtitle: length
    });
  }
  return items;
}

// 是否还有下一页：底部分页条里出现了「下一页」的页码，或者出现了省略号。
function hasMore(html, pageNo) {
  var at = html.indexOf('id="bottomControls"');
  if (at < 0) return false;
  var end = html.indexOf('</div>', at);
  var block = html.slice(at, end < 0 ? Math.min(html.length, at + 3000) : end);
  if (block.indexOf('...') >= 0) return true;
  var currentMatch = /<span class="current">\s*(\d+)\s*<\/span>/.exec(block);
  var current = currentMatch ? Number(currentMatch[1]) : pageNo;
  return new RegExp('>' + (current + 1) + '<').test(block);
}

// 详情页里的播放串：<video src="…full.mp4?ahk=…">
function videoOf(html) {
  var matched = /<video\b[^>]*\bsrc="([^"]+)"/i.exec(html) || /<source\b[^>]*\bsrc="([^"]+)"/i.exec(html);
  if (!matched) return '';
  var url = decode(matched[1]);
  return /\.(mp4|m3u8|webm|flv)(\?|#|$)/i.test(url) ? url : '';
}

function posterOf(html) {
  var matched = /<video\b[^>]*\bposter="([^"]+)"/i.exec(html);
  return matched ? absolute(decode(matched[1])) : '';
}

function videoHeaders() {
  return { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' };
}

var LumeSource = {
  id: 'zoosexfarm_video',
  name: 'Zoo Sex Farm',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://zoosexfarm.com'],

  async categories() {
    // 站点没有可用的分类页（/top/ 是友链，条目全是 410），只给「最新」。
    return [{ id: 'new', title: '最新' }];
  },

  async home() {
    var first = await fetchPage(listPath(1));
    var items = parseItems(first.html);
    if (!items.length) throw new Error('Zoo Sex Farm：首页没认出条目（站点可能改版）');
    return [{ title: '最新更新', moreUrl: 'new', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    if (keyword) {
      // 站点没有搜索接口：返回空列表（不拼接假地址）。
      return { items: [], hasMore: false };
    }
    var page = await fetchPage(listPath(pageNo));
    var items = parseItems(page.html);
    return { items: items, hasMore: hasMore(page.html, pageNo) };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var page = await fetchPage(id);
    var titleMatch = /<h1>([\s\S]*?)<\/h1>/i.exec(page.html);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) return null;
    var direct = videoOf(page.html);
    return {
      id: page.url || absolute(id),
      title: title,
      cover: posterOf(page.html),
      subtitle: direct ? 'MP4 直链' : '网页播放'
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return [];
    // 单视频站点：一集「正片」，id 就是详情页 —— content() 会重新拉详情页取**当次**的
    // 签名播放串（ahk 带时间戳，缓存旧地址会 302 到过期页）。
    return [{ id: absolute(id), title: '正片' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id).trim() : '';
    var target = chapterId || id;
    if (!target) throw new Error('缺少详情页地址');
    if (/\/content\/[^?#]+\.(?:mp4|m3u8|webm|flv)(\?|#|$)/i.test(target)) {
      var body = await LumeSource.http.get(absolute(target), { headers: videoHeaders() });
      var type = body && body.headers ? String(body.headers['content-type'] || '') : '';
      if (body && body.status === 200 && /video|octet-stream/i.test(type)) {
        return { kind: 'video', url: absolute(target), headers: videoHeaders() };
      }
    }
    var page = await fetchPage(target);
    var url = videoOf(page.html);
    if (url) return { kind: 'video', url: url, headers: videoHeaders() };
    return { kind: 'webplayer', pageUrl: page.url || absolute(target), headers: headers() };
  }
};
