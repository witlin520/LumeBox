// LumeSource: {"id":"pica177_comic","name":"177漫畫","version":"1.0.0","category":"comic","mirrors":["https://www.177pica.com"]}
//
// 站点：177漫畫 https://www.177pica.com （WordPress + azzxx 主题，日文/中文成人 H 漫 + 全彩 CG，18+）
//
// 结构（2026-10-25 逐页 curl 实测，全部直连 200；首页 53KB / 分类页 50KB / 文章页 54KB）：
//   · 首页      /                            最新文章（20 条/页），翻页 /page/{n}/
//   · 分类      /html/category/{jj|tt|cg}/    jj=日文成人H漫畫、tt=中文成人H漫畫、cg=全彩CG
//               翻页 /html/category/{jj|tt|cg}/page/{n}/（jj 实测 630 页）
//   · 搜索      /?s={词}（WordPress 原生），翻页 /page/{n}/?s={词}
//   · 卡片      <article class="picture …">
//                 <a href="https://www.177pica.com/html/2026/10/8801651.html">
//                   <img src="…/timthumb.php?src=http://img.177pica.com/uploads/2026/02a/000438-38.jpg&w=280&h=210&a=t&zc=1"
//                        alt="アクションピザッツ 2025年3月号 [DL版][370P]"></a>
//                 <h2 class="grid-title"><a href="…">标题</a></h2>
//               永久链接形态是 **/html/{yyyy}/{mm}/{id}.html**（不是 /html/{id}/10/{id}.html，
//               那种是老域名的路由，现站在用日期路径），所以列表只认 href，不拼 URL。
//   · 文章页    单篇图集：<div class="single-content"> 里逐页
//               <img src="data:image/svg+xml,…" data-lazy-src="http://img.177pica.com/uploads/…jpg">
//               + 紧跟一个 <noscript><img src="http://img.177pica.com/…jpg"></noscript>
//               → 真图就在 data-lazy-src（懒加载占位符是 svg data URI，必须跳过）。
//   · **文章内部分页**（关键坑）：一篇杂志扫图会被 WP 的 <!--nextpage--> 切成很多段，
//               每段 HTML 只放 **5 张**图，其余在
//               /html/{y}/{m}/{id}.html/{n}/（n=2..N）。实测 8801657 共 **91 段**（≈455 张）、
//               8801651 共 74 段。所以「一篇 = 一集」讲不通：直接当一集只能拿到 5 张。
//               本源的切法：每 **5 段** 合成一「話」（≈25 张图），chapter id 形如
//               `https://…/8801657.html?lp=6`（lp = 起始段号），content() 并行取 5 段拼图。
//               这样既无损又不把 91 次请求塞进一次 content() 里。
//   · 图床      img.177pica.com，html 里写的是 http://；实测 **https 同样 200**（478KB image/jpeg），
//               统一升成 https 免得 App 里被明文 http 拦。
//   · 封面      timthumb.php 缩略（280×210，28KB）实测 200，直接用，不必回源取大图。
var DEFAULT_BASE = 'https://www.177pica.com';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
// 每 5 个文章内部段合成一「話」（≈25 张图）；段是站点自己的 <!--nextpage--> 切分，每段固定 5 张。
var SEGMENTS_PER_CHAPTER = 5;

var CATEGORIES = [
  { id: 'jj', title: '日文成人H漫畫' },
  { id: 'tt', title: '中文成人H漫畫' },
  { id: 'cg', title: '全彩CG' }
];

var CATEGORY_NAMES = {
  jj: '日文成人H漫畫',
  tt: '中文成人H漫畫',
  cg: '全彩CG'
};

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
}

function https(url) {
  return String(url || '').replace(/^http:\/\//i, 'https://');
}

function decode(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, function (all, hex) {
      return String.fromCharCode(parseInt(hex, 16));
    })
    .replace(/&#(\d+);/g, function (all, code) {
      return String.fromCharCode(Number(code));
    })
    .replace(/&nbsp;/g, ' ')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Referer: base() + '/'
  };
  for (var key in extra || {}) {
    if (Object.prototype.hasOwnProperty.call(extra, key)) result[key] = extra[key];
  }
  return result;
}

async function getHtml(path) {
  var url = /^https?:\/\//i.test(path) ? path : base() + (String(path).charAt(0) === '/' ? path : '/' + path);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var body = String((response && response.body) || '');
  if (status !== 200) throw new Error('177漫畫 页面打不开：HTTP ' + status + ' ' + url);
  if (body.length < 1500) {
    throw new Error('177漫畫 返回了空页面（' + body.length + ' 字节）：' + url);
  }
  return body;
}

// ---------------------------------------------------------------- 列表解析
function postIdOf(url) {
  var matched = /\/html\/\d{4}\/\d{2}\/(\d+)\.html/.exec(url);
  return matched ? matched[1] : '';
}

function parseCards(pageHtml) {
  var items = [];
  var seen = {};
  var pattern = /<article class="picture[\s\S]*?<\/article>/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var block = matched[0];
    var linkMatch = /href="(https?:\/\/[^"]+\/html\/\d{4}\/\d{2}\/\d+\.html)"/i.exec(block);
    if (!linkMatch) continue;
    var url = linkMatch[1];
    if (seen[url]) continue;

    var imgMatch = /<img[^>]+src="([^"]+)"[^>]*alt="([^"]*)"/i.exec(block) ||
      /<img[^>]+alt="([^"]*)"[^>]*src="([^"]+)"/i.exec(block);
    var cover = imgMatch ? decode(imgMatch[1]) : '';
    if (cover && !/^https?:\/\//i.test(cover)) cover = absolute(cover);

    var titleMatch = /<h2[^>]*class="grid-title"[^>]*>[\s\S]{0,200}?<a[^>]*>([\s\S]{0,240}?)<\/a>/i.exec(block) ||
      /<img[^>]+alt="([^"]*)"/i.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;

    var pagesMatch = /\[(\d+)P\]/i.exec(title);
    var catMatch = /\/html\/category\/([a-z\-]+)\//.exec(block);
    var parts = [];
    if (catMatch && CATEGORY_NAMES[catMatch[1]]) parts.push(CATEGORY_NAMES[catMatch[1]]);
    if (pagesMatch) parts.push(pagesMatch[1] + ' 页');

    seen[url] = true;
    items.push({
      id: url,
      title: title,
      cover: cover,
      subtitle: parts.join(' · ')
    });
  }
  return items;
}

function maxPageOf(pageHtml, pathPrefix) {
  var max = 0;
  var pattern = new RegExp(pathPrefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + 'page\\/(\\d+)\\/', 'g');
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var value = Number(matched[1]);
    if (value > max) max = value;
  }
  return max;
}

// ---------------------------------------------------------------- 文章解析
function postTitle(pageHtml) {
  var matched = /<h1[^>]*class="entry-title"[^>]*>([\s\S]{0,300}?)<\/h1>/i.exec(pageHtml) ||
    /<title>([\s\S]*?)<\/title>/i.exec(pageHtml);
  return decode(matched ? matched[1] : '').replace(/\s*\|\s*177漫畫\s*$/, '');
}

function postCategory(pageHtml) {
  var matched = /<div class="single-cat">[\s\S]{0,200}?<a[^>]*>([\s\S]{0,120}?)<\/a>/i.exec(pageHtml);
  return matched ? decode(matched[1]) : '';
}

// 正文区所有真图：优先 data-lazy-src，其次 <noscript> 里的 src。
function postImages(pageHtml) {
  var images = [];
  var seen = {};
  var start = pageHtml.indexOf('class="single-content"');
  var body = start >= 0 ? pageHtml.slice(start) : pageHtml;

  var pattern = /<img[^>]+>/gi;
  var tag;
  while ((tag = pattern.exec(body)) !== null) {
    var text = tag[0];
    var srcMatch = /data-lazy-src="([^"]+)"/i.exec(text) || /data-src="([^"]+)"/i.exec(text) || /src="([^"]+)"/i.exec(text);
    if (!srcMatch) continue;
    var url = decode(srcMatch[1]);
    if (!/^https?:\/\//i.test(url)) continue;
    if (/\.(?:svg|gif)(?:\?|$)/i.test(url)) continue;
    if (!/\.(?:jpg|jpeg|png|webp)(?:\?|$)/i.test(url)) continue;
    if (/logo|favicon|avatar|gravatar|spinner|loading/i.test(url)) continue;
    url = https(url);
    if (seen[url]) continue;
    seen[url] = true;
    images.push(url);
  }
  return images;
}

// 文章内部分页：/html/{y}/{m}/{id}.html/{n}/（n 从 2 起；第 1 段就是文章本页）。
function pageUrl(articleUrl, pageNo) {
  var clean = String(articleUrl).split('?')[0].split('#')[0];
  if (!pageNo || pageNo < 2) return clean;
  return clean + '/' + pageNo + '/';
}

function maxSegment(pageHtml) {
  var max = 1;
  var pattern = /\/html\/\d{4}\/\d{2}\/\d+\.html\/(\d+)\//g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var value = Number(matched[1]);
    if (value > max) max = value;
  }
  return max;
}

function chapterId(articleUrl, startSegment) {
  var clean = String(articleUrl).split('?')[0].split('#')[0];
  return clean + '?lp=' + startSegment;
}

function startSegmentOf(value) {
  var matched = /[?&]lp=(\d+)/.exec(String(value || ''));
  var number = matched ? Number(matched[1]) : 1;
  return !number || number < 1 ? 1 : number;
}

function imageHeaders() {
  return {
    'User-Agent': UA,
    Referer: base() + '/',
    Accept: 'image/avif,image/webp,image/*,*/*;q=0.8'
  };
}

function idOf(argument) {
  return argument && argument.id ? String(argument.id).trim() : '';
}

var LumeSource = {
  id: 'pica177_comic',
  name: '177漫畫',
  version: '1.0.0',
  category: 'comic',
  mirrors: ['https://www.177pica.com'],

  async categories() {
    return CATEGORIES.slice();
  },

  async home() {
    var boards = [];
    try {
      var homeHtml = await getHtml('/');
      var latest = parseCards(homeHtml);
      if (latest.length) boards.push({ title: '最新上架', moreUrl: '', items: latest.slice(0, 18) });
    } catch (error) {
      /* 首页挂了还有分类页兜底 */
    }
    for (var index = 0; index < CATEGORIES.length && boards.length < 3; index++) {
      try {
        var catHtml = await getHtml('/html/category/' + CATEGORIES[index].id + '/');
        var items = parseCards(catHtml);
        if (items.length) {
          boards.push({ title: CATEGORIES[index].title, moreUrl: CATEGORIES[index].id, items: items.slice(0, 18) });
        }
      } catch (error) {
        if (!boards.length && index === CATEGORIES.length - 1) throw error;
      }
    }
    if (!boards.length) throw new Error('177漫畫：首页没认出条目（站点可能改版）');
    return boards;
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';

    if (keyword) {
      var searchPath = pageNo > 1 ? '/page/' + pageNo + '/?s=' + encodeURIComponent(keyword) : '/?s=' + encodeURIComponent(keyword);
      var searchHtml = await getHtml(searchPath);
      var hits = parseCards(searchHtml);
      var searchMax = 0;
      var pagedMatch = /\/page\/(\d+)\/\?s=/g;
      var pagedRun;
      while ((pagedRun = pagedMatch.exec(searchHtml)) !== null) {
        var value = Number(pagedRun[1]);
        if (value > searchMax) searchMax = value;
      }
      return { items: hits, hasMore: searchMax > pageNo };
    }

    if (category && CATEGORY_NAMES[category]) {
      var catPath = '/html/category/' + category + '/' + (pageNo > 1 ? 'page/' + pageNo + '/' : '');
      var catHtml = await getHtml(catPath);
      var catItems = parseCards(catHtml);
      return { items: catItems, hasMore: maxPageOf(catHtml, '/html/category/' + category + '/') > pageNo };
    }

    var homePath = pageNo > 1 ? '/page/' + pageNo + '/' : '/';
    var homeHtml = await getHtml(homePath);
    var items = parseCards(homeHtml);
    return { items: items, hasMore: maxPageOf(homeHtml, '/') > pageNo };
  },

  async detail(argument) {
    var id = idOf(argument);
    if (!id) return null;
    if (!/^https?:\/\//i.test(id)) id = absolute(id);
    var pageHtml = await getHtml(id);
    var title = postTitle(pageHtml);
    if (!title) return null;
    var images = postImages(pageHtml);
    var segments = maxSegment(pageHtml);
    var parts = [];
    var category = postCategory(pageHtml);
    if (category) parts.push(category);
    if (segments > 1) {
      parts.push('约 ' + segments * images.length + ' 张');
      parts.push(segments + ' 段');
    } else if (images.length) {
      parts.push(images.length + ' 张');
    }
    return {
      id: /^https?:\/\//i.test(id) ? id : absolute(id),
      title: title,
      cover: images.length ? images[0] : '',
      subtitle: parts.join(' · '),
      description: (category ? category + '｜' : '') + title +
        (segments > 1 ? '（' + segments + ' 段，约 ' + segments * images.length + ' 张图）' : images.length ? '（共 ' + images.length + ' 页）' : '')
    };
  },

  async chapters(argument) {
    var id = idOf(argument);
    if (!id) return [];
    if (!/^https?:\/\//i.test(id)) id = absolute(id);
    var article = id.split('?')[0];
    var pageHtml = await getHtml(article);
    var total = maxSegment(pageHtml);
    var rows = [];
    if (total <= SEGMENTS_PER_CHAPTER) {
      var single = postImages(pageHtml);
      rows.push({
        id: chapterId(article, 1),
        title: '全一話' + (single.length ? '（' + single.length + ' 页）' : '')
      });
      return rows;
    }
    for (var start = 1; start <= total; start += SEGMENTS_PER_CHAPTER) {
      var end = Math.min(start + SEGMENTS_PER_CHAPTER - 1, total);
      rows.push({
        id: chapterId(article, start),
        title: '第 ' + start + (end > start ? '–' + end : '') + ' 页'
      });
    }
    return rows;
  },

  async content(argument) {
    var chapterIdValue = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var target = chapterIdValue || idOf(argument);
    if (!target) throw new Error('缺少文章地址');
    if (!/^https?:\/\//i.test(target)) target = absolute(target);

    var article = target.split('?')[0];
    var start = startSegmentOf(target);
    var firstHtml = await getHtml(pageUrl(article, start));
    var total = start > 1 ? Math.max(maxSegment(firstHtml), start) : maxSegment(firstHtml);
    var end = Math.min(start + SEGMENTS_PER_CHAPTER - 1, total);

    var images = postImages(firstHtml);
    if (end > start) {
      var jobs = [];
      for (var pageNo = start + 1; pageNo <= end; pageNo++) {
        jobs.push(getHtml(pageUrl(article, pageNo)));
      }
      var pages = await Promise.all(jobs);
      for (var index = 0; index < pages.length; index++) {
        var chunk = postImages(pages[index]);
        for (var j = 0; j < chunk.length; j++) images.push(chunk[j]);
      }
    }
    if (!images.length) throw new Error('177漫畫：文章页没解析到图片（' + target + '）');
    return { kind: 'images', images: images, headers: imageHeaders() };
  }
};
