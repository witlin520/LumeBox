// LumeSource: {"id":"boysyo_comic","name":"啵乐","version":"1.0.0","category":"comic","mirrors":["https://boysyo.cc"]}

// 站点：https://boysyo.cc（标题「啵乐 - 腐味满满」）
//
// ⚠️ 和 `boylove.cc`（香香腐宅 / 腐宅BoyLove）**不是同一套代码**，所以单独一份脚本：
//    boylove：`/home/book/index/id/{id}`、`/home/api/…` JSON 接口、PHP 风格
//    boysyo ：`/cat_intro/{id}`、`/thread_comic/{作品id}/{章节id}`、Laravel + Vue，
//              页面里直接内联 `const book_info = {...}` 和 `const _pics = []`。
//    路由、接口、模板全不一样，硬凑在一个文件里只会两边都脆，因此分开。
//
// ## 抓取口径（全部对着实时页面核过）
//
//   分类/列表  GET /list_comic?sort={new|rank}&mode=block&p={N}[&status=&query={标签}]
//              服务端直出 35 条/页。卡片：
//                <a class="grid_item__img lazy" data-bg="封面" href="/cat_intro/{id}">
//                <h5 class="grid_item__title line-clamp"> 标题 </h5>
//                <div class="update"> 更新至第6话 </div>
//              分类档位就是页面上的标签 chips（`…&status=&query=兽耳` 这种），本源把
//              它们和「最新 / 排行榜」一起当 categories 的 id 交给 list()（list() 只改 p=N）。
//   搜索      GET /tag_result?query={UTF-8 编码}&search_type=all&p={N}
//              ⚠️ search_type 只有 `all` 是真搜索（实测 tag/book/title/comic/name 都只回
//              5 个无关结果；`all` 回 30 条/页并带「共 N 笔」与 p=2 分页）。
//              结果卡片是另一套：`a.list_item__img[data-bg]` + `a.title`，本源统一解析。
//   详情      GET /cat_intro/{id}：页内 `<script>const book_info = {…}</script>`
//              （title / cover / intro / author / serial_status / newest_serial / tags 全在里面，
//              比刮 HTML 稳），标题另有一份 `<h1 style="display:none">` 但混了作者和最新话，不用。
//   目录      详情页 `div.chapterList > a.chapter[href=/thread_comic/{作品id}/{章节id}]`，
//              站点是**新→旧**，本源反转成旧→新。
//   正文      GET /thread_comic/{作品id}/{章节id}：图片由 Vue 组件渲染，但地址是
//              **服务端内联**在页面里的 `const _pics = []; _pics.push("first"); _pics.push("https://img.boysyo.cc/volume/…jpg?Expires=…&Signature=…")`。
//              只收 `_pics.push("http…")` 这些（`"first"` 是占位、广告位是纯数字 zoneid）。
//              ⚠️ 这些是**带签名的临时地址**（Expires/Signature，约按小时级续签），
//              所以章节正文必须在打开时现取一遍，不能缓存复用旧 URL。
//
// 图片域名 img.boysyo.cc 实测带不带 Referer 都是 200/206（签名在 URL 里），headers 照契约给站点 Referer。

var BASE_URL = 'https://boysyo.cc';

var PAGE_SIZE_LIST = 35;   // /list_comic 每页 35 条（实测）
var PAGE_SIZE_SEARCH = 30; // /tag_result 每页 30 条（实测）
var MAX_ITEMS = 100;
var CARD_WINDOW = 900;
var MAX_CHAPTERS = 3000;
var MAX_IMAGES = 400;

var LumeSource = {
  id: 'boysyo_comic',
  name: '啵乐',
  version: '1.0.0',
  category: 'comic',

  // ---------------------------------------------------------------- 分类

  /// 分类 = 列表页自己的标签 chips（`/list_comic?…&query=标签`）+ 最新 / 排行榜。
  async categories() {
    var html = await this.__get(BASE_URL + '/list_comic?sort=new&mode=block&p=1');
    var out = [
      { id: '/list_comic?sort=new&mode=block&p=1', title: '最新' },
      { id: '/list_comic?sort=rank&mode=block&p=1', title: '排行榜' }
    ];
    var seen = {};
    seen['/list_comic?sort=new&mode=block&p=1'] = true;
    seen['/list_comic?sort=rank&mode=block&p=1'] = true;
    var at = html.indexOf('/list_comic?sort=new');
    var guard = 0;
    while (at >= 0 && guard < 200 && out.length < 20) {
      guard++;
      var start = html.lastIndexOf('<a', at);
      var hrefEnd = html.indexOf('"', at);
      var tagEnd = html.indexOf('>', hrefEnd);
      var close = html.indexOf('</a>', tagEnd);
      if (start >= 0 && hrefEnd > at && tagEnd > 0 && close > tagEnd) {
        var href = html.slice(at, hrefEnd).replace(/&amp;/g, '&');
        var text = this.__plain(html.slice(tagEnd + 1, close));
        var key = href.replace(/[?&]p=\d+/, '');
        if (text && text.length <= 12 && !seen[key] && href.indexOf('query=') > 0) {
          seen[key] = true;
          out.push({ id: href, title: this.__cut(text, 12) });
        }
      }
      at = html.indexOf('/list_comic?sort=new', hrefEnd > at ? hrefEnd : at + 10);
    }
    console.warn('[boysyo] 分类 ' + out.length + ' 项');
    return out;
  },

  /// 首页：站点自己的三块（排行榜 / 最新 / 已完结），每块 `section_header__name` + grid_items。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = [];
    var at = html.indexOf('section_header__name');
    var guard = 0;
    while (at >= 0 && boards.length < 6 && guard < 10) {
      guard++;
      var next = html.indexOf('section_header__name', at + 20);
      var window = html.slice(at, next > at ? next : Math.min(html.length, at + 80000));
      var titleAt = window.indexOf('>', at - at);
      var name = this.__plain(window.slice(titleAt + 1, window.indexOf('</div>', titleAt)));
      var items = this.__items(window);
      if (name && items.length) {
        boards.push({ title: this.__cut(name, 16), moreUrl: '/list_comic?sort=new&mode=block&p=1', items: items.slice(0, 12) });
      }
      at = next;
    }
    if (boards.length) {
      console.warn('[boysyo] 首页板块 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ categoryId: '/list_comic?sort=new&mode=block&p=1', page: 1 });
    if (latest && latest.items && latest.items.length) {
      console.warn('[boysyo] 首页没认出板块，退回列表一块');
      return [{ title: '最新', moreUrl: '/list_comic?sort=new&mode=block&p=1', items: latest.items.slice(0, 12) }];
    }
    return [];
  },

  // ---------------------------------------------------------------- 列表

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';
    var searching = !!keyword;
    var url = searching ? this.__searchUrl(keyword, page) : this.__listUrl(category, page);
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[boysyo] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    var pageSize = searching ? PAGE_SIZE_SEARCH : PAGE_SIZE_LIST;
    console.warn('[boysyo] 列表命中：' + url + '（' + items.length + ' 条）');
    // 列表页的分页器 `#pagination` 是 JS 现算的（HTML 里是空 div），拿不到 maxPage；
    // 实测每页 35 张卡片、本源能稳定解析 27～35 条，所以按「接近满页」判还有下一页。
    var threshold = searching ? PAGE_SIZE_SEARCH : Math.floor(PAGE_SIZE_LIST * 0.7);
    return { items: items, hasMore: items.length >= threshold };
  },

  __listUrl(category, page) {
    var path = String(category || '/list_comic?sort=new&mode=block&p=1');
    if (path.indexOf('http') === 0) {
      var m = /^https?:\/\/[^\/]+(\/.*)$/.exec(path);
      path = m ? m[1] : '/list_comic?sort=new&mode=block&p=1';
    }
    path = path.replace(/[?&]p=\d+/, '');
    if (path.indexOf('?') < 0) path += '?p=';
    else path += '&p=';
    return BASE_URL + path + page;
  },

  __searchUrl(keyword, page) {
    return BASE_URL + '/tag_result?query=' + this.__encode(keyword) + '&search_type=all&p=' + page;
  },

  /// 卡片解析：两种版式的**锚都在 data-bg 前面**，所以从 `data-bg="封面"` 往回找所属的
  /// `/cat_intro/{id}`（往回找不到才往后找），再以那个锚为窗口起点取标题：
  ///   grid_item：`<a class="grid_item" href="/cat_intro/{id}">` +
  ///              `<div class="grid_item__img lazy" data-bg="封面">` +
  ///              `<h5 class="grid_item__title line-clamp"> 标题 </h5>`
  ///   list_item（搜索结果）：`<a href="/cat_intro/{id}" data-bg="封面" class="list_item__img lazy">`
  ///              + `<a class="title"> 标题 </a>`
  /// （早先把窗口从 data-bg 往后开，结果每张封面都串到了下一部作品上，实测抓出来的是隔壁的图。）
  __items(html) {
    var items = [];
    var seen = {};
    var at = html.indexOf('data-bg="');
    var guard = 0;
    while (at >= 0 && items.length < MAX_ITEMS) {
      if (++guard > 400) break;
      var cover = this.__attrValue(html, at + 8);
      var anchorAt = this.__lastBookHref(html, at);
      var window;
      var id = '';
      if (anchorAt >= 0) {
        var back = html.slice(anchorAt, at + 12);
        var bm = /href="\/cat_intro\/(\d+)"/.exec(back);
        if (bm) id = bm[1];
        window = html.substr(anchorAt, CARD_WINDOW);
      } else {
        window = html.substr(at, CARD_WINDOW);
        var fm = /href="\/cat_intro\/(\d+)"/.exec(window);
        if (fm) id = fm[1];
      }
      if (id && !seen[id] && this.__isImage(cover)) {
        var title = '';
        var t = /class="grid_item__title[^"]*"[^>]*>\s*([^<]{1,80})/.exec(window);
        if (t) title = t[1];
        if (!title) {
          var t2 = /class="title[^"]*"[^>]*>\s*([^<]{1,80})/.exec(window);
          if (t2) title = t2[1];
        }
        title = this.__cut(this.__plain(title), 80);
        if (title) {
          seen[id] = true;
          items.push({
            id: BASE_URL + '/cat_intro/' + id,
            title: title,
            cover: this.__absolute(cover),
            coverHeaders: { 'Referer': BASE_URL + '/' },
            subtitle: this.__cardSubtitle(window)
          });
        }
      }
      at = html.indexOf('data-bg="', at + 8);
    }
    return items;
  },

  /// 往回找最近一个 `/cat_intro/{id}` 锚的位置（限定 600 字符内，避免跨卡片）。
  __lastBookHref(html, from) {
    var start = Math.max(0, from - 600);
    var slice = html.slice(start, from);
    var best = -1;
    var re = /href="\/cat_intro\/\d+"/g;
    var m;
    while ((m = re.exec(slice))) best = m.index;
    return best >= 0 ? start + best : -1;
  },

  __cardSubtitle(window) {
    var parts = [];
    var up = /class="update"[^>]*>\s*([^<]{1,30})/.exec(window);
    if (up) parts.push(up[1].trim());
    var author = /class="author"[^>]*>\s*([^<]{1,30})/.exec(window);
    if (author) parts.push(author[1].trim());
    return this.__cut(parts.join(' · '), 40);
  },

  __isImage(url) {
    var text = String(url || '').trim();
    return !!text && text.length < 400 && /\.(jpe?g|png|webp|gif|avif)(\?|$)/i.test(text);
  },

  // ---------------------------------------------------------------- 详情 / 目录

  async detail(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/cat_intro/' + id;
    var html = await this.__get(url);
    var info = this.__bookInfo(html);
    if (!info || !info.title) {
      console.warn('[boysyo] 详情页没认出 book_info：' + url + '（' + html.length + ' 字符）');
      return null;
    }
    return {
      id: url,
      title: info.title,
      cover: info.cover,
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut([info.author ? '作者：' + info.author : '', info.serial_status].join(' · ').replace(/^ · /, ''), 60),
      description: this.__cut(info.intro, 800),
      tags: info.tags,
      extra: { author: info.author, status: info.serial_status, latest: info.newest_serial }
    };
  },

  async chapters(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/cat_intro/' + id;
    var html = await this.__get(url);
    var out = this.__chapters(html, id);
    if (!out.length) {
      console.warn('[boysyo] 目录为空：' + url);
      return [];
    }
    console.warn('[boysyo] 目录 ' + out.length + ' 话（已翻成旧→新）：' + url);
    return out;
  },

  // ---------------------------------------------------------------- 正文

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('啵乐：缺少章节 ID（请先选择一话）');
    var url = this.__chapterUrl(chapterId, argument && argument.id);
    if (!url) throw new Error('啵乐：认不出章节地址（' + chapterId + '）');
    var html = await this.__get(url);
    var images = this.__pics(html);
    if (!images.length) {
      throw new Error('啵乐：这一话没解析出图片（' + url + '）——可能需要登录/VIP');
    }
    console.warn('[boysyo] 正文 ' + images.length + ' 张图：' + url);
    return { kind: 'images', images: images, headers: { 'Referer': BASE_URL + '/' } };
  },

  /// 正文图：页面内联 `_pics.push("https://img.boysyo.cc/volume/…?Expires=…&Signature=…")`。
  /// `"first"` 是占位、纯数字是广告 zoneid，只要 http 开头的。
  __pics(html) {
    var out = [];
    var seen = {};
    var at = html.indexOf('_pics.push(');
    var guard = 0;
    while (at >= 0 && out.length < MAX_IMAGES) {
      if (++guard > 4000) break;
      var open = html.indexOf('(', at) + 1;
      var quote = html.charAt(open);
      if (quote === '"' || quote === "'") {
        var end = html.indexOf(quote, open + 1);
        var value = end > open ? html.slice(open + 1, end) : '';
        if (value.indexOf('http') === 0 && !seen[value]) {
          seen[value] = true;
          var abs = this.__absolute(value);
          if (abs) out.push(abs);
        }
      }
      at = html.indexOf('_pics.push(', at + 11);
    }
    return out;
  },

  __chapterUrl(chapterId, itemId) {
    var value = String(chapterId || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      if (value.indexOf(BASE_URL) === 0) return value;
      var m = /^https?:\/\/boysyo\.cc(\/.*)$/.exec(value);
      return m ? BASE_URL + m[1] : '';
    }
    if (value.indexOf('/thread_comic/') === 0) return BASE_URL + value;
    if (/^\d+$/.test(value)) {
      var book = '';
      try { book = this.__bookId(itemId); } catch (error) { book = ''; }
      if (!book) return '';
      return BASE_URL + '/thread_comic/' + book + '/' + value;
    }
    return '';
  },

  __bookId(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    else if (typeof argument === 'string') id = argument;
    var value = String(id || '').trim();
    if (!value) throw new Error('啵乐：缺少作品 ID');
    var m = /\/cat_intro\/(\d+)/.exec(value);
    if (m) return m[1];
    if (/^\d+$/.test(value)) return value;
    throw new Error('啵乐：认不出的作品 ID（' + id + '）');
  },

  /// 详情页里内联的 `const book_info = {…};`
  __bookInfo(html) {
    var at = html.indexOf('const book_info');
    if (at < 0) at = html.indexOf('book_info =');
    if (at < 0) return null;
    var start = html.indexOf('{', at);
    if (start < 0) return null;
    var depth = 0;
    var i = start;
    var inString = false;
    var quote = '';
    var escaped = false;
    for (; i < html.length && i < start + 20000; i++) {
      var ch = html.charAt(i);
      if (inString) {
        if (escaped) escaped = false;
        else if (ch === '\\') escaped = true;
        else if (ch === quote) inString = false;
        continue;
      }
      if (ch === '"' || ch === "'") { inString = true; quote = ch; continue; }
      if (ch === '{') depth++;
      else if (ch === '}') {
        depth--;
        if (depth === 0) { i++; break; }
      }
    }
    var text = html.slice(start, i);
    var obj = null;
    try {
      obj = JSON.parse(text);
    } catch (error) {
      console.warn('[boysyo] book_info 不是合法 JSON：' + (error && error.message));
      return null;
    }
    var tags = [];
    if (obj.tags && obj.tags.length) {
      for (var t = 0; t < obj.tags.length && tags.length < 8; t++) {
        if (obj.tags[t] && obj.tags[t].tag_name) tags.push(this.__plain(obj.tags[t].tag_name));
      }
    }
    return {
      title: this.__plain(obj.title || ''),
      cover: this.__absolute(String(obj.cover || '')),
      intro: this.__plain(String(obj.intro || '')),
      author: this.__plain(String(obj.author || '')),
      serial_status: this.__plain(String(obj.serial_status || '')),
      newest_serial: this.__plain(String(obj.newest_serial || '')),
      tags: tags
    };
  },

  __chapters(html, bookId) {
    var out = [];
    var seen = {};
    var start = html.indexOf('chapterList');
    var area = start >= 0 ? html.slice(start, Math.min(html.length, start + 300000)) : html;
    var needle = '/thread_comic/' + bookId + '/';
    var at = area.indexOf(needle);
    var guard = 0;
    while (at >= 0 && out.length < MAX_CHAPTERS) {
      if (++guard > MAX_CHAPTERS * 3) break;
      var anchorAt = area.lastIndexOf('<a', at);
      var hrefEnd = area.indexOf('"', at);
      var tagEnd = area.indexOf('>', hrefEnd);
      if (anchorAt >= 0 && hrefEnd > at && tagEnd > 0) {
        var href = area.slice(at, hrefEnd);
        var url = BASE_URL + href;
        if (!seen[url]) {
          var title = this.__plain(area.slice(tagEnd + 1, area.indexOf('</a>', tagEnd)));
          if (title) {
            seen[url] = true;
            out.push({ id: url, title: this.__cut(title, 60) });
          }
        }
      }
      at = area.indexOf(needle, hrefEnd > at ? hrefEnd : at + 10);
    }
    out.reverse();
    return out;
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
        throw new Error('NEED_WEBVIEW_VERIFY：啵乐 需要网页视图过一次 Cloudflare 校验（HTTP ' + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    }
    return body;
  },

  __absolute(url) {
    var text = String(url || '').trim().replace(/\\\//g, '/');
    if (!text) return '';
    if (text.indexOf('//') === 0) return 'https:' + text;
    if (text.indexOf('http') === 0) return text;
    if (text.charAt(0) === '/') return BASE_URL + text;
    return BASE_URL + '/' + text;
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

  __attrValue(text, from) {
    var quote = text.charAt(from);
    if (quote !== '"' && quote !== "'") return '';
    var end = text.indexOf(quote, from + 1);
    if (end < 0) return '';
    return text.slice(from + 1, end);
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
