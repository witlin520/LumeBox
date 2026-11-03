// LumeSource: {"id":"mxgmh_comic","name":"漫香阁","version":"1.0.0","category":"comic","mirrors":["https://xn--ksp-mxgmxgcom-yp8ve33bkpevz1kpxq.mxgmh.com"]}

// 站点：https://xn--ksp-mxgmxgcom-yp8ve33bkpevz1kpxq.mxgmh.com
//   （punycode 主机，页内 canonical 写的是 https://xn--wgv69rba1382b.com/，也就是「漫香阁.com」这套；
//     本脚本只用 mirrors 里那个主机，页内 canonical 一概不跟——换成别的镜像会丢会话/签名）
//
// ## 入口（对着实时页面核过）
//
//   列表  GET /list-1.html … /list-4.html     四个分类（韩漫 / 单行本 / Cosplay / 同人志）
//         GET /list-{c}-{tag}-{page}.html     分类内的标签 + 页码；tag=0 是「全部」
//         （「全部」链接就是 list-1-0-1.html，实测与 list-1.html 等价；页码 21 页）
//   搜索  GET /search.php?key={kw}&typeid=0&p={n}
//         搜索表单本身只提交 key（action="/search.php"），分页是站点自己写在翻页器上的
//         `&typeid=0&p=N`。注意 key 至少 2 个字符，否则站点自己的校验会拦。
//   详情  两种地址，**性质不同**：
//         · /book-{hash}.html      作品页（列表页给的是这种）：h2 标题 + .infoL 封面 +
//                                   .infoR 简介 + ul.listmh 章节列表
//         · /content-{hash}-{cid}.html  直接是某一话的阅读页（首页/搜索给的是这种）：
//                                   没有章节列表，内容就是 ul.contentmh 里的图
//         站点对「book-{hash}」在只存在 content 的作品上直接 500，所以 content 型 id
//         不去猜 book 地址，按「全一話」处理。
//   正文  GET /content-{hash}-{cid}.html
//         图全在 `ul.contentmh > li > img[data-original]`，一页给全（实测 214 张）。
//         站点顺手把 onerror 也写成同一个地址，可以忽略。
//
// ## 图片
//   全部在 manxiangge.hotlinkprotect.com/files/ 下（webp），实测**不校验 Referer**
//   （带不带都 206，也支持 Range），URL 里没有签名/时效参数；仍按站点口径带
//   Referer: <mirror>/（无害）。
//
// ## 站点的混淆脚本
//   每页都挂一段 `_0xodW` / `_0xe3fa` 的 obfuscator 输出，只做「推荐位轮播 / 搜索跳转」，
//   和条目、图片无关，脚本完全不执行它（沙箱无 DOM），只做静态解析。

var BASE_URL = 'https://xn--ksp-mxgmxgcom-yp8ve33bkpevz1kpxq.mxgmh.com';

var MAX_ITEMS = 120;
var ITEM_WINDOW = 2000;
var MAX_IMAGES = 600;
var MAX_CHAPTERS = 500;

// 分类名以站点自己的导航为准；读不到时用这份（就是导航上那几个字）。
var FALLBACK_CATS = [
  { id: 'list-1', title: '韓漫' },
  { id: 'list-2', title: '單行本' },
  { id: 'list-3', title: 'Cosplay' },
  { id: 'list-4', title: '同人志' }
];

var SKIP_IMAGE = /logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|men-bars/i;

var LumeSource = {
  id: 'mxgmh_comic',
  name: '漫香阁',
  version: '1.0.0',
  category: 'comic',

  // ------------------------------------------------------------- 契约方法

  /// 分类：首页顶部导航 `ul#menu li a`（/list-1.html 韩漫 …），按 list 序号升序排
  /// （站点导航把 logo 插在中间，DOM 顺序是 单行本→同人志→韩漫→Cosplay，序号排更稳）。
  /// 导航读不到就用固定那四个（同一批地址）。
  async categories() {
    try {
      var html = await this.__get(BASE_URL + '/');
      var found = this.__categories(html);
      if (found.length) {
        found.sort(function (a, b) {
          return Number(String(a.id).replace('list-', '')) - Number(String(b.id).replace('list-', ''));
        });
        console.warn('[mxgmh] 导航读到 ' + found.length + ' 个分类');
        return found;
      }
    } catch (error) {
      console.warn('[mxgmh] 首页导航拉取失败（' + (error && error.message) + '），用固定分类');
    }
    return FALLBACK_CATS.slice(0);
  },

  /// 首页：站点的楼层（每个 `div.imenu` 是块名 + 一个 `div.top-grids` 列表）。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = this.__boards(html);
    if (boards.length) {
      console.warn('[mxgmh] 首页楼层 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ page: 1, categoryId: 'list-1' });
    if (latest && latest.items && latest.items.length) {
      console.warn('[mxgmh] 首页没认出楼层，退回韩漫一块');
      return [{ title: '韓漫', moreUrl: 'list-1', items: latest.items.slice(0, 12) }];
    }
    return [];
  },

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : 'list-1';

    var url = this.__listUrl(category, keyword, page);
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[mxgmh] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[mxgmh] 列表命中 ' + items.length + ' 条：' + url);
    return { items: items, hasMore: this.__hasNext(html, url, page, items.length) };
  },

  async detail(argument) {
    var url = this.__itemUrl(this.__id(argument));
    var html = await this.__get(url);
    var isBook = url.indexOf('/book-') >= 0;
    var info = isBook ? this.__bookInfo(html) : this.__contentInfo(html, url);
    if (!info.title) {
      console.warn('[mxgmh] 详情页没认出标题：' + url);
      return null;
    }
    return {
      id: url,
      title: info.title,
      cover: info.cover,
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut(info.subtitle, 80),
      description: this.__cut(info.description, 800),
      extra: { kind: isBook ? 'book' : 'content' }
    };
  },

  /// 目录：`book-{hash}` 作品页的 `ul.listmh` 是完整章节表；
  /// `content-{hash}-{cid}` 只有一话 → 一集「全一話」。
  async chapters(argument) {
    var url = this.__itemUrl(this.__id(argument));
    if (url.indexOf('/book-') < 0) {
      console.warn('[mxgmh] 单话地址，返回一集「全一話」：' + url);
      return [{ id: url, title: '全一話' }];
    }
    var html = await this.__get(url);
    var chapters = this.__catalog(html);
    if (!chapters.length) {
      // 作品页没有章节表时退回一集，至少能读。
      console.warn('[mxgmh] 作品页没认出章节表，退回一集：' + url);
      return [{ id: url, title: '全一話' }];
    }
    console.warn('[mxgmh] 目录 ' + chapters.length + ' 话：' + url);
    return chapters;
  },

  /// 正文：`ul.contentmh` 里的 data-original，一页给全。
  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('漫香阁：缺少章节 ID（请先选择一话）');
    var url = this.__itemUrl(chapterId);
    var html = await this.__get(url);
    var images = this.__contentImages(html);
    if (!images.length) {
      // 兜底：整页 manxiangge 图床上的图（排除站标那几张）。
      images = this.__fallbackImages(html);
    }
    if (!images.length) {
      throw new Error('漫香阁：这一话没解析出图片（' + url + '）——把运行日志发回来收敛解析规则');
    }
    console.warn('[mxgmh] 正文 ' + images.length + ' 张图：' + url);
    return {
      kind: 'images',
      images: images,
      headers: { 'Referer': BASE_URL + '/' }
    };
  },

  // ------------------------------------------------------------- 地址策略

  __listUrl(category, keyword, page) {
    if (keyword) {
      return BASE_URL + '/search.php?key=' + this.__enc(keyword) + '&typeid=0&p=' + page;
    }
    var spec = this.__categorySpec(category);
    if (page <= 1 && spec.tag === '0') return BASE_URL + '/' + spec.base + '.html';
    return BASE_URL + '/' + spec.base + '-' + spec.tag + '-' + page + '.html';
  },

  /// 'list-1' → {base:'list-1', tag:'0'}；'list-1-8' → {base:'list-1', tag:'8'}；
  /// 'list-1-8-3' / 绝对地址 → 取 base + tag，页码由调用方给。
  __categorySpec(category) {
    var value = String(category == null ? '' : category).trim();
    if (!value) return { base: 'list-1', tag: '0' };
    if (/^https?:\/\//i.test(value)) {
      var at = value.indexOf('/list-');
      value = at >= 0 ? value.slice(at + 1) : '';
    }
    value = value.replace(/^\//, '').replace(/\.html$/, '');
    var parts = value.split('-');
    if (parts[0] === 'list' && parts.length >= 2 && this.__digits(parts[1])) {
      var tag = parts.length >= 3 && this.__digits(parts[2]) ? parts[2] : '0';
      return { base: 'list-' + parts[1], tag: tag };
    }
    console.warn('[mxgmh] 认不出的分类地址：' + category + '，退回 list-1');
    return { base: 'list-1', tag: '0' };
  },

  __id(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    if (!id) throw new Error('漫香阁：缺少作品 ID');
    return id;
  },

  /// 条目地址归一：绝对地址 / `book-x.html` / `content-x-1.html` / 裸文件名 都认。
  __itemUrl(id) {
    var value = String(id == null ? '' : id).trim();
    if (!value) throw new Error('漫香阁：缺少作品 ID');
    if (/^https?:\/\//i.test(value)) {
      var at = value.indexOf('/book-');
      var at2 = value.indexOf('/content-');
      if (at >= 0) value = value.slice(at + 1);
      else if (at2 >= 0) value = value.slice(at2 + 1);
      else throw new Error('漫香阁：作品地址不在本站（' + id + '）');
    }
    value = value.replace(/^\//, '');
    if (value.charAt(0) !== 'b' && value.charAt(0) !== 'c') {
      throw new Error('漫香阁：认不出的作品地址（' + id + '）——id 应当来自 list()/detail()');
    }
    var cut = value.indexOf('?');
    if (cut >= 0) value = value.slice(0, cut);
    return BASE_URL + '/' + value;
  },

  // ------------------------------------------------------------- 分类 / 首页

  __categories(html) {
    var out = [];
    var seen = {};
    var at = html.indexOf('id="menu"');
    if (at < 0) return out;
    var end = html.indexOf('</ul>', at);
    var area = html.slice(at, end > 0 ? end : Math.min(html.length, at + 8000));
    var anchorAt = area.indexOf('<a');
    var scanned = 0;
    while (anchorAt >= 0 && scanned < 40) {
      scanned++;
      var tagEnd = area.indexOf('>', anchorAt);
      if (tagEnd < 0) break;
      var href = this.__attr(area.slice(anchorAt, tagEnd + 1), 'href');
      var spec = String(href || '').replace(/^\//, '').replace(/\.html$/, '');
      var parts = spec.split('-');
      if (parts[0] === 'list' && parts.length === 2 && this.__digits(parts[1]) && !seen[spec]) {
        var title = this.__cut(this.__plain(this.__readText(area, tagEnd + 1, 60)), 12);
        if (title) {
          seen[spec] = true;
          out.push({ id: spec, title: title });
        }
      }
      anchorAt = area.indexOf('<a', tagEnd);
    }
    return out;
  },

  /// 首页楼层：`div.imenu`（块名 + 「更多」）后面跟着 `div.top-grids` 列表。
  __boards(html) {
    var boards = [];
    var at = html.indexOf('class="imenu"');
    var scanned = 0;
    while (at >= 0 && boards.length < 8 && scanned < 20) {
      scanned++;
      var next = html.indexOf('class="imenu"', at + 14);
      var end = next > at ? next : Math.min(html.length, at + 80000);
      var block = html.slice(at, end);
      var title = this.__imenuTitle(block);
      var items = this.__items(block);
      if (title && items.length) {
        boards.push({ title: title, moreUrl: this.__imenuMore(block), items: items.slice(0, 12) });
      }
      at = next;
    }
    return boards;
  },

  /// `<div class="imenu"><div …>单行本</div><div …><a href="/list-2.html">更多>></a></div></div>`
  __imenuTitle(block) {
    var at = block.indexOf('class="imenu"');
    if (at < 0) return '';
    var open = block.indexOf('>', at);
    if (open < 0) return '';
    var text = this.__plain(this.__readText(block, open + 1, 400));
    // 去掉「更多>>」
    text = text.replace(/更多\s*>>?/g, '').trim();
    return this.__cut(text, 12);
  },

  __imenuMore(block) {
    var at = block.indexOf('更多');
    if (at < 0) return '';
    var open = block.lastIndexOf('<a', at);
    var close = block.indexOf('>', at);
    if (open < 0 || close < 0) return '';
    var href = this.__attr(block.slice(open, close + 1), 'href');
    if (!href) return '';
    return href.replace(/^\//, '').replace(/\.html$/, '');
  },

  // ------------------------------------------------------------- 列表解析

  /// 列表条目：`<a href="book-{hash}.html">`（作品页）或 `<a href="content-{hash}-1.html">`
  /// （首页/搜索给的直接是第 1 话）。块内：
  ///   封面   style="…background-image: url('https://manxiangge…/x.webp')…"
  ///   标题   <h3>…</h3>
  ///   副标题 div.dstate（「更新第33话」）或 h3 后面那段 <p>（简介）
  __items(html) {
    var items = [];
    var seen = {};
    var at = this.__findItemHref(html, 0);
    var scanned = 0;
    while (at >= 0 && scanned < 800 && items.length < MAX_ITEMS) {
      scanned++;
      var end = html.indexOf('</a>', at);
      var block = html.slice(at, end > at ? Math.min(end + 4, at + ITEM_WINDOW) : Math.min(html.length, at + ITEM_WINDOW));
      var rel = this.__hrefValue(html, at);
      var url = '';
      try { url = rel ? this.__itemUrl(rel) : ''; } catch (error) { url = ''; }
      if (url && !seen[url]) {
        var title = this.__h3(block);
        if (title) {
          seen[url] = true;
          items.push({
            id: url,
            title: this.__cut(title, 100),
            cover: this.__backgroundImage(block),
            coverHeaders: { 'Referer': BASE_URL + '/' },
            subtitle: this.__cut(this.__itemSubtitle(block), 40)
          });
        }
      }
      at = this.__findItemHref(html, at + 4);
    }
    return items;
  },

  /// 从 from 起找下一个 `href="book-` / `href="content-` 的位置。
  __findItemHref(html, from) {
    var a = html.indexOf('href="book-', from);
    var b = html.indexOf('href="content-', from);
    if (a < 0) return b;
    if (b < 0) return a;
    return a < b ? a : b;
  },

  __hrefValue(html, at) {
    var start = at + 'href="'.length;
    var end = html.indexOf('"', start);
    if (end < 0) return '';
    return html.slice(start, end);
  },

  __h3(block) {
    var at = block.indexOf('<h3');
    if (at < 0) return '';
    var open = block.indexOf('>', at);
    if (open < 0) return '';
    var close = block.indexOf('</h3>', open);
    if (close < 0) return '';
    return this.__plain(block.slice(open + 1, close));
  },

  __itemSubtitle(block) {
    var at = block.indexOf('class="dstate"');
    if (at >= 0) {
      var open = block.indexOf('>', at);
      if (open >= 0) {
        var text = this.__plain(this.__readText(block, open + 1, 80));
        if (text) return text;
      }
    }
    var h3 = block.indexOf('</h3>');
    if (h3 >= 0) {
      var p = block.indexOf('<p', h3);
      if (p >= 0) {
        var pOpen = block.indexOf('>', p);
        var pClose = block.indexOf('</p>', pOpen);
        if (pOpen >= 0 && pClose > pOpen) return this.__plain(block.slice(pOpen + 1, pClose));
      }
    }
    return '';
  },

  __backgroundImage(block) {
    var at = block.indexOf('background-image');
    if (at < 0) return '';
    var open = block.indexOf('url(', at);
    if (open < 0) return '';
    var start = open + 4;
    var quote = block.charAt(start);
    if (quote === '"' || quote === "'") start++;
    var end = block.indexOf(quote === '"' || quote === "'" ? quote : ')', start);
    if (end < 0) return '';
    return this.__img(block.slice(start, end).trim());
  },

  /// 翻页器：分类页是 `list-{c}-{tag}-{page}.html`，搜索页是 `search.php?key=…&p={page}`。
  __hasNext(html, url, page, count) {
    var current = page > 0 ? page : 1;
    var best = url.indexOf('search.php') >= 0 ? this.__maxAfter(html, '&p=') : this.__maxListPage(html);
    if (best > current) return true;
    if (best > 0) return false;
    return count >= 20;
  },

  /// `list-{c}-{tag}-{page}.html` 里最大的 page。
  __maxListPage(text) {
    var best = 0;
    var at = text.indexOf('list-');
    var scanned = 0;
    while (at >= 0 && scanned < 400) {
      scanned++;
      var i = at + 5;
      var numbers = [];
      var ok = true;
      while (numbers.length < 3) {
        var start = i;
        while (i < text.length && i - start < 5) {
          var code = text.charCodeAt(i);
          if (code < 48 || code > 57) break;
          i++;
        }
        if (i === start) { ok = false; break; }
        numbers.push(Number(text.slice(start, i)));
        if (numbers.length < 3) {
          if (text.charAt(i) !== '-') { ok = false; break; }
          i++;
        }
      }
      if (ok && numbers.length === 3 && numbers[2] > best) best = numbers[2];
      at = text.indexOf('list-', Math.max(i, at + 5));
    }
    return best;
  },

  __maxAfter(text, needle) {
    var best = 0;
    var at = text.indexOf(needle);
    var scanned = 0;
    while (at >= 0 && scanned < 400) {
      scanned++;
      var i = at + needle.length;
      var value = 0;
      var digits = 0;
      while (i < text.length && digits < 5) {
        var code = text.charCodeAt(i);
        if (code < 48 || code > 57) break;
        value = value * 10 + (code - 48);
        i++;
        digits++;
      }
      if (digits && value > best) best = value;
      at = text.indexOf(needle, i);
    }
    return best;
  },

  // ------------------------------------------------------------- 详情解析

  __bookInfo(html) {
    var result = { title: '', cover: '', subtitle: '', description: '' };
    var at = html.indexOf('class="services-desc"');
    var area = at >= 0 ? html.slice(at, Math.min(html.length, at + 12000)) : html;
    var h2 = area.indexOf('<h2');
    if (h2 >= 0) {
      var open = area.indexOf('>', h2);
      var close = area.indexOf('</h2>', open);
      if (open >= 0 && close > open) result.title = this.__cut(this.__plain(area.slice(open + 1, close)), 140);
    }
    if (!result.title) result.title = this.__docTitle(html);
    var infoL = area.indexOf('class="infoL"');
    if (infoL >= 0) {
      var img = area.indexOf('<img', infoL);
      if (img >= 0) {
        var imgEnd = area.indexOf('>', img);
        if (imgEnd > 0) result.cover = this.__img(this.__attr(area.slice(img, imgEnd + 1), 'src'));
      }
      result.subtitle = this.__cut(this.__classText(area.slice(infoL), 'dstate'), 40);
    }
    if (!result.cover) result.cover = this.__firstImage(html);
    var infoR = area.indexOf('class="infoR"');
    if (infoR >= 0) {
      var p = area.indexOf('<p', infoR);
      if (p >= 0) {
        var pOpen = area.indexOf('>', p);
        var pClose = area.indexOf('</p>', pOpen);
        if (pOpen >= 0 && pClose > pOpen) result.description = this.__cut(this.__plain(area.slice(pOpen + 1, pClose)), 800);
      }
    }
    return result;
  },

  __contentInfo(html, url) {
    var result = { title: this.__docTitle(html), cover: '', subtitle: '', description: '' };
    var area = this.__contentArea(html);
    var count = 0;
    var at = area.indexOf('<img');
    var seen = {};
    while (at >= 0 && count < 4000) {
      count++;
      var end = area.indexOf('>', at);
      if (end < 0) break;
      var abs = this.__img(this.__attr(area.slice(at, end + 1), 'data-original'));
      if (abs) {
        if (!result.cover) result.cover = abs;
        if (!seen[abs]) seen[abs] = true;
      }
      at = area.indexOf('<img', end);
    }
    var total = 0;
    for (var key in seen) {
      if (Object.prototype.hasOwnProperty.call(seen, key)) total++;
    }
    result.subtitle = total ? '單話 · 共' + total + '張' : '單話';
    return result;
  },

  __docTitle(html) {
    var at = html.indexOf('<title>');
    if (at < 0) return '';
    var end = html.indexOf('</title>', at);
    if (end < 0) return '';
    var text = this.__plain(html.slice(at + 7, end));
    var cut = text.lastIndexOf(' - ');
    if (cut > 0) text = text.slice(0, cut);
    return this.__cut(text.trim(), 140);
  },

  /// 章节表：`<ul class="listmh"> <li><a href="content-{hash}-{cid}.html">第1話</a></li> … </ul>`
  __catalog(html) {
    var start = html.indexOf('class="listmh"');
    if (start < 0) return [];
    var end = html.indexOf('</ul>', start);
    var area = html.slice(start, end > 0 ? end : Math.min(html.length, start + 200000));
    var out = [];
    var seen = {};
    var at = area.indexOf('href="content-');
    var scanned = 0;
    while (at >= 0 && scanned < MAX_CHAPTERS * 2 && out.length < MAX_CHAPTERS) {
      scanned++;
      var start2 = at + 'href="'.length;
      var close = area.indexOf('"', start2);
      if (close < 0) break;
      var rel = area.slice(start2, close);
      var tagEnd = area.indexOf('>', close);
      var label = tagEnd >= 0 ? this.__cut(this.__plain(this.__readText(area, tagEnd + 1, 60)), 60) : '';
      var url = '';
      try { url = this.__itemUrl(rel); } catch (error) { url = ''; }
      if (url && !seen[url]) {
        seen[url] = true;
        out.push({ id: url, title: label || ('第' + (out.length + 1) + '話') });
      }
      at = area.indexOf('href="content-', close);
    }
    return out;
  },

  // ------------------------------------------------------------- 正文解析

  __contentArea(html) {
    var start = html.indexOf('class="contentmh"');
    if (start < 0) return html;
    var end = html.indexOf('</ul>', start);
    return html.slice(start, end > 0 ? end : Math.min(html.length, start + 400000));
  },

  __contentImages(html) {
    var area = this.__contentArea(html);
    var images = [];
    var seen = {};
    var at = area.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 4000 && images.length < MAX_IMAGES) {
      scanned++;
      var end = area.indexOf('>', at);
      if (end < 0) break;
      var tag = area.slice(at, end + 1);
      var abs = this.__img(this.__attr(tag, 'data-original') || this.__attr(tag, 'src'));
      if (abs && !seen[abs]) {
        seen[abs] = true;
        images.push(abs);
      }
      at = area.indexOf('<img', end);
    }
    return images;
  },

  __fallbackImages(html) {
    var images = [];
    var seen = {};
    var at = html.indexOf('manxiangge.hotlinkprotect.com');
    var scanned = 0;
    while (at >= 0 && scanned < 4000 && images.length < MAX_IMAGES) {
      scanned++;
      var start = html.lastIndexOf('https://', at);
      var end = html.indexOf('"', at);
      if (start >= 0 && end > at) {
        var abs = this.__img(html.slice(start, end));
        if (abs && !seen[abs]) {
          seen[abs] = true;
          images.push(abs);
        }
      }
      at = html.indexOf('manxiangge.hotlinkprotect.com', at + 20);
    }
    return images;
  },

  // ------------------------------------------------------------- 基础工具

  async __get(url) {
    if (!url) throw new Error('漫香阁：空地址');
    var response = await LumeSource.http.get(url, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'text/html,application/xhtml+xml,*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 || status === 503 || status === 429 || status === 500) {
        throw new Error('NEED_WEBVIEW_VERIFY：漫香阁 拉取失败（HTTP ' + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    }
    return body;
  },

  __img(url) {
    var text = String(url == null ? '' : url).trim();
    if (!text || text.length > 500) return '';
    if (text.indexOf('data:') === 0) return '';
    var full = '';
    if (text.indexOf('//') === 0) full = 'https:' + text;
    else if (text.indexOf('http') === 0) full = text;
    else if (text.charAt(0) === '/') full = BASE_URL + text;
    else full = BASE_URL + '/' + text;
    full = full.replace(/^http:\/\//i, 'https://');
    if (SKIP_IMAGE.test(full)) return '';
    return full;
  },

  __firstImage(block) {
    var at = block.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 6) {
      scanned++;
      var end = block.indexOf('>', at);
      if (end < 0) break;
      var tag = block.slice(at, end + 1);
      var abs = this.__img(this.__attr(tag, 'data-original') || this.__attr(tag, 'src'));
      if (abs) return abs;
      at = block.indexOf('<img', end);
    }
    return '';
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
