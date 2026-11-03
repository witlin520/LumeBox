// LumeSource: {"id":"ihanman_comic","name":"爱韩漫","version":"1.0.0","category":"comic","mirrors":["https://www.ihanman.com"]}

// 站点：https://www.ihanman.com（移动版 m.ihanman.com，标记与桌面版**完全同款**，脚本只用 www）
//
// ## 抓取口径（全部对着实时页面核过）
//
//   分类  GET /all（全部）、/all/area/{guonei|riben|hanguo|oumei}、/all/theme/{slug}、
//         /new（最近更新）、/hot（排行榜）。分类条是首页 navbar + subnav 里的真实链接，
//         categories() 每次现读（读不到才用内置兜底），id 就是站内路径。
//   列表  GET {分类}/page/{N}，30 条/页，分页器 `div.pages > ul.pagination` 里写
//         `/all/page/2` 这种**路径段**（`?page=2` 实测无效，会回第 1 页内容）。
//         /hot 与 /new 是**整表页**（没有分页器），只有第 1 页。
//   搜索  GET /search?q={关键词}。表单里那个 `__searchtoken__` 隐藏字段**不校验**
//         （带 token / 不带 token 返回的字节数完全一致，都是同一批结果），也**不分页**
//         （`/search?q=x&page=2` 与 `/search/page/2?q=x` 都落到「未找到相关漫画」），
//         所以搜索固定 hasMore=false。
//   详情  GET /detail/{10位id}：标题 `h1.metas-title`、封面 `div.metas-image > img[src]`
//         （图在 img.ihanman.com，带不带 Referer 都是 200）、简介 `div.metas-desc`、
//         作者/状态/地区是 `div.metas-body > span.author`、题材是该体里的 `/all/theme/…` 锚。
//   目录  就在详情页：`ul.comic-chapters > li > a[href=/detail/{id}/{n}.html]`，旧→新。
//   正文  GET /detail/{id}/{n}.html。**页面里没有 img 标签**：图片在
//         `<script>var config = …, params = '<base64>'</script>` 这一段里，由
//         /static/js/cms.min.js 的 CMS.chapter.decrypt() 解开，算法是
//           base64 解码 → 前 16 字节当 IV → 余下做 AES-128-CBC(PKCS7) → JSON.parse
//         密钥写死在 cms.min.js 里：`5V&RoR%Jf@pJPydF`（16 字节 ASCII）。
//         沙箱里没有 atob/Buffer，所以本源自带 base64 解码 + AES-128-CBC 解密 + UTF-8 解码
//         （约 120 行纯 ES5），解出来的 JSON 才有 `chapter_images`。
//
// ## 两个实测出来的坑（写错就整章空白）
//
// 1. **图片必须补 `.webp` 后缀**。params 里给的 `chapter_images` 全是 `…/1.jpg`，
//    而这个 CDN（c-nd3-1.6wm.top）上真实文件是 `…/1.webp`；原样请求 `.jpg` 一律
//    404（无 Referer）或 301 到 `/link/link.webp`（带 Referer）。实测 8/10 条
//    `.webp` 都是 200 image/webp。所以 content() 会对第一条图片做一次 Range 探测：
//    原样能拿 200/206 就用原样，否则换 `.webp` 再探，选定后统一套用。
// 2. **图片域名不能带 Referer**。给 c-nd3 发任何 Referer（本站首页/章节页/自身域名）
//    都会回 301 → `https://c-nd3-1.6wm.top/link/link.webp`（防盗链占位图）；
//    不带 Referer 才是 200/206。所以 content() 返回的 headers 里**不放 Referer**，
//    这也是本站图片能在 App 里正常显示的前提。
//
// 另外 params 里还有 `images_domain`(+`images_base64`)，那是 cms 的「网关」模式
// （把图片 URL base64 后拼到 two.mhpic.net/ 后面）。该网关本机实测一律 404/403，
// 而直连 CDN 的 .webp 可用，所以本源走直连，不碰网关。

var BASE_URL = 'https://www.ihanman.com';

var PAGE_SIZE = 30;          // 列表每页条数（实测 /all 一页 30 条）
var MAX_ITEMS = 120;         // 单次列表最多产出
var ITEM_WINDOW = 900;       // 单条 item 往后看的窗口
var MAX_ITEMS_SCAN = 150;    // 最多扫多少个作品锚
var MAX_CHAPTERS = 3000;     // 目录最多解析多少话
var MAX_IMAGES = 400;        // 正文最多收多少张图
var DETAIL_SCAN = 200000;    // 详情/正文页最多扫多少字符

// 整表页（站点没有分页器，只有第 1 页）
var SINGLE_PAGE_PATHS = ['/hot', '/new'];

// 不是封面的图
var SKIP_IMAGE = /logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|spacer|234x60/i;

var LumeSource = {
  id: 'ihanman_comic',
  name: '爱韩漫',
  version: '1.0.0',
  category: 'comic',

  // ---------------------------------------------------------------- 分类

  /// 分类条就是站点自己的 navbar + subnav（全部 / 国内 / 日本 / 韩国 / 欧美 / 最近更新 /
  /// 排行榜 / 题材…）。id 用站内路径，list() 原样认。
  async categories() {
    var html = await this.__get(BASE_URL + '/');
    var found = this.__navCategories(html);
    if (found.length) {
      console.warn('[ihanman] 分类 ' + found.length + ' 项（现读站点导航）');
      return found;
    }
    console.warn('[ihanman] 导航没认出分类，用内置兜底');
    return this.__fallbackCategories();
  },

  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = this.__boards(html);
    if (boards.length) {
      console.warn('[ihanman] 首页板块 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ categoryId: '/all', page: 1 });
    if (latest && latest.items && latest.items.length) {
      console.warn('[ihanman] 首页没认出板块，退回列表一块');
      return [{ title: '全部漫画', moreUrl: '/all', items: latest.items.slice(0, 12) }];
    }
    return [];
  },

  // ---------------------------------------------------------------- 列表

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    var url = this.__listUrl(category, keyword, page);
    if (!url) {
      console.warn('[ihanman] 「' + (category || '全部') + '」只有第 1 页，第 ' + page + ' 页返回空');
      return { items: [], hasMore: false };
    }
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[ihanman] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[ihanman] 列表命中：' + url + '（' + items.length + ' 条）');
    return { items: items, hasMore: this.__hasNext(html, page) };
  },

  __listUrl(category, keyword, page) {
    if (keyword) {
      // 搜索只有一页（见文件头），第 2 页直接给空，不去请求必然「未找到」的地址。
      if (page > 1) return '';
      return BASE_URL + '/search?q=' + this.__encode(keyword);
    }
    var path = this.__categoryPath(category);
    if (this.__isSinglePagePath(path)) {
      if (page > 1) return '';
      return BASE_URL + this.__encodePath(path);
    }
    if (page > 1) path = path.replace(/\/$/, '') + '/page/' + page;
    return BASE_URL + this.__encodePath(path);
  },

  __categoryPath(category) {
    var id = String(category == null ? '' : category).trim();
    if (!id) return '/all';
    if (id.charAt(0) === '/') return id;
    if (id.indexOf('http') === 0) {
      if (id.indexOf(BASE_URL) === 0) {
        var rest = id.slice(BASE_URL.length);
        return rest || '/all';
      }
      var m = /^https?:\/\/[^\/]+(\/.*)$/.exec(id);
      if (m) return m[1];
      return '/all';
    }
    return '/' + id;
  },

  __isSinglePagePath(path) {
    for (var i = 0; i < SINGLE_PAGE_PATHS.length; i++) {
      if (path === SINGLE_PAGE_PATHS[i]) return true;
    }
    return false;
  },

  // ---------------------------------------------------------------- 详情 / 目录

  async detail(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/detail/' + id;
    var html = await this.__get(url);
    var info = this.__detailFields(html);
    if (!info.title) {
      console.warn('[ihanman] 详情页没认出标题：' + url + '（' + html.length + ' 字符）');
      return null;
    }
    return {
      id: url,
      title: info.title,
      cover: info.cover,
      subtitle: this.__subtitle(info),
      description: info.description,
      tags: info.tags,
      extra: { author: info.author, status: info.status, area: info.area, updated: info.updated }
    };
  },

  async chapters(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/detail/' + id;
    var html = await this.__get(url);
    var chapters = this.__chapters(html, id);
    if (!chapters.length) {
      console.warn('[ihanman] 目录为空：' + url + '（该作品可能还没更新）');
      return [];
    }
    console.warn('[ihanman] 目录 ' + chapters.length + ' 话：' + url);
    return chapters;
  },

  // ---------------------------------------------------------------- 正文

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('爱韩漫：缺少章节 ID（请先选择一话）');
    var url = this.__chapterUrl(chapterId, argument && argument.id);
    if (!url) throw new Error('爱韩漫：认不出章节地址（' + chapterId + '）');
    var html = await this.__get(url);
    var obj = this.__params(html);
    if (!obj) {
      throw new Error('爱韩漫：这一话没解出 params（' + url + '）——页面结构变了');
    }
    if (obj.comic_status === 'down') {
      throw new Error('爱韩漫：这一话已下架（' + url + '）');
    }
    var images = this.__images(obj);
    if (!images.length) {
      throw new Error('爱韩漫：这一话没解析出图片（' + url + '）');
    }
    images = await this.__pickImageForm(images);
    console.warn('[ihanman] 正文 ' + images.length + ' 张图：' + url);
    // 图片域名对任何 Referer 都 301 到防盗链占位图（见文件头「坑 2」）→ 不带 Referer。
    return { kind: 'images', images: images, headers: {} };
  },

  __chapterUrl(chapterId, itemId) {
    var value = String(chapterId || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      if (value.indexOf(BASE_URL) === 0) return value;
      return '';
    }
    if (value.charAt(0) === '/') return BASE_URL + value;
    // 只给了 {n}：用作品 id 拼站点自己的形状 /detail/{id}/{n}.html
    if (/^\d+$/.test(value)) {
      var book = '';
      try { book = this.__bookId(itemId); } catch (error) { book = ''; }
      if (!book) return '';
      return BASE_URL + '/detail/' + book + '/' + value + '.html';
    }
    return '';
  },

  /// 取 `<script>var config = {…}, params = '<base64>'</script>` 里的 params 并解密。
  /// ⚠️ base64 会随图片数量变长（41 张图那话就 17KB+），所以**不切窗口**：
  /// 定位到 `params = '` 之后直接找下一个单引号，再整段解密。
  __params(html) {
    var at = html.indexOf('params');
    var guard = 0;
    while (at >= 0 && guard < 200) {
      guard++;
      var head = html.slice(at, Math.min(html.length, at + 40));
      var m = /^params\s*=\s*'/.exec(head);
      if (m) {
        var start = at + m[0].length;
        var end = html.indexOf("'", start);
        if (end > start) {
          try {
            return this.__decryptParams(html.slice(start, end));
          } catch (error) {
            console.warn('[ihanman] params 解密失败：' + (error && error.message));
            return null;
          }
        }
      }
      at = html.indexOf('params', at + 6);
    }
    return null;
  },

  __images(obj) {
    var raw = obj.chapter_images || [];
    var local = obj.chapter_local_images || [];
    var all = [];
    var i;
    for (i = 0; i < local.length; i++) all.push(local[i]);
    for (i = 0; i < raw.length; i++) all.push(raw[i]);
    var out = [];
    var seen = {};
    for (i = 0; i < all.length && out.length < MAX_IMAGES; i++) {
      var url = this.__imageUrl(all[i], obj);
      if (url && !seen[url]) {
        seen[url] = true;
        out.push(url);
      }
    }
    return out;
  },

  __imageUrl(value, obj) {
    var text = String(value == null ? '' : value).trim();
    if (!text) return '';
    if (text.indexOf('http') !== 0) {
      var domain = String(obj.images_domain || '');
      if (domain) {
        if (obj.images_base64) text = domain + this.__b64encode(text);
        else text = domain + text.replace(/^\//, '');
      }
    }
    text = this.__absolute(text);
    if (!/^https?:\/\//i.test(text)) return '';
    if (SKIP_IMAGE.test(text)) return '';
    return text;
  },

  /// 图片后缀实测：params 里写 `.jpg`，CDN 上真实文件是 `.webp`（见文件头「坑 1」）。
  /// 先拿第一条探一次：原样能 200/206 就整章用原样；否则换 `.webp` 再探，
  /// 成功就整章套 `.webp`；两次都不行就原样返回（至少 App 里能看到链接）。
  async __pickImageForm(images) {
    var first = images[0];
    if (this.__endsWith(String(first).toLowerCase(), '.webp')) return images;
    var direct = await this.__head(first);
    if (direct) return images;
    var swapped = this.__toWebp(first);
    if (!swapped) return images;
    if (await this.__head(swapped)) return this.__mapWebp(images);
    // 首图文件可能单独缺失（站点自己也会缺页）→ 再看一眼中段图，别因为一张图否定整章
    var mid = images[Math.floor(images.length / 2)];
    if (mid && mid !== first && (await this.__head(this.__toWebp(mid)))) return this.__mapWebp(images);
    return images;
  },

  __mapWebp(images) {
    var out = [];
    for (var i = 0; i < images.length; i++) out.push(this.__toWebp(images[i]));
    return out;
  },

  __toWebp(url) {
    return String(url).replace(/\.(jpg|jpeg|png)(\?|$)/i, '.webp$2');
  },

  async __head(url) {
    try {
      var res = await LumeSource.http.get(url, { headers: { 'Range': 'bytes=0-99' } });
      if (!res) return false;
      var status = Number(res.status);
      return status === 200 || status === 206;
    } catch (error) {
      return false;
    }
  },

  // ---------------------------------------------------------------- 解析

  /// 作品 id：绝对地址 / 站内路径 / 裸 10 位 id 都认。
  __bookId(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    else if (typeof argument === 'string') id = argument;
    var value = String(id || '').trim();
    if (!value) throw new Error('爱韩漫：缺少作品 ID');
    if (value.indexOf('http') === 0) value = value.replace(BASE_URL, '');
    var m = /\/detail\/([A-Za-z0-9]{6,20})(?:\/|$)/.exec(value);
    if (m) return m[1];
    if (/^[A-Za-z0-9]{6,20}$/.test(value)) return value;
    throw new Error('爱韩漫：认不出的作品 ID（' + id + '）');
  },

  __navCategories(html) {
    var out = [];
    var seen = {};
    var start = html.indexOf('<nav class="navbar"');
    var end = html.indexOf('<main', start < 0 ? 0 : start);
    if (start < 0) return out;
    if (end < 0 || end - start > 12000) end = Math.min(html.length, start + 12000);
    var area = html.slice(start, end);
    var at = area.indexOf('<a ');
    var guard = 0;
    while (at >= 0 && guard < 80) {
      guard++;
      var tagEnd = area.indexOf('>', at);
      if (tagEnd < 0) break;
      var tag = area.slice(at, tagEnd + 1);
      var href = this.__attr(tag, 'href');
      var title = this.__plain(this.__textAfter(area, tagEnd + 1, 40));
      var path = this.__navPath(href);
      if (path && title && !seen[path] && title !== '首页') {
        seen[path] = true;
        out.push({ id: path, title: this.__cut(title, 12) });
      }
      at = area.indexOf('<a ', tagEnd);
    }
    // 排序：**韩国放第一档**（这就是「爱韩漫」，站点主力也是韩漫），然后「全部」，
    // 再按站点原顺序排其余。实测 `/all`（全部）第 1 条是《一人之下》，那一部的
    // 图片在 CDN 上整套 404（.jpg 与 .webp 都没有，站点自己缺图），放在默认页会是一片空白；
    // 韩国档第 1 条的作品实测 .webp 都是 200，默认页才有内容。
    var ordered = [];
    var i;
    var used = {};
    var preferred = ['/all/area/hanguo', '/all'];
    for (i = 0; i < preferred.length; i++) {
      for (var j = 0; j < out.length; j++) {
        if (out[j].id === preferred[i] && !used[out[j].id]) {
          used[out[j].id] = true;
          ordered.push(out[j]);
        }
      }
    }
    if (!used['/all']) ordered.push({ id: '/all', title: '全部' });
    for (i = 0; i < out.length; i++) {
      if (!used[out[i].id]) {
        used[out[i].id] = true;
        ordered.push(out[i]);
      }
    }
    return ordered;
  },

  __navPath(href) {
    var text = String(href || '').trim();
    if (!text || text.charAt(0) === '#') return '';
    if (text.indexOf('http') === 0) {
      if (text.indexOf(BASE_URL) !== 0) return '';
      text = text.slice(BASE_URL.length);
    }
    if (text === '/' || text === '') return '';
    if (text.charAt(0) !== '/') return '';
    if (text.indexOf('/all') !== 0 && text !== '/new' && text !== '/hot') return '';
    if (text.indexOf('/page/') >= 0) return text;
    return text;
  },

  __fallbackCategories() {
    return [
      { id: '/all', title: '全部' },
      { id: '/new', title: '最近更新' },
      { id: '/hot', title: '排行榜' },
      { id: '/all/area/guonei', title: '国内' },
      { id: '/all/area/riben', title: '日本' },
      { id: '/all/area/hanguo', title: '韩国' },
      { id: '/all/area/oumei', title: '欧美' }
    ];
  },

  /// 首页板块：一个 `div.panel.is-white` 一块，标题在 `div.panel-heading > h2`，
  /// 条目是 `div.grid > div.cell.comic-item`；右侧「人气排行榜」用的是 `div.media`，
  /// 收不到 comic-item 的板块自动跳过（不把排行榜当板块）。
  __boards(html) {
    var boards = [];
    var found = 0;
    var at = html.indexOf('class="panel is-white');
    var titleMap = this.__navTitleMap(html);
    while (at >= 0 && boards.length < 10) {
      var next = html.indexOf('class="panel is-white', at + 20);
      var stop = next > at ? next : Math.min(html.length, at + 40000);
      var window = html.slice(at, stop);
      var title = this.__h2Title(window);
      var items = this.__items(window);
      if (title && items.length) {
        boards.push({ title: this.__cut(title, 16), moreUrl: titleMap[title] || '', items: items.slice(0, 12) });
      }
      found++;
      at = next;
      if (found > 14) break;
    }
    return boards;
  },

  /// 板块标题 → 站内路径（首页导航里的同名锚，例如「韩国」→ /all/area/hanguo）。
  __navTitleMap(html) {
    var map = {};
    var start = html.indexOf('<nav class="navbar"');
    if (start < 0) return map;
    var end = Math.min(html.length, start + 12000);
    var area = html.slice(start, end);
    var at = area.indexOf('<a ');
    var guard = 0;
    while (at >= 0 && guard < 80) {
      guard++;
      var tagEnd = area.indexOf('>', at);
      if (tagEnd < 0) break;
      var tag = area.slice(at, tagEnd + 1);
      var path = this.__navPath(this.__attr(tag, 'href'));
      var title = this.__plain(this.__textAfter(area, tagEnd + 1, 40));
      if (path && title && !map[title]) map[title] = path;
      at = area.indexOf('<a ', tagEnd);
    }
    if (!map['最近更新']) map['最近更新'] = '/new';
    return map;
  },

  __h2Title(window) {
    var at = window.indexOf('<h2');
    if (at < 0) return '';
    var open = window.indexOf('>', at);
    if (open < 0) return '';
    var close = window.indexOf('</h2>', open);
    if (close < 0) return '';
    return this.__plain(window.slice(open + 1, close));
  },

  /// 列表条目：站点两套卡片，统一按「作品锚」抓
  ///   列表/搜索：`<a class="image lazy" href="/detail/{id}" data-original="封面">标题</a>`
  ///             + 紧随的 `div.media-content`（`a.title` / `li 最新：` 副标题）
  ///   首页格子：`<a href="/detail/{id}"><div class="image lazy" data-original="封面">
  ///             </div><div class="name">标题</div></a><p class="chapter">最新话</p>`
  __items(html) {
    var items = [];
    var seen = {};
    var at = html.indexOf('/detail/');
    var guard = 0;
    while (at >= 0 && items.length < MAX_ITEMS) {
      if (++guard > MAX_ITEMS_SCAN * 4) break;
      var seg = html.substr(at + 8, 12);
      var m = /^([A-Za-z0-9]{6,20})(\/|$|")/.exec(seg);
      if (!m) {
        at = html.indexOf('/detail/', at + 8);
        continue;
      }
      var id = m[1];
      if (m[2] === '/') { // 章节链接，不是作品
        at = html.indexOf('/detail/', at + 8);
        continue;
      }
      if (!seen[id]) {
        var anchorAt = html.lastIndexOf('<a ', at);
        var item = anchorAt >= 0 ? this.__itemAt(html, anchorAt, id) : null;
        if (item) {
          seen[id] = true;
          items.push(item);
        }
      }
      at = html.indexOf('/detail/', at + 8);
    }
    return items;
  },

  __itemAt(html, anchorAt, id) {
    var tagEnd = html.indexOf('>', anchorAt);
    if (tagEnd < 0) return null;
    var tag = html.slice(anchorAt, tagEnd + 1);
    var href = this.__attr(tag, 'href') || '';
    if (href.indexOf('/detail/' + id) !== 0) return null;
    var window = html.substr(anchorAt, ITEM_WINDOW);
    var title = this.__plain(this.__attr(tag, 'title')) ||
      this.__plain(this.__textAfter(window, tagEnd - anchorAt + 1, 120)) ||
      this.__classText(window, 'name text-ignore') ||
      this.__classText(window, 'name') ||
      this.__classText(window, 'title');
    title = this.__cut(this.__stripBrackets(title), 80);
    if (!title) return null;
    var cover = this.__firstAttr(window, 'data-original') || this.__firstAttr(window, 'data-setbg');
    if (!cover) {
      var img = /<img[^>]*src="(https?:\/\/[^"]*img\.ihanman\.com[^"]*)"/i.exec(window);
      if (img) cover = img[1];
    }
    var subtitle = this.__classText(window, 'chapter') || this.__latestIn(window);
    return {
      id: BASE_URL + '/detail/' + id,
      title: title,
      cover: this.__absolute(cover),
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut(this.__plain(subtitle), 40)
    };
  },

  /// 列表页的「最新：第12话」那一行
  __latestIn(window) {
    var at = window.indexOf('最新');
    if (at < 0) return '';
    var close = window.indexOf('</li>', at);
    if (close < 0) return '';
    var row = window.slice(at + 2, close);
    var m = /<span>([\s\S]{0,60}?)<\/span>/.exec(row);
    if (m) return this.__plain(m[1]);
    return this.__plain(row).replace(/^[:：]\s*/, '');
  },

  __hasNext(html, page) {
    var pager = html.indexOf('class="pages');
    if (pager < 0) return false;
    var max = this.__maxPageIn(html.substr(pager, 4000));
    if (max > page) return true;
    if (max > 0) return false;
    return false;
  },

  __maxPageIn(text) {
    var best = 0;
    var at = text.indexOf('/page/');
    var guard = 0;
    while (at >= 0 && guard < 200) {
      guard++;
      var i = at + 6;
      var value = 0;
      var digits = 0;
      while (i < text.length && digits < 4) {
        var code = text.charCodeAt(i);
        if (code < 48 || code > 57) break;
        value = value * 10 + (code - 48);
        i++;
        digits++;
      }
      if (digits && value > best) best = value;
      at = text.indexOf('/page/', i);
    }
    return best;
  },

  __detailFields(html) {
    var info = { title: '', cover: '', description: '', author: '', status: '', area: '', updated: '', tags: [] };
    var at = html.indexOf('metas-title');
    if (at >= 0) {
      var open = html.indexOf('>', at);
      var close = html.indexOf('</h1>', open);
      if (open >= 0 && close > open) info.title = this.__cut(this.__plain(html.slice(open + 1, close)), 120);
    }
    if (!info.title) {
      var raw = this.__titleTag(html);
      var cut = raw.indexOf(' - ');
      if (cut > 0) raw = raw.slice(0, cut);
      info.title = this.__plain(this.__stripBrackets(raw));
    }
    var pick = html.indexOf('metas-image');
    if (pick >= 0) {
      var img = /<img[^>]*src="([^"]+)"/.exec(html.slice(pick, pick + 800));
      if (img) info.cover = this.__absolute(img[1]);
    }
    var desc = html.indexOf('metas-desc');
    if (desc >= 0) {
      var body = html.slice(desc, Math.min(html.length, desc + 4000));
      var end = body.indexOf('</div>', body.indexOf('metas-desc'));
      var text = this.__plain(end > 0 ? body.slice(body.indexOf('>', 10) + 1, end) : body);
      info.description = this.__cut(text.replace(/\[展开\]/g, '').trim(), 800);
    }
    info.author = this.__metasField(html, '作者');
    info.status = this.__metasField(html, '状态');
    info.area = this.__metasField(html, '地区');
    info.updated = this.__metasField(html, '更新时间');
    info.tags = this.__detailTags(html);
    return info;
  },

  /// `div.metas-body` 里 `span.author` 一组标签行：「作者：xxx」「状态：连载中」…
  __metasField(html, label) {
    var from = html.indexOf('metas-body');
    if (from < 0) return '';
    var area = html.slice(from, Math.min(html.length, from + 3000));
    var at = area.indexOf(label);
    if (at < 0) return '';
    var open = area.indexOf('>', at);
    var close = area.indexOf('</span>', open);
    if (open < 0 || close < 0) return '';
    var raw = area.slice(open + 1, close);
    var text = this.__plain(raw);
    var colon = text.search(/[:：]/);
    if (colon >= 0) text = text.slice(colon + 1);
    return this.__cut(text.trim(), 40);
  },

  __detailTags(html) {
    var tags = [];
    var seen = {};
    var at = html.indexOf('metas-body');
    if (at < 0) return tags;
    var area = html.slice(at, Math.min(html.length, at + 3000));
    var pos = area.indexOf('/all/theme/');
    var guard = 0;
    while (pos >= 0 && guard < 30) {
      guard++;
      var start = area.lastIndexOf('<a', pos);
      var tagEnd = area.indexOf('>', pos);
      if (start >= 0 && tagEnd > pos) {
        var text = this.__plain(this.__textAfter(area, tagEnd + 1, 40));
        if (text && text.length <= 8 && !seen[text]) {
          seen[text] = true;
          tags.push(text);
        }
      }
      pos = area.indexOf('/all/theme/', tagEnd > 0 ? tagEnd : pos + 10);
    }
    return tags;
  },

  __subtitle(info) {
    var parts = [];
    if (info.author) parts.push('作者：' + info.author);
    if (info.status) parts.push(info.status);
    if (info.area) parts.push(info.area);
    return this.__cut(parts.join(' · '), 60);
  },

  __chapters(html, bookId) {
    var out = [];
    var seen = {};
    var start = html.indexOf('comic-chapters');
    var area = '';
    if (start >= 0) {
      var end = html.indexOf('</ul>', start);
      if (end < 0) end = Math.min(html.length, start + DETAIL_SCAN);
      area = html.slice(start, end);
    } else {
      area = html.slice(0, Math.min(html.length, DETAIL_SCAN));
    }
    var prefix = '/detail/' + bookId + '/';
    var at = area.indexOf(prefix);
    var guard = 0;
    while (at >= 0 && out.length < MAX_CHAPTERS) {
      if (++guard > MAX_CHAPTERS * 3) break;
      var anchorAt = area.lastIndexOf('<a ', at);
      var tagEnd = area.indexOf('>', at);
      if (anchorAt >= 0 && tagEnd > at) {
        var tag = area.slice(anchorAt, tagEnd + 1);
        var href = this.__attr(tag, 'href');
        if (href.indexOf(prefix) === 0 && this.__endsWith(href, '.html')) {
          var url = BASE_URL + href;
          if (!seen[url]) {
            var title = this.__plain(this.__attr(tag, 'title')) ||
              this.__plain(this.__textAfter(area, tagEnd + 1, 120));
            if (title && title.indexOf('上一') !== 0 && title.indexOf('下一') !== 0) {
              seen[url] = true;
              out.push({ id: url, title: this.__cut(title, 60) });
            }
          }
        }
      }
      at = area.indexOf(prefix, at + prefix.length);
    }
    return out;
  },

  // ---------------------------------------------------------------- 加解密

  /// params → JSON。算法见文件头：base64 → IV(前16字节) → AES-128-CBC → PKCS7 → UTF-8。
  __decryptParams(blob) {
    var bytes = this.__b64decode(blob);
    if (bytes.length < 32) throw new Error('params 太短（' + bytes.length + ' 字节）');
    var iv = bytes.slice(0, 16);
    var ct = bytes.slice(16);
    var key = [];
    var keyText = '5V&RoR%Jf@pJPydF';
    for (var i = 0; i < keyText.length; i++) key.push(keyText.charCodeAt(i) & 0xff);
    var plain = this.__aesCbcDecrypt(key, iv, ct);
    plain = this.__unpad(plain);
    var text = this.__utf8(plain);
    return JSON.parse(text);
  },

  __b64decode(text) {
    var map = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var out = [];
    var buf = 0;
    var bits = 0;
    var str = String(text || '');
    for (var i = 0; i < str.length; i++) {
      var ch = str.charAt(i);
      if (ch === '=') break;
      var v = map.indexOf(ch);
      if (v < 0) continue;
      buf = ((buf << 6) | v) & 0xffffff;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((buf >> bits) & 0xff);
      }
    }
    return out;
  },

  __b64encode(text) {
    var map = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var bytes = this.__utf8Bytes(String(text));
    var out = '';
    var i = 0;
    while (i < bytes.length) {
      var b0 = bytes[i++];
      var b1 = i < bytes.length ? bytes[i++] : -1;
      var b2 = i < bytes.length ? bytes[i++] : -1;
      var n = (b0 << 16) | ((b1 < 0 ? 0 : b1) << 8) | (b2 < 0 ? 0 : b2);
      out += map.charAt((n >> 18) & 63) + map.charAt((n >> 12) & 63);
      out += b1 < 0 ? '=' : map.charAt((n >> 6) & 63);
      out += b2 < 0 ? '=' : map.charAt(n & 63);
    }
    return out;
  },

  __utf8Bytes(text) {
    var out = [];
    for (var i = 0; i < text.length; i++) {
      var code = text.charCodeAt(i);
      if (code < 0x80) out.push(code);
      else if (code < 0x800) {
        out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        var low = text.charCodeAt(i + 1);
        var cp = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
        i++;
        out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
      } else {
        out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      }
    }
    return out;
  },

  __utf8(bytes) {
    var out = '';
    var i = 0;
    while (i < bytes.length) {
      var b = bytes[i++];
      if (b < 0x80) {
        out += String.fromCharCode(b);
      } else if (b >= 0xc0 && b < 0xe0 && i < bytes.length) {
        out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i++] & 0x3f));
      } else if (b >= 0xe0 && b < 0xf0 && i + 1 < bytes.length) {
        var c1 = bytes[i++];
        var c2 = bytes[i++];
        out += String.fromCharCode(((b & 0x0f) << 12) | ((c1 & 0x3f) << 6) | (c2 & 0x3f));
      } else if (b >= 0xf0 && i + 2 < bytes.length) {
        var d1 = bytes[i++];
        var d2 = bytes[i++];
        var d3 = bytes[i++];
        var cp = ((b & 0x07) << 18) | ((d1 & 0x3f) << 12) | ((d2 & 0x3f) << 6) | (d3 & 0x3f);
        cp -= 0x10000;
        out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      }
    }
    return out;
  },

  __unpad(bytes) {
    var n = bytes.length ? bytes[bytes.length - 1] : 0;
    if (n > 0 && n <= 16 && n <= bytes.length) return bytes.slice(0, bytes.length - n);
    return bytes;
  },

  __aesCbcDecrypt(key, iv, ct) {
    this.__aesInit();
    var w = this.__aesExpandKey(key);
    var out = [];
    var prev = iv.slice(0);
    var i;
    var j;
    for (i = 0; i + 16 <= ct.length; i += 16) {
      var block = this.__aesDecryptBlock(w, ct.slice(i, i + 16));
      for (j = 0; j < 16; j++) out.push((block[j] ^ prev[j]) & 0xff);
      prev = ct.slice(i, i + 16);
    }
    return out;
  },

  __aesInit() {
    if (this.__sbox) return;
    var sbox = new Array(256);
    var inv = new Array(256);
    var p = 1;
    var q = 1;
    var guard = 0;
    do {
      if (++guard > 400) break;
      p = (p ^ ((p << 1) & 0xff) ^ ((p & 0x80) ? 0x1b : 0)) & 0xff;
      q = (q ^ (q << 1)) & 0xff;
      q = (q ^ (q << 2)) & 0xff;
      q = (q ^ (q << 4)) & 0xff;
      if (q & 0x80) q = (q ^ 0x09) & 0xff;
      var x = (q ^ this.__rotl(q, 1) ^ this.__rotl(q, 2) ^ this.__rotl(q, 3) ^ this.__rotl(q, 4)) & 0xff;
      sbox[p] = (x ^ 0x63) & 0xff;
    } while (p !== 1);
    sbox[0] = 0x63;
    for (var i = 0; i < 256; i++) inv[sbox[i]] = i;
    this.__sbox = sbox;
    this.__inv = inv;
  },

  __rotl(value, n) {
    return ((value << n) | (value >>> (8 - n))) & 0xff;
  },

  __xtime(value) {
    return ((value << 1) ^ ((value & 0x80) ? 0x1b : 0)) & 0xff;
  },

  __aesExpandKey(key) {
    var w = new Array(176);
    var i;
    for (i = 0; i < 16; i++) w[i] = key[i] & 0xff;
    var rcon = 1;
    for (i = 16; i < 176; i += 4) {
      var t0 = w[i - 4];
      var t1 = w[i - 3];
      var t2 = w[i - 2];
      var t3 = w[i - 1];
      if (i % 16 === 0) {
        var tmp = t0;
        t0 = this.__sbox[t1] ^ rcon;
        t1 = this.__sbox[t2];
        t2 = this.__sbox[t3];
        t3 = this.__sbox[tmp];
        rcon = this.__xtime(rcon);
      }
      w[i] = w[i - 16] ^ t0;
      w[i + 1] = w[i - 15] ^ t1;
      w[i + 2] = w[i - 14] ^ t2;
      w[i + 3] = w[i - 13] ^ t3;
    }
    return w;
  },

  __aesDecryptBlock(w, input) {
    var s = input.slice(0);
    this.__addRoundKey(s, w, 10);
    for (var round = 9; round >= 1; round--) {
      this.__invShiftRows(s);
      this.__invSubBytes(s);
      this.__addRoundKey(s, w, round);
      this.__invMixColumns(s);
    }
    this.__invShiftRows(s);
    this.__invSubBytes(s);
    this.__addRoundKey(s, w, 0);
    return s;
  },

  __addRoundKey(s, w, round) {
    var base = round * 16;
    for (var i = 0; i < 16; i++) s[i] = (s[i] ^ w[base + i]) & 0xff;
  },

  __invSubBytes(s) {
    for (var i = 0; i < 16; i++) s[i] = this.__inv[s[i]];
  },

  __invShiftRows(s) {
    var copy = s.slice(0);
    for (var r = 1; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        s[r + 4 * c] = copy[r + 4 * ((c - r + 4) % 4)];
      }
    }
  },

  __invMixColumns(s) {
    for (var c = 0; c < 4; c++) {
      var i = 4 * c;
      var a0 = s[i];
      var a1 = s[i + 1];
      var a2 = s[i + 2];
      var a3 = s[i + 3];
      s[i] = (this.__gmul(a0, 14) ^ this.__gmul(a1, 11) ^ this.__gmul(a2, 13) ^ this.__gmul(a3, 9)) & 0xff;
      s[i + 1] = (this.__gmul(a0, 9) ^ this.__gmul(a1, 14) ^ this.__gmul(a2, 11) ^ this.__gmul(a3, 13)) & 0xff;
      s[i + 2] = (this.__gmul(a0, 13) ^ this.__gmul(a1, 9) ^ this.__gmul(a2, 14) ^ this.__gmul(a3, 11)) & 0xff;
      s[i + 3] = (this.__gmul(a0, 11) ^ this.__gmul(a1, 13) ^ this.__gmul(a2, 9) ^ this.__gmul(a3, 14)) & 0xff;
    }
  },

  __gmul(a, b) {
    var p = 0;
    var x = a & 0xff;
    var y = b & 0xff;
    for (var i = 0; i < 8; i++) {
      if (y & 1) p ^= x;
      var high = x & 0x80;
      x = (x << 1) & 0xff;
      if (high) x ^= 0x1b;
      y >>= 1;
    }
    return p & 0xff;
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
      if (status === 403 || status === 503 || status === 429 ||
        /just a moment|__cf_chl|challenge-platform|cf-mitigated/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：爱韩漫 需要网页视图过一次 Cloudflare 校验（HTTP ' + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    }
    if (/<title>\s*Just a moment/i.test(body)) {
      throw new Error('NEED_WEBVIEW_VERIFY：爱韩漫 需要网页视图过一次 Cloudflare 校验（' + url + '）');
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

  __encodePath(path) {
    var str = String(path || '');
    var out = '';
    for (var i = 0; i < str.length; i++) {
      var code = str.charCodeAt(i);
      out += code < 0x80 ? str.charAt(i) : this.__utf8Escape(code, str, i);
    }
    return out;
  },

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
        out += this.__utf8Escape(code, str, i);
      }
    }
    return out;
  },

  __utf8Escape(code, str, i) {
    var value = code;
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < str.length) {
      var low = str.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) value = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
    }
    if (value < 0x800) {
      return '%' + this.__hex(0xc0 | (value >> 6)) + '%' + this.__hex(0x80 | (value & 0x3f));
    }
    if (value < 0x10000) {
      return '%' + this.__hex(0xe0 | (value >> 12)) +
        '%' + this.__hex(0x80 | ((value >> 6) & 0x3f)) +
        '%' + this.__hex(0x80 | (value & 0x3f));
    }
    return '%' + this.__hex(0xf0 | (value >> 18)) +
      '%' + this.__hex(0x80 | ((value >> 12) & 0x3f)) +
      '%' + this.__hex(0x80 | ((value >> 6) & 0x3f)) +
      '%' + this.__hex(0x80 | (value & 0x3f));
  },

  __hex(value) {
    var text = value.toString(16).toUpperCase();
    return text.length < 2 ? '0' + text : text;
  },

  __attr(tag, name) {
    var needle = name + '=';
    var at = tag.indexOf(needle);
    var guard = 0;
    while (at >= 0 && guard < 12) {
      guard++;
      var before = at > 0 ? tag.charCodeAt(at - 1) : 32;
      if (this.__isSpace(before)) {
        var value = this.__attrValue(tag, at + needle.length);
        if (value) return value;
      }
      at = tag.indexOf(needle, at + needle.length);
    }
    return '';
  },

  __firstAttr(window, name) {
    var at = window.indexOf(name + '=');
    var guard = 0;
    while (at >= 0 && guard < 4) {
      guard++;
      var value = this.__attrValue(window, at + name.length + 1);
      if (value) return value;
      at = window.indexOf(name + '=', at + name.length + 1);
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

  __textAfter(text, from, limit) {
    var end = Math.min(text.length, from + limit);
    var i = from;
    while (i < end && this.__isSpace(text.charCodeAt(i))) i++;
    if (i >= end) return '';
    if (text.charAt(i) === '<') return '';
    var stop = text.indexOf('<', i);
    if (stop < 0 || stop > end) stop = end;
    return this.__plain(text.slice(i, stop));
  },

  __classText(window, name) {
    var at = window.indexOf('class="' + name);
    if (at < 0) return '';
    var open = window.indexOf('>', at);
    if (open < 0) return '';
    var close = window.indexOf('<', open + 1);
    if (close < 0) return '';
    return this.__plain(window.slice(open + 1, close));
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

  __plain(text) {
    var value = String(text == null ? '' : text);
    if (value.indexOf('<') >= 0) value = value.replace(/<[^>]*>/g, ' ');
    value = value.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&hellip;/g, '…').replace(/&mdash;/g, '—');
    return value.replace(/\s+/g, ' ').trim();
  }
};
