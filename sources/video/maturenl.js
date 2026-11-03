// LumeSource: {"id":"maturenl_video","name":"Mature.nl","version":"1.0.0","category":"video","mirrors":["https://www.mature.nl"]}
//
// 站点：Mature.nl（https://www.mature.nl，"the largest mature porn database on the net"，
// 熟女/年长题材，全站 18+）
// 性质：**会员库**（更新页公开的是每个场景的 **官方预告片 trailer_soft.mp4**），本源取 trailer。
//
// 结构（2026-10-25 实测）：
//   · 更新列表    GET /en/updates
//   · 分类（niche）GET /en/niche/{nicheId}/1/{slug}     例：/en/niche/465/1/40-plus
//   · 模特        GET /en/model/{modelId}/{slug}
//   · 卡片        <div class="card"><div class="card-img"><a href="/en/update/{id}/{slug}">
//                   <img data-src="https://s.cdn.mature.nl/update_support/2/{id}/cs_en.jpg?validfrom=…&validto=…&hash=…"></a>
//                 <div class="card-title"><a href="/en/update/{id}/{slug}">{标题}</a>
//                 <div class="card-subtitle"><a href="/en/model/{id}/{name}">{模特}</a> (45)…
//   · 详情        GET /en/update/{id}/{slug}   标题、poster、`<video id="vidUpdateTrailer">`
//   · 播放        `<source src="https://l.cdn.mature.nl/update_support/2/{id}/trailer_soft.mp4?validfrom=…&validto=…&hash=…">`
//                 **签名带时间窗**（validfrom/validto，约 2 小时），所以每次播放都重新拉更新页；
//                 `&amp;` 要还原成 `&`。全片在会员区（/join）。
var BASE_URL = 'https://www.mature.nl';
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
    Accept: 'text/html,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function getText(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  if (status !== 200) throw new Error('Mature.nl：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

// 卡片：<div class="grid-item"><div class="card">…<a href="/en/update/{id}/{slug}">…data-src="{封面}"
function parseCards(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('class="grid-item"');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 2500);
    var hrefMatch = /href="(\/en\/update\/\d+\/[^"]+)"/.exec(block);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (seen[href]) continue;
    var titleMatch = /class="card-title"[^>]*>[\s\S]{0,80}?<a[^>]*>([\s\S]{0,200}?)<\/a>/.exec(block) ||
      /<a[^>]+href="\/en\/update\/\d+\/[^"]+"[^>]*>([^<]{2,200})<\/a>/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /data-src="([^"]+)"/.exec(block);
    var modelMatch = /href="\/en\/model\/\d+\/([^"]+)"[^>]*>([^<]{1,40})<\/a>/.exec(block);
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1].replace(/&amp;/g, '&')) : '',
      subtitle: modelMatch ? decode(modelMatch[2]) : ''
    });
  }
  return items;
}

// 详情页里的 trailer mp4（签名带时间窗）
function trailerOf(html) {
  var matched = /<source[^>]+src="([^"]+\.mp4[^"]*)"/i.exec(html) ||
    /(https?:\/\/[^"'\s<>]+trailer[^"'\s<>]*\.mp4[^"'\s<>]*)/i.exec(html);
  if (!matched) return '';
  return matched[1].replace(/&amp;/g, '&');
}

var LumeSource = {
  id: 'maturenl_video',
  name: 'Mature.nl',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.mature.nl'],

  async categories() {
    return [
      { id: 'updates', title: '最新更新' },
      { id: 'finest', title: '精选' },
      { id: 'niche:465', title: '40 Plus' },
      { id: 'niche:310', title: 'Big Ass Mature' },
      { id: 'niche:129', title: 'Big Natural Tits' }
    ];
  },

  async home() {
    var html = await getText('/en/updates');
    var items = parseCards(html);
    if (!items.length) throw new Error('Mature.nl：更新页没认出卡片（站点可能改版）');
    return [{ title: '最新更新', moreUrl: 'updates', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'updates';
    var keyword = settings.keyword ? String(settings.keyword).trim().toLowerCase() : '';
    var path;
    if (category.indexOf('niche:') === 0) {
      path = '/en/niche/' + category.slice(6) + '/' + pageNo + '/all';
    } else if (category === 'finest') {
      path = '/en/finestUpdates';
    } else {
      path = '/en/updates' + (pageNo > 1 ? '/' + pageNo : '');
    }
    var html = await getText(path);
    var items = parseCards(html);
    if (keyword) {
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(keyword) >= 0;
      });
    }
    return { items: items, hasMore: items.length >= 12 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var html = await getText(id);
    var titleMatch = /<h1[^>]*>([\s\S]{0,220}?)<\/h1>/.exec(html) || /<title>([\s\S]*?)<\/title>/.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*-\s*Mature\.nl.*$/i, '').trim();
    if (!title) return null;
    var coverMatch = /<video[^>]+poster="([^"]+)"/.exec(html) ||
      /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/.exec(html);
    var descMatch = /<meta[^>]+name="description"[^>]+content="([^"]*)"/.exec(html);
    var trailer = trailerOf(html);
    return {
      id: absolute(id),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1].replace(/&amp;/g, '&')) : '',
      subtitle: trailer ? '官方预告片' : '会员内容',
      description: decode(descMatch ? descMatch[1] : '').slice(0, 300)
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return [];
    var html = await getText(id);
    var trailer = trailerOf(html);
    if (trailer) return [{ id: trailer, title: '官方预告片' }];
    return [{ id: absolute(id), title: '详情页' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id).trim() : '';
    if (chapterId && /\.mp4/i.test(chapterId) && chapterId.indexOf('cdn.mature.nl') >= 0) {
      return {
        kind: 'video',
        url: chapterId.replace(/&amp;/g, '&'),
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    if (!id) throw new Error('Mature.nl：缺少场景地址');
    var html = await getText(id);
    var trailer = trailerOf(html);
    if (trailer) {
      return {
        kind: 'video',
        url: trailer,
        headers: { Referer: absolute(id), 'User-Agent': UA, Accept: '*/*' }
      };
    }
    return { kind: 'webplayer', pageUrl: absolute(id), headers: headers() };
  }
};
