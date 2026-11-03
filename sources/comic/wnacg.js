// LumeSource: {"id":"wnacg_comic","name":"紳士漫畫","version":"1.0.0","category":"comic","mirrors":["https://wnacg.com","https://www.wnacg.com","https://m.wnacg.com"]}
// 镜像：www 与 m 子域同站（m 会 302 到 www）

// 站点：https://wnacg.com（移动版主题 themes/mo；UTF-8）
//
// ## 入口（全部对着实时页面核过）
//
//   列表  GET /albums.html                                    → 第 1 页
//         GET /albums-index-page-{n}.html                     → 第 n 页
//         GET /albums-index-cate-{cid}.html                   → 分类第 1 页
//         GET /albums-index-page-{n}-cate-{cid}.html          → 分类第 n 页
//         GET /albums-favorite_ranking.html                   → 收藏排行第 1 页
//         GET /albums-favorite_ranking-page-{n}-type-week.html → 排行第 n 页
//         GET /search/index.php?q={kw}&m=&syn=yes&f=_all&s=create_time_DESC[&p={n}]
//         （站内搜索表单 action="/search/" 会 302 到 /search/index.php；直接走后者，
//           p 就是页码。q 是 UTF-8 百分号编码。搜索页每页 24 条。）
//   详情  GET /photos-index-aid-{aid}.html
//         标题与封面都在 `#Cover` 那张 img 上：`<img src="////t4.qy0.ru/…" title="标题">`
//         （src 是**四个斜杠**，浏览器把它当协议相对处理，这里按「去掉前导 / 后接域名」归一）
//         简介在 `div.dv-desc-text`，作者 `a.introName`，页数 `span.date`，题材 `a.dv-tag`
//   目录  同一张详情页的 `ul#dv-ch-list`（第 1 页 12 话），其余分页走 JSON 接口：
//         GET /?ctl=photos&act=chapters&sid={aid}&page={n}&order=asc
//         → {"code":0,"list":[{"id":235275,"idx":1,"name":"慾海交鋒 1-7話"}],"total":49,"page":1,"ended":0}
//         没有 `#dv-ch-list` 的作品（单册 55P 那类）→ 一集「全一話」。
//   正文  GET /photos-slide-aid-{chid}.html 是滑动阅读器，图**不在** HTML 里，
//         而是它引的外链脚本 /photos-item-aid-{chid}.html：
//             mReader.initData({"page_url":["http://img5.qy0.ru/…?verify=…", …], …});
//         所以 content() 直接取 /photos-item-aid-{chid}.html 解析 page_url 数组即可，
//         **不用**拼 /photos-index-aid-{aid}-page-{n}.html（那是详情页，没有图片列表）。
//
// ## 图片
//   图床是 img5.qy0.ru / t4.qy0.ru 这类 qy0.ru 域，URL 自带 verify 签名，几小时后过期，
//   所以必须每次实时取（不能缓存）。实测：
//     · **按 UA 拦**：curl 默认 UA 会 403，iPhone UA / 桌面 UA 都 200；
//     · 不校验 Referer（带不带都 200/206）；
//     · 同一 URL 把 http:// 换成 https:// 也能取（206 分片正常），这里统一升到 https，
//       避免 iOS ATS 拦明文。
//   即便如此仍按站点口径在 content() 里带 Referer: https://wnacg.com/（无害且和站点一致）。

var BASE_URL = 'https://wnacg.com';

var MAX_ITEMS = 120;          // 单次列表最多产出
var ITEM_WINDOW = 2600;       // 单条往后看的窗口
var PAGER_WINDOW = 2500;      // 分页器窗口
var MAX_CHAPTER_PAGES = 80;   // 章节 JSON 最多翻多少页（12 话/页）
var MAX_CHAPTERS = 1200;
var MAX_IMAGES = 600;
var MAX_TAGS = 10;

var SKIP_IMAGE = /logo|avatar|banner|advert|placeholder|blank|loading|icon|sprite|qrcode|share|yandex|spacer|stat/i;

var LumeSource = {
  id: 'wnacg_comic',
  name: '紳士漫畫',
  version: '1.0.0',
  category: 'comic',

  // ------------------------------------------------------------- 契约方法

  /// 分类：站点自己的列表地址。先把「更新 / 排行」两根入口放前面（这两页一定有内容），
  /// 再按 /albums.html 的分类面板（4 组：同人志 / 单行本 / 杂志短篇 / 韩漫）逐条列出。
  /// 面板读不到就只给两个入口——不编不存在的分类地址。
  async categories() {
    var found = [
      { id: '/albums.html', title: '最新更新' },
      { id: '/albums-favorite_ranking.html', title: '收藏排行' }
    ];
    try {
      var html = await this.__get(BASE_URL + '/albums.html');
      var panels = this.__categories(html);
      for (var i = 0; i < panels.length; i++) found.push(panels[i]);
      console.warn('[wnacg] 分类面板读到 ' + panels.length + ' 项');
    } catch (error) {
      console.warn('[wnacg] 分类面板拉取失败（' + (error && error.message) + '），只给两个入口');
    }
    return found;
  },

  /// 首页：站点首页（推荐）按 `div.imgBox` 分块，每块 `Sub_H2 > span.Title` 是块名，
  /// 块内 `ul.col_3_2 > li` 是条目（6 条/块）。
  async home() {
    var html = await this.__get(BASE_URL + '/');
    var boards = this.__boards(html);
    if (boards.length) {
      console.warn('[wnacg] 首页板块 ' + boards.length + ' 块');
      return boards;
    }
    var latest = await this.list({ page: 1 });
    if (latest && latest.items && latest.items.length) {
      console.warn('[wnacg] 首页没认出板块，退回列表一块');
      return [{ title: '最新更新', moreUrl: '/albums.html', items: latest.items.slice(0, 12) }];
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
    var items = this.__items(html);
    if (!items.length) {
      console.warn('[wnacg] 列表没解析出条目：' + url + '（' + html.length + ' 字符）');
      return { items: [], hasMore: false };
    }
    console.warn('[wnacg] 列表命中 ' + items.length + ' 条：' + url);
    return { items: items, hasMore: this.__hasNext(html, page, items.length) };
  },

  async detail(argument) {
    var url = this.__detailUrl(this.__id(argument));
    var html = await this.__get(url);
    var cover = this.__cover(html);
    var title = this.__coverTitle(html) || this.__plain(this.__titleTag(html)).split(' - ')[0];
    if (!title) {
      console.warn('[wnacg] 详情页没认出标题：' + url);
      return null;
    }
    var author = this.__classText(html, 'introName');
    var pages = this.__classText(html, 'date');
    var parts = [];
    if (author) parts.push('作者 ' + author);
    if (pages) parts.push(pages);
    return {
      id: url,
      title: title,
      cover: cover,
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: this.__cut(parts.join(' · '), 80),
      description: this.__descText(html),
      tags: this.__tags(html),
      extra: { author: author, pages: pages }
    };
  },

  /// 目录：详情页 `ul#dv-ch-list` 给第 1 页 12 话，其余走 ctl=photos&act=chapters 的 JSON。
  /// 每话的 id 都是**完整阅读页地址**（/photos-slide-aid-{chid}-sid-{aid}.html），
  /// content() 拿它就能直接取到 /photos-item-aid-{chid}.html。
  async chapters(argument) {
    var aid = this.__albumId(this.__id(argument));
    var url = BASE_URL + '/photos-index-aid-' + aid + '.html';
    var html = await this.__get(url);
    var chapters = this.__htmlChapters(html, aid);
    if (chapters.length) {
      var rest = await this.__apiChapters(aid, chapters.length, chapters);
      for (var i = 0; i < rest.length; i++) chapters.push(rest[i]);
      console.warn('[wnacg] 目录 ' + chapters.length + ' 话（含 JSON 分页）：' + url);
      return chapters;
    }
    // 单册作品：详情页没有章节块，阅读按钮直接指向阅读器。
    var reader = this.__readerHref(html) || (BASE_URL + '/photos-slide-aid-' + aid + '.html');
    console.warn('[wnacg] 单册作品，返回一集「全一話」：' + reader);
    return [{ id: reader, title: '全一話' }];
  },

  /// 正文：阅读器的图挂在 /photos-item-aid-{chid}.html 的 mReader.initData 里。
  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('紳士漫畫：缺少章节 ID（请先选择一话）');
    var chid = this.__slideId(chapterId);
    if (!chid) {
      var aid = this.__albumId(argument && argument.id);
      if (!aid) throw new Error('紳士漫畫：认不出章节地址（' + chapterId + '）');
      chid = aid;
    }
    var itemUrl = BASE_URL + '/photos-item-aid-' + chid + '.html';
    var js = await this.__get(itemUrl);
    var images = this.__pageUrls(js);
    if (!images.length) {
      // 兜底：从阅读器页面里找真正引用的脚本名（站点若改了 chid 的来源，这里还能救回来）。
      var reader = /^https?:/i.test(chapterId) ? chapterId : (BASE_URL + '/photos-slide-aid-' + chid + '.html');
      console.warn('[wnacg] ' + itemUrl + ' 里没有 page_url，回退解析阅读器页');
      var html = await this.__get(reader);
      var src = this.__itemScript(html);
      if (src && src !== itemUrl) {
        var js2 = await this.__get(src);
        images = this.__pageUrls(js2);
      }
    }
    if (!images.length) {
      throw new Error('紳士漫畫：这一话没解析出图片（' + itemUrl + '）——把运行日志发回来收敛解析规则');
    }
    console.warn('[wnacg] 正文 ' + images.length + ' 张图：' + itemUrl);
    return {
      kind: 'images',
      images: images,
      headers: { 'Referer': BASE_URL + '/' }
    };
  },

  // ------------------------------------------------------------- 地址策略

  __listUrl(category, keyword, page) {
    if (keyword) {
      var search = '/search/index.php?q=' + this.__enc(keyword) +
        '&m=&syn=yes&f=_all&s=create_time_DESC';
      if (page > 1) search += '&p=' + page;
      return BASE_URL + search;
    }
    var path = this.__categoryPath(category);
    var cate = this.__cateId(path);
    if (cate) {
      if (page <= 1) return BASE_URL + '/albums-index-cate-' + cate + '.html';
      return BASE_URL + '/albums-index-page-' + page + '-cate-' + cate + '.html';
    }
    if (path.indexOf('favorite_ranking') >= 0) {
      if (page <= 1) return BASE_URL + '/albums-favorite_ranking.html';
      return BASE_URL + '/albums-favorite_ranking-page-' + page + '-type-week.html';
    }
    if (path === '/' || path === '' || path.indexOf('albums.html') >= 0 || path === '/albums') {
      if (page <= 1) return BASE_URL + '/albums.html';
      return BASE_URL + '/albums-index-page-' + page + '.html';
    }
    // 认不出的地址：第 1 页原样请求，后续页不再瞎猜。
    if (page > 1) {
      console.warn('[wnacg] 认不出的列表地址，第 ' + page + ' 页不再请求：' + path);
      return '';
    }
    return BASE_URL + path;
  },

  __categoryPath(category) {
    var value = String(category == null ? '' : category).trim();
    if (!value) return '/albums.html';
    if (value.indexOf('http') === 0) {
      if (value.indexOf('wnacg.com') >= 0) {
        value = value.replace(/^https?:\/\/(www\.)?wnacg\.com/, '');
        if (!value) value = '/';
        if (value.charAt(0) !== '/') value = '/' + value;
        return value;
      }
      console.warn('[wnacg] 分类地址不是本站：' + category + '，退回更新列表');
      return '/albums.html';
    }
    if (value.charAt(0) !== '/') value = '/' + value;
    return value;
  },

  __cateId(path) {
    var at = String(path || '').indexOf('albums-index-cate-');
    if (at < 0) return '';
    var i = at + 'albums-index-cate-'.length;
    var start = i;
    while (i < path.length && i - start < 4) {
      var code = path.charCodeAt(i);
      if (code < 48 || code > 57) break;
      i++;
    }
    return i > start ? path.slice(start, i) : '';
  },

  /// id → 相册数字 ID。绝对地址 / 站内路径 / 纯数字三种都认。
  __albumId(id) {
    var value = String(id == null ? '' : id).trim();
    if (!value) throw new Error('紳士漫畫：缺少作品 ID');
    var at = value.indexOf('aid-');
    if (at >= 0) {
      var i = at + 4;
      var start = i;
      while (i < value.length) {
        var code = value.charCodeAt(i);
        if (code < 48 || code > 57) break;
        i++;
      }
      if (i > start) return value.slice(start, i);
    }
    var digits = this.__digits(value);
    if (digits) return digits;
    throw new Error('紳士漫畫：认不出的作品地址（' + id + '）——id 应当来自 list()/detail()');
  },

  __id(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    if (!id) throw new Error('紳士漫畫：缺少作品 ID');
    return id;
  },

  __detailUrl(id) {
    return BASE_URL + '/photos-index-aid-' + this.__albumId(id) + '.html';
  },

  // ------------------------------------------------------------- 分类 / 首页

  /// 分类面板：#classTit 是 4 个组名（同人志/单行本/杂志短篇/韩漫），
  /// #classCon 里跟着 4 个 <ul>，第 i 个 ul 的条目属于第 i 个组名。
  __categories(html) {
    var out = [];
    var seen = {};
    var groups = [];
    var tit = html.indexOf('id="classTit"');
    if (tit >= 0) {
      var titEnd = html.indexOf('</ul>', tit);
      var area = html.slice(tit, titEnd > 0 ? titEnd : tit + 4000);
      var gat = area.indexOf('<a');
      while (gat >= 0 && groups.length < 8) {
        var gend = area.indexOf('>', gat);
        if (gend < 0) break;
        var text = this.__cut(this.__plain(this.__readText(area, gend + 1, 60)), 12);
        if (text) groups.push(text);
        gat = area.indexOf('<a', gend);
      }
    }
    var con = html.indexOf('id="classCon"');
    if (con < 0) return out;
    var conEnd = html.indexOf('</div>', con);
    var box = html.slice(con, conEnd > 0 ? conEnd : con + 20000);
    var ulAt = box.indexOf('<ul');
    var group = 0;
    while (ulAt >= 0 && group < 8) {
      var ulEnd = box.indexOf('</ul>', ulAt);
      var seg = box.slice(ulAt, ulEnd > 0 ? ulEnd : box.length);
      var groupName = groups[group] || '';
      var at = seg.indexOf('<a');
      while (at >= 0) {
        var tagEnd = seg.indexOf('>', at);
        if (tagEnd < 0) break;
        var tag = seg.slice(at, tagEnd + 1);
        var href = this.__attr(tag, 'href');
        var cid = this.__cateId(href);
        if (cid && !seen[cid]) {
          var name = this.__cut(this.__plain(this.__readText(seg, tagEnd + 1, 40)), 10);
          if (name) {
            seen[cid] = true;
            out.push({
              id: '/albums-index-cate-' + cid + '.html',
              title: groupName ? groupName + '·' + name : name
            });
          }
        }
        at = seg.indexOf('<a', tagEnd);
      }
      group++;
      ulAt = box.indexOf('<ul', ulEnd > 0 ? ulEnd : box.length);
    }
    return out;
  },

  /// 首页板块：`div.imgBox` → `span.Title` 当块名，块内 li 即条目。
  __boards(html) {
    var boards = [];
    var at = html.indexOf('class="imgBox"');
    var scanned = 0;
    while (at >= 0 && boards.length < 8 && scanned < 24) {
      scanned++;
      var next = html.indexOf('class="imgBox"', at + 12);
      var end = next > at ? next : Math.min(html.length, at + 40000);
      var block = html.slice(at, end);
      var title = this.__headingText(block, 'class="Title"');
      var moreId = this.__moreHref(block);
      var items = this.__items(block);
      if (title && items.length) {
        boards.push({ title: title, moreUrl: moreId, items: items.slice(0, 12) });
      }
      at = next;
    }
    return boards;
  },

  __moreHref(block) {
    var at = block.indexOf('icon_More');
    if (at < 0) return '';
    var open = block.lastIndexOf('<a', at);
    var close = block.indexOf('>', at);
    if (open < 0 || close < 0) return '';
    var href = this.__attr(block.slice(open, close + 1), 'href');
    return href ? this.__sitePath(href) : '';
  },

  __sitePath(href) {
    var value = String(href || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      value = value.replace(/^https?:\/\/(www\.)?wnacg\.com/, '');
    }
    if (value.charAt(0) !== '/') value = '/' + value;
    return value;
  },

  // ------------------------------------------------------------- 列表解析

  /// 列表条目。站内三种版式，统一按「photos-index-aid- 锚点 + 所在块」解析：
  ///   列表/首页  <li class="cate-N"><a class="ImgA" href=…><img src="//t4…"></a>
  ///                <a class="txtA">标题</a><span class="info">55張圖片，創建於…</span></li>
  ///   搜索页      <li class="cate-N"><a class="ImgA" href=…><img src=…>
  ///                <span …>标题</span></a><span class="info">44张图片，…</span></li>
  ///   排行榜      <div class="itemBox"><div class="itemImg"><a href=…><img src=…></a></div>
  ///                <div class="itemTxt"><a class="title" href=…>标题</a>…</div></div>
  __items(html) {
    var items = [];
    var seen = {};
    var needle = 'photos-index-aid-';
    var at = html.indexOf(needle);
    var scanned = 0;
    while (at >= 0 && scanned < 600 && items.length < MAX_ITEMS) {
      scanned++;
      var begin = at;
      var li = html.lastIndexOf('<li', at);
      var box = html.lastIndexOf('class="itemBox"', at);
      var pick = li > box ? li : box;
      if (pick >= 0 && at - pick <= 3000) begin = pick;
      var block = html.slice(begin, Math.min(html.length, begin + ITEM_WINDOW));

      var id = '';
      var hit = block.indexOf(needle);
      if (hit >= 0) {
        var i = hit + needle.length;
        var start = i;
        while (i < block.length) {
          var code = block.charCodeAt(i);
          if (code < 48 || code > 57) break;
          i++;
        }
        id = block.slice(start, i);
      }
      if (id && !seen[id]) {
        var title = this.__itemTitle(block);
        if (title) {
          seen[id] = true;
          items.push({
            id: BASE_URL + '/photos-index-aid-' + id + '.html',
            title: this.__cut(title, 100),
            cover: this.__firstImage(block),
            coverHeaders: { 'Referer': BASE_URL + '/' },
            subtitle: this.__cut(this.__classText(block, 'info'), 40)
          });
        }
      }
      at = html.indexOf(needle, at + needle.length);
    }
    return items;
  },

  __itemTitle(block) {
    var title = this.__classText(block, 'txtA');
    if (title) return title;
    title = this.__classText(block, 'title');
    if (title) return title;
    // 搜索页：标题是 ImgA 锚里那个内联 span。
    var anchor = block.indexOf('class="ImgA');
    if (anchor >= 0) {
      var open = block.indexOf('>', anchor);
      var span = open >= 0 ? block.indexOf('<span', open) : -1;
      if (span >= 0) {
        var spanEnd = block.indexOf('>', span);
        if (spanEnd >= 0) {
          var text = this.__cut(this.__plain(this.__readText(block, spanEnd + 1, 200)), 100);
          if (text) return text;
        }
      }
    }
    var img = block.indexOf('<img');
    if (img >= 0) {
      var imgEnd = block.indexOf('>', img);
      if (imgEnd > 0) {
        var tag = block.slice(img, imgEnd + 1);
        var alt = this.__attr(tag, 'alt') || this.__attr(tag, 'title');
        if (alt) return this.__plain(alt);
      }
    }
    return '';
  },

  __firstImage(block) {
    var at = block.indexOf('<img');
    var scanned = 0;
    while (at >= 0 && scanned < 4) {
      scanned++;
      var end = block.indexOf('>', at);
      if (end < 0) break;
      var tag = block.slice(at, end + 1);
      var url = this.__attr(tag, 'data-original') || this.__attr(tag, 'src');
      var abs = this.__img(url);
      if (abs) return abs;
      at = block.indexOf('<img', end);
    }
    return '';
  },

  /// 还有下一页：分页器 `div.block-pagination`（搜索页是 `div.paginator`）里的最大页码。
  __hasNext(html, page, count) {
    var current = page > 0 ? page : 1;
    var at = html.indexOf('block-pagination');
    if (at < 0) at = html.indexOf('class="paginator"');
    if (at < 0) return count >= 20;
    var window = html.substr(at, PAGER_WINDOW);
    var best = this.__maxPage(window);
    if (best > current) return true;
    if (best > 0) return false;
    return count >= 20;
  },

  __maxPage(text) {
    var best = 0;
    var i = 0;
    var patterns = ['-page-', '/page/', '&p=', '?p='];
    while (i < text.length) {
      var hit = -1;
      var hitLen = 0;
      for (var k = 0; k < patterns.length; k++) {
        var at = text.indexOf(patterns[k], i);
        if (at >= 0 && (hit < 0 || at < hit)) {
          hit = at;
          hitLen = patterns[k].length;
        }
      }
      if (hit < 0) break;
      var j = hit + hitLen;
      var value = 0;
      var digits = 0;
      while (j < text.length && digits < 5) {
        var code = text.charCodeAt(j);
        if (code < 48 || code > 57) break;
        value = value * 10 + (code - 48);
        j++;
        digits++;
      }
      if (digits && value > best) best = value;
      i = j > hit ? j : hit + hitLen;
    }
    return best;
  },

  // ------------------------------------------------------------- 详情解析

  __cover(html) {
    var at = html.indexOf('id="Cover"');
    if (at >= 0) {
      var img = html.indexOf('<img', at);
      if (img >= 0) {
        var end = html.indexOf('>', img);
        if (end > 0) {
          var abs = this.__img(this.__attr(html.slice(img, end + 1), 'src'));
          if (abs) return abs;
        }
      }
    }
    return this.__firstImage(html);
  },

  __coverTitle(html) {
    var at = html.indexOf('id="Cover"');
    if (at < 0) return '';
    var img = html.indexOf('<img', at);
    if (img < 0) return '';
    var end = html.indexOf('>', img);
    if (end < 0) return '';
    return this.__cut(this.__plain(this.__attr(html.slice(img, end + 1), 'title')), 120);
  },

  __descText(html) {
    var at = html.indexOf('class="dv-desc-text"');
    if (at < 0) return '';
    var open = html.indexOf('>', at);
    if (open < 0) return '';
    var end = html.indexOf('</div>', open);
    var text = html.slice(open + 1, end > 0 ? end : Math.min(html.length, open + 3000));
    return this.__cut(this.__plain(text), 800);
  },

  __tags(html) {
    var tags = [];
    var seen = {};
    var at = html.indexOf('class="dv-tag"');
    var scanned = 0;
    while (at >= 0 && scanned < 60 && tags.length < MAX_TAGS) {
      scanned++;
      var open = html.indexOf('>', at);
      if (open < 0) break;
      var text = this.__cut(this.__plain(this.__readText(html, open + 1, 40)), 12);
      if (text && !seen[text]) {
        seen[text] = true;
        tags.push(text);
      }
      at = html.indexOf('class="dv-tag"', open);
    }
    return tags;
  },

  __readerHref(html) {
    var at = html.indexOf('id="reader-btn"');
    if (at < 0) return '';
    var open = html.lastIndexOf('<a', at);
    var end = html.indexOf('>', at);
    if (open < 0 || end < 0) return '';
    var href = this.__attr(html.slice(open, end + 1), 'href');
    if (!href) return '';
    if (/^https?:/i.test(href)) return href;
    return BASE_URL + (href.charAt(0) === '/' ? href : '/' + href);
  },

  __htmlChapters(html, aid) {
    var start = html.indexOf('id="dv-ch-list"');
    if (start < 0) return [];
    var end = html.indexOf('</ul>', start);
    var area = html.slice(start, end > 0 ? end : Math.min(html.length, start + 60000));
    var out = [];
    var seen = {};
    var at = area.indexOf('<a');
    while (at >= 0 && out.length < MAX_CHAPTERS) {
      var tagEnd = area.indexOf('>', at);
      if (tagEnd < 0) break;
      var tag = area.slice(at, tagEnd + 1);
      var href = this.__attr(tag, 'href');
      var url = this.__readerUrl(href);
      if (url && !seen[url]) {
        seen[url] = true;
        var label = this.__chapterLabel(this.__attr(tag, 'title')) || this.__plain(this.__readText(area, tagEnd + 1, 60));
        out.push({ id: url, title: this.__cut(label || '第' + (out.length + 1) + '話', 60) });
      }
      at = area.indexOf('<a', tagEnd);
    }
    return out;
  },

  __chapterLabel(text) {
    var value = this.__plain(text);
    value = value.replace(/《/g, ' ').replace(/》/g, ' ');
    value = value.replace(/\s+/g, ' ').trim();
    return value;
  },

  /// 章节 JSON 分页：HTML 里已经有第 1 页那 12 话，所以从「已有条数 ÷ 每页 12 + 1」页起补。
  /// 同时按阅读页地址去重——万一每页条数和 12 不一致，也不会把已收的话再收一遍。
  async __apiChapters(aid, have, existing) {
    var out = [];
    var total = 0;
    var seen = {};
    var i;
    for (i = 0; i < existing.length; i++) seen[existing[i].id] = true;
    var page = Math.floor(have / 12) + 1;
    while (page <= MAX_CHAPTER_PAGES && (total === 0 || have + out.length < total)) {
      var url = BASE_URL + '/?ctl=photos&act=chapters&sid=' + aid + '&page=' + page + '&order=asc';
      var body = '';
      try {
        body = await this.__get(url);
      } catch (error) {
        console.warn('[wnacg] 章节 JSON 第 ' + page + ' 页失败：' + (error && error.message));
        break;
      }
      var data = null;
      try { data = JSON.parse(body); } catch (error) { data = null; }
      if (!data || Number(data.code) !== 0 || !data.list || !data.list.length) break;
      total = Number(data.total) || 0;
      for (i = 0; i < data.list.length; i++) {
        var row = data.list[i];
        if (!row || row.id == null) continue;
        var chapterUrl = BASE_URL + '/photos-slide-aid-' + row.id + '-sid-' + aid + '.html';
        if (seen[chapterUrl]) continue;
        if (have + out.length >= MAX_CHAPTERS) break;
        seen[chapterUrl] = true;
        var label = '第' + (row.idx != null ? row.idx : (have + out.length + 1)) + '話' + (row.name ? ' ' + row.name : '');
        out.push({ id: chapterUrl, title: this.__cut(label, 60) });
      }
      if (data.ended === 1 || data.ended === '1') break;
      page++;
    }
    if (out.length) console.warn('[wnacg] 章节 JSON 补到 ' + out.length + ' 话（total ' + total + '）');
    return out;
  },

  __readerUrl(href) {
    var value = String(href || '').trim();
    if (!value) return '';
    if (value.indexOf('photos-slide-aid-') < 0) return '';
    if (/^https?:/i.test(value)) return value.replace(/^http:/i, 'https:');
    return BASE_URL + (value.charAt(0) === '/' ? value : '/' + value);
  },

  // ------------------------------------------------------------- 正文解析

  __slideId(value) {
    var text = String(value || '');
    var at = text.indexOf('photos-slide-aid-');
    if (at < 0) return this.__digits(text);
    var i = at + 'photos-slide-aid-'.length;
    var start = i;
    while (i < text.length) {
      var code = text.charCodeAt(i);
      if (code < 48 || code > 57) break;
      i++;
    }
    return i > start ? text.slice(start, i) : '';
  },

  __itemScript(html) {
    var at = html.indexOf('/photos-item-aid-');
    if (at < 0) return '';
    var end = html.indexOf('"', at);
    if (end < 0) return '';
    var path = html.slice(at, end);
    return BASE_URL + (path.charAt(0) === '/' ? path : '/' + path);
  },

  /// 解析 `"page_url":["http://img5.qy0.ru/…","…",]`（站点在 ] 前留了个多余逗号）。
  __pageUrls(js) {
    var at = js.indexOf('"page_url"');
    if (at < 0) return [];
    var open = js.indexOf('[', at);
    if (open < 0) return [];
    var close = js.indexOf(']', open);
    var area = js.slice(open + 1, close > 0 ? close : Math.min(js.length, open + 300000));
    var images = [];
    var seen = {};
    var i = 0;
    while (i < area.length && images.length < MAX_IMAGES) {
      var q = area.indexOf('"', i);
      if (q < 0) break;
      var end = area.indexOf('"', q + 1);
      if (end < 0) break;
      var url = area.slice(q + 1, end);
      i = end + 1;
      var abs = this.__img(url);
      if (abs && !seen[abs]) {
        seen[abs] = true;
        images.push(abs);
      }
    }
    return images;
  },

  // ------------------------------------------------------------- 基础工具

  async __get(url) {
    if (!url) throw new Error('紳士漫畫：空地址');
    var response = await LumeSource.http.get(url, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'text/html,application/xhtml+xml,*/*',
        'Accept-Language': 'zh-TW,zh;q=0.9,ja;q=0.8'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) {
      if (status === 403 || status === 503 || status === 429 ||
          /just a moment|__cf_chl|challenge-platform|cf-mitigated|checking your browser/i.test(body)) {
        throw new Error('NEED_WEBVIEW_VERIFY：紳士漫畫 需要网页视图过一次 Cloudflare 校验（HTTP ' + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    }
    return body;
  },

  /// 图片地址归一：`////t4.qy0.ru/a.jpg` / `//t4.qy0.ru/a.jpg` / `/a.jpg` / 绝对地址 都认。
  /// 统一升到 https（同一 URL https 实测 206 正常，避开 iOS 明文限制）。
  __img(url) {
    var text = String(url == null ? '' : url).trim();
    if (!text || text.length > 500) return '';
    if (text.indexOf('data:') === 0) return '';
    if (/^https?:\/\//i.test(text)) {
      var abs = text.replace(/^http:\/\//i, 'https://');
      return SKIP_IMAGE.test(abs) ? '' : abs;
    }
    var rest = text;
    while (rest.charAt(0) === '/') rest = rest.slice(1);
    if (!rest || rest.indexOf('?') === 0) return '';
    var slash = rest.indexOf('/');
    var host = slash > 0 ? rest.slice(0, slash) : rest;
    if (host.indexOf('.') < 0) return '';
    var full = 'https://' + rest;
    return SKIP_IMAGE.test(full) ? '' : full;
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

  __headingText(block, marker) {
    var at = block.indexOf(marker);
    if (at < 0) return '';
    var open = block.indexOf('>', at);
    if (open < 0) return '';
    var close = block.indexOf('</span>', open);
    if (close < 0) close = Math.min(block.length, open + 120);
    return this.__cut(this.__plain(block.slice(open + 1, close)), 20);
  },

  __titleTag(html) {
    var at = html.indexOf('<title>');
    if (at < 0) return '';
    var end = html.indexOf('</title>', at);
    if (end < 0) return '';
    return html.slice(at + 7, end);
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
