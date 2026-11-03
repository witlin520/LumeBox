// LumeSource: {"id":"fuzhaiboylove_comic","name":"腐宅BoyLove","version":"1.0.0","category":"comic","mirrors":["https://fuzhaiboylove.work","https://fuzhaiboylove1.work","https://boylove.cc"]}

// 站点：香香腐宅 BoyLove。`fuzhaiboylove.work` 与 `fuzhaiboylove1.work` 实测都是
// **301 到 https://boylove.cc**（同一套站、同一份数据），所以一份脚本吃三个域名：
// mirrors 里三个都列出给 App 切换，脚本内部一律按 boylove.cc 取（跳转后 URL 也是它，
// 图片/接口又都是绝对地址，省得每次多一跳）。
// ⚠️ 同名的 `boysyo.cc`（啵乐）是**另一套代码**（Laravel + Vue，路由 /cat_intro/、
// /list_comic、/thread_comic），不在本源覆盖范围，另有 boysyo.js。
//
// ## 抓取口径（全部对着实时页面核过）
//
//   ⚠️ 分类页 /home/book/cate.html 与首页、搜索页的**书目都是 JS 渲染**的
//      （HTML 里只有 `#booklist` 这类 `<script type="text/html">` 模板，没有一条真实条目），
//      所以列表/搜索/目录三处都走站点自己的 JSON 接口（下面这些地址全部来自
//      /static/js/config.js 的 appCenter.* 实现，不是猜的）：
//
//   分类  GET /home/api/cate/tp/{cate}-{tag}-{done}-{order}-{page}-{is18}-1-{vip}?mt=0
//         cate=1；tag 是标签（中文，需百分号编码，0=全部）；
//         done：0 连载中 / 1 已完结 / 2 全部；order：1 默认（按更新时间）
//         is18：0 全部 / 1 清水 / 2 有肉；vip：0 一般 / 1 VIP / 2 全部
//         ⚠️ 分类页 URL 里的 `m_type`（韩漫/日漫/国漫/台漫）**不进接口**——站点自己的
//            initGetCateData() 只把 tag/done/order/page/is18/vip 拼进去，第 7 段是写死的
//            "1"，实测把第 7 段改成 0/1/2/3 有变化但语义对不上韩漫/日漫（改成 2 出来的是
//            短篇合集那批），所以本源**不把 m_type 当分类档位**，只暴露接口真正吃得下的维度。
//         返回 {code, result:{list:[…], lastPage}}, lastPage=false 就是「还有下一页」。
//   首页  用同一接口拼 4 块（最近更新 / 连载中 / 已完结 / VIP 专区），每块 12 条。
//   搜索  GET /home/api/searchk?keyword={UTF-8 编码}&type=&pageNo={N}
//         → result.list、result.lastPage（type 传空就是全站搜）。
//   详情  GET /home/book/index/id/{id}：标题 `p.book-title`、封面 `div.book div.cover img[src]`、
//         作者 `div.book-intro li.info`（`作者:` 那行）、状态紧随的 `<li>`（连载中/已完结）、
//         简介 `p.book-desc`。
//   目录  GET /home/api/chapter_list/tp/{作品id} → result.list[{id,title,isvip}]，**一次给全**
//         （实测 34 话一次全返，totalRow 与 list 长度一致；带 `-order-page-size` 的扩展形态
//         反而回错误），顺序是 预告→第01话→…（旧→新），原样用。
//         章节 id 用完整阅读地址 `/home/book/capter/id/{章节id}` 存给 content()。
//   正文  GET /home/book/capter/id/{章节id}：图片是懒加载
//         `<div class="reader-cartoon-image" data-page="N"><img data-original="…webp?w=2250_3200">`，
//         一章一页（实测 117 张，`data-page` 是图序号不是子页）。只收 `div.reader-cartoon-chapter`
//         这一段里的 `data-original`，页面别处的推荐位/广告不会混进来。
//
// 图片域名 img.boylove.cc 实测**带不带 Referer 都是 200/206**，headers 照契约给站点 Referer。

var BASE_URL = 'https://boylove.cc';
var IMG_BASE = 'https://img.boylove.cc';

var PAGE_SIZE = 24;       // 接口每页条数（实测 24）
var MAX_ITEMS = 96;       // 单次列表最多产出
var MAX_CHAPTERS = 3000;  // 目录最多解析多少话
var MAX_IMAGES = 500;     // 正文最多收多少张图

var LumeSource = {
  id: 'fuzhaiboylove_comic',
  name: '腐宅BoyLove',
  version: '1.0.0',
  category: 'comic',

  // ---------------------------------------------------------------- 分类

  /// 分类 = 分类页自己的筛选档位（全部/连载中/已完结/一般/VIP/清水/有肉）+ 站内热门标签。
  /// id 统一成站点自己的分类地址形状 `/home/book/cate/tag/…/progress/…/is18/…/isVip/…/m_type/0`，
  /// list() 再把这几段翻译成接口参数。
  async categories() {
    var html = await this.__get(BASE_URL + '/home/book/cate.html');
    var out = [];
    var seen = {};
    var at = html.indexOf('/home/book/cate/tag/');
    var guard = 0;
    while (at >= 0 && guard < 60) {
      guard++;
      var start = html.lastIndexOf('<a', at);
      var end = html.indexOf('</a>', at);
      if (start >= 0 && end > at) {
        var tagEnd = html.indexOf('>', at);
        var href = this.__attr(html.slice(start, tagEnd + 1), 'href');
        var text = this.__plain(html.slice(tagEnd + 1, end));
        var key = href.replace(/\/page\/\d+$/, '');
        var typeSeg = /\/m_type\/(\d+)/.exec(key);
        // m_type（韩漫/日漫/国漫/台漫）这一维接口不吃（见文件头），接口对它们返回的是同一批数据，
        // 摆出来只会骗人，所以只保留 m_type=0 的档位。
        var usable = !typeSeg || typeSeg[1] === '0';
        if (usable && href && text && text.length <= 10 && !/^\d+$/.test(text) && text !== '下一页' && !seen[key]) {
          seen[key] = true;
          out.push({ id: key, title: this.__cut(text, 10) });
        }
      }
      at = html.indexOf('/home/book/cate/tag/', end > at ? end : at + 10);
    }
    var tags = this.__hotTags(html, seen);
    var alL = [{ id: '/home/book/cate/tag/0/progress/2/is18/0/isVip/2/m_type/0', title: '全部' }];
    var merged = [];
    var i;
    for (i = 0; i < alL.length; i++) {
      if (!seen[alL[i].id]) merged.push(alL[i]);
    }
    for (i = 0; i < out.length; i++) merged.push(out[i]);
    for (i = 0; i < tags.length; i++) merged.push(tags[i]);
    if (merged.length < 3) {
      console.warn('[fuzhai] 分类页没读出筛选条（' + html.length + ' 字符），用内置兜底');
      return this.__fallbackCategories();
    }
    console.warn('[fuzhai] 分类 ' + merged.length + ' 项（筛选档位 + 热门标签）');
    return merged;
  },

  /// 标签档位：`<a class="tagBtnClass" data-value="甜宠">甜宠</a>`（没有 href，得自己拼地址）。
  __hotTags(html, seen) {
    var out = [];
    var at = html.indexOf('data-str="tag"');
    if (at < 0) return out;
    var area = html.slice(at, Math.min(html.length, at + 6000));
    var pos = area.indexOf('data-value="');
    var guard = 0;
    while (pos >= 0 && guard < 40 && out.length < 12) {
      guard++;
      var value = this.__attrValue(area, pos + 11);
      var tagEnd = area.indexOf('>', pos);
      var close = area.indexOf('</a>', tagEnd);
      var text = tagEnd > 0 && close > tagEnd ? this.__plain(area.slice(tagEnd + 1, close)) : '';
      if (value && value !== '0' && text) {
        var href = '/home/book/cate/tag/' + this.__encode(value) + '/progress/2/is18/0/isVip/2/m_type/0';
        if (!seen[href]) {
          seen[href] = true;
          out.push({ id: href, title: this.__cut(text, 10) });
        }
      }
      pos = area.indexOf('data-value="', tagEnd > 0 ? tagEnd : pos + 12);
    }
    return out;
  },

  __fallbackCategories() {
    return [
      { id: '/home/book/cate/tag/0/progress/2/is18/0/isVip/2/m_type/0', title: '全部' },
      { id: '/home/book/cate/tag/0/progress/0/is18/0/isVip/2/m_type/0', title: '连载中' },
      { id: '/home/book/cate/tag/0/progress/1/is18/0/isVip/2/m_type/0', title: '已完结' },
      { id: '/home/book/cate/tag/0/progress/2/is18/0/isVip/1/m_type/0', title: 'VIP' },
      { id: '/home/book/cate/tag/0/progress/2/is18/1/isVip/2/m_type/0', title: '清水' },
      { id: '/home/book/cate/tag/0/progress/2/is18/2/isVip/2/m_type/0', title: '有肉' }
    ];
  },

  // ---------------------------------------------------------------- 首页

  /// 首页书目在 HTML 里也是空的（只有 JS 模板），所以用接口拼 4 块。
  async home() {
    var specs = [
      { title: '最近更新', tp: '1-0-2-1-1-0-1-2' },
      { title: '连载中', tp: '1-0-0-1-1-0-1-2' },
      { title: '已完结', tp: '1-0-1-1-1-0-1-2' },
      { title: 'VIP 专区', tp: '1-0-2-1-1-0-1-1' }
    ];
    var boards = [];
    for (var i = 0; i < specs.length; i++) {
      try {
        var json = await this.__json('/home/api/cate/tp/' + specs[i].tp + '?mt=0');
        var items = this.__itemsFromList((json.result || {}).list || []);
        if (items.length) {
          boards.push({
            title: specs[i].title,
            moreUrl: '/home/book/cate/tag/0/progress/' + specs[i].tp.split('-')[2] +
              '/is18/0/isVip/' + specs[i].tp.split('-')[7] + '/m_type/0',
            items: items.slice(0, 12)
          });
        }
      } catch (error) {
        console.warn('[fuzhai] 首页板块「' + specs[i].title + '」失败：' + (error && error.message));
      }
    }
    if (boards.length) console.warn('[fuzhai] 首页板块 ' + boards.length + ' 块');
    return boards;
  },

  // ---------------------------------------------------------------- 列表

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    var url = keyword
      ? '/home/api/searchk?keyword=' + this.__encode(keyword) + '&type=&pageNo=' + page
      : this.__cateApi(category, page);
    var json = await this.__json(url);
    var result = json.result || {};
    var items = this.__itemsFromList(result.list || []);
    if (!items.length) {
      console.warn('[fuzhai] 列表为空：' + url);
      return { items: [], hasMore: false };
    }
    console.warn('[fuzhai] 列表命中：' + url + '（' + items.length + ' 条）');
    return { items: items, hasMore: result.lastPage === false };
  },

  __cateApi(category, page) {
    var path = String(category || '');
    if (path.indexOf('http') === 0) {
      var m = /^https?:\/\/[^\/]+(\/.*)$/.exec(path);
      path = m ? m[1] : '';
    }
    var tag = this.__segment(path, 'tag');
    var done = this.__segment(path, 'progress');
    var is18 = this.__segment(path, 'is18');
    var vip = this.__segment(path, 'isVip');
    if (!tag) tag = '0';
    if (!done) done = '2';
    if (!is18) is18 = '0';
    if (!vip) vip = '2';
    return '/home/api/cate/tp/1-' + tag + '-' + done + '-1-' + page + '-' + is18 + '-1-' + vip + '?mt=0';
  },

  /// 从分类地址里取一段（tag 可能是已编码的中文，也可能是裸中文）。
  __segment(path, name) {
    var text = String(path || '');
    var at = text.indexOf('/' + name + '/');
    if (at < 0) return '';
    var start = at + name.length + 2;
    var end = text.indexOf('/', start);
    if (end < 0) end = text.length;
    var value = text.slice(start, end);
    if (name === 'tag' && value && !/^\d+$/.test(value)) {
      try { value = encodeURIComponent(decodeURIComponent(value)); } catch (error) { value = this.__encode(value); }
    }
    return value;
  },

  __itemsFromList(list) {
    var items = [];
    for (var i = 0; i < list.length && items.length < MAX_ITEMS; i++) {
      var row = list[i] || {};
      if (row.id == null) continue;
      var title = this.__plain(row.title || '');
      if (!title) continue;
      var image = String(row.image || '');
      var cover = image.indexOf('http') === 0 ? image : (image ? IMG_BASE + image : '');
      items.push({
        id: BASE_URL + '/home/book/index/id/' + row.id,
        title: this.__cut(title, 80),
        cover: cover,
        coverHeaders: { 'Referer': BASE_URL + '/' },
        subtitle: this.__cut(this.__status(row.mhstatus) +
          (row.last_chapter_title ? ' · 更新至' + this.__plain(row.last_chapter_title) : ''), 40)
      });
    }
    return items;
  },

  __status(mhstatus) {
    if (String(mhstatus) === '1') return '已完结';
    if (String(mhstatus) === '0') return '连载中';
    return '';
  },

  // ---------------------------------------------------------------- 详情 / 目录

  async detail(argument) {
    var id = this.__bookId(argument);
    var url = BASE_URL + '/home/book/index/id/' + id;
    var html = await this.__get(url);
    var info = this.__detailFields(html);
    if (!info.title) {
      console.warn('[fuzhai] 详情页没认出标题：' + url + '（' + html.length + ' 字符）');
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
      extra: { author: info.author, status: info.status, updated: info.updated, latest: info.latest }
    };
  },

  async chapters(argument) {
    var id = this.__bookId(argument);
    var json = await this.__json('/home/api/chapter_list/tp/' + id);
    var list = (json.result || {}).list || [];
    var out = [];
    for (var i = 0; i < list.length && out.length < MAX_CHAPTERS; i++) {
      var row = list[i] || {};
      if (row.id == null) continue;
      var title = this.__plain(row.title || '') || ('第' + (i + 1) + '话');
      out.push({
        id: BASE_URL + '/home/book/capter/id/' + row.id,
        title: this.__cut(title, 60)
      });
    }
    if (!out.length) {
      console.warn('[fuzhai] 目录为空：作品 ' + id);
      return [];
    }
    console.warn('[fuzhai] 目录 ' + out.length + ' 话：作品 ' + id);
    return out;
  },

  // ---------------------------------------------------------------- 正文

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('腐宅BoyLove：缺少章节 ID（请先选择一话）');
    var url = this.__chapterUrl(chapterId);
    if (!url) throw new Error('腐宅BoyLove：认不出章节地址（' + chapterId + '）');
    var html = await this.__get(url);
    var images = this.__images(html);
    if (!images.length) {
      throw new Error('腐宅BoyLove：这一话没解析出图片（' + url + '）——可能需要登录/VIP');
    }
    console.warn('[fuzhai] 正文 ' + images.length + ' 张图：' + url);
    return { kind: 'images', images: images, headers: { 'Referer': BASE_URL + '/' } };
  },

  __chapterUrl(chapterId) {
    var value = String(chapterId || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) {
      if (value.indexOf(BASE_URL) === 0) return value;
      var m = /^https?:\/\/(?:fuzhaiboylove1?\.work|boylove\.cc)(\/.*)$/.exec(value);
      return m ? BASE_URL + m[1] : '';
    }
    if (value.charAt(0) === '/') return BASE_URL + value;
    if (/^\d+$/.test(value)) return BASE_URL + '/home/book/capter/id/' + value;
    return '';
  },

  __images(html) {
    var images = [];
    var seen = {};
    var at = html.indexOf('reader-cartoon-chapter');
    var area = at >= 0 ? html.slice(at, Math.min(html.length, at + 400000)) : html;
    var pos = area.indexOf('data-original="');
    var guard = 0;
    while (pos >= 0 && images.length < MAX_IMAGES) {
      if (++guard > 4000) break;
      var value = this.__attrValue(area, pos + 14);
      var url = this.__absolute(value);
      if (url && url.indexOf('/bookimages/') > 0 && !seen[url]) {
        seen[url] = true;
        images.push(url);
      }
      pos = area.indexOf('data-original="', pos + 12);
    }
    return images;
  },

  __bookId(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id);
    else if (argument && argument.comicId != null) id = String(argument.comicId);
    else if (typeof argument === 'string') id = argument;
    var value = String(id || '').trim();
    if (!value) throw new Error('腐宅BoyLove：缺少作品 ID');
    var m = /\/home\/book\/index\/id\/(\d+)/.exec(value);
    if (m) return m[1];
    if (/^\d+$/.test(value)) return value;
    throw new Error('腐宅BoyLove：认不出的作品 ID（' + id + '）');
  },

  __detailFields(html) {
    var info = { title: '', cover: '', description: '', author: '', status: '', updated: '', latest: '', tags: [] };
    var at = html.indexOf('book-title');
    if (at >= 0) {
      var open = html.indexOf('>', at);
      var close = html.indexOf('</p>', open);
      if (open >= 0 && close > open) info.title = this.__cut(this.__plain(html.slice(open + 1, close)), 120);
    }
    if (!info.title) {
      var raw = this.__titleTag(html);
      var cut = raw.indexOf(' - ');
      if (cut > 0) raw = raw.slice(0, cut);
      info.title = this.__plain(raw);
    }
    var book = html.indexOf('class="book"');
    var intro = html.indexOf('class="book-intro"');
    if (intro >= 0) {
      var block = html.slice(intro, Math.min(html.length, intro + 4000));
      var infoAt = block.indexOf('class="info"');
      if (infoAt >= 0) {
        var infoEnd = block.indexOf('</li>', infoAt);
        var author = this.__plain(block.slice(infoAt, infoEnd)).replace(/^作者[:：]\s*/, '');
        info.author = this.__cut(author, 40);
      }
      var statusAt = block.indexOf('</li>', infoAt > 0 ? infoAt : 0);
      if (statusAt >= 0) {
        var nextLi = block.indexOf('<li', statusAt);
        var nextEnd = block.indexOf('</li>', nextLi);
        if (nextLi > 0 && nextEnd > nextLi) {
          var text = this.__plain(block.slice(nextLi, nextEnd));
          if (text.indexOf('连载') >= 0 || text.indexOf('完结') >= 0) info.status = this.__cut(text, 12);
        }
      }
      var up = block.indexOf('最后更新');
      if (up >= 0) info.updated = this.__cut(this.__plain(block.slice(up, up + 120)).replace(/^最后更新[:：]?\s*/, ''), 20);
      var latest = block.indexOf('最新话数');
      if (latest >= 0) info.latest = this.__cut(this.__plain(block.slice(latest, latest + 120)).replace(/^最新话数[:：]?\s*/, ''), 30);
    }
    if (book >= 0) {
      var cwin = html.slice(book, Math.min(html.length, book + 1200));
      var img = /<img[^>]*src="([^"]+)"/.exec(cwin);
      if (img) info.cover = this.__absolute(img[1]);
    }
    var desc = html.indexOf('class="book-desc"');
    if (desc >= 0) {
      var dEnd = html.indexOf('</p>', desc);
      var dText = dEnd > desc ? html.slice(desc + 18, dEnd) : '';
      info.description = this.__cut(this.__plain(dText.replace(/<br\s*\/?>/gi, '\n')), 800);
    }
    info.tags = this.__detailTags(html);
    return info;
  },

  __detailTags(html) {
    var tags = [];
    var seen = {};
    var at = html.indexOf('/home/index/searchkw/?keywords=');
    var guard = 0;
    while (at >= 0 && guard < 40 && tags.length < 10) {
      guard++;
      var start = html.lastIndexOf('<a', at);
      var tagEnd = html.indexOf('>', at);
      if (start >= 0 && tagEnd > at) {
        var text = this.__plain(html.slice(tagEnd + 1, html.indexOf('</a>', tagEnd)));
        if (text && text.length <= 12 && !seen[text]) {
          seen[text] = true;
          tags.push(text);
        }
      }
      at = html.indexOf('/home/index/searchkw/?keywords=', tagEnd > 0 ? tagEnd : at + 30);
    }
    return tags;
  },

  // ---------------------------------------------------------------- 基础工具

  async __json(path) {
    var url = path.indexOf('http') === 0 ? path : BASE_URL + path;
    var response = await LumeSource.http.get(url, {
      headers: {
        'Referer': BASE_URL + '/',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest'
      }
    });
    var status = response ? response.status : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) throw new Error('接口失败：HTTP ' + status + ' ' + url);
    var json;
    try {
      json = JSON.parse(body);
    } catch (error) {
      throw new Error('接口不是 JSON（' + url + '）：' + body.slice(0, 120));
    }
    // ⚠️ 站点两套约定：分类/目录接口成功是 code=1，搜索接口成功是 code=0（实测），
    // 所以 0 和 1 都算成功，其它值（例如 code=500 Server Error）才抛。
    var code = json && json.code != null ? String(json.code) : '';
    if (code && code !== '0' && code !== '1') {
      throw new Error('接口返回 code=' + json.code + ' ' + (json.errorMsg || '') + '（' + url + '）');
    }
    return json;
  },

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
        throw new Error('NEED_WEBVIEW_VERIFY：腐宅BoyLove 需要网页视图过一次 Cloudflare 校验（HTTP ' + status + ' ' + url + '）');
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
