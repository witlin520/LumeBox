// LumeSource: {"id":"rmtt2_comic","name":"肉漫天堂","version":"1.0.0","category":"comic","mirrors":["https://rmtt2.com"]}

// 站点：https://rmtt2.com（MacCMS + conch 主题，与 X漫 / 18禁漫 同一族；桌面与移动共用同一套标记）
//
// ## 抓取口径（2026-10-25 对实时页面逐条核过；路径前缀与 X漫 不同，见下）
//
//   列表  GET /comics-cata/{分类}/ob/time/st/all/page/{N}   24 条/页
//         条目在 `li.vodlist_item` 里：
//           <a class="vodlist_thumb lazyload" href="/comics-detail/{数字id}"
//              title="标题" data-original="封面">
//         标题在 `p.vodlist_title > a[title]`；副标题是紧跟的 `p.vodlist_sub`
//         （列表页放「N小时之前」，首页板块放「最新话」——两种都当纯文本用）。
//         封面**只在 data-original 里**（lazyload，src 是空的）。
//   分类  GET /comics-cata 的导航：`/comics-cata/{类}/ob/time/st/all` 形态的锚点
//         （全部/韩漫/日漫/3D漫画/真人美女/单本）。分类 id 直接存这个路径段。
//   筛选  站点自己的列表 URL 就带两个维度（实测分类页里那两排就是它们）：
//           · 状态 `st`：all 全部 / serialized 更新中 / completed 已完结
//           · 排序 `ob`：time 按时间 / hits 按阅读
//         本源做成 `filters()` 的两组，`list()` 拼进 `/comics-cata/{类}/ob/{排序}/st/{状态}/page/N`。
//   更新  GET /nm   最新更新整表页（实测 180 条、**没有分页器**，只有第 1 页）。
//   排行  GET /mrank  排行榜：`li.ranklist_item`（**不是** vodlist_item），
//         多块（每周排行…），标题在 `h4.title`，封面在 `div.ranklist_thumb[data-original]`。
//   搜索  GET /comics-search/{关键词}/page/{N}   24 条/页，条目与列表页同一套标记。
//   详情  GET /comics-detail/{id}
//         标题 `<h1 class="title">`；封面在 `div.content_thumb` 里
//         （页面别处还有别人的推荐封面，**不能全局取第一个 data-original**）；
//         简介在 `li.desc`；标签在 `li.data` 的 `a[href=/comics-search/…]`。
//   目录  就在详情页里（单页、旧→新）：`a[href=/comics-read/{作品id}/{token}]`。
//         {token} 是 20 位随机串；还有一条同为 /comics-read 的「开始阅读」按钮，
//         按文案（开始阅读 / 继续阅读）剔除。同一 token 会出现两次（按钮 + 目录），
//         按 token 去重、保留有标题的那条。
//   正文  GET /comics-read/{作品id}/{token}
//         图片在 `div#m_r_imgbox_0` 里：`<img width="100%" data-src="{图址}"
//         data-index="{序号}">`——**懒加载，只认 data-src**（整页唯一一张带 src 的
//         图是 yandex 统计像素）。图床实测不需要 Referer。
//
// ## 实测出来的两条（写错了会少数据 / 抓错图）
//
// 1. **分类 / 搜索路径里的中文自己百分号编码**。站点自己的链接是裸中文
//    （/comics-cata/韩漫/…、/comics-search/恋/page/2），脚本一律 encodeURIComponent 后拼；
//    两种写法实测都能 200，但编码可控、不赌服务端对裸中文路径的解码。
// 2. **详情页的封面不能全局取**：`/comics-detail/{id}` 页面里除本作封面外还挂着
//    推荐位封面（实测第 2、3 个 data-original 是别人的），必须先在
//    `content_thumb` 块内取。
//
// 站点有 Cloudflare 前置但普通 GET 没有挑战页（快照与实时页都没有 __cf_chl /
// challenge-platform 痕迹）；被拦时的标记路径照留（见 __get）：真拦了就抛
// NEED_WEBVIEW_VERIFY，App 拉起网页视图过一次校验。

var BASE_URL = 'https://rmtt2.com';

var PAGE_SIZE = 24;          // 列表/搜索每页条数（快照实测）
var HOME_BUDGET_MS = 6000;   // 首页软截止（沙箱单次调用预算是 3–10s，见 home()）
var ITEM_WINDOW = 1600;      // 单条往后看的窗口（封面/副标题都在这段里）
var MAX_ITEMS = 400;         // 单次解析最多产出（/nm 整表页实测 180 条）
var MAX_CHAPTERS = 4000;     // 目录最多解析多少话
var MAX_IMAGES = 600;        // 正文最多收多少张图（实测一章 154 张）
var MAX_TAGS = 12;           // 详情页标签最多收几个
var DETAIL_SCAN = 400000;    // 详情页最多扫多少字符（实测 ≈66KB）

var LumeSource = {
  id: 'rmtt2_comic',
  name: '肉漫天堂',
  version: '1.0.0',
  category: 'comic',

  // ---------------------------------------------------------------- 契约方法

  /// 分类：站点导航里 `/{段}/ob/time/st/all` 形态的锚点（实时抓，不写死），
  /// 前面补「全部」（站点自己的 /comics-cata/all/ob/time/st/all），后面补两个整表页
  /// （更新 / 排行）——它们是站点自己的栏目，list() 也认这两个 id。
  async categories() {
    var html = await this.__get('/comics-cata');
    var pattern = /href="\/comics-cata\/([^"\/]+)\/ob\/time\/st\/all"/g;
    var seen = {};
    var result = [{ id: 'all', title: '全部' }];
    seen['all'] = true;
    var match;
    while ((match = pattern.exec(html)) !== null) {
      var slug = match[1];
      if (seen[slug]) continue;
      seen[slug] = true;
      result.push({ id: slug, title: slug });
    }
    result.push({ id: 'nm', title: '最新更新' });
    result.push({ id: 'rank', title: '排行榜' });
    return result;
  },

  /// 筛选：站点自己的两个维度（状态 / 排序，来自列表页 URL 的 st 与 ob 段）。
  async filters() {
    return {
      groups: [
        {
          id: 'status',
          title: '状态',
          options: [
            { id: 'all', title: '全部' },
            { id: 'serialized', title: '更新中' },
            { id: 'completed', title: '已完结' }
          ]
        },
        {
          id: 'sort',
          title: '排序',
          options: [
            { id: 'time', title: '按时间' },
            { id: 'hits', title: '按阅读' }
          ]
        }
      ]
    };
  },

  /// 首页：最新更新（整表页）+ 两个分类的首屏，每块 12 条。
  ///
  /// **逐块 try/catch + 软截止**：沙箱给单次调用的墙钟预算是 3–10 秒（默认 10），
  /// 四块串行请求在慢网络下会顶到上限、整个 home 以「调用超时」收场（实测过一次：
  /// 四个板块全在时 home 超时，页面上什么都没有）。因此到点就**把已经拿到的
  /// 板块先返回**——首页有几块是几块，好过整页空白。
  async home() {
    var started = new Date().getTime();
    var boards = [];
    try {
      var latest = await this.list({ categoryId: 'nm', page: 1 });
      if (latest && latest.items && latest.items.length) {
        boards.push({
          title: '最新更新',
          moreUrl: 'nm',
          items: latest.items.slice(0, 12)
        });
      }
    } catch (error) {
      console.warn('[rmtt2] 首页「最新更新」失败：' + error);
    }
    var picks = ['韩漫', '3D漫画'];
    for (var i = 0; i < picks.length; i++) {
      if (this.__overBudget(started, HOME_BUDGET_MS)) {
        console.warn('[rmtt2] 首页到软截止（' + HOME_BUDGET_MS + 'ms），先返回已有的 '
          + boards.length + ' 块');
        break;
      }
      try {
        var payload = await this.list({ categoryId: picks[i], page: 1 });
        var items = payload && payload.items ? payload.items : [];
        if (!items.length) continue;
        boards.push({
          title: picks[i],
          moreUrl: picks[i],
          items: items.slice(0, 12)
        });
      } catch (error) {
        console.warn('[rmtt2] 首页「' + picks[i] + '」失败：' + error);
      }
    }
    return boards;
  },

  async list(argument) {
    var page = argument && argument.page ? Number(argument.page) : 1;
    if (!(page > 0)) page = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';

    if (keyword) {
      var html = await this.__get('/comics-search/' + encodeURIComponent(keyword) + '/page/' + page);
      var hits = this.__listItems(html);
      return { items: hits, hasMore: this.__hasNextPage(html, page, hits.length) };
    }

    if (category === 'nm' || category === 'rank') {
      // 两个整表页：站点没有分页器（实测 /nm 180 条、/mrank 多块），
      // 第 2 页不去请求一个不存在的地址。
      if (page > 1) return { items: [], hasMore: false };
      var tableHtml = await this.__get(category === 'nm' ? '/update-manga' : '/comics-rank');
      var tableItems = category === 'nm'
        ? this.__listItems(tableHtml)
        : this.__rankItems(tableHtml);
      return { items: tableItems, hasMore: false };
    }

    if (!category) category = 'all';
    // 筛选（站点自己的 URL 维度）：只认白名单值，别把任意串拼进地址。
    var selected = argument && argument.filters ? argument.filters : {};
    var sort = String(selected.sort == null ? '' : selected.sort).split(',')[0];
    var status = String(selected.status == null ? '' : selected.status).split(',')[0];
    if (sort !== 'hits') sort = 'time';
    if (status !== 'serialized' && status !== 'completed') status = 'all';
    var url = '/comics-cata/' + encodeURIComponent(category) + '/ob/' + sort
      + '/st/' + status + '/page/' + page;
    var pageHtml = await this.__get(url);
    var items = this.__listItems(pageHtml);
    return { items: items, hasMore: this.__hasNextPage(pageHtml, page, items.length) };
  },

  async detail(argument) {
    var id = this.__id(argument);
    var html = await this.__get('/comics-detail/' + id);
    var title = this.__title(html);
    if (!title) {
      console.warn('[rmtt2] 详情页没认出标题：' + id + '（' + html.length + ' 字符）');
      return null;
    }
    var info = this.__detailInfo(html);
    return {
      id: id,
      title: title,
      cover: this.__detailCover(html),
      coverHeaders: { 'Referer': BASE_URL + '/' },
      subtitle: info.status,
      description: info.description,
      tags: info.tags,
      extra: {
        author: info.author,
        category: info.category,
        status: info.status
      }
    };
  },

  async chapters(argument) {
    var id = this.__id(argument);
    var html = await this.__get('/comics-detail/' + id);
    var chapters = this.__chapters(html, id);
    if (!chapters.length) {
      throw new Error('肉漫天堂：详情页没认出章节链接（id=' + id + '）——把运行日志发回来收敛解析规则');
    }
    return chapters;
  },

  async content(argument) {
    var id = this.__id(argument);
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (!chapterId) throw new Error('肉漫天堂：缺少章节 token（请重新进一次目录再打开）');
    var html = await this.__get('/comics-read/' + id + '/' + chapterId);
    var images = this.__images(html);
    if (!images.length) {
      throw new Error('肉漫天堂：正文页没认出图片（' + id + '/' + chapterId + '，' + html.length + ' 字符）');
    }
    return { kind: 'images', images: images };
  },

  // ---------------------------------------------------------------- 内部工具

  __id(argument) {
    var id = '';
    if (argument && argument.id != null) id = String(argument.id).trim();
    if (!id) throw new Error('肉漫天堂：缺少作品 ID');
    return id;
  },

  /// 软截止判定：单次调用已经跑了多久（`home()` 逐块拼装时用）。
  __overBudget(started, budgetMs) {
    return new Date().getTime() - started > budgetMs;
  },

  /// 列表 / 搜索页的条目（同一套标记）。
  __listItems(html) {
    var items = [];
    var seen = {};
    var pattern = /<li class="vodlist_item[^"]*">/g;
    var match;
    while ((match = pattern.exec(html)) !== null) {
      if (items.length >= MAX_ITEMS) break;
      var block = html.slice(match.index, match.index + ITEM_WINDOW);
      var link = /href="\/comics-detail\/(\d+)"/.exec(block);
      if (!link) continue;
      var id = link[1];
      if (seen[id]) continue;
      seen[id] = true;
      var titleMatch = /class="vodlist_title"[\s\S]{0,300}?title="([^"]*)"/.exec(block)
        || /title="([^"]*)"/.exec(block);
      var coverMatch = /data-original="([^"]*)"/.exec(block);
      var subMatch = /class="vodlist_sub"[^>]*>([\s\S]{0,300}?)<\/p>/.exec(block);
      items.push({
        id: id,
        title: this.__clean(titleMatch ? titleMatch[1] : id),
        cover: this.__absolute(coverMatch ? coverMatch[1] : ''),
        coverHeaders: { 'Referer': BASE_URL + '/' },
        subtitle: this.__clean(this.__stripTags(subMatch ? subMatch[1] : ''))
      });
    }
    return items;
  },

  /// 排行榜页的条目（`li.ranklist_item`，与列表页不是一套标记）。
  __rankItems(html) {
    var items = [];
    var seen = {};
    var pattern = /<li class="ranklist_item[^"]*">/g;
    var match;
    while ((match = pattern.exec(html)) !== null) {
      if (items.length >= MAX_ITEMS) break;
      var block = html.slice(match.index, match.index + ITEM_WINDOW);
      var link = /<a[^>]+title="([^"]*)"[^>]+href="\/comics-detail\/(\d+)"/.exec(block)
        || /href="\/comics-detail\/(\d+)"/.exec(block);
      if (!link) continue;
      var id = link.length > 2 ? link[2] : link[1];
      var title = link.length > 2 ? link[1] : '';
      if (seen[id]) continue;
      seen[id] = true;
      var headMatch = /class="title">([^<]*)</.exec(block);
      if (headMatch) title = headMatch[1];
      var coverMatch = /data-original="([^"]*)"/.exec(block);
      var subMatch = /class="vodlist_sub"[^>]*>([^<]{0,60})</.exec(block);
      items.push({
        id: id,
        title: this.__clean(title || id),
        cover: this.__absolute(coverMatch ? coverMatch[1] : ''),
        coverHeaders: { 'Referer': BASE_URL + '/' },
        subtitle: this.__clean(subMatch ? subMatch[1] : '')
      });
    }
    return items;
  },

  __title(html) {
    var match = /<h1 class="title">([\s\S]{0,200}?)<\/h1>/.exec(html);
    if (match) return this.__clean(match[1]);
    match = /property="og:title" content="([^"]*)"/.exec(html);
    return match ? this.__clean(match[1]) : '';
  },

  /// 详情页封面：**只在 content_thumb 块里取**（页面别处有推荐位封面）。
  __detailCover(html) {
    var match = /class="content_thumb[\s\S]{0,600}?data-original="([^"]+)"/.exec(html);
    if (match) return this.__absolute(match[1]);
    match = /property="og:image" content="([^"]+)"/.exec(html);
    return match ? this.__absolute(match[1]) : '';
  },

  __detailInfo(html) {
    var head = html.slice(0, DETAIL_SCAN);
    var authorMatch = /作者：<\/span>\s*<span><a[^>]*>([^<]*)<\/a>/.exec(head);
    var categoryMatch = /href="\/comics-cata\/([^"\/]+)"><span>([^<]*)<\/span>/.exec(head);
    var statusMatch = /<font[^>]*>\s*([\s\S]{0,80}?)<\/font>/.exec(head);
    var descMatch = /class="desc[^"]*">([\s\S]{0,4000}?)<\/li>/.exec(head);
    var description = this.__clean(this.__stripTags(descMatch ? descMatch[1] : ''));
    description = description.replace(/^(?:简介|簡介)\s*[：:]\s*/, '');
    var tags = [];
    var tagMatch = /标签：<\/span>([\s\S]{0,2000}?)<\/li>/.exec(head);
    if (tagMatch) {
      var tagPattern = /<a[^>]*>([^<]{1,20})<\/a>/g;
      var item;
      while ((item = tagPattern.exec(tagMatch[1])) !== null) {
        var tag = this.__clean(item[1]);
        if (tag && tags.indexOf(tag) < 0 && tags.length < MAX_TAGS) tags.push(tag);
      }
    }
    return {
      author: this.__clean(authorMatch ? authorMatch[1] : ''),
      category: this.__clean(categoryMatch ? categoryMatch[2] : ''),
      status: this.__clean(this.__stripTags(statusMatch ? statusMatch[1] : '')),
      description: description,
      tags: tags
    };
  },

  /// 目录：详情页里的 /comics-read/{作品id}/{token} 锚点，按 token 去重、旧→新。
  __chapters(html, id) {
    var pattern = new RegExp('<a[^>]+href="/comics-read/' + id + '/([A-Za-z0-9]+)"[^>]*>([^<]{0,120})<', 'g');
    var chapters = [];
    var index = {};
    var match;
    while ((match = pattern.exec(html)) !== null) {
      if (chapters.length >= MAX_CHAPTERS) break;
      var token = match[1];
      var title = this.__clean(match[2]);
      // 「开始阅读」按钮与目录里的第一条是同一个 token：按文案剔除按钮那条。
      if (title.indexOf('开始阅读') >= 0 || title.indexOf('继续阅读') >= 0) title = '';
      if (index[token] != null) {
        if (title && !chapters[index[token]].title) chapters[index[token]].title = title;
        continue;
      }
      index[token] = chapters.length;
      chapters.push({ id: token, title: title });
    }
    // 没标题的条目补「第 N 话」——站点目录每一条都带标题，这条只是兜底。
    for (var i = 0; i < chapters.length; i++) {
      if (!chapters[i].title) chapters[i].title = '第 ' + (i + 1) + ' 话';
    }
    return chapters;
  },

  /// 正文图片：`img[data-src][data-index]`（懒加载，src 是空的）。
  __images(html) {
    var images = [];
    var pattern = /<img[^>]+data-src="(https?:\/\/[^"]+)"[^>]*data-index="/g;
    var match;
    while ((match = pattern.exec(html)) !== null) {
      if (images.length >= MAX_IMAGES) break;
      images.push(match[1]);
    }
    return images;
  },

  /// 「还有下一页」：先看分页器的「共有 N 页」（整页找——它在页面中段，不在尾部），
  /// 再看有没有「下一页」锚点，最后退回「本页是否满页」。
  __hasNextPage(html, page, itemCount) {
    var total = /共有\s*(\d+)\s*页/.exec(html);
    if (total) return page < Number(total[1]);
    if (/>\s*下一页\s*</.test(html)) return true;
    return itemCount >= PAGE_SIZE - 4;
  },

  __absolute(url) {
    var value = String(url || '').trim();
    if (!value) return '';
    if (value.indexOf('http') === 0) return value;
    if (value.indexOf('//') === 0) return 'https:' + value;
    return BASE_URL + (value.charAt(0) === '/' ? '' : '/') + value;
  },

  __stripTags(text) {
    return String(text || '').replace(/<[^>]*>/g, ' ');
  },

  __clean(text) {
    return this.__stripTags(text)
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/\s+/g, ' ')
      .trim();
  },

  /// 所有请求的唯一出口：补全地址、发请求、被 WAF 拦下时抛固定标记。
  async __get(path) {
    var url = path.indexOf('http') === 0 ? path : BASE_URL + path;
    var response = await LumeSource.http.get(url, {
      headers: { 'Referer': BASE_URL + '/' }
    });
    var status = response ? Number(response.status) : 0;
    var body = response && response.body ? String(response.body) : '';
    if (status !== 200) {
      // Cloudflare / 同类人机校验：抛固定标记，App 拉起网页视图过一次校验。
      if (status === 403 || status === 503 || status === 429) {
        throw new Error('NEED_WEBVIEW_VERIFY：站点触发了 Cloudflare 人机校验（HTTP '
          + status + ' ' + url + '）');
      }
      throw new Error('拉取失败：HTTP ' + status + ' ' + url);
    }
    if (/just a moment|challenge-platform|__cf_chl|cf-chl-/.test(body)) {
      throw new Error('NEED_WEBVIEW_VERIFY：站点触发了 Cloudflare 人机校验（HTTP '
        + status + ' ' + url + '）');
    }
    return body;
  }
};
