// LumeSource: {"id":"yidan17_comic","name":"一耽女孩","version":"1.0.0","category":"comic","mirrors":["https://www.yidan17.club"]}
//
// 站点：一耽女孩（www.yidan17.club，BL 韩漫）—— Vue CLI + uni-app 的 H5 SPA
//
// ── 外壳（1.8KB）就读出两件事（2026-10-25 实测，全部走本机代理出口）
//   · `<title>` 是「涓€鑰藉コ瀛?」——UTF-8 被当 GBK 显示，真名就是**一耽女孩**。
//   · 只加载 `/static/js/chunk-vendors.78147ed0.js`(974KB) + `/static/js/index.82c533ce.js`(1.95MB)，
//     内容全在 JS 里（无 /_nuxt，那是 Nuxt；这里没有 SSR、没有 sitemap）。
//   · index.js 里 axios 实例 `create({timeout:15000, withCredentials:true})`，
//     响应拦截器**出错时**才把备用域名写进 storage：
//       uni.setStorageSync("apiList", JSON.stringify(["https://g.o-22166.xyz/api/","https://g.o-26337.xyz/api/"]))
//     默认 `getApiUrl()` = storage.config.apiUrl || **"/api/"**（同域）。
//
// ── 接口：全部是 POST + JSON body，路径 `${apiUrl}${action}`
//   域名实测结果：g.o-22166.xyz / g.o-26337.xyz 在这台机器上**连接超时**（不是 403，是根本没回包），
//   同域 `https://www.yidan17.club/api/` 和 index 的 `result.config.apiUrl`
//   给的 `https://yd-a.obkqwz.cn/api/` 都是 200 —— 本源就用这两个，前者优先，挂了一个换另一个。
//   参数名是**站点自定义**的，不是 REST 直觉（踩过坑，实测过）：
//     · getComicInfo        {comicId}         ← 用 {id} / {novelId} 一律 500「无法获取漫画」
//                           → {comic:{id,novelTitle,author,introduction,categoryName,tags,
//                                     imgUrl,bigImgUrl,clickCount,lastUpdateTime,lastChapter,overType},
//                              chapterList:[{id,chapterName,createTime,needGold,golds,imgUrl}],
//                              randomList,userOp}
//     · getComicChapter     {comicId, chapterId}
//                           → {balance,state,pay_coin,content:[{url}]}；state=1 时 content 是整章图集
//                             （实测 35 / 137 张 png 全给，needGold:1 的章节也能拿到 → 免登录可读）
//     · getComicCategoryList {}                → [{id,categoryName}]（实测 20 个：青柠竹马/办公室/娱乐圈/…/架空）
//     · getByComicCategoryId {categoryId,page} → {total,list:[…]}，每页 20 条（实测 34 号 total=69，page2 换了一批）
//     · searchNovel         {key}              ← 用 {keyword}/{word}/{kw}/{title} 都是空数组
//                           → [{id,novelTitle,…}]（**page 参数被忽略**，实测 {key:'魔',page:1} 与 page:2 同 17 条，
//                             所以本源对搜索结果自己做 20 条切片分页）
//     · getMhIndexData      {}                 → {noticeList,colList:[{id,title,list:[…]}×5],
//                                                 topList:{tgTop,favTop,clickTop,createTimeTop,praiseTop},
//                                                 mhBannerList,config:{apiUrl,webUrl,OssUrl,…}}
//   图片：`https://resvsm.jlznis.cn/images/mhtp/yidan/{hash}/chapter_file/{n}/{n}.png`
//        实测 Node fetch 直连 200（content-type: application/octet-stream，其实内容是 png，373KB），
//        带不带 Referer 都行；带 iPhone UA 也一样。
//   阅读页路由（给 webplayer 兜底用）：/pages/comic/content?id=&chapterId=
var DEFAULT_BASE = 'https://www.yidan17.club';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var API_HOSTS = ['https://yd-a.obkqwz.cn/api/', 'https://www.yidan17.club/api/'];
var PAGE_SIZE = 20;

var apiHost = ''; // 探通后记住，省掉每轮重试

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    'Content-Type': 'application/json;charset=UTF-8',
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Origin: base(),
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

function decode(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&#(\d+);/g, function (all, code) {
      return String.fromCharCode(Number(code));
    })
    .replace(/\\u002F/gi, '/')
    .replace(/\\\//g, '/')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[ \t\r\n]+/g, ' ')
    .trim();
}

// 逐台试 apiUrl，通了就记住；全挂才抛错
async function api(action, body) {
  var payload = JSON.stringify(body || {});
  var hosts = apiHost ? [apiHost] : API_HOSTS.slice();
  var lastError = null;
  for (var index = 0; index < hosts.length; index++) {
    var url = hosts[index] + action;
    try {
      var response = await LumeSource.http.post(url, payload, { headers: headers() });
      var status = response ? response.status : 0;
      var text = String((response && response.body) || '');
      if (status !== 200) {
        lastError = new Error('一耽女孩接口 HTTP ' + status + '：' + url);
        continue;
      }
      var parsed;
      try {
        parsed = JSON.parse(text);
      } catch (error) {
        lastError = new Error('一耽女孩接口返回的不是 JSON：' + url);
        continue;
      }
      if (parsed && parsed.success === false) {
        lastError = new Error('一耽女孩接口报错（' + action + '）：' + String(parsed.message || ''));
        // 接口本身通了，参数错不用换域名
        apiHost = hosts[index];
        throw lastError;
      }
      apiHost = hosts[index];
      return parsed && parsed.result !== undefined ? parsed.result : parsed;
    } catch (error) {
      if (error && /一耽女孩接口报错/.test(String(error.message))) throw error;
      lastError = error;
    }
  }
  throw lastError || new Error('一耽女孩：所有接口域名都不通');
}

function coverOf(row) {
  var text = String((row && (row.bigImgUrl || row.imgUrl || row.picUrl)) || '').trim();
  return text;
}

function itemOf(row) {
  if (!row || row.id == null) return null;
  var id = String(row.id);
  var parts = [];
  if (row.author) parts.push('作者 ' + String(row.author).trim());
  if (row.clickCount) parts.push(Number(row.clickCount) + ' 点击');
  if (row.lastChapter) parts.push('最新 ' + String(row.lastChapter));
  return {
    id: id,
    title: decode(row.novelTitle || row.title || id),
    cover: coverOf(row),
    subtitle: parts.join(' · ')
  };
}

function itemsOf(rows) {
  var items = [];
  for (var index = 0; index < (rows || []).length; index++) {
    var item = itemOf(rows[index]);
    if (item) items.push(item);
  }
  return items;
}

var categoryCache = null;

var LumeSource = {
  id: 'yidan17_comic',
  name: '一耽女孩',
  version: '1.0.0',
  category: 'comic',
  mirrors: ['https://www.yidan17.club'],

  /// 分类：getComicCategoryList 的 20 个题材。
  async categories() {
    if (categoryCache && categoryCache.length) return categoryCache.slice();
    var rows = await api('getComicCategoryList', {});
    var out = [];
    for (var index = 0; index < (rows || []).length; index++) {
      var row = rows[index];
      if (!row || row.id == null) continue;
      out.push({ id: String(row.id), title: decode(row.categoryName || row.name || '') });
    }
    if (!out.length) throw new Error('一耽女孩：分类列表是空的');
    categoryCache = out;
    return out.slice();
  },

  /// 首页：getMhIndexData 的 colList（实测 5 个栏目，每个栏目 3-6 本）。
  async home() {
    var data = await api('getMhIndexData', {});
    var boards = [];
    var cols = (data && data.colList) || [];
    for (var index = 0; index < cols.length; index++) {
      var col = cols[index];
      var items = itemsOf(col && col.list).slice(0, 18);
      if (!items.length) continue;
      boards.push({ title: decode((col && col.title) || '推荐'), moreUrl: '', items: items });
    }
    if (!boards.length && data && data.topList) {
      // colList 空时退到榜单
      var lists = data.topList;
      var names = { tgTop: '飙升榜', favTop: '收藏榜', clickTop: '热度榜', createTimeTop: '新作榜', praiseTop: '好评榜' };
      for (var key in names) {
        var rows = itemsOf(lists[key]).slice(0, 18);
        if (rows.length) boards.push({ title: names[key], moreUrl: '', items: rows });
      }
    }
    if (!boards.length) throw new Error('一耽女孩：首页一个栏目都解析不出来（接口可能改版）');
    return boards;
  },

  /// 列表 / 搜索：目录走 getByComicCategoryId（每页 20）；关键词走 searchNovel 的 `key` 参数。
  async list(argument) {
    var settings = argument || {};
    var page = Number(settings.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';

    if (keyword) {
      var hits = await api('searchNovel', { key: keyword, page: page });
      var rows = Array.isArray(hits) ? hits : (hits && hits.list) || [];
      // 接口忽略 page（实测 page=1 与 page=2 同结果），所以本地切片
      var total = rows.length;
      var start = (page - 1) * PAGE_SIZE;
      var slice = rows.slice(start, start + PAGE_SIZE);
      return { items: itemsOf(slice), hasMore: start + PAGE_SIZE < total };
    }

    var categoryId = settings.categoryId ? String(settings.categoryId).trim() : '';
    if (!categoryId || !/^\d+$/.test(categoryId)) {
      var cats = await this.categories();
      categoryId = cats[0].id;
    }
    var result = await api('getByComicCategoryId', { categoryId: Number(categoryId), page: page });
    var list = (result && result.list) || (Array.isArray(result) ? result : []);
    var items = itemsOf(list);
    var totalCount = Number((result && result.total) || 0);
    return { items: items, hasMore: totalCount ? page * PAGE_SIZE < totalCount : items.length >= PAGE_SIZE };
  },

  /// 详情：getComicInfo 用 **comicId**（{id} 会 500）。
  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id || !/^\d+$/.test(id)) return null;
    var data = await api('getComicInfo', { comicId: Number(id) });
    var comic = (data && data.comic) || {};
    var parts = [];
    if (comic.categoryName) parts.push(decode(comic.categoryName));
    if (comic.author) parts.push('作者 ' + decode(comic.author));
    if (comic.lastUpdateTime) parts.push('更新 ' + decode(comic.lastUpdateTime));
    if (comic.clickCount) parts.push(Number(comic.clickCount) + ' 点击');
    var chapters = (data && data.chapterList) || [];
    if (chapters.length) parts.push(chapters.length + ' 话');
    return {
      id: String(comic.id || id),
      title: decode(comic.novelTitle || id),
      cover: coverOf(comic),
      subtitle: parts.join(' · '),
      description: decode(comic.introduction || '') || '一耽女孩 · ' + id
    };
  },

  /// 章节：getComicInfo 的 chapterList（按站点顺序，第1话 → 最新）。
  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id || !/^\d+$/.test(id)) return [];
    var data = await api('getComicInfo', { comicId: Number(id) });
    var rows = (data && data.chapterList) || [];
    var out = [];
    for (var index = 0; index < rows.length; index++) {
      var row = rows[index];
      if (!row || row.id == null) continue;
      out.push({ id: String(row.id), title: decode(row.chapterName || '第 ' + (index + 1) + ' 话') });
    }
    return out;
  },

  /// 内容：getComicChapter {comicId, chapterId} → result.content[].url 整章图集。
  async content(argument) {
    var settings = argument || {};
    var comicId = String(settings.id || '').trim();
    var chapterId = String(settings.chapterId || '').trim();
    if (!comicId || !/^\d+$/.test(comicId)) throw new Error('缺少漫画 id');
    var imageHeaders = { 'User-Agent': UA, Referer: base() + '/' };
    if (chapterId && /^\d+$/.test(chapterId)) {
      var data = await api('getComicChapter', { comicId: Number(comicId), chapterId: Number(chapterId) });
      var rows = (data && data.content) || [];
      var images = [];
      for (var index = 0; index < rows.length; index++) {
        var url = String((rows[index] && rows[index].url) || '').trim();
        if (url && /^https?:\/\//i.test(url)) images.push(url);
      }
      if (images.length) return { kind: 'images', images: images, headers: imageHeaders };
    }
    // 付费锁定 / 章节下架 / 接口只回 state 不回图：交给 App 的网页阅读页
    return {
      kind: 'webplayer',
      pageUrl: base() + '/pages/comic/content?id=' + encodeURIComponent(comicId) + '&chapterId=' + encodeURIComponent(chapterId || ''),
      headers: imageHeaders
    };
  }
};
