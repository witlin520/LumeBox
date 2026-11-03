// LumeSource: {"id":"long91_comic","name":"龙禁漫","version":"1.0.0","category":"comic","mirrors":["https://long91.com"]}

// 站点：https://long91.com（conch 模板皮肤；路由前缀 /manhua/{作品id}.html 与 /manhua/{作品id}/{token}.html）
// 移动版与桌面版是**同一套标记**（站点没有移动子域），脚本不挑 UA，
// 走 App 内置 iPhone UA 即可。全站 UTF-8。
//
// ## 抓取口径（每一条都对着**实时页面**核过）
//
//   列表  GET /bookcata/all/ob/time/st/completed[/page/N]
//         24 条/页；分页器是**路径段** `/page/{N}`，不是查询串（`?page=N` 在部分皮肤上
//         只是首页随机排序，不能当分页用）。条目是 `a[href=/manhua/{id}.html]`：
//         封面只在 `img[data-original]` 里（`src` 是 `/images/loading.png` 占位图），
//         标题在 `a[title]`（91jmd/hman8）或紧跟着的 `h2 > a` 文本里（jmdw8 的卡片
//         锚点自己没有 title），所以标题先读 title 属性、空了再读锚点内文本。
//   搜索  GET /cata.php?key={UTF-8 百分号编码}[&page=N]
//         就是站内搜索表单自己的 action 与参数名（`<form action="/cata.php" ...><input name="key">`）。
//         实测 GET 与 POST 同结果，脚本走 GET（编码可控、可翻页）。
//   详情  GET /manhua/{作品id}.html
//         标题 `<h1>《秘密教学》</h1>`——**书名号包着**，解析后要去掉《》
//         封面 `.module-info-poster img[data-original]`
//         简介 `.module-info-introduction-content > p`
//   目录  **就在详情页里**（站点没有单独的目录地址，单页完整）：
//         `div.module-play-list-base > a.module-play-list-link[href=/manhua/{id}/{token}.html]`
//                  （这皮肤没有排序小表，目录只有一份；650 话那部 ≈80KB，窗口给到 400KB）。
//         {token} 是 20/22 位大小写混合随机串，只认「/manhua/{id}/{token}.html」这个形状，
//         不按固定长度写死（同一部作品里两种长度会混着出现）。
//   正文  GET /manhua/{id}/{token}.html（章节 id 存的就是这个完整地址）
//         图片在 `img[data-src][data-index]`（懒加载属性，`src` 多为空/占位）；
//         页面上还混着 JuicyAds 的 <ins> 广告块与统计像素，所以**只认 data-src /
//         data-original**，绝不整页抓裸 <img>，再按 `data-index` 排回原顺序。
//         一章一页、**没有章内翻页**（不拼 ?page=）。
//
// ## 两条实测出来的坑
//
// 1. **分类路径要自己百分号编码**。站点自己的链接是裸中文（/bookcata/韩漫/ob/time/st/completed），
//    把中文原样塞进请求路径在部分服务端会撞字符集判定；同一地址写成
//    %E9%9F%A9%E6%BC%AB 就是正常 24 条。这里 __encodePath() 只编码非 ASCII 字符，
//    '/' 与已编码的 % 原样保留。
// 2. **章节标题不要在作品标题里找**。条目 title 是「作品名-第N话-小标题」，
//    直接取会把作品名带进每一话；优先用 `<span>` 里的正文，取不到才按最后一个 '-'
//    切 title 属性。
//
// 图片域名（img.nnpic.xyz）实测**不需要 Referer**（带不带都 206），
// 但 content() 仍返回 `Referer: https://long91.com/`，给以后收紧防盗链留一层保险。
// 站点目前没有 Cloudflare 挑战页（实时页没有 __cf_chl / challenge-platform 痕迹），
// 被拦时的标记路径照留（见 __get），真拦了就抛 NEED_WEBVIEW_VERIFY 让 App 拉起网页视图。

var BASE_URL = 'https://long91.com';

var VERSION = '1.0.0';

var CATALOG_TPL = '/bookcata/{seg}/ob/time/st/completed';        // {seg} 会被换成分类自己的路径段
var SEARCH_TPL = '/cata.php';          // 站内搜索表单 action，参数名 key
var RANK_PATH = '/bookrank';            // 排行榜整表页（首页板块用，失败不影响主流程）

// 作品卡片 / 章节页的路径形状（已实测，见文件头）
var CARD_PATH = /^\/manhua\/(\d+)\.html$/;
var CHAPTER_PATH = /^\/manhua\/\d+\/[A-Za-z0-9_-]+\.html$/;

// 详情页选择器
var DETAIL_TITLE_RE = /<h1[^>]*>([\s\S]*?)<\/h1>/i;
var DETAIL_COVER_RE = /module-info-poster[\s\S]{0,600}?data-original="([^"]+)"/i;
var DETAIL_DESC_RE = /module-info-introduction-content[^>]*>([\s\S]*?)<\/div>/i;

// 目录所在区块（'' = 全页）；CHAPTER_CLASS 为空表示不按类名过滤
var CHAPTER_BLOCK = 'module-play-list-base';
var CHAPTER_CLASS = 'module-play-list-link';

var PAGE_SIZE = 24;         // 列表/搜索每页条数（实测）
var ITEM_WINDOW = 1500;     // 单条往后看的窗口（封面、副标题都在这段里）
var MAX_ITEMS = 120;        // 单次列表最多产出
var MAX_ANCHORS = 6000;     // 单次解析最多看多少个 <a>
var MAX_CHAPTERS = 1500;    // 目录最多解析多少话（实测 650 话那部 ≈80KB）
var MAX_IMAGES = 400;       // 正文最多收多少张图（实测一章 55–119 张）
var CHAPTER_WINDOW = 400000;// 目录区块往后看的窗口
var CACHE_TTL = 60000;      // 详情页 HTML 复用窗口（detail→chapters 少发一次请求）

// 「这不是封面/正文图」：站标、占位图、统计像素、广告。平铺直 test，可安全用于完整 URL。
var SKIP_IMAGE = /(?:logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|spacer|pixel|1x1)\./i;

// 分类：id 是稳定短名（App 存的是这个），seg 是站点自己路径里的那一段（裸中文）
var CATEGORIES = [
    { id: 'all', title: '全部', seg: 'all' },
    { id: 'hanman', title: '韩漫', seg: '韩漫' },
    { id: 'riman', title: '日漫', seg: '日漫' },
    { id: '3d', title: '3D漫画', seg: '3D漫画' },
    { id: 'meinv', title: '美女', seg: '美女' },
    { id: 'danben', title: '单本', seg: '单本' }
  ];

// 详情页 HTML 复用（同一部作品的 detail() → chapters() 只打一次网络）
var __cache = {};

// 用来找「下一个 <a」的游标正则（每次用前改 lastIndex，避免每条切片炸内存）
var ANCHOR_START = /<a[\s>]/gi;

var LumeSource = {
  id: 'long91_comic',
  name: '龙禁漫',
  version: VERSION,
  category: 'comic',
  mirrors: ['https://long91.com'],

  // ---------------------------------------------------------------- 契约方法

  /// 分类：站点自己的筛选条（列表页左侧 library-item / sort 页的分类页签）。
  /// 每一条都核过 200，不编假分类。
  async categories() {
    return CATEGORIES.slice();
  },

  /// 首页：站点首页卡片一块 + 排行榜一块（排行榜失败就只留一块，不让首页挂掉）。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = [];
    var latest = this.__items(html);
    if (latest.length) boards.push({ title: '最新更新', items: latest.slice(0, PAGE_SIZE) });
    try {
      var rank = await this.__get(BASE_URL + RANK_PATH);
      var top = this.__items(rank);
      if (top.length) boards.push({ title: '排行榜', items: top.slice(0, PAGE_SIZE) });
    } catch (error) {
      console.warn('[long91] 排行榜板块跳过：' + this.__message(error));
    }
    if (!boards.length) {
      var fallback = await this.list({ page: 1 });
      if (fallback.items.length) boards.push({ title: '最近更新', items: fallback.items });
    }
    return boards;
  },

  /// 列表 / 搜索。keyword 优先（走站内搜索），否则按分类走列表页第 N 页。
  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    var url;
    if (keyword) {
      url = BASE_URL + SEARCH_TPL + '?key=' + this.__encode(keyword);
      if (page > 1) url += '&page=' + page;
    } else {
      var seg = this.__seg(category);
      url = BASE_URL + this.__encodePath(CATALOG_TPL.replace('{seg}', seg));
      if (page > 1) url += '/page/' + page;
    }
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[long91] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[long91] 列表命中：' + url + '（' + items.length + ' 条）');
    return { items: items, hasMore: this.__hasMore(html, page, items.length) };
  },

  async detail(argument) {
    var url = this.__abs(argument && argument.id);
    var html = await this.__get(url);
    var title = this.__match(DETAIL_TITLE_RE, html);
    if (!title) title = this.__match(/<h1[^>]*>([\s\S]*?)<\/h1>/i, html);
    title = this.__stripBook(title);
    if (!title) title = this.__match(/<title>([\s\S]*?)<\/title>/i, html);
    var cover = this.__abs(this.__plain(this.__match(DETAIL_COVER_RE, html)));
    if (cover && SKIP_IMAGE.test(cover)) cover = '';
    var description = this.__text(this.__match(DETAIL_DESC_RE, html));
    // .vod_content 末尾挂着「展开」这个收起按钮的文本，不要带进简介
    description = description.replace(/\s*(展开|收起)$/, '').trim();
    return {
      id: url,
      title: title,
      cover: cover,
      subtitle: this.__status(html),
      description: description
    };
  },

  /// 目录：就在详情页里，{token} 只从页面解析，id 存完整章节地址（content 直接用）。
  async chapters(argument) {
    var url = this.__abs(argument && argument.id);
    var html = await this.__get(url);
    var block = html;
    if (CHAPTER_BLOCK) {
      var at = html.indexOf(CHAPTER_BLOCK);
      if (at >= 0) block = html.slice(at, at + CHAPTER_WINDOW);
    }
    var out = [];
    var seen = {};
    var re = /<a\b([^>]*)>([\s\S]{0,160}?)<\/a>/gi;
    var match;
    while ((match = re.exec(block)) !== null) {
      var attrs = match[1];
      if (CHAPTER_CLASS && attrs.indexOf(CHAPTER_CLASS) < 0) continue;
      var href = this.__attr(attrs, 'href');
      if (!href) continue;
      var path = this.__path(href);
      if (!CHAPTER_PATH.test(path)) continue;
      var id = BASE_URL + path;
      if (seen[id]) continue;
      seen[id] = 1;
      out.push({ id: id, title: this.__chapterTitle(match[2], this.__attr(attrs, 'title')) });
      if (out.length >= MAX_CHAPTERS) break;
    }
    if (!out.length) console.warn('[long91] 目录没解析出章节：' + url);
    return out;
  },

  /// 正文：图片只在懒加载属性里，按 data-index 排回原顺序。
  async content(argument) {
    var url = this.__abs(argument && argument.chapterId);
    var html = await this.__get(url);
    var images = this.__images(html);
    if (!images.length) throw new Error('正文没解析出图片：' + url + '（' + html.length + ' 字符）');
    console.warn('[long91] 正文 ' + images.length + ' 张：' + url);
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
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.6'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body != null ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 || status === 503 || status === 429 ||
          /just a moment|__cf_chl|cf-chl|challenge-platform|cf-mitigated|checking your browser/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：龙禁漫 需要网页视图过一次校验（HTTP ' + status + ' ' + key + '）');
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
      // 窗口只到「下一个 <a」为止：卡片之间不会串封面（首页轮播那种没有 img 的块，
      // 不会被后面卡片的封面顶替）。
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
      if (!entry.subtitle) entry.subtitle = this.__subtitle(window);
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
    // 侧栏「本周热门」那种纯文字链也用同一个 href 形状（long91 列表页顶部就有 10 条），
    // 它们没有封面。既然同页里存在带封面的卡片，就说明这是卡片页：
    // 没有封面的条目一律当侧栏链接丢掉（有封面的条目一张都不会被误删）。
    var covered = [];
    for (var k = 0; k < picked.length; k++) {
      if (picked[k].cover) covered.push(picked[k]);
    }
    if (covered.length && covered.length < picked.length) {
      console.warn('[long91] 丢掉 ' + (picked.length - covered.length) + ' 条无封面的侧栏链接');
      return covered;
    }
    return picked;
  },

  /// 封面：只认懒加载属性，`src` 是占位图；窗口里第一条不是占位图的就算。
  /// 首页轮播块没有 <img>，封面写在 `style="background: url(...)"` 里，这里兜一层。
  __cover(window) {
    var match = /(?:data-original|data-src|data-lazy-src|data-echo)=["']([^"']+)["']/i.exec(window);
    if (!match) match = /<img[^>]*\bsrc=["']([^"']+)["']/i.exec(window);
    if (!match) match = /background[^;)]*url\(\s*["']?([^"')]+\.(?:jpe?g|png|webp)[^"')]*)/i.exec(window);
    var url = match ? this.__abs(this.__plain(match[1])) : '';
    if (!url || SKIP_IMAGE.test(url)) return '';
    return url;
  },

  /// 副标题：conch 卡片的「最新话 / 更新时间 / 分类」那几行（skin 不同类名不同）。
  __subtitle(window) {
    var match = /<div class="module-item-note"[^>]*>([\s\S]{0,300}?)<\/div>/i.exec(window) ||
      /<div class="module-item-caption"[^>]*>([\s\S]{0,400}?)<\/div>/i.exec(window) ||
      /<div class="note"[^>]*>([\s\S]{0,200}?)<\/div>/i.exec(window);
    if (!match) return '';
    var text = this.__text(match[1]);
    return text.length > 80 ? text.slice(0, 80) : text;
  },

  __hasMore(html, page, count) {
    var text = String(html || '');
    var next = page + 1;
    if (text.indexOf('/page/' + next + '"') >= 0) return true;
    if (text.indexOf('/page/' + next + "'") >= 0) return true;
    if (text.indexOf('/page/' + next + '>') >= 0) return true;
    if (text.indexOf('/page/' + next + '/') >= 0) return true;
    if (text.indexOf('page=' + next) >= 0) return true;
    return count >= PAGE_SIZE - 2;
  },

  // ---------------------------------------------------------------- 正文解析

  /// 图片：只认 data-src / data-original（`src` 多为空或占位）；
  /// 有 data-index 就按它排序（实测顺序与 index 一致，缺一个就退回页面顺序）。
  __images(html) {
    var text = String(html || '');
    var re = /<img\b[^>]*>/gi;
    var match;
    var rows = [];
    while ((match = re.exec(text)) !== null) {
      var tag = match[0];
      var src = this.__attr(tag, 'data-src') || this.__attr(tag, 'data-original') || this.__attr(tag, 'data-lazy-src');
      if (!src) continue;
      var url = this.__abs(this.__plain(src));
      if (!url || SKIP_IMAGE.test(url)) continue;
      var index = this.__attr(tag, 'data-index');
      rows.push({ url: url, index: index === '' ? -1 : Number(index) });
    }
    var ordered = rows.length > 0;
    for (var i = 0; i < rows.length; i++) {
      if (!(rows[i].index >= 0)) {
        ordered = false;
        break;
      }
    }
    if (ordered) rows.sort(function (a, b) { return a.index - b.index; });
    var out = [];
    var seen = {};
    for (var j = 0; j < rows.length; j++) {
      if (seen[rows[j].url]) continue;
      seen[rows[j].url] = 1;
      out.push(rows[j].url);
      if (out.length >= MAX_IMAGES) break;
    }
    return out;
  },

  // ---------------------------------------------------------------- 小工具

  __seg(category) {
    for (var i = 0; i < CATEGORIES.length; i++) {
      if (CATEGORIES[i].id === category) return CATEGORIES[i].seg;
    }
    return CATEGORIES[0].seg;
  },

  __chapterTitle(rawText, rawTitle) {
    var text = this.__text(rawText);
    if (text) return text;
    var title = this.__text(rawTitle);
    var dash = title.lastIndexOf('-');
    if (dash > 0 && dash < title.length - 1) return title.slice(dash + 1);
    return title;
  },

  /// 详情标题兜底：long91 把标题写成《秘密教学》，去掉书名号。
  __stripBook(text) {
    var value = String(text || '').trim();
    if (value.length > 2 && value.charAt(0) === '《' && value.charAt(value.length - 1) === '》') {
      return value.slice(1, -1);
    }
    return value;
  },

  /// 状态副标题：详情页里必然出现的「连载中 / 已完结」。
  __status(html) {
    var text = String(html || '');
    if (text.indexOf('已完结') >= 0) return '已完结';
    if (text.indexOf('连载中') >= 0) return '连载中';
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
      .replace(/&hearts;/gi, '♥')
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

  /// 标签属性。只认带引号的写法（站点两种引号都用过）；靠「属性名前是空白」区分
  /// data-href 与 href 这类同后缀属性。
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

  /// 路径里的非 ASCII 字符（中文分类名）转 UTF-8 百分号编码（见文件头「坑 1」）。
  __encodePath(path) {
    var str = String(path || '');
    var out = '';
    for (var i = 0; i < str.length; i++) {
      var code = str.charCodeAt(i);
      out += code < 0x80 ? str.charAt(i) : this.__utf8(code, str, i);
    }
    return out;
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
