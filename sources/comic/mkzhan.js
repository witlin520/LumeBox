// LumeSource: {"id":"mkzhan_comic","name":"漫客栈","version":"1.0.0","category":"comic","mirrors":["https://m.mkzhan.com"]}

// 站点：https://m.mkzhan.com（漫客栈移动版；正文走 comic.mkzcdn.com 的 JSON 接口）
//
// ## 入口（对着实时页面/接口核过）
//
//   列表  GET /update/                  更新（HTML 直出，52 条，**只有一页**：?page=2 返回同一批）
//         GET /top/{name}/             排行，name ∈ popularity / ticket / collection / exclusive /
//                                      latest / ascension（HTML 直出 40 条，同样只有一页）
//         GET https://comic.mkzcdn.com/search/filter/?{筛选}&page_num={n}&page_size=12
//                                      「独家作品」= /category/?copyright=1 → copyright=1；
//                                      这是分类页「点击加载更多」用的接口，**能真分页**。
//   搜索  GET https://comic.mkzcdn.com/search/keyword/?keyword={kw}&page_num={n}&page_size=50
//         `/search/` 页面本身是空壳（结果全靠这个接口渲染）。注意搜索无结果时站点回
//         {"code":"199","message":"搜索结果为空"}，要当空列表处理而不是报错。
//         keyword 必须是站内真有的词（比如「地府」「武神」）；生僻词站点就是 0 条。
//   详情  GET https://comic.mkzcdn.com/comic/info/?comic_id={id}
//         比抓 /{id}/ 那一页省得多（那页 800KB，这部 791 话的全在 HTML 里）：
//         data.title / data.cover / data.content（简介）/ data.chapter_number / data.finish
//   目录  GET https://comic.mkzcdn.com/chapter/v1/?comic_id={id}   → data[] 每项
//         {chapter_id, title, number, is_vip, price}；阅读页 = /{comic_id}/{chapter_id}.html
//   正文  GET https://comic.mkzcdn.com/chapter/content/v1/?chapter_id={cid}&comic_id={id}
//              &quality=1&type=1&format=0
//         → data.page[] = [{page_id, image}]，image 是 content.mkzcdn.com 的带 auth_key 签名地址
//         （签名约 1 天后过期 → 必须实时取，不能缓存）。
//         实测这三个接口**都不校验 Referer / cookie / sign**（页面前端会带 uid+sign，
//         不带也照样 200），所以脚本只带 Referer: https://m.mkzhan.com/ 这一个头。
//
// ## 图片
//   content.mkzcdn.com 的 `…jpg!page-800?auth_key=…`。实测不校验 Referer、支持 Range（206），
//   http 与 https 都能取；这里统一升到 https（iOS ATS）。

var BASE_URL = 'https://m.mkzhan.com';
var API_COMIC = 'https://comic.mkzcdn.com';

var MAX_ITEMS = 120;
var ITEM_WINDOW = 2200;
var MAX_IMAGES = 400;
var CHAPTER_PAGE_SIZE = 12;   // 分类接口每页条数（站点自己的 page_size）
var SEARCH_PAGE_SIZE = 50;

var RANK_NAMES = ['popularity', 'ticket', 'collection', 'exclusive', 'latest', 'ascension'];
var RANK_TITLES = { popularity: '人氣榜', ticket: '月票榜', collection: '收藏榜', exclusive: '獨家榜', latest: '新作榜', ascension: '上升榜' };

var SKIP_IMAGE = /logo|avatar|banner|placeholder|blank|loading|icon|sprite|qrcode|share|bg_loading/i;

var LumeSource = {
  id: 'mkzhan_comic',
  name: '漫客栈',
  version: '1.0.0',
  category: 'comic',

  // ------------------------------------------------------------- 契约方法

  /// 分类：站点的三根入口（更新 / 独家作品 / 六个榜单）。
  /// 更新与榜单页是 HTML 直出（各只有第 1 页）；独家作品走 search/filter 接口（能翻页）。
  async categories() {
    var out = [
      { id: 'update', title: '更新' },
      { id: 'copyright', title: '獨家作品' }
    ];
    for (var i = 0; i < RANK_NAMES.length; i++) {
      out.push({ id: 'top/' + RANK_NAMES[i], title: RANK_TITLES[RANK_NAMES[i]] });
    }
    return out;
  },

  /// 首页：站点的三个楼层（客栈精品 / 独家作品 / 最近更新），块名取楼层标题。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = this.__floors(html);
    if (boards.length) {
      console.warn('[mkzhan] 首页楼层 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ page: 1, categoryId: 'update' });
    if (latest && latest.items && latest.items.length) {
      console.warn('[mkzhan] 首页没认出楼层，退回更新一块');
      return [{ title: '更新', moreUrl: 'update', items: latest.items.slice(0, 12) }];
    }
    return [];
  },

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : 'update';

    if (keyword) return this.__searchList(keyword, page);

    if (category === 'copyright' || category.indexOf('copyright') >= 0) {
      return this.__filterList(this.__copyrightParams(category), page);
    }
    if (category.indexOf('top') === 0) {
      return this.__htmlList(category, page);
    }
    if (category === 'update' || category === '' || category === 'all') {
      return this.__htmlList('update', page);
    }
    if (category.indexOf('http') === 0 || category.charAt(0) === '/') {
      return this.__htmlList(category, page);
    }
    return this.__htmlList('update', page);
  },

  async detail(argument) {
    var comicId = this.__comicId(this.__id(argument));
    var json = await this.__api(API_COMIC + '/comic/info/?comic_id=' + comicId);
    var data = json && json.data ? json.data : null;
    if (!data || !data.title) {
      console.warn('[mkzhan] comic/info 没给详情：' + comicId);
      return null;
    }
    var bits = [];
    if (data.chapter_number) bits.push('共' + data.chapter_number + '話');
    bits.push(String(data.finish) === '2' ? '已完結' : '連載中');
    if (data.copyright === '1') bits.push('獨家');
    return {
      id: BASE_URL + '/' + comicId + '/',
      title: String(data.title),
      cover: this.__img(data.cover),
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut(bits.join(' · '), 80),
      description: this.__cut(this.__plain(data.content || ''), 800),
      extra: {
        chapterNumber: data.chapter_number || '',
        finish: data.finish || '',
        notice: this.__cut(this.__plain(data.notice || ''), 200)
      }
    };
  },

  /// 目录：comic 的章节接口一次给全（791 话也一次给完，约 370KB）。
  async chapters(argument) {
    var comicId = this.__comicId(this.__id(argument));
    var json = await this.__api(API_COMIC + '/chapter/v1/?comic_id=' + comicId);
    var rows = json && json.data ? json.data : null;
    if (!rows || !rows.length) {
      throw new Error('漫客栈：目录为空（comic ' + comicId + '）——把运行日志发回来收敛解析规则');
    }
    var out = [];
    var seen = {};
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (!row || row.chapter_id == null) continue;
      var url = BASE_URL + '/' + comicId + '/' + row.chapter_id + '.html';
      if (seen[url]) continue;
      seen[url] = true;
      out.push({ id: url, title: this.__cut(this.__plain(row.title || ('第' + (i + 1) + '話')), 60) });
    }
    console.warn('[mkzhan] 目录 ' + out.length + ' 话（comic ' + comicId + '）');
    return out;
  },

  /// 正文：chapter/content/v1 直接返回 page[].image。
  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('漫客栈：缺少章节 ID（请先选择一话）');
    var comicId = this.__comicId(argument && argument.id != null ? argument.id : chapterId);
    var cid = this.__chapterId(chapterId);
    if (!cid) throw new Error('漫客栈：认不出章节地址（' + chapterId + '）');
    var url = API_COMIC + '/chapter/content/v1/?chapter_id=' + cid + '&comic_id=' + comicId +
      '&quality=1&type=1&format=0';
    var json = await this.__api(url);
    var pages = json && json.data && json.data.page ? json.data.page : null;
    if (!pages || !pages.length) {
      throw new Error('漫客栈：这一话没解析出图片（' + url + '）——把运行日志发回来收敛解析规则');
    }
    var images = [];
    var seen = {};
    for (var i = 0; i < pages.length && images.length < MAX_IMAGES; i++) {
      var abs = this.__img(pages[i] && pages[i].image);
      if (abs && !seen[abs]) {
        seen[abs] = true;
        images.push(abs);
      }
    }
    if (!images.length) throw new Error('漫客栈：图片列表为空（' + url + '）');
    console.warn('[mkzhan] 正文 ' + images.length + ' 张图（comic ' + comicId + ' / chapter ' + cid + '）');
    return {
      kind: 'images',
      images: images,
      headers: { 'Referer': BASE_URL + '/' }
    };
  },

  // ------------------------------------------------------------- 列表（三种来源）

  /// 更新 / 排行：HTML 直出，站内只有第 1 页（?page=N 返回同一批），所以 hasMore 恒 false。
  async __htmlList(category, page) {
    var path = this.__listPath(category);
    if (page > 1) {
      console.warn('[mkzhan] 「' + category + '」只有第 1 页，第 ' + page + ' 页返回空');
      return { items: [], hasMore: false };
    }
    var html = await this.__get(BASE_URL + path);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[mkzhan] 列表没解析出条目：' + path + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[mkzhan] 列表命中 ' + items.length + ' 条：' + path);
    return { items: items, hasMore: false };
  },

  async __filterList(params, page) {
    var url = API_COMIC + '/search/filter/?' + params + '&page_num=' + page + '&page_size=' + CHAPTER_PAGE_SIZE;
    var json = await this.__api(url);
    var rows = json && json.data && json.data.list ? json.data.list : [];
    var items = this.__apiItems(rows);
    if (!items.length) {
      console.warn('[mkzhan] 分类接口无条目：' + url);
      return { items: [], hasMore: false };
    }
    console.warn('[mkzhan] 分类接口 ' + items.length + ' 条：' + url);
    return { items: items, hasMore: items.length >= CHAPTER_PAGE_SIZE };
  },

  async __searchList(keyword, page) {
    var url = API_COMIC + '/search/keyword/?keyword=' + this.__enc(keyword) +
      '&page_num=' + page + '&page_size=' + SEARCH_PAGE_SIZE;
    var json = await this.__api(url);
    var data = json && json.data ? json.data : null;
    if (!data || !data.list || !data.list.length) {
      console.warn('[mkzhan] 搜索无结果：「' + keyword + '」（code ' + (json && json.code) + '）');
      return { items: [], hasMore: false };
    }
    var items = this.__apiItems(data.list);
    var count = Number(data.count) || 0;
    var hasMore = count ? page * SEARCH_PAGE_SIZE < count : items.length >= SEARCH_PAGE_SIZE;
    console.warn('[mkzhan] 搜索「' + keyword + '」' + items.length + ' 条（共 ' + count + '）');
    return { items: items, hasMore: hasMore };
  },

  __listPath(category) {
    var value = String(category == null ? '' : category).trim();
    if (!value || value === 'update' || value === 'all') return '/update/';
    if (value.indexOf('http') === 0) {
      if (value.indexOf('mkzhan.com') >= 0) {
        value = value.replace(/^https?:\/\/(m\.)?mkzhan\.com/, '');
        return value.charAt(0) === '/' ? value : '/' + value;
      }
      console.warn('[mkzhan] 分类地址不是本站：' + category + '，退回更新');
      return '/update/';
    }
    if (value.charAt(0) === '/') return value;
    if (value.indexOf('top/') === 0) return '/' + value + '/';
    return '/' + value + '/';
  },

  __copyrightParams(category) {
    // 分类页的「更多」只用自己的查询串：/category/?copyright=1 → 接口原样转 param=value。
    var value = String(category || '');
    var at = value.indexOf('?');
    if (at >= 0 && value.length > at + 1) {
      var query = value.slice(at + 1);
      if (query.indexOf('=') > 0) return query;
    }
    return 'copyright=1';
  },

  /// 接口列表条目 → 契约条目（comic_id / title / cover / feature / chapter_num）。
  __apiItems(rows) {
    var items = [];
    var seen = {};
    for (var i = 0; i < rows.length && items.length < MAX_ITEMS; i++) {
      var row = rows[i];
      if (!row || row.comic_id == null) continue;
      var id = BASE_URL + '/' + row.comic_id + '/';
      if (seen[id]) continue;
      seen[id] = true;
      items.push({
        id: id,
        title: this.__cut(this.__plain(row.title || ''), 100),
        cover: this.__img(row.cover_lateral || row.cover),
        coverHeaders: { 'Referer': BASE_URL + '/' },
        subtitle: this.__cut(this.__plain(row.chapter_title || row.feature || '') ||
          (row.chapter_num ? '更新至' + row.chapter_num + '话' : ''), 40)
      });
    }
    return items;
  },

  // ------------------------------------------------------------- HTML 解析

  /// 首页楼层：`div.floor` 里 `h2.title` 是块名，条目在 `ul > li.comic-item*`。
  /// 注意 `div.floor-view` 也以 `class="floor` 开头，所以标记要按「后面必须是空格或引号」判。
  __floors(html) {
    var boards = [];
    var marker = 'class="floor';
    var at = this.__markerAt(html, 0, marker);
    var scanned = 0;
    while (at >= 0 && boards.length < 8 && scanned < 20) {
      scanned++;
      var next = this.__markerAt(html, at + marker.length, marker);
      var end = next > at ? next : Math.min(html.length, at + 80000);
      var block = html.slice(at, end);
      var title = this.__headingText(block, 'class="title"');
      var items = this.__items(block);
      if (title && items.length) {
        boards.push({ title: title, moreUrl: this.__floorMore(block), items: items.slice(0, 12) });
      }
      at = next;
    }
    return boards;
  },

  /// 找标记，且标记后一个字符必须是空白或引号（免得 `floor` 命中 `floor-view`）。
  __markerAt(text, from, marker) {
    var at = text.indexOf(marker, from);
    var scanned = 0;
    while (at >= 0 && scanned < 400) {
      scanned++;
      var next = text.charAt(at + marker.length);
      if (next === '"' || next === ' ' || next === "'" || next === '\t') return at;
      at = text.indexOf(marker, at + marker.length);
    }
    return -1;
  },

  __floorMore(block) {
    var at = block.indexOf('class="more"');
    if (at < 0) return 'update';
    var open = block.lastIndexOf('<a', at);
    var close = block.indexOf('>', at);
    if (open < 0 || close < 0) return 'update';
    var href = this.__attr(block.slice(open, close + 1), 'href');
    if (!href) return 'update';
    return href;
  },

  /// 楼层标题：`<h2 class="title"><a href=…><i …></i><span>客棧精品</span>…</a></h2>`。
  __headingText(block, marker) {
    var at = block.indexOf(marker);
    if (at < 0) return '';
    var span = block.indexOf('<span', at);
    if (span < 0) return '';
    var open = block.indexOf('>', span);
    if (open < 0) return '';
    return this.__cut(this.__plain(this.__readText(block, open + 1, 120)), 20);
  },

  /// HTML 列表条目。三种版式共用一个「/{数字}/ 锚点 + 所在块」的形状：
  ///   更新   div.update-item > p.comic-name > a[href=/id/] + a.cover > img[data-src]
  ///   排行   div.rank-item  > a[href=/id/] > img.comic-cover[data-src] + p.comic-name
  ///   分类   li.class-comic-item > a[href=/id/] > img[data-src] + p.comic-name
  __items(html) {
    var items = [];
    var seen = {};
    var at = this.__findItemHref(html, 0);
    var scanned = 0;
    while (at >= 0 && scanned < 800 && items.length < MAX_ITEMS) {
      scanned++;
      var begin = at;
      var li = html.lastIndexOf('<li', at);
      var upd = html.lastIndexOf('class="update-item', at);
      var rank = html.lastIndexOf('class="rank-item', at);
      var pick = li > upd ? li : upd;
      if (rank > pick) pick = rank;
      if (pick >= 0 && at - pick <= 2500) begin = pick;
      var block = html.slice(begin, Math.min(html.length, begin + ITEM_WINDOW));
      var id = this.__hrefComicId(html, at);
      if (id && !seen[id]) {
        var title = this.__classText(block, 'comic-name') || this.__anchorText(block);
        if (title) {
          seen[id] = true;
          items.push({
            id: BASE_URL + '/' + id + '/',
            title: this.__cut(title, 100),
            cover: this.__firstImage(block),
            coverHeaders: { 'Referer': BASE_URL + '/' },
            subtitle: this.__cut(this.__itemSubtitle(block), 40)
          });
        }
      }
      at = this.__findItemHref(html, at + 4);
    }
    return items;
  },

  /// 从 from 起找下一个 `href="/{数字}/"` 的位置。
  __findItemHref(html, from) {
    var needle = 'href="/';
    var at = html.indexOf(needle, from);
    var scanned = 0;
    while (at >= 0 && scanned < 4000) {
      scanned++;
      var i = at + needle.length;
      var start = i;
      while (i < html.length && i - start < 8) {
        var code = html.charCodeAt(i);
        if (code < 48 || code > 57) break;
        i++;
      }
      if (i > start && html.charAt(i) === '/' && html.charAt(i + 1) === '"') return at;
      at = html.indexOf(needle, at + needle.length);
    }
    return -1;
  },

  __hrefComicId(html, at) {
    var i = at + 'href="/'.length;
    var start = i;
    while (i < html.length && i - start < 8) {
      var code = html.charCodeAt(i);
      if (code < 48 || code > 57) break;
      i++;
    }
    return i > start ? html.slice(start, i) : '';
  },

  __anchorText(block) {
    var at = block.indexOf('href="/');
    if (at < 0) return '';
    var open = block.indexOf('>', at);
    if (open < 0) return '';
    var close = block.indexOf('</a>', open);
    if (close < 0) return '';
    return this.__cut(this.__plain(block.slice(open + 1, close)), 100);
  },

  __itemSubtitle(block) {
    var text = this.__classText(block, 'comic-update-at') ||
      this.__classText(block, 'comic-tip') ||
      this.__classText(block, 'comic-update') ||
      this.__classText(block, 'update-feature');
    return this.__plain(text);
  },

  __firstImage(block) {
    var at = block.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 6) {
      scanned++;
      var end = block.indexOf('>', at);
      if (end < 0) break;
      var tag = block.slice(at, end + 1);
      var abs = this.__img(this.__attr(tag, 'data-src') || this.__attr(tag, 'src'));
      if (abs) return abs;
      at = block.indexOf('<img', end);
    }
    return '';
  },

  // ------------------------------------------------------------- 地址工具

  __id(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    if (!id) throw new Error('漫客栈：缺少作品 ID');
    return id;
  },

  /// 作品 ID：绝对地址 / `/{数字}/` / 纯数字 都认。
  __comicId(id) {
    var value = String(id == null ? '' : id).trim();
    if (!value) throw new Error('漫客栈：缺少作品 ID');
    var text = value;
    if (/^https?:\/\//i.test(text) || text.charAt(0) === '/') {
      text = text.replace(/^https?:\/\/(m\.)?mkzhan\.com/i, '');
      // /{comicId}/{chapterId}.html 也算作品地址
      var parts = text.split('/');
      for (var i = 0; i < parts.length; i++) {
        var digits = this.__digits(parts[i]);
        if (digits) return digits;
      }
    }
    var only = this.__digits(text);
    if (only) return only;
    throw new Error('漫客栈：认不出的作品地址（' + id + '）——id 应当来自 list()/detail()');
  },

  __chapterId(value) {
    var text = String(value == null ? '' : value).trim();
    if (!text) return '';
    if (/^https?:\/\//i.test(text) || text.charAt(0) === '/') {
      var path = text.replace(/^https?:\/\/(m\.)?mkzhan\.com/i, '');
      var parts = path.split('/');
      for (var i = parts.length - 1; i >= 0; i--) {
        var digits = this.__digits(String(parts[i]).replace(/\.html$/, ''));
        if (digits) return digits;
      }
      return '';
    }
    return this.__digits(text);
  },

  // ------------------------------------------------------------- 基础工具

  async __get(url) {
    if (!url) throw new Error('漫客栈：空地址');
    var response = await LumeSource.http.get(url, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'text/html,application/xhtml+xml,*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    return body;
  },

  async __api(url) {
    var body = await this.__get(url);
    var json = null;
    try { json = JSON.parse(body); } catch (error) { json = null; }
    if (!json) throw new Error('漫客栈：接口返回不是 JSON（' + url + '）');
    var code = String(json.code == null ? '' : json.code);
    if (code && code !== '200' && code !== '199') {
      throw new Error('漫客栈：接口 ' + code + ' ' + (json.message || '') + '（' + url + '）');
    }
    return json;
  },

  /// 图片地址归一。注意站的封面带尺寸后缀（`…jpg!banner-600` / `…png!cover-400`），
  /// 那些后缀里有 banner / cover 字样，所以「是不是站标图」只在 `!` 与 `?` 之前的**路径**上判。
  __img(url) {
    var text = String(url == null ? '' : url).trim();
    if (!text || text.length > 600) return '';
    if (text.indexOf('data:') === 0) return '';
    var full = '';
    if (text.indexOf('//') === 0) full = 'https:' + text;
    else if (text.indexOf('http') === 0) full = text;
    else if (text.charAt(0) === '/') full = BASE_URL + text;
    else full = BASE_URL + '/' + text;
    full = full.replace(/^http:\/\//i, 'https://');
    var path = full.split('!')[0].split('?')[0];
    if (SKIP_IMAGE.test(path)) return '';
    return full;
  },

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

  __readText(text, from, limit) {
    var end = Math.min(text.length, from + limit);
    var i = from;
    while (i < end && this.__isSpace(text.charCodeAt(i))) i++;
    if (i >= end) return '';
    if (text.charAt(i) === '<') {
      var tagEnd = text.indexOf('>', i);
      if (tagEnd < 0 || tagEnd > end) return '';
      var tag = text.slice(i, tagEnd + 1);
      var title = this.__plain(this.__attr(tag, 'title'));
      if (title) return title;
      var textEnd = text.indexOf('<', tagEnd + 1);
      if (textEnd < 0 || textEnd > end) return '';
      return this.__plain(text.slice(tagEnd + 1, textEnd));
    }
    var stop = text.indexOf('<', i);
    if (stop < 0 || stop > end) stop = end;
    return this.__plain(text.slice(i, stop));
  },

  __classText(window, name) {
    var at = window.indexOf('class="' + name);
    if (at < 0) return '';
    var open = window.indexOf('>', at);
    if (open < 0) return '';
    return this.__plain(this.__readText(window, open + 1, 300));
  },

  __digits(text) {
    var value = String(text == null ? '' : text).trim();
    if (!value || value.length > 12) return '';
    for (var i = 0; i < value.length; i++) {
      var code = value.charCodeAt(i);
      if (code < 48 || code > 57) return '';
    }
    return value;
  },

  __enc(text) {
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
      .replace(/&hellip;/g, '…');
    value = value.replace(/\s+/g, ' ').trim();
    return value;
  }
};
