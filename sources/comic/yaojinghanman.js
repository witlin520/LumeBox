// LumeSource: {"id":"yaojinghanman_comic","name":"妖精漫画","version":"1.0.0","category":"comic","mirrors":["https://www.yaojinghanman.com"]}

// 站点：https://www.yaojinghanman.com（妖精漫画网；Laravel + 自研主题 default7）。
// 与姊妹站七七韩漫（qqhanman.com，主题 default2）**同一个后端**：Id 编号、封面域
// images.manhuatupian.sbs、正文路由 /comic/media 全部一致，只是模板标记不同。
// 本源一套解析同时吃两套标记，两站的差别（都实测过）如下：
//
//   同一处          七七（default2）                          妖精（default7）
//   列表卡片        article.book-card                        article.book-card
//   封面属性        img[data-lazy-src]                       img[data-src]（alt 带「封面」后缀）
//   副标题          <p>第7話-無套會更爽♥</p>                 <p title="…">第7話-… · 2026-10-15</p>
//   分类面板        <a class="chip" href="/category?Id=20…">  <button form="filter-Id-1"> + 隐藏表单
//   详情标题        <h1 id="comic-title" title="…">           <h1>（**没有 title 属性**，只能读文字）
//   详情封面        div.detail-cover                          span.art.lazy-media.detail-cover
//   状态/简介       span.status / p.summary                  p.detail-status / p.comic-summary
//   目录锚          <a href>＋<span>                          <a class="chapter-row">＋<span title>
//   正文档容器      div.reader-images                        div.reader-panels
//   分页            rel="next" + span.page-status            rel="next" + span.page-position
//
// ## 实测结论（每一条都对着实时页面核过，2026-10-25，走本机 7890 代理）
//
//   分类  GET /category            筛选面板 <section class="filter-panel"> 第一排是题材
//         （全部 / 肉慾 / 浪漫 / 都市剧情 … 31 个），后面两排是状态（?finish=no|yes）
//         与排序（?order_by=view|created_at|updated_at|total_chapter）。
//         本站这一排是 **JS 表单**：`<button type="submit" form="filter-Id-1">肉慾</button>`
//         ＋一堆 `<form id="filter-Id-1" action="/category" method="get" hidden>`
//         （每个表单两个 hidden：Id=20、order_by=view）。**这些隐藏表单放在
//         `</section>` 之后**（实测面板结束在 27279、第一个 filter-Id-0 表单在 27320），
//         所以本源从整页抽表单、从第一排抽按钮。没有 href 可抄，categories() 用隐藏表单
//         拼出站内路径 `/category?Id=20&order_by=view`，list() 原样认，翻页再加 &page=N。
//         姊妹站那种 <a class="chip"> 写法也一起认。
//   列表  GET /category[?Id={题材}&order_by={排序}&finish={no|yes}][&page=N]  —— 48 条/页
//         GET /category/finish   （已完结，站点自己的路由）
//         GET /top /top/week     （总榜 / 周榜；标记是 article.rank-card。每页条数两站
//                                 不一样：七七 48 条/页、本站 20 条/页，本源按实际条数走）
//         GET /tags?tag={题材}   （标签页；标记是 article.result-card，48 条/页）
//         条目标记三套（本源靠「锚点 + /comic?Id=」统一抽，三种一起认）：
//           article.book-card   → <a href="/comic?Id=3120"><span class="art lazy-media">
//                                 <img data-src="封面" alt="…封面"></span><h3 title="标题">…</h3></a>
//                                 <p title="第7話-無套會更爽♥ · 2026-10-15">…</p>
//           article.result-card → <a class="result-cover" href=…> + <a class="result-title">
//                                 <h2 title="标题">…</h2> + <a class="latest-link">第224話</a>
//           article.rank-card   → <a class="rank-cover" href=…><img …></a> + <h2 title="标题">
//   搜索  GET /search?keyword={UTF-8 编码}[&page=N]   —— 表单 action 就是本站 /search，
//         输入框名 keyword；结果同样是 article.result-card，分页有 rel="next"。
//   详情  GET /comic?Id={数字}
//         标题 <h1>一發致富</h1>（无 title 属性）→ 本源读 h1 文字；
//         封面 span.art.lazy-media.detail-cover 里的 img[data-src]；
//         作者 <p class="author">作者：<a>…</a></p>；
//         状态 <p class="detail-status">连载中 · 共7话</p>；简介 <p class="comic-summary">…</p>；
//         题材 <a class="tag-link" aria-label="查看X标签的漫画">X</a>。
//   目录  **就在详情页里**（单页完整，不翻页）：div.chapter-list >
//         `<a class="chapter-row" href="/chapter?Id=101088"><span title="第7話-無套會更爽♥">
//          <b>第7話</b> 無套會更爽♥</span><small class="content-vip-badge">VIP</small>…</a>`
//         240 话的《秘密教学》也是一整页吐出来（实测 240 条、0 分页器）。
//         **站点顺序是新→旧**，本源按话数重排成升序（第 1 话在前）。
//   正文  GET /chapter?Id={数字}：一章一页、不翻页（页面自己写「共 55 页」= 一次全给）。
//         图片是**站内路由，没有扩展名**：
//           <div class="reader-panels"><figure class="reader-panel">
//             <img class="lazy-visual lazy-source"
//                  data-src="/comic/media?comic=470&amp;chapter=17632&amp;image={sha256}">
//         按扩展名判图会一张都收不到 → 本源按「URL 里带 /comic/media」判正文图，
//         并把 &amp; 解回 &。同一张图在 data-src 与 noscript 的 src 里各出现一次，
//         按 URL 去重（实测每章 55 张 / 268 张）。
//
// ## 三个实测坑
//
// 1. **VIP 章节匿名访问回 403**（付费墙，不是 CF 挑战）。chapters() 在标题里标 `· VIP`，
//    content() 撞到 403 给明确报错。实测第 1 话免费，第 3 话起就是 VIP——目录重排成
//    升序后 index 0 是第 1 话，检查器取的就是它。
// 2. **封面/标题不能取「窗口里第一个 title=」**：default7 的封面容器里有
//    `<span class="media-failure" title="图片加载失败，点击重试">`，先撞上就把标题读成这句。
//    本源只在 h3/h2 标签上读 title，最后才退到 img 的 alt（并去掉 alt 的「封面」后缀）。
// 3. **懒加载属性名三套**：data-src（本站）、data-lazy-src（姊妹站）、个别老页面
//    data-original。三个按优先级全试，逐张校验（排除 .svg / image-failed / logo / icon）。
//
// 图片域 images.manhuatupian.sbs 与正文路由 /comic/media 实测**不需要 Referer**：
// 带不带 `-e <站点>/` 都回 206 + image/jpeg（2026-10-25 两站各验过）。本源照浏览器
// 习惯给所有 HTML 请求带 `<站点>/`，content() 把同一份 headers 回给 App（多带不亏）。
// 站点前面有 Cloudflare，普通 GET 没有挑战页——注意正常页面里也有
// `/cdn-cgi/challenge-platform/scripts/jsd/main.js`（CF 的 JS 探测，不是挑战页；
// 页尾那段 `window.__CF$cv$params` 就是它），所以**不能拿 challenge-platform 当判据**。
// 只有「标题是 Just a moment / cf-error-details / cf-browser-verification / __cf_chl_opt」
// 才抛 NEED_WEBVIEW_VERIFY 让 App 拉起网页视图过一次校验。

var BASE_URL = 'https://www.yaojinghanman.com';
var SITE_NAME = '妖精漫画';
var LOG_TAG = 'yaojinghanman';

var PER_PAGE = 48;        // 列表/搜索每页条数（实测）
var MIN_PAGE_ITEMS = PER_PAGE - 8;  // 「还有下一页」的条数兜底
var MAX_ITEMS = 60;       // 单次列表最多产出（实测一页 48 条）
var MAX_ANCHORS = 600;    // 单次解析最多看多少个 <a>
var MAX_BOARDS = 10;      // 首页最多几块
var BOARD_ITEMS = 24;     // 单块最多几条（站点自己排 12 条）
var MAX_CHAPTERS = 3000;  // 目录最多解析多少话（实测 240 话 → 157KB）
var CATALOG_SCAN = 400000;// 目录块最多扫多少字符
var MAX_INLINE_SCAN = 400000; // 正文页最多扫多少字符
var MAX_IMAGES = 600;     // 正文最多收多少张图（实测一章 55–268 张）
var MAX_IMG_TAGS = 4000;
var TAG_LIMIT = 8;

// 不是封面/正文图：站标、失败占位、统计像素、广告、头像。
var SKIP_IMAGE = /logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|spinner|failure|failed|spacer|yandex|jads/i;

// 详情页面的分块标记（两套主题的名字）
var COVER_MARKS = ['class="detail-cover"', 'class="comic-intro"'];
var SUMMARY_MARKS = ['class="summary"', 'class="comic-summary"', 'class="synopsis"'];
var READER_MARKS = ['class="reader-images"', 'class="reader-panels"', 'class="reader-main"'];

var LumeSource = {
  id: 'yaojinghanman_comic',
  name: '妖精漫画',
  version: '1.0.0',
  category: 'comic',
  mirrors: [BASE_URL],

  // ---------------------------------------------------------------- 契约方法

  /// 分类：读 /category 自己的筛选面板「分类」那一排（全部 + 32 个题材）。
  /// id 用站内路径 + 查询串（list() 原样认）。面板认不出来就只给「全部」——
  /// `/category?order_by=view` 永远是真实地址，不编分类。
  async categories() {
    var html = await this.__get(BASE_URL + '/category');
    var found = this.__genres(html);
    if (!found.length) {
      console.warn('[' + LOG_TAG + '] 分类页没认出筛选面板（' + html.length + ' 字符），只给「全部」');
      return [{ id: '/category?order_by=view', title: '全部' }];
    }
    console.warn('[' + LOG_TAG + '] 筛选面板读到 ' + found.length + ' 个题材');
    return found;
  },

  /// 首页：站点自己的板块（热门推荐 / 随机推荐 / 新作上架 / 最新更新 / 人气排行 /
  /// 连载漫画 / 完结漫画）。板块「更多」原样透传给 list()；「漫画标签」那种纯标签块没有
  /// 条目，直接跳过。一块都认不出来就退回列表页一块（不让首页空着）。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = this.__boards(html);
    if (boards.length) {
      console.warn('[' + LOG_TAG + '] 首页板块 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ categoryId: '', page: 1 });
    if (latest && latest.items && latest.items.length) {
      console.warn('[' + LOG_TAG + '] 首页没认出板块（' + html.length + ' 字符），退回列表页一块');
      return [{ title: '最近更新', moreUrl: '/category?order_by=updated_at', items: latest.items.slice(0, 12) }];
    }
    return [];
  },

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    var url = this.__listUrl(category, keyword, page);
    var html = await this.__get(url);
    var items = this.__items(html, MAX_ITEMS);
    if (!items.length) {
      console.warn('[' + LOG_TAG + '] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[' + LOG_TAG + '] 列表命中：' + url + '（' + items.length + ' 条）');
    return { items: items, hasMore: this.__hasNext(html, page) };
  },

  async detail(argument) {
    var url = this.__comicUrl(this.__id(argument));
    var html = await this.__get(url);
    var title = this.__detailTitle(html);
    if (!title) {
      console.warn('[' + LOG_TAG + '] 详情页没认出标题：' + url + '（' + html.length + ' 字符）');
      return null;
    }
    var info = this.__detailInfo(html);
    return {
      id: url,
      title: title,
      cover: this.__detailCover(html),
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut(info.author || info.status || info.updated, 60),
      description: info.description,
      tags: info.tags,
      extra: { author: info.author, status: info.status, updated: info.updated }
    };
  },

  /// 目录：详情页内的 div.chapter-list（单页完整、新→旧）。按话数重排成升序，
  /// 话数有重复（第二季/重制）就整体退回站点顺序。VIP 章节在标题里标 · VIP。
  async chapters(argument) {
    var url = this.__comicUrl(this.__id(argument));
    var html = await this.__get(url);
    var rows = this.__catalog(html);
    if (!rows.length) {
      throw new Error(SITE_NAME + '：目录没认出章节链接（' + url + '）——把运行日志发回来收敛解析规则');
    }
    var chapters = this.__order(rows);
    console.warn('[' + LOG_TAG + '] 目录 ' + chapters.length + ' 话（已按话数升序）：' + url);
    return chapters;
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error(SITE_NAME + '：缺少章节 ID（请先选择一话）');
    var url = this.__chapterUrl(chapterId, argument && argument.id);
    if (!url) throw new Error(SITE_NAME + '：认不出章节地址（' + chapterId + '）——章节 id 应当来自 chapters()');
    var html = await this.__get(url);
    var images = this.__readerImages(html);
    if (!images.length) {
      if (this.__isVipPage(html)) {
        throw new Error(SITE_NAME + '：这一话是 VIP 付费章节，匿名访问拿不到正文（' + url + '）');
      }
      throw new Error(SITE_NAME + '：这一话没解析出图片（' + url + '）——把运行日志发回来收敛解析规则');
    }
    console.warn('[' + LOG_TAG + '] 正文 ' + images.length + ' 张图（单页，不翻页）：' + url);
    return { kind: 'images', images: images, headers: { 'Referer': BASE_URL + '/' } };
  },

  // ---------------------------------------------------------------- 地址策略

  /// 列表地址。categoryId 认这几种形态（都来自站点自己的链接）：
  ///   '' / 'all'   → /category?order_by=view（全站，分页）
  ///   '/xxx?…'     → 站内路径原样用（筛选面板 / 首页「更多」都是这个形状）
  ///   纯数字        → /category?Id={数字}&order_by=view
  ///   题材名        → /category?Id 查不到就退回全部（不猜地址）
  /// 搜索一律 /search?keyword=（站内表单自己的 action）。
  __listUrl(category, keyword, page) {
    if (keyword) {
      var search = '/search?keyword=' + this.__encode(keyword);
      if (page > 1) search += '&page=' + page;
      return BASE_URL + search;
    }
    var path = this.__categoryPath(category);
    return BASE_URL + this.__withPage(path, page);
  },

  __categoryPath(category) {
    var id = String(category == null ? '' : category).trim();
    if (!id || id === 'all') return '/category?order_by=view';
    if (id.indexOf('http') === 0) {
      if (id.indexOf(BASE_URL) !== 0) {
        console.warn('[' + LOG_TAG + '] 认不出的分类地址（不是本站）：' + id + '，退回全部');
        return '/category?order_by=view';
      }
      id = id.slice(BASE_URL.length);
    }
    if (id.charAt(0) !== '/') id = '/' + id;
    // 只认站点自己的三条列表路由，别的一律退回全部（不请求陌生地址）。
    if (!/^\/(category|top|tags|search)(\/|\?|$)/.test(id)) {
      console.warn('[' + LOG_TAG + '] 认不出的分类地址：' + category + '，退回全部');
      return '/category?order_by=view';
    }
    return id;
  },

  /// 给站内路径加/换 page 参数（`/category?Id=20&order_by=view` → 末尾 &page=2）。
  __withPage(path, page) {
    var text = String(path || '/category');
    var current = page > 0 ? page : 1;
    if (/[?&]page=\d+/.test(text)) return text.replace(/([?&])page=\d+/, '$1page=' + current);
    if (current <= 1) return text;
    return text + (text.indexOf('?') >= 0 ? '&' : '?') + 'page=' + current;
  },

  __id(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    else if (argument && argument.bookId != null) id = String(argument.bookId);
    if (!id) throw new Error(SITE_NAME + '：缺少作品 ID');
    return id;
  },

  /// 作品地址：数字 / 站内路径 / 完整地址都认，统一成 `{BASE}/comic?Id={数字}`。
  __comicUrl(id) {
    var value = String(id || '').trim();
    if (!value) throw new Error(SITE_NAME + '：缺少作品 ID');
    if (value.indexOf('http') === 0) {
      if (value.indexOf(BASE_URL) !== 0) throw new Error(SITE_NAME + '：作品地址不在本站（' + value + '）');
      value = value.slice(BASE_URL.length);
    }
    var digits = this.__comicId(value);
    if (!digits) throw new Error(SITE_NAME + '：认不出的作品地址（' + id + '）——id 应当来自 list()/detail()');
    return BASE_URL + '/comic?Id=' + digits;
  },

  /// 从任意 href / 路径里抠出作品数字 id（`/comic?Id=3120`、`https://…/comic?Id=3120`）。
  __comicId(href) {
    var text = String(href || '').trim().replace(/&amp;/g, '&');
    if (!text) return '';
    var at = text.indexOf('/comic?Id=');
    if (at < 0) return '';
    var i = at + '/comic?Id='.length;
    var start = i;
    while (i < text.length && i - start < 12) {
      var code = text.charCodeAt(i);
      if (code < 48 || code > 57) break;
      i++;
    }
    return i > start ? text.slice(start, i) : '';
  },

  __chapterUrl(chapterId, itemId) {
    var value = String(chapterId || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      if (value.indexOf(BASE_URL) !== 0) return '';
      value = value.slice(BASE_URL.length);
    }
    var digits = '';
    var at = value.indexOf('/chapter?Id=');
    if (at >= 0) {
      digits = this.__digits(value.slice(at + '/chapter?Id='.length, at + '/chapter?Id='.length + 12));
    } else if (this.__digits(value)) {
      digits = this.__digits(value);
    }
    return digits ? BASE_URL + '/chapter?Id=' + digits : '';
  },

  // ---------------------------------------------------------------- 分类 / 首页

  /// 筛选面板「分类」那一排。两套主题两种写法都认：
  ///   default2：<a class="chip" href="/category?Id=20&amp;order_by=view">肉慾</a>
  ///   default7：<button form="filter-Id-1">肉慾</button> + <form id="filter-Id-1"> 里两个 hidden
  /// 只取 Id 组（filter-Id-*，以及 chip 里带 Id= 的），状态/排序组不进分类。
  __genres(html) {
    var panel = this.__panel(html);
    if (!panel) return [];
    var row = this.__firstRow(panel);
    var found = [];
    var seen = {};
    // default2：带 href 的 chip
    var at = 0;
    var scanned = 0;
    while (at >= 0 && found.length < 60) {
      at = row.indexOf('class="chip', at);
      if (at < 0) break;
      if (++scanned > 80) break;
      var open = row.lastIndexOf('<a', at);
      var tagEnd = row.indexOf('>', at);
      if (open < 0 || tagEnd < 0) { at = tagEnd + 1; continue; }
      var tag = row.slice(open, tagEnd + 1);
      var href = this.__attr(tag, 'href');
      var closeAt = row.indexOf('</a>', tagEnd);
      var label = this.__cut(this.__text(row.slice(tagEnd + 1, closeAt > tagEnd ? closeAt : tagEnd + 60)), 16);
      var path = this.__listPath(href);
      if (path && label && !seen[path]) {
        seen[path] = true;
        found.push({ id: path, title: label });
      }
      at = tagEnd + 1;
    }
    if (found.length) return found;
    // default7：<button form="filter-Id-N">名称</button> + 一堆隐藏表单。
    // 隐藏表单在 **`</section>` 之后**（不在筛选面板里，实测 panel 到 27279、第一个
    // filter-Id-0 表单在 27320），所以表单从整页抽、按钮从第一排抽。
    var forms = this.__forms(html);
    var bAt = 0;
    var bScanned = 0;
    while (bAt >= 0 && found.length < 60) {
      bAt = row.indexOf('<button', bAt);
      if (bAt < 0) break;
      if (++bScanned > 120) break;
      var bEnd = row.indexOf('>', bAt);
      if (bEnd < 0) break;
      var bTag = row.slice(bAt, bEnd + 1);
      var target = this.__attr(bTag, 'form');
      var close = row.indexOf('</button>', bEnd);
      var text = this.__cut(this.__text(row.slice(bEnd + 1, close < 0 ? bEnd + 200 : close)), 16);
      if (target && forms[target] && text && target.indexOf('filter-Id-') === 0) {
        var built = '/category?' + forms[target];
        if (!seen[built]) {
          seen[built] = true;
          found.push({ id: built, title: text });
        }
      }
      bAt = bEnd + 1;
    }
    return found;
  },

  /// `id="…"` 的隐藏表单 → 查询串（`Id=20&order_by=view`）。
  __forms(area) {
    var forms = {};
    var at = 0;
    var scanned = 0;
    while (at >= 0 && scanned < 120) {
      at = area.indexOf('<form', at);
      if (at < 0) break;
      scanned++;
      var bodyStart = area.indexOf('>', at);
      if (bodyStart < 0) break;
      var formId = this.__attr(area.slice(at, bodyStart + 1), 'id');
      var end = area.indexOf('</form>', bodyStart);
      if (end < 0) end = Math.min(area.length, bodyStart + 4000);
      var query = '';
      if (formId) {
        var inputAt = bodyStart;
        while (inputAt >= 0 && inputAt < end) {
          inputAt = area.indexOf('<input', inputAt);
          if (inputAt < 0 || inputAt > end) break;
          var inputEnd = area.indexOf('>', inputAt);
          if (inputEnd < 0) break;
          var inputTag = area.slice(inputAt, inputEnd + 1);
          var name = this.__attr(inputTag, 'name');
          var value = this.__attr(inputTag, 'value');
          if (name) query += (query ? '&' : '') + name + '=' + this.__encode(value);
          inputAt = inputEnd + 1;
        }
        if (query) forms[formId] = query;
      }
      at = end + 7;
    }
    return forms;
  },

  /// 筛选面板本体（`<section class="filter-panel"` 到它自己的 </section>）。
  __panel(html) {
    var at = html.indexOf('class="filter-panel');
    if (at < 0) return '';
    var start = html.lastIndexOf('<', at);
    var end = html.indexOf('</section>', at);
    if (end < 0) end = Math.min(html.length, at + 40000);
    return html.slice(start < 0 ? at : start, end);
  },

  /// 面板里第一排（「分类」那排）。第二排起是状态（finish）与排序（order_by），
  /// 那些是筛选值不是题材，不进 categories()。
  __firstRow(panel) {
    if (!panel) return '';
    var at = panel.indexOf('class="filter-row"');
    if (at < 0) return panel;
    var next = panel.indexOf('class="filter-row"', at + 18);
    return panel.slice(at, next > at ? next : panel.length);
  },

  /// 站内列表路径（只认 /category、/top、/tags；查询串原样保留，&amp; 解回 &）。
  __listPath(href) {
    var text = String(href || '').trim().replace(/&amp;/g, '&');
    if (!text || text.indexOf('javascript:') === 0 || text.charAt(0) === '#') return '';
    if (text.indexOf('http') === 0) {
      if (text.indexOf(BASE_URL) !== 0) return '';
      text = text.slice(BASE_URL.length);
    }
    if (text.charAt(0) !== '/') return '';
    if (!/^\/(category|top|tags)(\/|\?|$)/.test(text)) return '';
    return text;
  },

  /// 首页板块：`<section class="… home-section">` + `<div class="section-heading"><h2>标题</h2>`
  /// + 一个「更多」锚（default2 是 a.more，default7 是 a.more-link）。
  /// 窗口 = 本级 section 到下一个 section；纯标签块没有条目，自然被丢掉。
  __boards(html) {
    var boards = [];
    var starts = [];
    var at = 0;
    var scanned = 0;
    while (at >= 0 && starts.length < 60) {
      at = html.indexOf('<section', at);
      if (at < 0) break;
      if (++scanned > 80) break;
      var tagEnd = html.indexOf('>', at);
      if (tagEnd < 0) break;
      var tag = html.slice(at, tagEnd + 1);
      if (tag.indexOf('home-section') >= 0) starts.push(at);
      at = tagEnd + 1;
    }
    for (var i = 0; i < starts.length && boards.length < MAX_BOARDS; i++) {
      var end = i + 1 < starts.length ? starts[i + 1] : Math.min(html.length, starts[i] + 120000);
      var window = html.slice(starts[i], end);
      var title = this.__heading(window);
      var items = this.__items(window, BOARD_ITEMS);
      if (title && items.length && title.indexOf('标签') < 0) {
        boards.push({ title: title, moreUrl: this.__morePath(window), items: items });
      }
    }
    return boards;
  },

  __heading(window) {
    var at = window.indexOf('<h2');
    if (at < 0) return '';
    var open = window.indexOf('>', at);
    if (open < 0) return '';
    var close = window.indexOf('</h2>', open);
    if (close < 0) close = Math.min(window.length, open + 160);
    return this.__cut(this.__text(window.slice(open + 1, close)), 20);
  },

  /// 板块「更多」→ list() 认得的分类 id（站内路径）；认不出就退回全部更新。
  __morePath(window) {
    var at = window.indexOf('class="more');
    if (at < 0) return '/category?order_by=updated_at';
    var start = window.lastIndexOf('<a', at);
    var end = window.indexOf('>', at);
    if (start < 0 || end < 0) return '/category?order_by=updated_at';
    var path = this.__listPath(this.__attr(window.slice(start, end + 1), 'href'));
    return path || '/category?order_by=updated_at';
  },

  // ---------------------------------------------------------------- 解析

  /// 条目抽取（三套主题统一）：扫 `<a>`，只要 href 里有 /comic?Id= 就是一条作品，
  /// 标题在锚内的 h3/h2 title → img alt → 锚自己的 title；封面在锚内的懒加载属性；
  /// 副标题在锚后 2.5KB 里找 latest-link / 第一个 <p>。
  /// 同一部作品在一页里可以有两个锚（封面锚 + 标题锚，搜索页就是这样）→ 按作品去重。
  __items(html, limit) {
    var items = [];
    var seen = {};
    var at = 0;
    var scanned = 0;
    var cap = limit > 0 ? limit : MAX_ITEMS;
    while (items.length < cap) {
      at = html.indexOf('<a', at);
      if (at < 0) break;
      if (++scanned > MAX_ANCHORS) break;
      var tagEnd = html.indexOf('>', at);
      if (tagEnd < 0) break;
      var tag = html.slice(at, tagEnd + 1);
      var digits = this.__comicId(this.__attr(tag, 'href'));
      if (!digits) {
        at = tagEnd + 1;
        continue;
      }
      var id = BASE_URL + '/comic?Id=' + digits;
      var close = html.indexOf('</a>', tagEnd);
      var innerEnd = close > tagEnd && close - tagEnd < 8000 ? close : Math.min(html.length, tagEnd + 3000);
      if (!seen[id]) {
        var inner = html.slice(tagEnd + 1, innerEnd);
        var title = this.__itemTitle(tag, inner);
        if (title) {
          seen[id] = true;
          items.push({
            id: id,
            title: title,
            cover: this.__coverIn(inner) || this.__coverIn(tag),
            coverHeaders: { 'Referer': BASE_URL + '/' },
            subtitle: this.__subtitle(html, innerEnd)
          });
        }
      }
      at = innerEnd;
    }
    return items;
  },

  __itemTitle(tag, inner) {
    var title = this.__headingTitle(inner, '<h3') || this.__headingTitle(inner, '<h2');
    if (title) return this.__cut(title, 80);
    var alt = this.__imgAlt(inner);
    if (alt) return this.__cut(this.__stripCover(alt), 80);
    var own = this.__plain(this.__attr(tag, 'title'));
    if (own) return this.__cut(own, 80);
    return '';
  },

  /// `<h3 title="标题">` → 标题；没有 title 属性就读标签里的文字。
  __headingTitle(inner, marker) {
    var at = inner.indexOf(marker);
    if (at < 0) return '';
    var open = inner.indexOf('>', at);
    if (open < 0) return '';
    var tag = inner.slice(at, open + 1);
    var own = this.__plain(this.__attr(tag, 'title'));
    if (own) return own;
    var close = inner.indexOf('</', open);
    if (close < 0) close = Math.min(inner.length, open + 200);
    return this.__plain(inner.slice(open + 1, close));
  },

  __imgAlt(inner) {
    var at = inner.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 4) {
      scanned++;
      var end = inner.indexOf('>', at);
      if (end < 0) return '';
      var alt = this.__plain(this.__attr(inner.slice(at, end + 1), 'alt'));
      if (alt) return alt;
      at = inner.indexOf('<img', end);
    }
    return '';
  },

  __stripCover(text) {
    var value = String(text || '').trim();
    if (this.__endsWith(value, '封面图')) return value.slice(0, value.length - 3).trim();
    if (this.__endsWith(value, '封面')) return value.slice(0, value.length - 2).trim();
    return value;
  },

  /// 副标题：锚后面先找 `class="latest-link"`（搜索/榜单卡片写「第224話」），
  /// 再找 `<p …>文字</p>`（列表卡片写「第7話-無套會更爽♥ · 日期」）。
  __subtitle(html, from) {
    var window = html.slice(from, Math.min(html.length, from + 2500));
    var at = window.indexOf('class="latest-link"');
    if (at >= 0) {
      var end = window.indexOf('>', at);
      var close = window.indexOf('</a>', end);
      if (end >= 0 && close > end) {
        var link = this.__cut(this.__text(window.slice(end + 1, close)), 40);
        if (link) return link;
      }
    }
    var p = window.indexOf('<p');
    if (p >= 0) {
      var pEnd = window.indexOf('>', p);
      var pClose = window.indexOf('</p>', pEnd);
      if (pEnd >= 0 && pClose > pEnd) {
        var text = this.__text(window.slice(pEnd + 1, pClose));
        if (text && text.length <= 60) return this.__cut(text, 40);
      }
    }
    return '';
  },

  /// 窗口里第一张合格封面（三种懒加载属性 + src，逐张校验）。
  __coverIn(window) {
    var at = window.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 8) {
      scanned++;
      var end = window.indexOf('>', at);
      if (end < 0) break;
      var tag = window.slice(at, end + 1);
      var lazies = ['data-lazy-src', 'data-src', 'data-original', 'src'];
      for (var i = 0; i < lazies.length; i++) {
        var url = this.__attr(tag, lazies[i]);
        if (url && this.__isCover(url)) return this.__absolute(url);
      }
      at = window.indexOf('<img', end);
    }
    return '';
  },

  __isCover(url) {
    var text = String(url || '').trim();
    if (!text || text.length > 400) return false;
    if (text.indexOf('data:') === 0) return false;
    if (SKIP_IMAGE.test(text)) return false;
    var path = text.split('?')[0].toLowerCase();
    if (this.__endsWith(path, '.svg')) return false;
    return this.__isImagePath(path);
  },

  __isImagePath(path) {
    return this.__endsWith(path, '.jpg') || this.__endsWith(path, '.jpeg') ||
      this.__endsWith(path, '.png') || this.__endsWith(path, '.webp') ||
      this.__endsWith(path, '.avif') || this.__endsWith(path, '.gif');
  },

  /// 详情标题：h1 的文字（default7 的 h1 没有 title 属性，所以先读文字再读 title 属性）。
  __detailTitle(html) {
    var at = html.indexOf('<h1');
    if (at >= 0) {
      var open = html.indexOf('>', at);
      var close = open >= 0 ? html.indexOf('</h1>', open) : -1;
      if (open >= 0 && close > open) {
        var text = this.__plain(html.slice(open + 1, close));
        if (text) return this.__stripBrackets(this.__cut(text, 100));
      }
      var tagTitle = this.__plain(this.__attr(html.slice(at, open + 1), 'title'));
      if (tagTitle) return this.__stripBrackets(this.__cut(tagTitle, 100));
    }
    var raw = this.__titleTag(html);
    var cut = raw.indexOf(' - ');
    if (cut > 0) raw = raw.slice(0, cut);
    return this.__plain(this.__stripBrackets(raw));
  },

  __detailCover(html) {
    for (var i = 0; i < COVER_MARKS.length; i++) {
      var at = html.indexOf(COVER_MARKS[i]);
      if (at < 0) continue;
      var cover = this.__coverIn(html.substr(at, 8000));
      if (cover) return cover;
    }
    return this.__coverIn(html.substr(0, Math.min(html.length, 30000)));
  },

  /// 详情信息：作者 / 状态 / 更新 / 简介 / 题材，两套主题的标记都试。
  __detailInfo(html) {
    var result = { author: '', status: '', updated: '', description: '', tags: [] };
    result.author = this.__cut(this.__blockText(html, 'class="author"', '</a>', 300) ||
      this.__blockText(html, 'class="author"', '</p>', 300), 40);
    result.status = this.__cut(this.__blockText(html, 'class="detail-status"', '</p>', 600) ||
      this.__blockText(html, 'class="status', '</span>', 300), 30);
    result.updated = this.__cut(this.__blockText(html, 'class="update"', '</p>', 300), 40);
    for (var i = 0; i < SUMMARY_MARKS.length; i++) {
      var marker = SUMMARY_MARKS[i];
      var close = marker.indexOf('synopsis') >= 0 ? '</details>' : '</p>';
      var text = this.__blockText(html, marker, close, 40000);
      if (text) { result.description = this.__cut(text, 600); break; }
    }
    result.tags = this.__detailTags(html);
    return result;
  },

  /// 取 `marker` 所在元素的文字（从它的 `>` 读到 closeTag）。
  __blockText(html, marker, closeTag, limit) {
    var at = html.indexOf(marker);
    if (at < 0) return '';
    var open = html.indexOf('>', at);
    if (open < 0) return '';
    var close = html.indexOf(closeTag, open);
    if (close < 0 || close - open > limit) close = Math.min(html.length, open + limit);
    return this.__text(html.slice(open + 1, close));
  },

  /// 题材：详情页 `a.tag`（default2）/ `a.tag-link`（default7），按文字去重。
  __detailTags(html) {
    var tags = [];
    var seen = {};
    var at = 0;
    var scanned = 0;
    while (tags.length < TAG_LIMIT && scanned < 40) {
      var tagStart = html.indexOf('class="tag', at);
      if (tagStart < 0) break;
      scanned++;
      var open = html.indexOf('>', tagStart);
      var close = open >= 0 ? html.indexOf('</a>', open) : -1;
      if (open < 0 || close < 0) break;
      var text = this.__plain(html.slice(open + 1, close));
      if (text && text.length <= 10 && !seen[text]) {
        seen[text] = true;
        tags.push(text);
      }
      at = close;
    }
    return tags;
  },

  /// 目录：div.chapter-list 里的 `/chapter?Id={数字}` 锚。标题优先 span 的 title 属性
  /// （default7 写成 `title="第7話-無套會更爽♥"`），否则读 span 里的文字。
  __catalog(html) {
    var start = html.indexOf('class="chapter-list"');
    var area = '';
    if (start >= 0) {
      var end = html.indexOf('</section>', start);
      if (end < 0 || end - start > CATALOG_SCAN) end = Math.min(html.length, start + CATALOG_SCAN);
      area = html.slice(start, end);
    } else {
      area = html.slice(0, Math.min(html.length, CATALOG_SCAN));
    }
    var rows = [];
    var seen = {};
    var at = 0;
    var scanned = 0;
    while (rows.length < MAX_CHAPTERS) {
      at = area.indexOf('<a', at);
      if (at < 0) break;
      if (++scanned > MAX_CHAPTERS * 2) break;
      var tagEnd = area.indexOf('>', at);
      if (tagEnd < 0) break;
      var tag = area.slice(at, tagEnd + 1);
      var href = this.__attr(tag, 'href');
      var url = this.__chapterUrl(href, '');
      if (!url) {
        at = tagEnd + 1;
        continue;
      }
      var close = area.indexOf('</a>', tagEnd);
      var innerEnd = close > tagEnd ? close : Math.min(area.length, tagEnd + 1200);
      var inner = area.slice(tagEnd + 1, innerEnd);
      if (!seen[url]) {
        var raw = this.__chapterLabel(inner);
        if (raw) {
          seen[url] = true;
          rows.push({
            id: url,
            raw: raw,
            number: this.__number(raw),
            vip: inner.indexOf('vip-badge') >= 0 || inner.indexOf('VIP') >= 0,
            order: rows.length
          });
        }
      }
      at = innerEnd;
    }
    return rows;
  },

  /// 章节名：`<span title="第7話-無套會更爽♥">…` 优先取 title；
  /// 否则取 span 文字（会带 <b>第7話</b> 这类子标签，__text 会去掉）。
  __chapterLabel(inner) {
    var at = inner.indexOf('<span');
    if (at >= 0) {
      var open = inner.indexOf('>', at);
      if (open >= 0) {
        var own = this.__plain(this.__attr(inner.slice(at, open + 1), 'title'));
        if (own) return this.__cut(own, 80);
        var close = inner.indexOf('</span>', open);
        if (close > open) {
          var text = this.__text(inner.slice(open + 1, close));
          if (text) return this.__cut(text, 80);
        }
      }
    }
    var cut = inner.indexOf('<small');
    var head = cut > 0 ? inner.slice(0, cut) : inner;
    var timeAt = head.indexOf('<time');
    if (timeAt > 0) head = head.slice(0, timeAt);
    return this.__cut(this.__text(head), 80);
  },

  /// 「第7話-無套會更爽♥」→ 7（站点自己用阿拉伯数字 + 話/话/章，实测全是这个形状）。
  /// 单遍字符扫描，不用带 /g 的正则（避免 lastIndex 跨调用复用）。
  __number(text) {
    var value = String(text || '');
    var at = value.indexOf('第');
    while (at >= 0) {
      var i = at + 1;
      var start = i;
      while (i < value.length && i - start < 5) {
        var code = value.charCodeAt(i);
        if (code < 48 || code > 57) break;
        i++;
      }
      if (i > start && i < value.length && '话話章回集'.indexOf(value.charAt(i)) >= 0) {
        return Number(value.slice(start, i));
      }
      at = value.indexOf('第', at + 1);
    }
    return -1;
  },

  /// 章节标题统一成「第 N 话」：话数后面的副标题保留（截断 40 字），VIP 加尾注。
  __chapterTitle(row) {
    var num = row.number;
    if (!(num >= 0)) return this.__cut(row.raw, 60);
    var label = '第' + num + '话';
    var rest = this.__chapterName(row.raw, num);
    if (rest) label += ' ' + rest;
    if (row.vip) label += ' · VIP';
    return this.__cut(label, 60);
  },

  /// 话数后面的副标题（去掉开头的 -、空格、冒号）。
  __chapterName(raw, num) {
    var value = String(raw || '');
    var at = value.indexOf('第');
    if (at < 0) return '';
    var i = at + 1;
    while (i < value.length && value.charCodeAt(i) >= 48 && value.charCodeAt(i) <= 57) i++;
    if (i < value.length && '话話章回集'.indexOf(value.charAt(i)) >= 0) i++;
    var rest = value.slice(i).trim();
    while (rest && '-－—_~～:：·.。、 '.indexOf(rest.charAt(0)) >= 0) rest = rest.slice(1).trim();
    return this.__cut(rest, 40);
  },

  /// 排序：站点自己的顺序是**新→旧**，但并非严格按话数（实测《秘密教学》240 话的
  /// 末尾是「…第226話、第2話、第225話、第1話」这种倒挂，另夹着 4 条
  /// 「休刊公告 / 停刊一周公告」这类没有话数的条目）。所以：
  ///   · 话数齐全且不重复 → 按话数升序，没有话数的公告排到末尾（读正文用不到它们）；
  ///   · 有重复话数（第二季/重制）→ 话数不是全序，整体退回站点顺序不动；
  ///   · 一条话数都认不出 → 反转站点顺序（让 index 0 落在最早的一话）。
  __order(rows) {
    var i;
    var numbered = [];
    var bare = [];
    var counts = {};
    var duplicated = false;
    for (i = 0; i < rows.length; i++) {
      if (rows[i].number >= 0) {
        if (counts[rows[i].number]) duplicated = true;
        counts[rows[i].number] = true;
        numbered.push(rows[i]);
      } else {
        bare.push(rows[i]);
      }
    }
    var list = [];
    if (!duplicated && numbered.length > 1 && numbered.length >= rows.length * 0.8) {
      numbered.sort(function (a, b) {
        return a.number - b.number || a.order - b.order;
      });
      list = numbered.concat(bare);
    } else if (!duplicated) {
      list = rows.slice().reverse();
    } else {
      list = rows.slice();
    }
    var out = [];
    for (i = 0; i < list.length; i++) out.push({ id: list[i].id, title: this.__chapterTitle(list[i]) });
    return out;
  },

  /// 正文图：div.reader-images / div.reader-panels 里的 img。**URL 没有扩展名**
  /// （/comic/media?comic=…&chapter=…&image={sha256}），所以按「带 /comic/media」
  /// 判正文图，再把 &amp; 解回 &；同一张图在懒加载属性与 noscript 里各出现一次 → 按 URL 去重。
  __readerImages(html) {
    var area = '';
    for (var i = 0; i < READER_MARKS.length; i++) {
      var at = html.indexOf(READER_MARKS[i]);
      if (at >= 0) {
        area = html.substr(at, MAX_INLINE_SCAN);
        break;
      }
    }
    if (!area) area = html.slice(0, Math.min(html.length, MAX_INLINE_SCAN));
    var images = [];
    var seen = {};
    var at2 = area.indexOf('<img');
    var scanned = 0;
    while (at2 >= 0 && images.length < MAX_IMAGES) {
      if (++scanned > MAX_IMG_TAGS) break;
      var end = area.indexOf('>', at2);
      if (end < 0) break;
      var tag = area.slice(at2, end + 1);
      var lazies = ['data-lazy-src', 'data-src', 'data-original', 'src'];
      for (var j = 0; j < lazies.length; j++) {
        var url = this.__attr(tag, lazies[j]);
        if (!url || !this.__isPageImage(url)) continue;
        var absolute = this.__absolute(this.__decode(url));
        if (absolute && !seen[absolute]) {
          seen[absolute] = true;
          images.push(absolute);
        }
        break;
      }
      at2 = area.indexOf('<img', end);
    }
    return images;
  },

  /// 正文图判定：带 /comic/media 的站内路由，或者是常规图片扩展名（站点换域名/换路由时的兜底）。
  __isPageImage(url) {
    var text = String(url || '').trim();
    if (!text || text.length > 900) return false;
    if (text.indexOf('data:') === 0) return false;
    if (SKIP_IMAGE.test(text)) return false;
    if (text.indexOf('/comic/media') >= 0) return true;
    var path = text.split('?')[0].toLowerCase();
    if (this.__endsWith(path, '.svg')) return false;
    return this.__isImagePath(path);
  },

  __isVipPage(html) {
    return /VIP|vip-badge|付费|解锁|会员专享/.test(html) &&
      !/comic\/media/.test(html);
  },

  /// 有没有下一页：站点的分页器给 `rel="next"`（末页改成 aria-disabled 的「下一页」，
  /// 实测末页 rel="next" 数量为 0）。认不出分页器时按条数兜底。
  __hasNext(html, page) {
    if (html.indexOf('rel="next"') >= 0) return true;
    var current = page > 0 ? page : 1;
    var at = html.indexOf('共 ');
    if (at >= 0) {
      var digits = this.__digits(html.slice(at + 2, at + 10));
      if (digits && Number(digits) > current) return true;
    }
    return false;
  },

  // ---------------------------------------------------------------- 基础工具

  async __get(url) {
    var response = await LumeSource.http.get(url, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'zh-CN,zh;q=0.9'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 && /vip|会员|付费|解锁/i.test(body)) {
        throw new Error(SITE_NAME + '：这一话是 VIP 付费章节（HTTP 403 ' + url + '）');
      }
      if (status === 403 || status === 503 || status === 429 ||
          /just a moment|__cf_chl|cf-chl|cf-mitigated|checking your browser/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：' + SITE_NAME + ' 需要网页视图过一次 Cloudflare 校验（HTTP ' + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    }
    // 注意：正常页面里也有 `/cdn-cgi/challenge-platform/scripts/jsd/main.js`（CF 的 JS 探测，
    // 不是挑战页），所以只在「明显是拦截页」时才抛 NEED_WEBVIEW_VERIFY：
    // 要么标题是 Just a moment，要么是 cf-error / cf-browser-verification 那种完整拦截页。
    if (/<title>\s*Just a moment/i.test(body) ||
        /id="cf-error-details"|cf-browser-verification|__cf_chl_opt/i.test(body)) {
      throw new Error('NEED_WEBVIEW_VERIFY：' + SITE_NAME + ' 需要网页视图过一次 Cloudflare 校验（' + url + '）');
    }
    return body;
  },

  __absolute(url) {
    var text = String(url || '').trim();
    if (!text) return '';
    if (text.indexOf('//') === 0) return 'https:' + text;
    if (text.indexOf('http') === 0) return text;
    if (text.charAt(0) === '/') return BASE_URL + text;
    return BASE_URL + '/' + text;
  },

  __decode(text) {
    return String(text || '')
      .replace(/&amp;/g, '&')
      .replace(/&#38;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
  },

  /// 查询串用的 UTF-8 百分号编码（字母数字与 -_.~ 原样，其余全编码）。
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
      if (low >= 0xDC00 && low <= 0xDFFF) value = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
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

  /// 标签属性。只认带引号的写法；属性名前一个字符必须是空白，免得把 data-href 当 href。
  __attr(tag, name) {
    var needle = name + '=';
    var at = tag.indexOf(needle);
    var scanned = 0;
    while (at >= 0 && scanned < 12) {
      scanned++;
      var before = at > 0 ? tag.charCodeAt(at - 1) : 32;
      if (this.__isSpace(before)) {
        var value = this.__attrValue(tag, at + needle.length);
        if (value) return value;
      }
      at = tag.indexOf(needle, at + needle.length);
    }
    return '';
  },

  __attrValue(text, from) {
    var quote = text.charAt(from);
    if (quote !== '"' && quote !== "'") return '';
    var end = text.indexOf(quote, from + 1);
    if (end < 0) return '';
    return text.slice(from + 1, end);
  },

  __titleTag(html) {
    var at = html.indexOf('<title>');
    if (at < 0) return '';
    var end = html.indexOf('</title>', at);
    if (end < 0) return '';
    return this.__plain(html.slice(at + 7, end));
  },

  __stripBrackets(text) {
    var value = String(text || '').trim();
    if (value.length > 2 && value.charAt(0) === '《' && value.charAt(value.length - 1) === '》') {
      value = value.slice(1, value.length - 1);
    }
    return value.trim();
  },

  __digits(text) {
    var value = String(text == null ? '' : text).trim();
    if (!value) return '';
    var out = '';
    for (var i = 0; i < value.length && i < 12; i++) {
      var code = value.charCodeAt(i);
      if (code < 48 || code > 57) break;
      out += value.charAt(i);
    }
    return out;
  },

  __endsWith(text, suffix) {
    return text.length >= suffix.length && text.slice(text.length - suffix.length) === suffix;
  },

  __isSpace(code) {
    return code === 32 || code === 9 || code === 10 || code === 13 || code === 12;
  },

  __cut(text, limit) {
    var value = String(text == null ? '' : text);
    return value.length > limit ? value.slice(0, limit) : value;
  },

  /// 去标签 + 压空白（只为展示用的少量文本调用；喂给 replace 不用 exec）。
  __plain(text) {
    var value = String(text == null ? '' : text);
    if (value.indexOf('<') >= 0) value = value.replace(/<[^>]*>/g, ' ');
    return this.__decode(value)
      .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&hellip;/g, '…').replace(/&hearts;/g, '♥')
      .replace(/\s+/g, ' ').trim();
  },

  /// 文本化：先去标签再解实体（章节名里有 ♥、·、?! 这类字符，保留原样）。
  __text(text) {
    return this.__plain(text);
  }
};
