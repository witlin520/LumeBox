// LumeSource: {"id":"manga18_comic","name":"Manga18","version":"1.0.0","category":"comic","mirrors":["https://manga18.me"]}

// 站点：https://manga18.me（英文站，Madara 主题 + 自家路由；页面全英文、UTF-8）
// 移动版与桌面版是**同一套标记**（站点没有移动子域），脚本不挑 UA，
// 走 App 内置 iPhone UA 即可。
//
// ## 抓取口径（每一条都对着**实时页面**核过）
//
//   列表  GET /manga[?page=N]          全部作品（24 条/页）
//         GET /completed[?page=N]      已完结
//         GET /genre/manhwa[?page=N]   韩漫
//         GET /genre/uncensored[?page=N] 无修正
//         GET /manhwa-raw[?page=N]     韩漫生肉
//         分页是**查询串** `?page=N`：站内自己的 `li.next` 写的是路径式 `/manga/2`，
//         实测两种等价（第 2 页条目一致），但 `/genre/manhwa/2` 这种拼法没核过，
//         所以统一走 `?page=N`——四个入口都实测翻页换了一批条目。
//         条目在 `div.page-item-detail` 里：
//           <div class="item-thumb"><a href="/manga/{slug}"><img data-src="封面"></a></div>
//           <div class="item-chapters"><a href="/manga/{slug}/chapter-35">Chapter 35</a>
//         封面锚点**自己没有 title 属性**，标题在紧邻的 `div.item-title > h3 > a` 文本里，
//         所以标题先读 title 属性、空了再读锚点内文本（卡片内窗口为此切到「下一个 <a」）。
//   搜索  GET /search?q={关键词}[&page=N] —— 站内搜索表单 `<form action="/search" method="get">`，
//         实测 24 条/页，`&page=2` 有效。**没有搜索结果时页面仍是 24 条的推荐位**，
//         所以结果按 href 去重后如常返回（不编假数据）。
//   详情  GET /manga/{slug}
//         标题 `div.post-title > h1`；
//         封面 `div.summary_image img[data-src]`（同页还有 sidebar 缩略图，按容器取）；
//         简介 `div.panel-story-description` 里 `div.ss-manga > p`。
//   目录  就在详情页：`ul.row-content-chapter > li > a.chapter-name[href=/manga/{slug}/chapter-N]`，
//         **站点是「新→旧」倒序**（Chapter 35 排第一），这里 reverse 成旧→新，
//         阅读器从第 1 话顺着看。话名用锚点文本（就是 `Chapter 35`），title 属性是
//         「作品名 Chapter 35」，取锚点文本更干净。
//   正文  GET /manga/{slug}/chapter-N
//         图片在 `div.read-content > img[data-src]`，**属性是单引号**（`data-src='...'`），
//         解析器两种引号都认。整页还有 4 张 sidebar 缩略图也用 data-src，
//         所以**按 `div.read-content` 容器切块**再取图，不整页抓裸 <img>。
//         一章一页、没有章内翻页；`class="p1…p24"` 的顺序就是页面顺序，不需要额外排序。
//
// ## 实测到的坑
//
// 1. **图片是单引号属性**。写成正则 `data-src="([^"]+)"` 会一张都抓不到（页面里是
//    `data-src='https://img-r2.manga18.me/...'`）。__attr() 两种引号都收。
// 2. **正文图必须按容器切**。chapter 页 24 张正文图 + 4 张 sidebar 缩略图混在一起，
//    只按 data-src 抓会把推荐位的封面混进正文。
// 3. **`/manga` 第 1 页没有页码段**：站内 `li.next` 给的是 `/manga/2`，别把 `/manga/1`
//    当第 1 页去请求（实测 `/manga/1` 也是第 1 页，但没意义，统一走查询串）。
//    同理分页链接 `/manga/2` 与作品地址同形，CARD_PATH 必须把「全数字 slug」排掉，
//    否则列表里会混进一条标题为 "2" 的假条目（实测踩到过）。
// 4. **越界页码不报 404**：`/manga/999` 会夹到最后一页并返回 4 条，所以「有没有下一页」
//    只认 `li.next`（最后一页那个 li 变成 `prev disabled` 一侧的写法，没有 next 链接）。
//
// 图片域名（manga18.me/webtoon 与 img-r2.manga18.me/chapters）实测**不需要 Referer**
// （带不带都 206 image/jpeg），content() 仍返回 `Referer: https://manga18.me/` 留一层保险。
// 站点有 Cloudflare 前置，但普通 GET 没有挑战页（实时页没有 __cf_chl / challenge-platform），
// 被拦时的标记路径照留（见 __get），真拦了就抛 NEED_WEBVIEW_VERIFY 让 App 拉起网页视图。

var BASE_URL = 'https://manga18.me';

var VERSION = '1.0.0';

// 作品地址 / 章节地址的形状（已实测，见文件头）
// 注意 `/manga/2` 是**分页链接**（li.next），不是作品：slug 全数字的一律排掉。
var CARD_PATH = /^\/manga\/(?!\d+$)[a-z0-9][a-z0-9-]*$/i;
var CHAPTER_PATH = /^\/manga\/[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]*$/i;

var SEARCH_PATH = '/search';        // 站内搜索表单 action，参数名 q
var SEARCH_PARAM = 'q';

// 分类：id 是稳定短名（App 存的是这个），path 是站点自己的列表地址
var CATEGORIES = [
  { id: 'all', title: '全部', path: '/manga' },
  { id: 'completed', title: '已完结', path: '/completed' },
  { id: 'manhwa', title: '韩漫', path: '/genre/manhwa' },
  { id: 'uncensored', title: '无修正', path: '/genre/uncensored' },
  { id: 'raw', title: '生肉', path: '/manhwa-raw' }
];

var PAGE_SIZE = 24;          // 列表/搜索每页条数（实测）
var ITEM_WINDOW = 1500;      // 单条往后看的窗口（封面、最新话都在这段里）
var MAX_ITEMS = 120;         // 单次列表最多产出
var MAX_ANCHORS = 6000;      // 单次解析最多看多少个 <a>
var MAX_CHAPTERS = 2000;     // 目录最多解析多少话
var MAX_IMAGES = 400;        // 正文最多收多少张图（实测一章 24 张）
var CACHE_TTL = 60000;       // 详情页 HTML 复用窗口（detail→chapters 少发一次请求）
var READ_WINDOW = 400000;    // 正文容器往后看的窗口

// 「这不是封面/正文图」：站标、占位图、统计像素、广告。平铺直 test，可安全用于完整 URL。
var SKIP_IMAGE = /(?:logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|spacer|pixel|1x1)\./i;

// 详情页 HTML 复用（同一部作品的 detail() → chapters() 只打一次网络）
var __cache = {};

// 用来找「下一个 <a」的游标正则（每次用前改 lastIndex，避免每条切片炸内存）
var ANCHOR_START = /<a[\s>]/gi;

var LumeSource = {
  id: 'manga18_comic',
  name: 'Manga18',
  version: VERSION,
  category: 'comic',
  mirrors: ['https://manga18.me'],

  // ---------------------------------------------------------------- 契约方法

  /// 分类：站点自己的列表入口（/manga、/completed、/genre/*、/manhwa-raw），
  /// 五个都实测 24 条/页，不编假分类。
  async categories() {
    return CATEGORIES.slice();
  },

  /// 首页：站点首页「LATEST Manga UPDATED」一块 + 已完结一块（后者失败就只留一块）。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = [];
    var latest = this.__items(html);
    if (latest.length) boards.push({ title: '最新更新', items: latest.slice(0, PAGE_SIZE) });
    try {
      var done = await this.__get(BASE_URL + '/completed');
      var finished = this.__items(done);
      if (finished.length) boards.push({ title: '已完结', items: finished.slice(0, PAGE_SIZE) });
    } catch (error) {
      console.warn('[manga18] 已完结板块跳过：' + this.__message(error));
    }
    if (!boards.length) {
      var fallback = await this.list({ page: 1 });
      if (fallback.items.length) boards.push({ title: '最近更新', items: fallback.items });
    }
    return boards;
  },

  /// 列表 / 搜索。keyword 优先（走 /search?q=），否则按分类走列表页第 N 页。
  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    var url;
    if (keyword) {
      url = BASE_URL + SEARCH_PATH + '?' + SEARCH_PARAM + '=' + this.__encode(keyword);
      if (page > 1) url += '&page=' + page;
    } else {
      url = BASE_URL + this.__categoryPath(category);
      if (page > 1) url += (url.indexOf('?') >= 0 ? '&' : '?') + 'page=' + page;
    }
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[manga18] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[manga18] 列表命中：' + url + '（' + items.length + ' 条）');
    return { items: items, hasMore: this.__hasMore(html, page, items.length) };
  },

  async detail(argument) {
    var url = this.__abs(argument && argument.id);
    var html = await this.__get(url);
    var title = this.__text(this.__match(/<div class="post-title[^"]*"[^>]*>\s*<h1[^>]*>([\s\S]*?)<\/h1>/i, html));
    if (!title) title = this.__text(this.__match(/<h1[^>]*>([\s\S]*?)<\/h1>/i, html));
    var cover = this.__abs(this.__plain(this.__match(/<div class="summary_image"?[^>]*>[\s\S]{0,400}?(?:data-src|data-lazy-src|src)=["']([^"']+)["']/i, html)));
    if (cover && SKIP_IMAGE.test(cover)) cover = '';
    var description = this.__text(this.__match(/panel-story-description[\s\S]{0,800}?<p>([\s\S]*?)<\/p>/i, html));
    return {
      id: url,
      title: title,
      cover: cover,
      subtitle: this.__status(html),
      description: description.replace(/\s*(Read more|Show more|收起|展开)$/i, '').trim()
    };
  },

  /// 目录：就在详情页里，站点是「新→旧」，这里 reverse 成旧→新。
  async chapters(argument) {
    var url = this.__abs(argument && argument.id);
    var html = await this.__get(url);
    var out = [];
    var seen = {};
    var re = /<a\b([^>]*)>([\s\S]{0,160}?)<\/a>/gi;
    var match;
    while ((match = re.exec(html)) !== null) {
      var attrs = match[1];
      if (attrs.indexOf('chapter-name') < 0) continue;
      var href = this.__attr(attrs, 'href');
      if (!href) continue;
      var path = this.__path(href);
      if (!CHAPTER_PATH.test(path)) continue;
      var id = BASE_URL + path;
      if (seen[id]) continue;
      seen[id] = 1;
      var name = this.__text(match[2]);
      if (!name) name = this.__text(this.__attr(attrs, 'title'));
      out.push({ id: id, title: name });
      if (out.length >= MAX_CHAPTERS) break;
    }
    if (!out.length) {
      console.warn('[manga18] 目录没解析出章节：' + url);
      return out;
    }
    // 站点倒序（Chapter 35 → 1），阅读器按旧→新更好用
    return out.reverse();
  },

  /// 正文：图片只在 read-content 容器里的 data-src（单引号属性），
  /// 整页另有 4 张 sidebar 缩略图同样带 data-src，必须按容器切掉。
  async content(argument) {
    var url = this.__abs(argument && argument.chapterId);
    var html = await this.__get(url);
    var images = this.__images(html);
    if (!images.length) throw new Error('正文没解析出图片：' + url + '（' + html.length + ' 字符）');
    console.warn('[manga18] 正文 ' + images.length + ' 张：' + url);
    return { kind: 'images', images: images, headers: { 'Referer': BASE_URL + '/' } };
  },

  // ---------------------------------------------------------------- 网络

  async __get(url) {
    var key = String(url);
    var hit = __cache[key];
    if (hit && Date.now() - hit.at < CACHE_TTL) return hit.html;
    var response = await LumeSource.http.get(key, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.5'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body != null ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 || status === 503 || status === 429 ||
          /just a moment|__cf_chl|cf-chl|challenge-platform|cf-mitigated|checking your browser/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：Manga18 需要网页视图过一次校验（HTTP ' + status + ' ' + key + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + key);
    }
    __cache[key] = { at: Date.now(), html: body };
    return body;
  },

  // ---------------------------------------------------------------- 列表解析

  __items(html) {
    var text = String(html || '');
    var out = [];
    var seen = {};
    var re = /<a\b([^>]*)>/gi;
    var match;
    var scanned = 0;
    while ((match = re.exec(text)) !== null && scanned < MAX_ANCHORS) {
      scanned++;
      var attrs = match[1];
      var href = this.__attr(attrs, 'href');
      if (!href) continue;
      var path = this.__path(href);
      if (!CARD_PATH.test(path)) continue;
      var id = BASE_URL + path;
      var from = re.lastIndex;
      // 窗口只到「下一个 <a」为止：缩略图锚点和标题锚点之间不会串到别的卡片，
      // 也不会把相邻卡片的封面顶上来。
      var end = from + ITEM_WINDOW;
      ANCHOR_START.lastIndex = from;
      var probe = ANCHOR_START.exec(text);
      if (probe && probe.index < end) end = probe.index;
      var window = text.slice(from, end);
      var entry = seen[id];
      if (!entry) {
        entry = { id: id, title: '', cover: '', subtitle: '' };
        seen[id] = entry;
        out.push(entry);
      }
      if (!entry.cover) entry.cover = this.__cover(window);
      if (!entry.subtitle) entry.subtitle = this.__cardChapter(window);
      if (!entry.title) {
        var title = this.__text(this.__attr(attrs, 'title'));
        if (!title) title = this.__innerText(text, from, 240);
        if (title) entry.title = title;
      }
      if (out.length >= MAX_ITEMS) break;
    }
    var picked = [];
    for (var i = 0; i < out.length; i++) {
      if (!out[i].title && !out[i].cover) continue;
      if (!out[i].title) out[i].title = out[i].subtitle || '未命名';
      picked.push(out[i]);
    }
    return picked;
  },

  /// 封面：摘要卡片里 img 同时写了 data-src 与 src（同一张），data-src 优先。
  __cover(window) {
    var match = /(?:data-src|data-lazy-src|data-original)=["']([^"']+)["']/i.exec(window);
    if (!match) match = /<img[^>]*\bsrc=["']([^"']+)["']/i.exec(window);
    var url = match ? this.__abs(this.__plain(match[1])) : '';
    if (!url || SKIP_IMAGE.test(url)) return '';
    return url;
  },

  /// 副标题：卡片里 `div.item-chapters` 的最新一话（例如 Chapter 35）。
  __cardChapter(window) {
    var match = /<div class="chapter-item[^"]*">[\s\S]{0,300}?<a[^>]*>([\s\S]{0,60}?)<\/a>/i.exec(window);
    if (!match) return '';
    var text = this.__text(match[1]);
    return text.length > 60 ? text.slice(0, 60) : text;
  },

  /// 有没有下一页：只认站点自己的 `li.next` 链接（越界页会被夹到末页且没有 next）。
  __hasMore(html, page, count) {
    var text = String(html || '');
    var match = /<li class="next">[\s\S]{0,200}?<a[^>]*href="([^"]+)"/i.exec(text);
    if (match) return true;
    if (/<li class="next">\s*<span/i.test(text)) return false;
    return count >= PAGE_SIZE - 2;
  },

  // ---------------------------------------------------------------- 正文解析

  /// 正文图：先切 `div.read-content` 容器（里面没有嵌套 div，切到第一个 </div> 即可），
  /// 再收 img 的 data-src；容器认不出就退回整页（但正常页面一定认得出）。
  __images(html) {
    var text = String(html || '');
    var at = text.indexOf('read-content');
    var block = text;
    if (at >= 0) {
      var open = text.lastIndexOf('<div', at);
      var start = open >= 0 ? open : at;
      var close = text.indexOf('</div>', start);
      var stop = close > start && close - start < READ_WINDOW ? close : Math.min(text.length, start + READ_WINDOW);
      block = text.slice(start, stop);
    } else {
      console.warn('[manga18] 没认出 div.read-content，退回整页取图（' + text.length + ' 字符）');
    }
    var re = /<img\b[^>]*>/gi;
    var match;
    var out = [];
    var seen = {};
    while ((match = re.exec(block)) !== null) {
      var tag = match[0];
      var src = this.__attr(tag, 'data-src') || this.__attr(tag, 'data-lazy-src') || this.__attr(tag, 'data-original');
      if (!src) continue;
      var url = this.__abs(this.__plain(src));
      if (!url || SKIP_IMAGE.test(url)) continue;
      if (seen[url]) continue;
      seen[url] = 1;
      out.push(url);
      if (out.length >= MAX_IMAGES) break;
    }
    return out;
  },

  // ---------------------------------------------------------------- 小工具

  __categoryPath(category) {
    for (var i = 0; i < CATEGORIES.length; i++) {
      if (CATEGORIES[i].id === category) return CATEGORIES[i].path;
    }
    return CATEGORIES[0].path;
  },

  /// 状态副标题：详情页信息栏里的 Ongoing / Completed（英文站）。
  __status(html) {
    var text = String(html || '');
    if (/class="[^"]*post-status[^"]*"[\s\S]{0,400}?Completed/i.test(text)) return 'Completed';
    if (/class="[^"]*post-status[^"]*"[\s\S]{0,400}?Ongoing/i.test(text)) return 'Ongoing';
    if (/>\s*Completed\s*</i.test(text)) return 'Completed';
    if (/>\s*Ongoing\s*</i.test(text)) return 'Ongoing';
    return '';
  },

  __match(re, text) {
    var match = re.exec(String(text || ''));
    return match && match[1] != null ? match[1] : '';
  },

  /// 从 from 起读一小段纯文本（锚点内文本）；紧挨着子标签时返回空。
  __innerText(text, from, limit) {
    var end = Math.min(text.length, from + limit);
    var i = from;
    while (i < end && /\s/.test(text.charAt(i))) i++;
    if (i >= end || text.charAt(i) === '<') return '';
    var stop = text.indexOf('<', i);
    if (stop < 0 || stop > end) stop = end;
    return this.__text(text.slice(i, stop));
  },

  /// 去标签 + 解实体 + 收空白。沙箱没有 DOM，这张表够用（站点常见的几种）。
  __text(value) {
    var text = String(value == null ? '' : value);
    text = text.replace(/<[^>]*>/g, ' ');
    text = text.replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#0*39;/g, "'")
      .replace(/&apos;/gi, "'")
      .replace(/&hellip;/gi, '…')
      .replace(/&mdash;/gi, '—')
      .replace(/&ndash;/gi, '–')
      .replace(/&rsquo;/gi, '’')
      .replace(/&lsquo;/gi, '‘')
      .replace(/&ldquo;/gi, '“')
      .replace(/&rdquo;/gi, '”');
    text = text.replace(/&#(\d+);/g, function (_all, code) {
      return String.fromCharCode(Number(code));
    });
    text = text.replace(/&#x([0-9a-f]+);/gi, function (_all, code) {
      return String.fromCharCode(parseInt(code, 16));
    });
    return text.replace(/\s+/g, ' ').trim();
  },

  __plain(value) {
    return String(value == null ? '' : value).trim();
  },

  /// 只留路径部分：去掉协议+域名、查询串与锚点。
  __path(href) {
    var raw = String(href == null ? '' : href).trim();
    if (!raw) return '';
    var cut = raw.search(/[?#]/);
    if (cut >= 0) raw = raw.slice(0, cut);
    var origin = /^https?:\/\/[^\/]+/i.exec(raw);
    if (origin) raw = raw.slice(origin[0].length) || '/';
    if (raw.indexOf('//') === 0) {
      var at = raw.indexOf('/', 2);
      raw = at < 0 ? '/' : raw.slice(at);
    }
    if (raw.charAt(0) !== '/') raw = '/' + raw;
    return raw;
  },

  __abs(url) {
    var text = this.__plain(url);
    if (!text) return '';
    if (text.indexOf('//') === 0) return 'https:' + text;
    if (/^https?:\/\//i.test(text)) return text;
    if (text.charAt(0) === '/') return BASE_URL + text;
    return BASE_URL + '/' + text;
  },

  /// 标签属性。只认带引号的写法（这个站正文图用单引号、缩略图用双引号）；
  /// 靠「属性名前是空白」区分 data-href 与 href 这类同后缀属性。
  __attr(tag, name) {
    var needle = name + '=';
    var at = tag.indexOf(needle);
    var scanned = 0;
    while (at >= 0 && scanned < 12) {
      scanned++;
      var before = at > 0 ? tag.charCodeAt(at - 1) : 32;
      if (before === 32 || before === 9 || before === 10 || before === 13) {
        var quote = tag.charAt(at + needle.length);
        if (quote === '"' || quote === "'") {
          var end = tag.indexOf(quote, at + needle.length + 1);
          if (end > 0) return tag.slice(at + needle.length + 1, end);
        }
      }
      at = tag.indexOf(needle, at + needle.length);
    }
    return '';
  },

  /// 查询串编码（字母数字与 -_.~ 原样，其余全编码）。
  __encode(text) {
    var str = String(text);
    var out = '';
    for (var i = 0; i < str.length; i++) {
      var code = str.charCodeAt(i);
      if (code < 0x80) {
        var ch = str.charAt(i);
        var safe = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) || ch === '-' || ch === '_' || ch === '.' || ch === '~';
        out += safe ? ch : '%' + this.__hex(code);
      } else {
        out += this.__utf8(code, str, i);
      }
    }
    return out;
  },

  __utf8(code, str, i) {
    var value = code;
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
      var low = str.charCodeAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        value = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
      }
    }
    if (value < 0x800) {
      return '%' + this.__hex(0xC0 | (value >> 6)) + '%' + this.__hex(0x80 | (value & 0x3F));
    }
    if (value < 0x10000) {
      return '%' + this.__hex(0xE0 | (value >> 12)) +
        '%' + this.__hex(0x80 | ((value >> 6) & 0x3F)) +
        '%' + this.__hex(0x80 | (value & 0x3F));
    }
    return '%' + this.__hex(0xF0 | (value >> 18)) +
      '%' + this.__hex(0x80 | ((value >> 12) & 0x3F)) +
      '%' + this.__hex(0x80 | ((value >> 6) & 0x3F)) +
      '%' + this.__hex(0x80 | (value & 0x3F));
  },

  __hex(value) {
    var text = value.toString(16).toUpperCase();
    return text.length < 2 ? '0' + text : text;
  },

  __message(error) {
    if (!error) return 'unknown';
    return String(error.message || error).slice(0, 200);
  }
};
