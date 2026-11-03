// LumeSource: {"id":"hentai3_comic","name":"3Hentai","version":"1.0.0","category":"comic","mirrors":["https://3hentai.club"]}

// 站点：https://3hentai.club（WordPress + 主题 tema-a43_2；前台是英文/葡语混排，UTF-8）
//
// ## 入口（对着实时页面核过）
//
//   列表  GET /                                    首页「最新」第 1 页（20 条/页）
//         GET /page/{n}/                           第 n 页
//         GET /category/{name}/                    分类（doujinshi / hentai / uncensored …）
//         GET /tag/{name}/                         标签
//         GET /parody/{name}/                      作品系列
//         以上三类分页都在路径上：`/tag/{name}/page/{n}/`
//   搜索  GET /?s={kw}   → 分页是 /page/2/?s={kw}（WordPress 的 search 分页形态，实测第 2 页
//         的内容与第 1 页不同）
//   详情  GET /{slug}/    ← 文章地址就是 slug，没有数字 id
//         标题 `h1.post-titulo`（里面 `[Doujinshi] <span>真名</span>`，取整段文本）；
//         封面 `div.post-capa > img`（这张是原图 1280w，不是缩略图）；
//         元信息在 `ul.post-itens`（Categories / Tags / Parody / Artist / Group / Language / Pages）
//   目录  站点是一篇一册（一篇 = 一册同人志），没有分话 → 固定返回一集「全一话」。
//   正文  就在详情页正文 `ul.post-fotos > li > a > img`，**一页给全所有图**（实测 49 张，
//         与页面上的 Pages 数一致；图是原尺寸文件名，不带 -213x300 那种尺寸后缀）。
//         页面上还有「You will like it too」相关推荐（同 .lista 缩略图），所以必须先切出
//         `ul.post-fotos … </ul>` 这一段再取 img，否则会把推荐位的缩略图当正文图。
//
// ## 图片
//   wp-content/uploads 下的原图，实测**不校验 Referer**（带不带都 206），也没有防盗链签名；
//   仍然在 content() 里带 Referer: https://3hentai.club/（和站点口径一致，无害）。

var BASE_URL = 'https://3hentai.club';

var MAX_ITEMS = 80;
var ITEM_WINDOW = 2600;
var MAX_IMAGES = 400;
var MAX_TAGS = 8;
var LIST_PER_PAGE = 20;

var SKIP_IMAGE = /logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|flag|bandeira|estados-unidos|espanha|cropped|favicon/i;

var LumeSource = {
  id: 'hentai3_comic',
  name: '3Hentai',
  version: '1.0.0',
  category: 'comic',

  // ------------------------------------------------------------- 契约方法

  /// 分类：站点顶部菜单 `ul#menu-id`（tag / category 混排）就是它自己的分类树，
  /// 前面补一个「最新」（`/`）。菜单读不到就只给最新 + 三个固定分类页（这三条地址
  /// 在第 1 页正文的 Categories 行里每次都会出现，不是编的）。
  async categories() {
    var out = [{ id: '/', title: '最新' }];
    var seen = { '/': true };
    try {
      var html = await this.__get(BASE_URL + '/');
      var menu = this.__menu(html);
      for (var i = 0; i < menu.length; i++) {
        if (!seen[menu[i].id]) {
          seen[menu[i].id] = true;
          out.push(menu[i]);
        }
      }
      if (out.length > 1) {
        console.warn('[3hentai] 菜单读到 ' + (out.length - 1) + ' 项分类');
        return out;
      }
    } catch (error) {
      console.warn('[3hentai] 菜单拉取失败（' + (error && error.message) + '），用固定分类');
    }
    out.push({ id: '/category/doujinshi/', title: 'Doujinshi' });
    out.push({ id: '/category/hentai/', title: 'Hentai' });
    out.push({ id: '/category/uncensored/', title: 'Uncensored' });
    return out;
  },

  /// 首页：首屏那块 `.lista` 就是「最新」列表（20 条）。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[3hentai] 首页没解析出条目（' + html.length + ' 字符）');
      return [];
    }
    console.warn('[3hentai] 首页 ' + items.length + ' 条');
    return [{ title: '最新', moreUrl: '/', items: items.slice(0, 12) }];
  },

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    var url = this.__listUrl(category, keyword, page);
    var html = await this.__get(url);
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[3hentai] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[3hentai] 列表命中 ' + items.length + ' 条：' + url);
    return { items: items, hasMore: this.__hasNext(html, page, items.length) };
  },

  async detail(argument) {
    var url = this.__postUrl(this.__id(argument));
    var html = await this.__get(url);
    var title = this.__postTitle(html);
    if (!title) {
      console.warn('[3hentai] 详情页没认出标题：' + url);
      return null;
    }
    var info = this.__postInfo(html);
    return {
      id: url,
      title: title,
      cover: this.__postCover(html),
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut(info.subtitle, 80),
      description: this.__cut(info.description, 800),
      tags: info.tags,
      extra: { pages: info.pages, artist: info.artist }
    };
  },

  /// 一篇 = 一册，没有分话。给一集「全一話」，id 就是文章地址本身。
  async chapters(argument) {
    var url = this.__postUrl(this.__id(argument));
    return [{ id: url, title: '全一話' }];
  },

  /// 正文图全在 `ul.post-fotos` 里一页给全（无章内分页）。
  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('3Hentai：缺少章节 ID（请先选择一话）');
    var url = this.__postUrl(chapterId);
    var html = await this.__get(url);
    var images = this.__contentImages(html);
    if (!images.length) {
      // 兜底：整页原图（排除站标/旗帜/推荐位缩略图）。
      images = this.__fallbackImages(html);
    }
    if (!images.length) {
      throw new Error('3Hentai：这一话没解析出图片（' + url + '）——把运行日志发回来收敛解析规则');
    }
    console.warn('[3hentai] 正文 ' + images.length + ' 张图：' + url);
    return {
      kind: 'images',
      images: images,
      headers: { 'Referer': BASE_URL + '/' }
    };
  },

  // ------------------------------------------------------------- 地址策略

  __listUrl(category, keyword, page) {
    var path = this.__categoryPath(category);
    if (keyword) {
      if (page > 1) return BASE_URL + '/page/' + page + '/?s=' + this.__enc(keyword);
      return BASE_URL + '/?s=' + this.__enc(keyword);
    }
    if (page <= 1) return BASE_URL + path;
    var trimmed = path === '/' ? '' : path.replace(/\/$/, '');
    return BASE_URL + trimmed + '/page/' + page + '/';
  },

  __categoryPath(category) {
    var value = String(category == null ? '' : category).trim();
    if (!value || value === '/') return '/';
    if (value.indexOf('http') === 0) {
      if (value.indexOf('3hentai.club') >= 0) {
        value = value.replace(/^https?:\/\/3hentai\.club/, '');
        if (!value) value = '/';
      } else {
        console.warn('[3hentai] 分类地址不是本站：' + category + '，退回首页');
        return '/';
      }
    }
    if (value.charAt(0) !== '/') value = '/' + value;
    // 已经带 /page/N/ 的地址按第 1 页处理，避免叠加。
    value = value.replace(/\/page\/\d+\/?$/, '/');
    return value || '/';
  },

  __id(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    if (!id) throw new Error('3Hentai：缺少作品 ID');
    return id;
  },

  /// 文章地址归一：绝对地址 / 站内路径 / 纯 slug 都认。允许附带 ?page= 之类尾巴（去掉）。
  __postUrl(id) {
    var value = String(id == null ? '' : id).trim();
    if (!value) throw new Error('3Hentai：缺少作品 ID');
    if (value.indexOf('http') === 0) {
      if (value.indexOf('3hentai.club') < 0) throw new Error('3Hentai：作品地址不在本站（' + id + '）');
      value = value.replace(/^https?:\/\/3hentai\.club/, '');
    }
    var cut = value.indexOf('?');
    if (cut >= 0) value = value.slice(0, cut);
    var hash = value.indexOf('#');
    if (hash >= 0) value = value.slice(0, hash);
    if (value.charAt(0) !== '/') value = '/' + value;
    if (value === '/') throw new Error('3Hentai：认不出的作品地址（' + id + '）');
    if (value.slice(-1) !== '/') value += '/';
    return BASE_URL + value;
  },

  // ------------------------------------------------------------- 分类 / 解析

  __menu(html) {
    var out = [];
    var seen = {};
    var at = html.indexOf('id="menu-id"');
    if (at < 0) return out;
    var end = html.indexOf('</ul>', at);
    var area = html.slice(at, end > 0 ? end : Math.min(html.length, at + 30000));
    var anchorAt = area.indexOf('<a');
    var scanned = 0;
    while (anchorAt >= 0 && scanned < 120) {
      scanned++;
      var tagEnd = area.indexOf('>', anchorAt);
      if (tagEnd < 0) break;
      var tag = area.slice(anchorAt, tagEnd + 1);
      var href = this.__attr(tag, 'href');
      var path = this.__sitePath(href);
      var title = this.__cut(this.__plain(this.__readText(area, tagEnd + 1, 60)), 24);
      if (path && title && !seen[path]) {
        seen[path] = true;
        out.push({ id: path, title: title });
      }
      anchorAt = area.indexOf('<a', tagEnd);
    }
    return out;
  },

  __sitePath(href) {
    var value = String(href || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      if (value.indexOf('3hentai.club') < 0) return '';
      value = value.replace(/^https?:\/\/3hentai\.club/, '');
    }
    if (value.charAt(0) !== '/') value = '/' + value;
    if (value === '/') return '/';
    if (!/\/(tag|category|parody|artist|group|language)\//.test(value)) return '';
    return value;
  },

  /// 列表条目：`div.lista > ul > li > div.thumb-conteudo`
  ///   <a class="thumbParodiaNome" href="/parody/x/">系列名</a>
  ///   <a href="/{slug}/" title="{标题}">
  ///     <span class="thumb-imagem"><img src="{封面}…"></span>
  ///     <span class="thumb-titulo"><span class="tituloConteudo"><img flag>标题</span></span>
  ///   </a>
  /// 所以条目锚 = `thumb-titulo` 之前最近的那个 <a>（href + title 都在它身上）。
  __items(html) {
    var items = [];
    var seen = {};
    var at = html.indexOf('class="thumb-titulo"');
    var scanned = 0;
    while (at >= 0 && scanned < 600 && items.length < MAX_ITEMS) {
      scanned++;
      var anchorAt = html.lastIndexOf('<a ', at);
      var blockStart = html.lastIndexOf('<li', at);
      if (anchorAt < 0 || blockStart < 0) break;
      var anchorEnd = html.indexOf('>', anchorAt);
      if (anchorEnd < 0) break;
      var blockEnd = html.indexOf('</li>', at);
      var block = html.slice(blockStart, blockEnd > 0 ? blockEnd : Math.min(html.length, at + ITEM_WINDOW));
      var tag = html.slice(anchorAt, anchorEnd + 1);
      var url = this.__postUrlSafe(this.__attr(tag, 'href'));
      var title = this.__plain(this.__attr(tag, 'title'));
      if (!title) {
        var tituloAt = block.indexOf('tituloConteudo');
        if (tituloAt >= 0) {
          var open = block.indexOf('>', tituloAt);
          if (open >= 0) {
            var close = block.indexOf('</span>', open);
            title = this.__cut(this.__plain(block.slice(open + 1, close > 0 ? close : open + 300)), 100);
          }
        }
      }
      if (url && title && !seen[url]) {
        seen[url] = true;
        items.push({
          id: url,
          title: this.__cut(title, 100),
          cover: this.__firstImage(block),
          coverHeaders: { 'Referer': BASE_URL + '/' },
          subtitle: this.__cut(this.__parodyName(block), 40)
        });
      }
      at = html.indexOf('class="thumb-titulo"', at + 20);
    }
    return items;
  },

  __postUrlSafe(href) {
    var value = String(href || '').trim();
    if (!value || value.indexOf('3hentai.club') < 0) return '';
    var path = value.replace(/^https?:\/\/3hentai\.club/, '');
    if (path === '/' || path.indexOf('/tag/') === 0 || path.indexOf('/category/') === 0 ||
        path.indexOf('/parody/') === 0 || path.indexOf('/artist/') === 0 ||
        path.indexOf('/group/') === 0 || path.indexOf('/language/') === 0 ||
        path.indexOf('/page/') === 0) return '';
    if (path.indexOf('/wp-') === 0 || path.indexOf('/custom-search') === 0) return '';
    if (path.slice(-1) !== '/') path += '/';
    var segments = path.split('/').length;
    if (segments !== 3) return '';
    return BASE_URL + path;
  },

  __parodyName(block) {
    var at = block.indexOf('thumbParodiaNome');
    if (at < 0) return '';
    var open = block.indexOf('>', at);
    if (open < 0) return '';
    return this.__plain(this.__readText(block, open + 1, 60));
  },

  __firstImage(block) {
    var at = block.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 6) {
      scanned++;
      var end = block.indexOf('>', at);
      if (end < 0) break;
      var url = this.__img(this.__attr(block.slice(at, end + 1), 'src'));
      if (url) return url;
      at = block.indexOf('<img', end);
    }
    return '';
  },

  __hasNext(html, page, count) {
    var current = page > 0 ? page : 1;
    var best = this.__maxPage(html);
    if (best > current) return true;
    if (best > 0) return false;
    return count >= LIST_PER_PAGE;
  },

  /// 分页器里的最大页码。站内只有 `/page/N/` 这一种形态（搜索页也一样）。
  __maxPage(text) {
    var best = 0;
    var needle = '/page/';
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

  __postTitle(html) {
    var at = html.indexOf('class="post-titulo"');
    if (at >= 0) {
      var open = html.indexOf('>', at);
      var close = html.indexOf('</h1>', at);
      if (open >= 0 && close > open) {
        var text = this.__plain(html.slice(open + 1, close));
        if (text) return this.__cut(text, 140);
      }
    }
    var raw = this.__titleTag(html);
    var cut = raw.lastIndexOf(' - ');
    if (cut > 0) raw = raw.slice(0, cut);
    return this.__cut(this.__plain(raw), 140);
  },

  __postCover(html) {
    var at = html.indexOf('class="post-capa"');
    if (at >= 0) {
      var img = html.indexOf('<img', at);
      if (img >= 0) {
        var end = html.indexOf('>', img);
        if (end > 0) {
          var url = this.__img(this.__attr(html.slice(img, end + 1), 'src'));
          if (url) return url;
        }
      }
    }
    return this.__firstImage(html);
  },

  __postInfo(html) {
    var result = { subtitle: '', description: '', tags: [], pages: '', artist: '' };
    var at = html.indexOf('class="post-itens"');
    var text = '';
    if (at >= 0) {
      var open = html.indexOf('>', at);
      var end = html.indexOf('</ul>', at);
      if (open >= 0) {
        text = this.__plain(html.slice(open + 1, end > 0 ? end : Math.min(html.length, open + 6000)));
      }
    }
    result.pages = this.__pages(html);
    result.artist = this.__labelled(html, 'Artist');
    var language = this.__labelled(html, 'Language');
    var group = this.__labelled(html, 'Group');
    var bits = [];
    if (result.pages) bits.push(result.pages + ' pages');
    if (result.artist) bits.push(result.artist);
    if (language) bits.push(language);
    result.subtitle = bits.join(' · ');
    result.description = text || result.subtitle;
    result.tags = this.__postTags(html);
    if (group && result.subtitle.length < 60) result.subtitle += ' · ' + group;
    return result;
  },

  /// `ul.post-itens` 里 `<li><strong>Pages</strong> 50</li>`。
  __pages(html) {
    var at = html.indexOf('<strong>Pages</strong>');
    if (at < 0) return '';
    var i = at + '<strong>Pages</strong>'.length;
    var start = -1;
    while (i < html.length && i - at < 200) {
      var code = html.charCodeAt(i);
      if (code >= 48 && code <= 57) {
        if (start < 0) start = i;
      } else if (start >= 0) {
        break;
      }
      i++;
    }
    return start >= 0 ? html.slice(start, i) : '';
  },

  /// `<strong>Artist</strong> <a …>名字</a>` → 名字。
  __labelled(html, label) {
    var at = html.indexOf('<strong>' + label + '</strong>');
    if (at < 0) return '';
    var open = html.indexOf('<a', at);
    if (open < 0 || open - at > 300) return '';
    var tagEnd = html.indexOf('>', open);
    if (tagEnd < 0) return '';
    return this.__cut(this.__plain(this.__readText(html, tagEnd + 1, 60)), 40);
  },

  /// 这篇自己的标签。**必须只扫 `Tags:` 那一行**：页面顶部的 `ul#menu-id` 挂了一大堆
  /// 全站标签链接（Ahegao / Yuri / …），整页扫 /tag/ 会把菜单当成这篇的标签（实测过）。
  __postTags(html) {
    var tags = [];
    var seen = {};
    var marker = html.indexOf('Tags:');
    if (marker < 0) return tags;
    var end = html.indexOf('</li>', marker);
    var area = html.slice(marker, end > marker ? end : Math.min(html.length, marker + 4000));
    var at = area.indexOf('/tag/');
    var scanned = 0;
    while (at >= 0 && scanned < 80 && tags.length < MAX_TAGS) {
      scanned++;
      var tagEnd = area.indexOf('>', at);
      if (tagEnd < 0) break;
      var text = this.__cut(this.__plain(this.__readText(area, tagEnd + 1, 40)), 20);
      if (text && !seen[text]) {
        seen[text] = true;
        tags.push(text);
      }
      at = area.indexOf('/tag/', tagEnd);
    }
    return tags;
  },

  __contentImages(html) {
    var start = html.indexOf('class="post-fotos"');
    if (start < 0) return [];
    var end = html.indexOf('</ul>', start);
    var area = html.slice(start, end > 0 ? end : Math.min(html.length, start + 400000));
    var images = [];
    var seen = {};
    var at = area.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 800 && images.length < MAX_IMAGES) {
      scanned++;
      var tagEnd = area.indexOf('>', at);
      if (tagEnd < 0) break;
      var url = this.__img(this.__attr(area.slice(at, tagEnd + 1), 'src'));
      if (url && !seen[url]) {
        seen[url] = true;
        images.push(url);
      }
      at = area.indexOf('<img', tagEnd);
    }
    return images;
  },

  __fallbackImages(html) {
    var images = [];
    var seen = {};
    var at = html.indexOf('/wp-content/uploads/');
    var scanned = 0;
    while (at >= 0 && scanned < 800 && images.length < MAX_IMAGES) {
      scanned++;
      var tagStart = html.lastIndexOf('<img', at);
      var end = html.indexOf('"', at);
      if (tagStart >= 0 && end > at) {
        var url = this.__img(html.slice(at, end));
        if (url && !seen[url]) {
          seen[url] = true;
          images.push(url);
        }
      }
      at = html.indexOf('/wp-content/uploads/', at + 20);
    }
    return images;
  },

  // ------------------------------------------------------------- 基础工具

  async __get(url) {
    if (!url) throw new Error('3Hentai：空地址');
    var response = await LumeSource.http.get(url, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'text/html,application/xhtml+xml,*/*',
        'Accept-Language': 'en-US,en;q=0.9,pt;q=0.8'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 || status === 503 || status === 429 ||
          /just a moment|__cf_chl|challenge-platform|cf-mitigated|checking your browser/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：3Hentai 需要网页视图过一次校验（HTTP ' + status + ' ' + url + '）');
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
    var path = full.split('?')[0].toLowerCase();
    if (!/\.(jpg|jpeg|png|webp|gif|avif)$/.test(path)) return '';
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

  __titleTag(html) {
    var at = html.indexOf('<title>');
    if (at < 0) return '';
    var end = html.indexOf('</title>', at);
    if (end < 0) return '';
    return this.__plain(html.slice(at + 7, end));
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
