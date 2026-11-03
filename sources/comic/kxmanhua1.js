// LumeSource: {"id":"kxmanhua1_comic","name":"开心看漫画","version":"1.0.0","category":"comic","mirrors":["https://kxmanhua1.com"]}

// 站点：https://kxmanhua1.com（发布页 kxkmh.xyz 只是一个「最新地址」跳转页，
// **不是镜像**：它返回的是 kxmanhua.com / kxmanhua1.com 的线路列表，没有漫画内容，
// 所以 mirrors 只放真正出内容的 kxmanhua1.com。）
//
// ## 抓取口径（全部对着实时页面核过）
//
//   分类  /manga/library?type={0..5}&complete={1..3}&orderby={1..3}&page={N}
//         type：0 全部 / 1 3D / 2 韩漫 / 3 日漫 / 4 真人 / 5 耽美BL
//         complete：1 全部 / 2 完结 / 3 连载；orderby：1 最热门 / 2 最近更新 / 3 最新上架
//         分类条就是这些真实链接，categories() 每次从列表页读出来（读不到才用内置兜底）。
//   列表  同上的 GET，24 条/页；分页器 `div.product__pagination` 写 `…&page=N`
//         （站内也接受单独 `?page=N`，但本源一律改 `page=` 那一段，保持 type/orderby 不丢）。
//   排行  /manga/rank —— 周榜/月榜/总榜三块，**没有分页器**（只有第 1 页）。
//   搜索  /manga/search?keyword={UTF-8 百分号编码}[&page=N]（表单 action 就是它，分页器带 page）。
//   详情  /manga/{数字id}：标题 `div.anime__details__title > h3`、封面
//         `div.anime__details__pic.set-bg[data-setbg]`、作者/别名是该块里的 `<span>` 行、
//         简介是 `div.anime__details__text` 里最长的那个 `<p>`、状态是封面块里的
//         `div.ep`(连载) / `div.epgreen`(完结)、分类是 `li > a[href=/manga/library?type=…]`。
//   目录  就在详情页 `div.chapter_list > a[href=/manga/{id}/detail/{章节id}]`，
//         站点是**新→旧**排列，本源反转成旧→新再交给 App。
//   正文  /manga/{id}/detail/{章节id}：服务端直出 `<img src="…webtoon/content/…">`
//         `loading="lazy"`，一章一页、不翻页。同一页还有 `/webtoon/ad-slider/*.gif` 广告图
//         和 `/img/view-*-logo.png` 站标，所以只收 **`img.imh99.top/webtoon/content/`** 这条路径，
//         绝不整页抓裸 <img>（实测一页 138 张正片 + 5 张广告/站标）。
//
// 图片域名 img.imh99.top 实测**带不带 Referer 都是 200/206**，headers 里照契约放站点 Referer。

var BASE_URL = 'https://kxmanhua1.com';

var PAGE_SIZE = 24;        // 列表每页条数（实测）
var MAX_ITEMS = 120;       // 单次列表最多产出
var CARD_WINDOW = 700;     // 卡片往后看的窗口
var MAX_CARDS = 220;       // 最多扫多少张卡
var MAX_CHAPTERS = 3000;   // 目录最多解析多少话
var MAX_IMAGES = 400;      // 正文最多收多少张图
var IMG_SCAN = 400000;     // 正文页最多扫多少字符

var DEFAULT_CATEGORY = '/manga/library?type=0&complete=1&orderby=1&page=1';

var LumeSource = {
  id: 'kxmanhua1_comic',
  name: '开心看漫画',
  version: '1.0.0',
  category: 'comic',

  // ---------------------------------------------------------------- 分类

  /// 分类条 = 列表页自己的 type 标签（全部/3D/韩漫/日漫/真人/耽美BL）+ 排行榜。
  /// id 是站内「路径 + 查询串」，list() 只改其中的 page=N。
  ///
  /// 顺序上把 **type=2（韩漫）提到第一档**：站点 `type=0 全部` 的第一条现在是
  /// [3D]奸魔再世，而 3D 那批作品的正文页 `img src` 全空（实测 3915 的两话
  /// 208/225 个 img 标签 src="" 且页内没有任何图片地址），整章取不到图；
  /// 韩漫档第一页的作品实测都是正常直出图。把能读的放第一档，用户点进来的默认页才有内容。
  async categories() {
    var html = await this.__get(BASE_URL + DEFAULT_CATEGORY);
    var found = this.__typeTabs(html);
    var boards = [{ id: '/manga/rank', title: '排行榜' }];
    if (found.length) {
      console.warn('[kxmanhua] 分类 ' + found.length + ' 项（现读站点筛选条）');
      return this.__koreanFirst(found).concat(boards);
    }
    console.warn('[kxmanhua] 没认出筛选条，用内置兜底');
    return this.__koreanFirst(this.__fallbackCategories()).concat(boards);
  },

  __koreanFirst(list) {
    var out = [];
    var i;
    for (i = 0; i < list.length; i++) {
      if (/[?&]type=2&/.test(list[i].id)) out.push(list[i]);
    }
    for (i = 0; i < list.length; i++) {
      if (!/[?&]type=2&/.test(list[i].id)) out.push(list[i]);
    }
    return out;
  },

  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = this.__boards(html);
    if (boards.length) {
      console.warn('[kxmanhua] 首页板块 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ categoryId: DEFAULT_CATEGORY, page: 1 });
    if (latest && latest.items && latest.items.length) {
      console.warn('[kxmanhua] 首页没认出板块，退回列表一块');
      return [{ title: '全部漫画', moreUrl: DEFAULT_CATEGORY, items: latest.items.slice(0, 12) }];
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
      console.warn('[kxmanhua] 「' + (category || '全部') + '」只有第 1 页，第 ' + page + ' 页返回空');
      return { items: [], hasMore: false };
    }
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[kxmanhua] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[kxmanhua] 列表命中：' + url + '（' + items.length + ' 条）');
    return { items: items, hasMore: this.__hasNext(html, page) };
  },

  __listUrl(category, keyword, page) {
    if (keyword) {
      var search = BASE_URL + '/manga/search?keyword=' + this.__encode(keyword);
      if (page > 1) search += '&page=' + page;
      return search;
    }
    var path = this.__categoryPath(category);
    if (path.indexOf('/manga/rank') === 0) {
      return page > 1 ? '' : BASE_URL + path;
    }
    if (!path) path = DEFAULT_CATEGORY;
    path = path.replace(/[?&]page=\d+/, '');
    if (path.indexOf('?') < 0) path += '?page=' + page;
    else path += '&page=' + page;
    return BASE_URL + path;
  },

  __categoryPath(category) {
    var id = String(category == null ? '' : category).trim();
    if (!id) return DEFAULT_CATEGORY;
    if (id.indexOf('http') === 0) {
      if (id.indexOf(BASE_URL) === 0) return id.slice(BASE_URL.length);
      var m = /^https?:\/\/[^\/]+(\/.*)$/.exec(id);
      return m ? m[1] : DEFAULT_CATEGORY;
    }
    if (id.charAt(0) !== '/') return '/' + id;
    return id;
  },

  /// 列表页的类型标签（`/manga/library?type=N&complete=1&page=1&orderby=1`）。
  /// 站点把 `&` 写成 `&amp;`，读出来统一还原成 `&`。
  __typeTabs(html) {
    var out = [];
    var seen = {};
    var at = 0;
    var guard = 0;
    while (guard++ < 400) {
      var pos = html.indexOf('/manga/library?type=', at);
      if (pos < 0) break;
      var quote = html.lastIndexOf('"', pos);
      var hrefEnd = html.indexOf('"', pos);
      var start = html.lastIndexOf('<a', pos);
      if (quote >= 0 && hrefEnd > pos && start >= 0) {
        var href = html.slice(pos, hrefEnd).replace(/&amp;/g, '&');
        var tagEnd = html.indexOf('>', hrefEnd);
        var close = html.indexOf('</a>', tagEnd);
        var text = tagEnd > 0 && close > tagEnd ? this.__plain(html.slice(tagEnd + 1, close)) : '';
        var key = href.replace(/[?&]page=\d+/, '');
        if (key.indexOf('complete=1') > 0 && key.indexOf('orderby=1') > 0 && text && !seen[key]) {
          seen[key] = true;
          out.push({ id: key, title: this.__cut(text, 12) });
        }
      }
      at = hrefEnd > pos ? hrefEnd : pos + 10;
    }
    return out;
  },

  __fallbackCategories() {
    return [
      { id: '/manga/library?type=0&complete=1&orderby=1&page=1', title: '全部漫画' },
      { id: '/manga/library?type=2&complete=1&orderby=1&page=1', title: '韩漫' },
      { id: '/manga/library?type=3&complete=1&orderby=1&page=1', title: '日漫' },
      { id: '/manga/library?type=1&complete=1&orderby=1&page=1', title: '3D漫画' },
      { id: '/manga/library?type=0&complete=1&orderby=2&page=1', title: '最近更新' },
      { id: '/manga/library?type=0&complete=1&orderby=3&page=1', title: '最新上架' }
    ];
  },

  /// 首页板块：首页把 5 个区块（最近更新 / 最新上架 / 热门韩漫 / 热门日漫 / 本周热门）
  /// 都包在 `div.section-title > h4` 里，跟着一块 `div.btn__all > a`（有的没有「更多」）。
  /// 所以按 `section-title` 切窗口最稳（左边两列用 trending__product，右边栏用
  /// product__sidebar，容器类名不一样，只有标题这一层是统一的）。
  __boards(html) {
    var boards = [];
    var at = html.indexOf('class="section-title"');
    var guard = 0;
    while (at >= 0 && boards.length < 8 && guard < 12) {
      guard++;
      var next = html.indexOf('class="section-title"', at + 20);
      var window = html.slice(at, next > at ? next : Math.min(html.length, at + 60000));
      var title = this.__h4Title(window);
      var items = this.__items(window);
      if (title && items.length) {
        boards.push({ title: this.__cut(title, 16), moreUrl: this.__moreHref(window), items: items.slice(0, 12) });
      }
      at = next;
    }
    return boards;
  },

  __h4Title(window) {
    var at = window.indexOf('<h4>');
    if (at < 0) return '';
    var close = window.indexOf('</h4>', at);
    if (close < 0) return '';
    return this.__plain(window.slice(at + 4, close));
  },

  __moreHref(window) {
    var at = window.indexOf('btn__all');
    if (at < 0) return DEFAULT_CATEGORY;
    var start = window.indexOf('<a', at);
    var end = window.indexOf('>', start);
    if (start < 0 || end < 0) return DEFAULT_CATEGORY;
    var href = this.__attr(window.slice(start, end + 1), 'href').replace(/&amp;/g, '&');
    if (!href) return DEFAULT_CATEGORY;
    return href;
  },

  /// 卡片解析：列表/首页是 `div.product__item`（`div.product__item__pic.set-bg[data-setbg]`
  /// + `h6 > a[href=/manga/{id}]`），排行榜是 `div.product__sidebar__view__item[data-setbg]`
  /// + `onclick="location.href='/manga/{id}'"` + `<a href=…>`。统一从 `data-setbg` 起跳。
  __items(html) {
    var items = [];
    var seen = {};
    var at = html.indexOf('data-setbg="');
    var guard = 0;
    while (at >= 0 && items.length < MAX_ITEMS) {
      if (++guard > MAX_CARDS) break;
      var cover = this.__attrValue(html, at + 11);
      var window = html.substr(at, CARD_WINDOW);
      var id = '';
      var m = /onclick="location\.href='\/manga\/(\d+)'/.exec(window);
      if (m) id = m[1];
      if (!id) {
        var m2 = /href="\/manga\/(\d+)"/.exec(window);
        if (m2) id = m2[1];
      }
      if (id && !seen[id] && this.__isCover(cover)) {
        // 站点卡片的 `title` 属性带「漫画」前缀（漫画秘密教学），锚内文字才是干净标题
        var title = '';
        var t2 = /href="\/manga\/\d+"[^>]*>([^<]{1,80})</.exec(window);
        if (t2) title = t2[1];
        if (!title) {
          var t = /<a[^>]*href="\/manga\/\d+"[^>]*title="([^"]*)"/.exec(window);
          if (t) title = t[1];
        }
        title = this.__cut(this.__plain(title), 80);
        if (title) {
          seen[id] = true;
          items.push({
            id: BASE_URL + '/manga/' + id,
            title: title,
            cover: this.__absolute(cover),
            coverHeaders: { 'Referer': BASE_URL + '/' },
            subtitle: this.__cardSubtitle(window)
          });
        }
      }
      at = html.indexOf('data-setbg="', at + 12);
    }
    return items;
  },

  __cardSubtitle(window) {
    var parts = [];
    var status = '';
    var ep = /class="epgreen"[^>]*>\s*([^<]{1,10})\s*</.exec(window);
    if (ep) status = ep[1];
    if (!status) {
      var ep2 = /class="ep"[^>]*>\s*([^<]{1,10})\s*</.exec(window);
      if (ep2) status = ep2[1];
    }
    if (status) parts.push(status.trim());
    var view = /class="view"[^>]*>[\s\S]{0,80}?([0-9.]+[wm]?)</.exec(window);
    if (view) parts.push(this.__plain(view[1]) + ' 阅读');
    return this.__cut(parts.join(' · '), 40);
  },

  __isCover(url) {
    var text = String(url || '').trim();
    if (!text || text.length > 400) return false;
    return /\.(webp|jpg|jpeg|png|gif|avif)$/i.test(text);
  },

  __hasNext(html, page) {
    var pager = html.indexOf('product__pagination');
    if (pager < 0) return false;
    var max = this.__maxPageIn(html.substr(pager, 8000));
    if (max > page) return true;
    return false;
  },

  __maxPageIn(text) {
    var best = 0;
    var at = text.indexOf('page=');
    var guard = 0;
    while (at >= 0 && guard < 400) {
      guard++;
      var i = at + 5;
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
      at = text.indexOf('page=', i);
    }
    return best;
  },

  // ---------------------------------------------------------------- 详情 / 目录

  async detail(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/manga/' + id;
    var html = await this.__get(url);
    var info = this.__detailFields(html);
    if (!info.title) {
      console.warn('[kxmanhua] 详情页没认出标题：' + url + '（' + html.length + ' 字符）');
      return null;
    }
    return {
      id: url,
      title: info.title,
      cover: info.cover,
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut([info.author ? '作者：' + info.author : '', info.status].join(' · ').replace(/^ · /, ''), 60),
      description: info.description,
      tags: info.tags,
      extra: { author: info.author, alias: info.alias, status: info.status }
    };
  },

  async chapters(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/manga/' + id;
    var html = await this.__get(url);
    var chapters = this.__chapters(html, id);
    if (!chapters.length) {
      console.warn('[kxmanhua] 目录为空：' + url);
      return [];
    }
    console.warn('[kxmanhua] 目录 ' + chapters.length + ' 话（已翻成旧→新）：' + url);
    return chapters;
  },

  // ---------------------------------------------------------------- 正文

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('开心看漫画：缺少章节 ID（请先选择一话）');
    var url = this.__chapterUrl(chapterId, argument && argument.id);
    if (!url) throw new Error('开心看漫画：认不出章节地址（' + chapterId + '）');
    var html = await this.__get(url, { 'Referer': BASE_URL + '/' });
    var images = this.__images(html);
    if (!images.length) {
      throw new Error('开心看漫画：这一话没解析出图片（' + url + '）');
    }
    console.warn('[kxmanhua] 正文 ' + images.length + ' 张图：' + url);
    return { kind: 'images', images: images, headers: { 'Referer': BASE_URL + '/' } };
  },

  __chapterUrl(chapterId, itemId) {
    var value = String(chapterId || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      if (value.indexOf(BASE_URL) === 0) return value;
      return '';
    }
    if (value.charAt(0) === '/') return BASE_URL + value;
    // 只给了章节 id：用作品 id 拼 /manga/{作品}/detail/{章节}
    if (/^\d+$/.test(value)) {
      var book = '';
      try { book = this.__bookId(itemId); } catch (error) { book = ''; }
      if (!book) return '';
      return BASE_URL + '/manga/' + book + '/detail/' + value;
    }
    return '';
  },

  __images(html) {
    var images = [];
    var seen = {};
    var area = html.slice(0, Math.min(html.length, IMG_SCAN));
    var at = area.indexOf('blog__details__content');
    var body = at >= 0 ? area.slice(at, Math.min(area.length, at + IMG_SCAN)) : area;
    var pos = body.indexOf('<img');
    var guard = 0;
    while (pos >= 0 && images.length < MAX_IMAGES) {
      if (++guard > 2000) break;
      var end = body.indexOf('>', pos);
      if (end < 0) break;
      var tag = body.slice(pos, end + 1);
      var src = this.__attr(tag, 'src') || this.__attr(tag, 'data-src') || this.__attr(tag, 'data-original');
      var url = this.__absolute(src);
      if (url && url.indexOf('/webtoon/content/') > 0 && !seen[url]) {
        seen[url] = true;
        images.push(url);
      }
      pos = body.indexOf('<img', end);
    }
    return images;
  },

  __bookId(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    else if (typeof argument === 'string') id = argument;
    var value = String(id || '').trim();
    if (!value) throw new Error('开心看漫画：缺少作品 ID');
    var m = /\/manga\/(\d+)/.exec(value);
    if (m) return m[1];
    if (/^\d+$/.test(value)) return value;
    throw new Error('开心看漫画：认不出的作品 ID（' + id + '）');
  },

  __detailFields(html) {
    var info = { title: '', cover: '', description: '', author: '', alias: '', status: '', tags: [] };
    var at = html.indexOf('anime__details__title');
    if (at >= 0) {
      var window = html.slice(at, Math.min(html.length, at + 2000));
      var h3 = /<h3[^>]*>([\s\S]{0,160}?)<\/h3>/.exec(window);
      if (h3) info.title = this.__cut(this.__plain(h3[1]), 120);
      var spans = window.match(/<span[^>]*>([\s\S]{0,120}?)<\/span>/g) || [];
      for (var i = 0; i < spans.length; i++) {
        var text = this.__plain(spans[i]);
        if (text.indexOf('作者') === 0) info.author = this.__cut(text.replace(/^作者[:：]\s*/, ''), 40);
        else if (text.indexOf('别名') === 0) info.alias = this.__cut(text.replace(/^别名[:：]\s*/, ''), 60);
      }
    }
    if (!info.title) {
      var raw = this.__titleTag(html);
      var cut = raw.indexOf(' - ');
      if (cut > 0) raw = raw.slice(0, cut);
      info.title = this.__plain(raw);
    }
    var pic = html.indexOf('anime__details__pic');
    if (pic >= 0) {
      var pwin = html.slice(pic, Math.min(html.length, pic + 700));
      var cover = this.__attr(pwin.slice(0, pwin.indexOf('>') + 1), 'data-setbg');
      if (cover) info.cover = this.__absolute(cover);
      var ep = /class="epgreen"[^>]*>\s*([^<]{1,10})\s*</.exec(pwin);
      if (ep) info.status = ep[1].trim();
      if (!info.status) {
        var ep2 = /class="ep"[^>]*>\s*([^<]{1,10})\s*</.exec(pwin);
        if (ep2) info.status = ep2[1].trim();
      }
    }
    var textBlock = html.indexOf('anime__details__text');
    if (textBlock >= 0) {
      var block = html.slice(textBlock, Math.min(html.length, textBlock + 6000));
      var ps = block.match(/<p[^>]*>([\s\S]{0,1200}?)<\/p>/g) || [];
      var best = '';
      for (var j = 0; j < ps.length; j++) {
        var plain = this.__plain(ps[j]);
        if (plain.length > best.length) best = plain;
      }
      info.description = this.__cut(best, 800);
      info.tags = this.__detailTags(block);
    }
    return info;
  },

  __detailTags(block) {
    var tags = [];
    var seen = {};
    var at = block.indexOf('/manga/library?type=');
    var guard = 0;
    while (at >= 0 && guard < 20) {
      guard++;
      var start = block.lastIndexOf('<a', at);
      var tagEnd = block.indexOf('>', at);
      if (start >= 0 && tagEnd > at) {
        var text = this.__plain(block.slice(tagEnd + 1, block.indexOf('</a>', tagEnd)));
        if (text && text.length <= 12 && !seen[text]) {
          seen[text] = true;
          tags.push(text);
        }
      }
      at = block.indexOf('/manga/library?type=', tagEnd > 0 ? tagEnd : at + 10);
    }
    return tags;
  },

  /// 目录：`div.chapter_list > a[href=/manga/{id}/detail/{cid}]`，站点新→旧，反转成旧→新。
  __chapters(html, bookId) {
    var out = [];
    var seen = {};
    var start = html.indexOf('chapter_list');
    var area = start >= 0 ? html.slice(start, Math.min(html.length, start + 300000)) : html;
    var prefix = '/manga/' + bookId + '/detail/';
    var at = area.indexOf(prefix);
    var guard = 0;
    while (at >= 0 && out.length < MAX_CHAPTERS) {
      if (++guard > MAX_CHAPTERS * 3) break;
      var anchorAt = area.lastIndexOf('<a ', at);
      var tagEnd = area.indexOf('>', at);
      if (anchorAt >= 0 && tagEnd > at) {
        var tag = area.slice(anchorAt, tagEnd + 1);
        var href = this.__attr(tag, 'href');
        if (href.indexOf(prefix) === 0) {
          var url = BASE_URL + href;
          if (!seen[url]) {
            var title = this.__plain(this.__attr(tag, 'title')) ||
              this.__plain(area.slice(tagEnd + 1, area.indexOf('</a>', tagEnd)));
            if (title) {
              seen[url] = true;
              out.push({ id: url, title: this.__cut(title, 60) });
            }
          }
        }
      }
      at = area.indexOf(prefix, at + prefix.length);
    }
    out.reverse();
    return out;
  },

  // ---------------------------------------------------------------- 基础工具

  async __get(url, extraHeaders) {
    var headers = {
      'Referer': BASE_URL + '/',
      'Accept': 'text/html,application/xhtml+xml',
      'Accept-Language': 'zh-CN,zh;q=0.9'
    };
    if (extraHeaders) {
      for (var key in extraHeaders) {
        if (Object.prototype.hasOwnProperty.call(extraHeaders, key)) headers[key] = extraHeaders[key];
      }
    }
    var response = await LumeSource.http.get(url, { headers: headers });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 || status === 503 || status === 429 ||
        /just a moment|__cf_chl|challenge-platform|cf-mitigated/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：开心看漫画 需要网页视图过一次 Cloudflare 校验（HTTP ' + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
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
