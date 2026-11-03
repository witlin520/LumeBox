// LumeSource: {"id":"kaotic_video","name":"Kaotic","version":"1.0.0","category":"video","mirrors":["https://kaotic.com"]}
//
// 站点：Kaotic（https://kaotic.com，"A Live Leak of Reality" —— 事故 / 暴力 / 战争 / 监控
// 一类**真实事件影像**，含大量血腥画面；不是成人站，但内容极端，观看前自己掂量）
// 结构：服务端渲染 HTML + video.js。实测 2026-10-25（请求全部走本机代理出口）：
//   · 首页/最新    /recent/                → 列表；翻页 /recent/?page=N（1 基，实测 1433 页）
//   · 分类索引     /categories/            → /category/{slug}/ 共 13 个（accident / fight /
//                  funny / justice / medical / other / picture-dump / protests / reposts /
//                  robbery / shooting / war / wtf）
//   · 分类列表     /category/{slug}/       → 有列表，但**不分页**（?page=2 返回同一批，实测集合相同）
//   · 搜索         /mediaSearch/?search=关键词&paged=N（1 基）。注意参数名是 `search`
//                  （表单是 <form action="/mediaSearch/"> name="search"），不是 q。
//   · 卡片         <div class="video"><div class="video-image"><a href="/video/{hash}_{时间戳}_t">
//                  <img src="https://cdn2.kaotic.com/thumbs/…jpg"></a></div>
//                  <h2 class="video-title"><a href="…">标题</a></h2>
//                  <div class="info"><span class="comments">24</span><span class="views">8,450</span></div>
//   · 详情/播放    <video id="container2" … poster="…jpg"><source src="https://cdns2.kaotic.com/
//                  …/xxxx.mp4?validto=…&rlimit=…&hash=…" type="video/mp4">。实测 206 + video/mp4，
//                  带不带 Referer 都能播；签名带 validto 过期时间，所以每次播放现取详情页。
//   · 代理：国内直连 TCP 不通，需要给本源配代理。
var BASE_URL = 'https://kaotic.com';
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
    .replace(/[ \t\r\n]+/g, ' ')
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
  var body = String((response && response.body) || '');
  if (status === 403 || status === 503 || status === 521 || /cf-chl-|Just a moment|challenge-platform/i.test(body)) {
    throw new Error('NEED_WEBVIEW_VERIFY：Kaotic 触发了 Cloudflare 人机校验（HTTP ' + status + '），请给本源配代理或在源设置里走网页视图');
  }
  if (status !== 200) throw new Error('Kaotic 页面打不开：HTTP ' + status + ' ' + url);
  return { html: body, url: url };
}

// 主列表区：第一个 tab-content 列表容器 → 到下一个 <h4>（侧栏「Do Not Miss This」之前）为止。
function listRegion(html) {
  var start = html.indexOf('<div class="tab-content');
  if (start < 0) return html;
  var end = html.indexOf('<h4>', start);
  if (end < 0) end = html.indexOf('Do Not Miss This', start);
  if (end < 0) end = html.length;
  return html.slice(start, end);
}

// /video/{hash}_{yyyymmddhhmmss}_t 里的时间戳 → 2026-10-23
function stampOf(url) {
  var matched = /_(\d{4})(\d{2})(\d{2})\d{6}_/.exec(String(url || ''));
  return matched ? matched[1] + '-' + matched[2] + '-' + matched[3] : '';
}

function parseItems(html) {
  var region = listRegion(html);
  var blocks = region.split('<div class="video">');
  var items = [];
  var seen = {};
  for (var index = 1; index < blocks.length; index++) {
    var block = blocks[index];
    var hrefMatch = /href="(https?:\/\/kaotic\.com\/video\/[^"]+)"/i.exec(block);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (seen[href]) continue;
    var titleMatch = /<h2 class="video-title">\s*<a[^>]*>([\s\S]*?)<\/a>/i.exec(block) ||
      /<img[^>]+alt="([^"]*)"/i.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /<img[^>]+src="([^"]+)"/i.exec(block);
    var viewsMatch = /<span class="views">([\s\S]*?)<\/span>/i.exec(block);
    var parts = [];
    var stamp = stampOf(href);
    if (stamp) parts.push(stamp);
    if (viewsMatch) parts.push(decode(viewsMatch[1]) + ' 次观看');
    seen[href] = true;
    items.push({
      id: href,
      title: title,
      cover: absolute(coverMatch ? coverMatch[1] : ''),
      subtitle: parts.join(' · ')
    });
  }
  return items;
}

function hasMore(html) {
  return /href="[^"]*page=\d+"/i.test(html) || /href="[^"]*paged=\d+"/i.test(html);
}

function metaOf(html, property) {
  var pattern = new RegExp('<meta[^>]+(?:property|name)="' + property + '"[^>]+content="([^"]*)"', 'i');
  var matched = pattern.exec(html);
  if (matched) return decode(matched[1]);
  pattern = new RegExp('<meta[^>]+content="([^"]*)"[^>]+(?:property|name)="' + property + '"', 'i');
  matched = pattern.exec(html);
  return matched ? decode(matched[1]) : '';
}

function videoOf(html) {
  var matched = /<source\b[^>]*\bsrc="([^"]+)"[^>]*type="video\/[^"]*"/i.exec(html) ||
    /<source\b[^>]*\bsrc="([^"]+)"/i.exec(html) ||
    /<video\b[^>]*\bsrc="([^"]+)"/i.exec(html);
  if (!matched) {
    var og = metaOf(html, 'og:video:url') || metaOf(html, 'og:video');
    return og && /\.(mp4|m3u8|webm)(\?|#|$)/i.test(og) ? og : '';
  }
  var url = decode(matched[1]);
  return /\.(mp4|m3u8|webm|flv)(\?|#|$)/i.test(url) ? url : '';
}

function posterOf(html) {
  var og = metaOf(html, 'og:image');
  if (og) return og;
  var matched = /<video\b[^>]*\bposter="([^"]+)"/i.exec(html);
  return matched ? absolute(decode(matched[1])) : '';
}

// 图集条目（/category/picture-dump/ 一类）：<div id="container2"> 里一串
// <div class="full_size_image_wrapper"><span class="inner_counter">1</span><img src="…jpeg">
function imagesOf(html) {
  var images = [];
  var seen = {};
  var pattern = /<div class="full_size_image_wrapper"[\s\S]{0,400}?<img[^>]+src="([^"]+)"/gi;
  var matched;
  while ((matched = pattern.exec(html)) !== null) {
    var url = absolute(decode(matched[1]));
    if (!url || seen[url]) continue;
    seen[url] = true;
    images.push(url);
  }
  if (!images.length) {
    var og = metaOf(html, 'og:video:url');
    if (og && /\.(?:jpe?g|png|webp|gif)(\?|#|$)/i.test(og)) images.push(absolute(og));
  }
  return images;
}

function videoHeaders() {
  return { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' };
}

var FIXED_CATEGORIES = [{ id: 'recent', title: '最新上传' }];

var LumeSource = {
  id: 'kaotic_video',
  name: 'Kaotic',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://kaotic.com'],

  async categories() {
    var cached = await LumeSource.fs.readText('classes.json');
    if (cached) {
      try {
        var hit = JSON.parse(cached);
        if (hit && hit.length) return hit;
      } catch (error) {
        /* 缓存坏了就重抓 */
      }
    }
    var list = FIXED_CATEGORIES.slice();
    try {
      var page = await fetchPage('/categories/');
      var pattern = /href="https?:\/\/kaotic\.com\/category\/([a-z0-9\-]+)\/"[^>]*class="prevent_pop[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
      var matched;
      var seen = { recent: true };
      while ((matched = pattern.exec(page.html)) !== null) {
        var slug = matched[1];
        var title = decode(matched[2]);
        if (!slug || !title || seen[slug]) continue;
        seen[slug] = true;
        list.push({ id: slug, title: title });
      }
    } catch (error) {
      /* 索引页拿不到就只留「最新上传」，不影响浏览 */
    }
    if (list.length) await LumeSource.fs.writeText('classes.json', JSON.stringify(list));
    return list;
  },

  async home() {
    var page = await fetchPage('/recent/');
    var items = parseItems(page.html);
    if (!items.length) throw new Error('Kaotic：首页没认出条目（站点可能改版）');
    return [{ title: '最新上传', moreUrl: 'recent', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';
    var path;
    var paged = true;
    if (keyword) {
      path = '/mediaSearch/?search=' + encodeURIComponent(keyword) + (pageNo > 1 ? '&paged=' + pageNo : '');
    } else if (category && category !== 'recent') {
      path = '/category/' + encodeURIComponent(category) + '/';
      paged = false; // 分类页不分页（?page=2 是同一批，实测）
    } else {
      path = '/recent/' + (pageNo > 1 ? '?page=' + pageNo : '');
    }
    var page = await fetchPage(path);
    var items = parseItems(page.html);
    return { items: items, hasMore: paged && items.length > 0 && hasMore(page.html) };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var page = await fetchPage(id);
    var title = metaOf(page.html, 'og:title');
    if (!title) {
      var heading = /<h1[^>]*>([\s\S]*?)<\/h1>/i.exec(page.html);
      title = heading ? decode(heading[1]) : '';
    }
    if (!title) return null;
    var parts = [];
    var stamp = stampOf(page.url || id);
    if (stamp) parts.push(stamp);
    var categoryMatch = /<a[^>]+href="https?:\/\/kaotic\.com\/category\/[a-z0-9\-]+\/"[^>]*>([^<]{1,40})<\/a>/i.exec(page.html);
    if (categoryMatch) parts.push(decode(categoryMatch[1]));
    return {
      id: page.url || absolute(id),
      title: title,
      cover: posterOf(page.html),
      subtitle: parts.join(' · '),
      description: metaOf(page.html, 'og:description')
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return [];
    // 单视频站点：一集「正片」，id 就是详情页；content() 现取详情页拿当次签名直链。
    return [{ id: absolute(id), title: '正片' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id).trim() : '';
    var target = chapterId || id;
    if (!target) throw new Error('缺少详情页地址');
    if (/\.(?:mp4|m3u8|webm|flv)(\?|#|$)/i.test(target) && target.indexOf('/video/') < 0) {
      return { kind: 'video', url: absolute(target), headers: videoHeaders() };
    }
    var page = await fetchPage(target);
    var url = videoOf(page.html);
    if (url) return { kind: 'video', url: url, headers: videoHeaders() };
    // 没有 mp4 的是图集条目（picture post）：直接给图片列表，走 App 的图片查看器。
    var images = imagesOf(page.html);
    if (images.length) {
      return { kind: 'images', images: images, headers: headers({ Accept: 'image/avif,image/webp,image/*,*/*;q=0.8' }) };
    }
    // 两者都没有：交给 App 的网页播放器直接开页面。
    return { kind: 'webplayer', pageUrl: page.url || absolute(target), headers: headers() };
  }
};
