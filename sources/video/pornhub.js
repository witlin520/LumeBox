// LumeSource: {"id":"pornhub_video","name":"Pornhub","version":"1.0.0","category":"video","mirrors":["https://www.pornhub.com"]}
//
// 站点：Pornhub（https://www.pornhub.com，全品类综合大站，全站 18+）
//
// 结构（2026-10-25 实测，curl 直连可拿，不需要浏览器）：
//   · 最新列表    GET /video?page=N                 每页 60+ 卡片，分页 `/video?page=2`、`?page=3`…
//   · 分类列表    GET /video?c={分类id}[&page=N]     分类 id 从首页 `/video?c=` 链接里取
//   · 卡片        <li … data-video-vkey="{vkey}" data-video-id="{id}" …>
//                   <a href="/view_video.php?viewkey={vkey}" title="{标题}">
//                     <img … src="{封面}">
//   · 详情        GET /view_video.php?viewkey={vkey}   标题 h1、封面 og:image、简介
//   · 播放        **两个坑，都实测过**：
//       1) 页面里 `mediaDefinitions` 给出 1080/480/240 的 **HLS**：
//          https://hv-h.phncdn.com/hls/{path}/{NNNP_XXXXK}.mp4/master.m3u8?h=…&e=…
//          直接请求会回 **410 Gone**；带上请求头 `Platform: pc`（+ Referer 首页）才回 **200（master.m3u8）**。
//          所以 headers 里固定加 `Platform: pc`。
//       2) `ev.phncdn.com/…/240P_1000K_….mp4?validfrom=…&validto=…` 是**渐进 mp4 兜底**（实测 206 video/mp4），
//          HLS 拿不到时用它。
//   · 失效        `/video/get_media?vkey=…` 现在返回 `[]`（老接口已废，别依赖）
var BASE_URL = 'https://www.pornhub.com';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

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
    Platform: 'pc',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function getText(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  if (status !== 200) throw new Error('Pornhub：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

// 卡片：data-video-vkey 分组
function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('data-video-vkey="');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 3000);
    var vkeyMatch = /^([a-z0-9]+)"/.exec(block);
    if (!vkeyMatch) continue;
    var vkey = vkeyMatch[1];
    if (seen[vkey]) continue;
    var titleMatch = /title="([^"]{2,300})"/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var imgMatch = /<img[^>]+(?:src|data-src|data-image)="(https:\/\/[^"]+)"/.exec(block);
    var durMatch = /class="[^"]*duration[^"]*"[^>]*>([^<]{0,12})</.exec(block);
    seen[vkey] = true;
    items.push({
      id: vkey,
      title: title,
      cover: imgMatch ? absolute(imgMatch[1]) : '',
      subtitle: durMatch ? decode(durMatch[1]) : ''
    });
  }
  return items;
}

// 从 mediaDefinitions 里挑 HLS（优先 1080 > 720 > 480 > 240），再退 240P 渐进 mp4
function mediaOf(html) {
  var hls = [];
  var defs = /"videoUrl":"([^"]+)"/g;
  var matched;
  while ((matched = defs.exec(html)) !== null) {
    var url = matched[1].replace(/\\\//g, '/').replace(/&amp;/g, '&');
    if (url.indexOf('.m3u8') < 0) continue;
    var qualityMatch = /(\d{3,4})P_/.exec(url);
    hls.push({ quality: qualityMatch ? Number(qualityMatch[1]) : 0, url: url });
  }
  hls.sort(function (a, b) { return b.quality - a.quality; });
  if (hls.length) return { kind: 'hls', url: hls[0].url, quality: hls[0].quality };
  var mp4 = /(https:\/\/ev\.phncdn\.com\/[^"'\s\\]+\.mp4\?[^"'\s\\]+)/.exec(html);
  if (mp4) return { kind: 'mp4', url: mp4[1].replace(/&amp;/g, '&'), quality: 240 };
  return null;
}

var LumeSource = {
  id: 'pornhub_video',
  name: 'Pornhub',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.pornhub.com'],

  async categories() {
    var list = [{ id: 'newest', title: '最新' }];
    try {
      var html = await getText('/');
      var pattern = /href="\/video\?c=(\d+)"[^>]*>([^<]{2,30})</g;
      var matched;
      var seen = {};
      while ((matched = pattern.exec(html)) !== null) {
        var id = matched[1];
        var title = decode(matched[2]);
        if (!id || !title || seen[id]) continue;
        seen[id] = true;
        list.push({ id: id, title: title });
      }
    } catch (error) {
      /* 只留「最新」 */
    }
    return list;
  },

  async home() {
    var html = await getText('/video');
    var items = parseItems(html);
    if (!items.length) throw new Error('Pornhub：列表页没认出卡片（可能被风控或改版）');
    return [{ title: '最新', moreUrl: 'newest', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'newest';
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var path;
    if (keyword) {
      path = '/video/search?search=' + encodeURIComponent(keyword) + (pageNo > 1 ? '&page=' + pageNo : '');
    } else if (/^\d+$/.test(category)) {
      path = '/video?c=' + category + (pageNo > 1 ? '&page=' + pageNo : '');
    } else {
      path = '/video' + (pageNo > 1 ? '?page=' + pageNo : '');
    }
    var html = await getText(path);
    var items = parseItems(html);
    return { items: items, hasMore: items.length >= 20 };
  },

  async detail(argument) {
    var vkey = argument && argument.id ? String(argument.id).replace(/[^a-z0-9]/gi, '') : '';
    if (!vkey) return null;
    var html = await getText('/view_video.php?viewkey=' + vkey);
    var titleMatch = /<h1[^>]*class="[^"]*title[^"]*"[^>]*>([\s\S]{0,300}?)<\/h1>/.exec(html) ||
      /<title>([\s\S]*?)<\/title>/i.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*-\s*Pornhub\.com\s*$/i, '').trim();
    if (!title) return null;
    var coverMatch = /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/.exec(html);
    var descMatch = /<meta[^>]+name="description"[^>]+content="([^"]*)"/.exec(html);
    return {
      id: vkey,
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: '综合',
      description: decode(descMatch ? descMatch[1] : '').slice(0, 300)
    };
  },

  async chapters(argument) {
    var vkey = argument && argument.id ? String(argument.id).replace(/[^a-z0-9]/gi, '') : '';
    if (!vkey) return [];
    var html = await getText('/view_video.php?viewkey=' + vkey);
    var media = mediaOf(html);
    if (media) return [{ id: media.url, title: media.kind === 'hls' ? (media.quality + 'p') : '240p' }];
    return [{ id: vkey, title: '正片' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var vkey = argument && argument.id ? String(argument.id).replace(/[^a-z0-9]/gi, '') : '';
    if (chapterId && /\.(m3u8|mp4)/i.test(chapterId)) {
      return {
        kind: 'video',
        url: chapterId.replace(/&amp;/g, '&'),
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*', Platform: 'pc' }
      };
    }
    if (!vkey) throw new Error('Pornhub：缺少 viewkey');
    var html = await getText('/view_video.php?viewkey=' + vkey);
    var media = mediaOf(html);
    if (media) {
      return {
        kind: 'video',
        url: media.url,
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*', Platform: 'pc' }
      };
    }
    return { kind: 'webplayer', pageUrl: base() + '/view_video.php?viewkey=' + vkey, headers: headers() };
  }
};
