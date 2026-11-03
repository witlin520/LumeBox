// LumeSource: {"id":"ikanmanhua_comic","name":"愛看漫畫","version":"1.0.0","category":"comic","mirrors":["https://ikanmanhua.org"]}
//
// 站点：愛看漫畫 https://ikanmanhua.org （Next.js App Router 服务端渲染，18+ 韩漫/日漫）
//
// 结构（2026-10-25 真浏览器快照 .tmp_probe/cf/ikanmanhua.html + 逐页 curl 实测，全部直连 200）：
//   · 首页      /                      最新更新卡片（20 条）
//   · 全部      /books?page={n}        52 页，20 条/页；分页参数就是 page
//   · 排行      /rank                  单页榜单
//   · 搜索      /search?keyword={词}   **表单字段名是 keyword（不是 q）**，服务端一次返回全部命中
//               （page=1 与 page=2 内容完全相同 → 搜索不服务端分页，hasMore 恒 false）
//   · 卡片      <a href="/book/517">…<img src="https://www.jjmh.cc/static/upload/book/517/cover.jpg"
//               alt="富家女姐姐">…<h3>富家女姐姐</h3><p class="…line-clamp-1">外傳 第15話-主僕之間</p>
//               封面图床是 **www.jjmh.cc**（不是主站域名），列表/详情/章节页一律用它。
//   · 详情      /book/{id}  → <h1 class="text-2xl font-bold">标题</h1>、<img … class="rounded-sm object-cover">、
//               <p class="text-sm text-gray-700">作者：<!-- -->NOAH</p>（还有 状态/地区/标签）、
//               <meta name="description"> 是本书简介（非书页上它是全站简介，已过滤）。
//   · 目录      /book/{id} 页里 <a href="/chapter/{cid}"> 列表，行内两个 span：序号 + 「第N話-标题」。
//   · 阅读      /chapter/{cid} 页把所有页 <img src="https://www.jjmh.cc/static/upload/book/{id}/{cid}/NNN.jpg">
//               直接铺在 HTML 里（实测第 100 話 40 张），不需要翻页、不需要 JS。
//   · 图片      实测不带 Referer 也 200 image/jpeg；仍然带上本站 Referer 稳妥。
//   · 坑        Cloudflare 的 /cdn-cgi/challenge-platform/scripts/jsd 会出现在**正常页面**里，
//               不能拿它当被拦信号；只看 HTTP 状态码 + 正文长度。
var DEFAULT_BASE = 'https://ikanmanhua.org';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var PAGE_SIZE = 20;

var CATEGORIES = [
  { id: 'home', title: '最近更新' },
  { id: 'books', title: '全部漫畫' },
  { id: 'rank', title: '排行榜' }
];

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
  if (status !== 200) throw new Error('愛看漫畫 页面打不开：HTTP ' + status + ' ' + url);
  if (body.length < 2000 && /Just a moment|请稍候|cf-mitigated/i.test(body)) {
    throw new Error('NEED_WEBVIEW_VERIFY：愛看漫畫 触发了 Cloudflare 人机校验，请给本源配代理');
  }
  return body;
}

// ---------------------------------------------------------------- 卡片解析
// 卡片有两种排版（首页/榜单 vs 搜索页），共同点是 <a href="/book/{id}"> 后紧跟
// 一个 <img src=… alt=标题>，再跟 <h3>标题</h3>，所以按 <a href="/book/…"> 切片取首个命中。
function parseCards(pageHtml) {
  var items = [];
  var seen = {};
  var pattern = /<a href="\/book\/(\d+)"[^>]*>/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var id = matched[1];
    if (seen[id]) continue;
    var start = matched.index;
    var nextIndex = pageHtml.indexOf('<a href="/book/', start + 8);
    var end = nextIndex < 0 ? start + 2600 : Math.min(nextIndex, start + 2600);
    var chunk = pageHtml.slice(start, end);

    var imgPattern = /<img[^>]+>/gi;
    var imgMatch = null;
    var imgTag;
    while ((imgTag = imgPattern.exec(chunk)) !== null) {
      var srcMatch = /src="([^"]+)"/i.exec(imgTag[0]);
      if (!srcMatch) continue;
      var src = srcMatch[1];
      if (!/^https?:\/\//i.test(src)) continue;
      if (/favicon|logo\.png/i.test(src)) continue;
      var altMatch = /alt="([^"]*)"/i.exec(imgTag[0]);
      imgMatch = { src: src, alt: altMatch ? altMatch[1] : '' };
      break;
    }
    if (!imgMatch) continue;

    var titleMatch = /<h3[^>]*>([\s\S]{0,160}?)<\/h3>/i.exec(chunk);
    var title = decode(titleMatch ? titleMatch[1] : '') || decode(imgMatch.alt);
    if (!title) continue;

    var subMatch = /<p[^>]*line-clamp-1[^>]*>([\s\S]{0,160}?)<\/p>/i.exec(chunk);
    var subtitle = subMatch ? decode(subMatch[1]) : '';
    if (/^评分/.test(subtitle)) subtitle = '';

    seen[id] = true;
    items.push({
      id: absolute('/book/' + id),
      title: title,
      cover: absolute(imgMatch.src),
      subtitle: subtitle
    });
  }
  return items;
}

function totalPagesOf(pageHtml) {
  var matched = /\\?"totalPages\\?":(\d+)/.exec(pageHtml) || /totalPages\\?":(\d+)/.exec(pageHtml);
  return matched ? Number(matched[1]) : 0;
}

function hasMore(pageHtml, pageNo, count) {
  var total = totalPagesOf(pageHtml);
  if (total) return pageNo < total;
  return count >= PAGE_SIZE;
}

// ---------------------------------------------------------------- 详情解析
function bookTitle(pageHtml) {
  var matched = /<h1[^>]*class="text-2xl font-bold"[^>]*>([\s\S]{0,200}?)<\/h1>/i.exec(pageHtml) ||
    /<h1[^>]*>([\s\S]{0,200}?)<\/h1>/i.exec(pageHtml);
  var text = matched ? decode(matched[1]) : '';
  if (!text) {
    var titleTag = /<title>([\s\S]*?)<\/title>/i.exec(pageHtml);
    text = decode(titleTag ? titleTag[1] : '').replace(/\s*-\s*愛看漫畫\s*$/, '');
  }
  return text;
}

function bookCover(pageHtml) {
  var matched = /<img[^>]+src="(https?:\/\/[^"]+)"[^>]+class="rounded-sm object-cover"/i.exec(pageHtml) ||
    /<img[^>]+class="rounded-sm object-cover"[^>]*src="(https?:\/\/[^"]+)"/i.exec(pageHtml) ||
    /(https?:\/\/[^"'\/]+\/static\/upload\/book\/\d+\/cover\.jpg)/i.exec(pageHtml);
  return matched ? absolute(decode(matched[1])) : '';
}

function metaInfo(pageHtml) {
  var parts = [];
  var labels = ['作者', '状态', '地区', '标签'];
  for (var index = 0; index < labels.length; index++) {
    var pattern = new RegExp('<p[^>]*class="text-sm text-gray-700"[^>]*>' + labels[index] + '：([\\s\\S]{0,200}?)<\\/p>', 'i');
    var matched = pattern.exec(pageHtml);
    if (!matched) continue;
    var value = decode(matched[1]);
    if (!value) continue;
    parts.push(labels[index] + '：' + value);
  }
  return parts.join(' · ');
}

function bookDescription(pageHtml) {
  var matched = /<meta[^>]+name="description"[^>]+content="([^"]*)"/i.exec(pageHtml);
  var text = matched ? decode(matched[1]) : '';
  // 书页上 og:description / 非书页的 description 都是全站宣传语，丢掉。
  if (!text || /愛看漫畫是免费|愛看漫畫是免費|专注优质漫画内容|專注優質漫畫內容/.test(text)) return '';
  return text;
}

// ---------------------------------------------------------------- 目录解析
function parseChapterList(pageHtml) {
  var rows = [];
  var seen = {};
  var pattern = /<a href="\/chapter\/(\d+)"[^>]*>([\s\S]{0,700}?)<\/a>/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var id = matched[1];
    if (seen[id]) continue;
    var inner = matched[2];
    var spans = [];
    var spanPattern = /<span[^>]*>([\s\S]{0,180}?)<\/span>/g;
    var span;
    while ((span = spanPattern.exec(inner)) !== null) {
      var text = decode(span[1]);
      if (text) spans.push(text);
    }
    var title = '';
    for (var index = spans.length - 1; index >= 0; index--) {
      if (spans[index].length > 1 && !/^\d+$/.test(spans[index])) {
        title = spans[index];
        break;
      }
    }
    if (!title) title = spans.length ? spans[spans.length - 1] : '第 ' + (rows.length + 1) + ' 話';
    seen[id] = true;
    rows.push({ id: absolute('/chapter/' + id), title: title });
  }
  return rows;
}

// ---------------------------------------------------------------- 阅读解析
function pageImages(pageHtml) {
  var images = [];
  var seen = {};
  var pattern = /<img[^>]+>/gi;
  var tag;
  while ((tag = pattern.exec(pageHtml)) !== null) {
    var srcMatch = /src="([^"]+)"/i.exec(tag[0]);
    if (!srcMatch) continue;
    var url = decode(srcMatch[1]);
    if (!/^https?:\/\//i.test(url)) continue;
    if (/favicon|logo\.png|avatar|statics\/img/i.test(url)) continue;
    if (!/\.(?:jpg|jpeg|png|webp|avif)(?:\?|$)/i.test(url)) continue;
    if (seen[url]) continue;
    seen[url] = true;
    images.push(url);
  }
  return images;
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
  id: 'ikanmanhua_comic',
  name: '愛看漫畫',
  version: '1.0.0',
  category: 'comic',
  mirrors: ['https://ikanmanhua.org'],

  async categories() {
    return CATEGORIES.slice();
  },

  async home() {
    var boards = [];
    var plans = [
      { path: '/', title: '最近更新' },
      { path: '/rank', title: '排行榜' },
      { path: '/books', title: '全部漫畫' }
    ];
    for (var index = 0; index < plans.length; index++) {
      try {
        var pageHtml = await getHtml(plans[index].path);
        var items = parseCards(pageHtml);
        if (items.length) {
          boards.push({ title: plans[index].title, moreUrl: CATEGORIES[index].id, items: items.slice(0, 18) });
        }
      } catch (error) {
        if (index === 0) throw error;
      }
    }
    if (!boards.length) throw new Error('愛看漫畫：首页没认出条目（站点可能改版）');
    return boards;
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';

    if (keyword) {
      // 表单字段是 keyword；服务端一次返回全部命中，不分页。
      var searchHtml = await getHtml('/search?keyword=' + encodeURIComponent(keyword) + '&page=' + pageNo);
      var hits = parseCards(searchHtml);
      return { items: hits, hasMore: false };
    }

    if (category === 'books') {
      var booksHtml = await getHtml('/books?page=' + pageNo);
      var books = parseCards(booksHtml);
      return { items: books, hasMore: hasMore(booksHtml, pageNo, books.length) };
    }
    if (category === 'rank') {
      var rankHtml = await getHtml('/rank');
      return { items: parseCards(rankHtml), hasMore: false };
    }
    var homeHtml = await getHtml('/');
    var items = parseCards(homeHtml);
    return { items: items, hasMore: false };
  },

  async detail(argument) {
    var id = idOf(argument);
    if (!id) return null;
    var pageHtml = await getHtml(id);
    var title = bookTitle(pageHtml);
    if (!title) return null;
    return {
      id: absolute(id),
      title: title,
      cover: bookCover(pageHtml),
      subtitle: metaInfo(pageHtml),
      description: bookDescription(pageHtml)
    };
  },

  async chapters(argument) {
    var id = idOf(argument);
    if (!id) return [];
    var pageHtml = await getHtml(id);
    return parseChapterList(pageHtml);
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var target = chapterId || idOf(argument);
    if (!target) throw new Error('缺少章节地址');
    if (!/^https?:\/\//i.test(target)) target = absolute(target);
    var pageHtml = await getHtml(target);
    var images = pageImages(pageHtml);
    if (!images.length) {
      throw new Error('愛看漫畫：章节页没解析到图片（' + target + '）');
    }
    return { kind: 'images', images: images, headers: imageHeaders() };
  }
};
