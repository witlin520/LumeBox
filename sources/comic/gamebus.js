// LumeSource: {"id":"gamebus_comic","name":"绅游巴士漫画","version":"1.0.0","category":"comic","contentCategory":"adult","mirrors":["https://gamebus001.cc"]}
// LumeRuntime: javascript
//
// 站点：绅游巴士（https://gamebus001.cc）—— Quasar/Vue 的 SSR 站，三个板块 /product（游戏）、/comic（H 漫）、
// /video（短片）。本源只做漫画，视频见 sources/video/gamebus.js，游戏站没有对应板块（下载站，不硬凑）。
//
// 接口（从 /assets/index-Cq4bvF8R.js 里扒出来的，全部带 /api 前缀，实测可用）：
//   · 列表   POST /api/comic/page/{page}   body {"keyword":"","page":N,"pageSize":30,"sort":"last_chapterAt"}
//              → {data:{list:[{id,title,cover_url,views,likes,tags[],last_chapterAt,last_chapterIndex}],total,page,pageSize}}
//              sort 实测可用：last_chapterAt（默认）/ createdAt / views / likes；hot 会 500
//              keyword 是站内全文搜索（实测 "NTR" → 34 条）
//   · 详情   GET  /api/comic/{id}
//   · 选集   GET  /api/comic/chapters?comicId={id}      → {data:{list:[{id,title,order_index,is_locked,pages}]}}
//   · 正文   GET  /api/comic/{chapterId}/pages          → {data:{chapter:{pages:[{image_path,order_index}]},prev,next}}
//              ★ 这个接口很干净，不用去解 /chapter/{id} 那 145 KB 的 __INITIAL_STATE__
//   · 标签   GET  /api/tag/comic（41 个，服务端**不支持**按标签过滤，所以本源不拿它当分类）
//
// 图片在 image.gamebus001.cc（webp，实测直连 200 + image/webp），不需要 Referer。
// 全站 18+（H 漫站），页面里还挂着广告跳转，本源一律不碰。

var BASE_URL = 'https://gamebus001.cc';
var UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
var PAGE_SIZE = 30;
var CATEGORY_FILE = 'categories.json';
var CATEGORY_TTL_MS = 6 * 3600 * 1000;

var SORTS = [
  { id: 'last_chapterAt', title: '最新更新' },
  { id: 'createdAt', title: '最新收录' },
  { id: 'views', title: '最多浏览' },
  { id: 'likes', title: '最多喜欢' },
];

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  return (domain || BASE_URL).replace(/\/+$/, '');
}

async function readJson(file) {
  try {
    var raw = await LumeSource.fs.readText(file);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch (error) {
    return null;
  }
}

async function writeJson(file, value) {
  try {
    await LumeSource.fs.writeText(file, JSON.stringify(value));
  } catch (error) {
    /* 缓存失败不影响主流程 */
  }
}

async function api(method, path, body) {
  var options = {
    method: method,
    headers: {
      Accept: 'application/json',
      'User-Agent': UA,
      Referer: base() + '/',
    },
  };
  if (body != null) {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }
  var reply = await LumeSource.http.request({
    url: base() + '/api' + path,
    method: method,
    headers: options.headers,
    body: options.body,
  });
  var status = reply ? reply.status : 0;
  if (status === 403 || status === 503) {
    throw new Error('NEED_WEBVIEW_VERIFY：绅游巴士被 Cloudflare 挡下（HTTP ' + status + '）');
  }
  if (status !== 200 && status !== 201) throw new Error('接口失败：HTTP ' + status + ' ' + path);
  var text = reply && reply.body ? String(reply.body) : '';
  var json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch (error) {
    json = null;
  }
  if (!json) throw new Error('接口返回的不是 JSON：' + path);
  if (typeof json.code === 'number' && json.code !== 200 && json.code !== 0) {
    throw new Error('接口报错：' + String(json.message || json.code));
  }
  return json.data !== undefined ? json.data : json;
}

function compact(number) {
  var value = Number(number) || 0;
  if (value >= 10000) return (value / 10000).toFixed(1).replace(/\.0$/, '') + '万';
  return String(value);
}

function mapItem(row) {
  if (!row || row.id == null) return null;
  var bits = [];
  if (Array.isArray(row.tags) && row.tags.length) bits.push(String(row.tags[0]));
  if (row.last_chapterIndex) bits.push(row.last_chapterIndex + '话');
  if (row.views) bits.push(compact(row.views) + '浏览');
  return {
    id: String(row.id),
    title: String(row.title || ('漫画 ' + row.id)),
    cover: String(row.cover_url || row.coverUrl || ''),
    subtitle: bits.join(' · '),
  };
}

async function fetchList(page, keyword, sort) {
  var data = await api('POST', '/comic/page/' + page, {
    keyword: keyword || '',
    page: page,
    pageSize: PAGE_SIZE,
    sort: sort || 'last_chapterAt',
  });
  var rows = data && Array.isArray(data.list) ? data.list : [];
  var items = [];
  for (var i = 0; i < rows.length; i++) {
    var item = mapItem(rows[i]);
    if (item) items.push(item);
  }
  var total = data && typeof data.total === 'number' ? data.total : 0;
  return { items: items, hasMore: total > page * PAGE_SIZE || rows.length >= PAGE_SIZE };
}

var LumeSource = {
  id: 'gamebus_comic',
  name: '绅游巴士漫画',
  version: '1.0.0',
  category: 'comic',
  contentCategory: 'adult',
  mirrors: ['https://gamebus001.cc'],

  async categories() {
    var cached = await readJson(CATEGORY_FILE);
    if (cached && Array.isArray(cached.list) && cached.list.length && Date.now() - Number(cached.at) < CATEGORY_TTL_MS) {
      return cached.list;
    }
    var list = [];
    for (var i = 0; i < SORTS.length; i++) list.push({ id: 'sort:' + SORTS[i].id, title: SORTS[i].title });
    await writeJson(CATEGORY_FILE, { at: Date.now(), list: list });
    return list;
  },

  async home() {
    var boards = [];
    var first = await fetchList(1, '', 'last_chapterAt');
    if (first.items.length) boards.push({ title: '最新更新', moreUrl: 'sort:last_chapterAt', items: first.items.slice(0, 12) });
    var hot = await fetchList(1, '', 'views');
    if (hot.items.length) boards.push({ title: '最多浏览', moreUrl: 'sort:views', items: hot.items.slice(0, 12) });
    var liked = await fetchList(1, '', 'likes');
    if (liked.items.length) boards.push({ title: '最多喜欢', moreUrl: 'sort:likes', items: liked.items.slice(0, 12) });
    return boards;
  },

  async filters() {
    var options = [];
    for (var i = 0; i < SORTS.length; i++) options.push({ id: SORTS[i].id, title: SORTS[i].title });
    return { groups: [{ id: 'sort', title: '排序', options: options }] };
  },

  async list(argument) {
    var args = argument || {};
    var page = Number(args.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = String(args.keyword == null ? '' : args.keyword).trim();
    var categoryId = String(args.categoryId == null ? '' : args.categoryId).trim();
    var filters = args.filters || {};
    var sort = String(filters.sort || '').trim();
    if (/^sort:/.test(categoryId)) sort = categoryId.slice(5);
    if (!sort) sort = 'last_chapterAt';
    return await fetchList(page, keyword, sort);
  },

  async detail(argument) {
    var id = String((argument && argument.id) || '').replace(/[^0-9]/g, '');
    if (!id) return null;
    var data = null;
    try {
      data = await api('GET', '/comic/' + id);
    } catch (error) {
      return null;
    }
    if (!data || !data.title) return null;
    var bits = [];
    if (data.author) bits.push(String(data.author));
    if (Array.isArray(data.tags) && data.tags.length) bits.push(data.tags.map(function (t) { return t.name; }).slice(0, 3).join(' / '));
    if (data.views) bits.push(compact(data.views) + '浏览');
    if (data.last_chapterIndex) bits.push('更新到第' + data.last_chapterIndex + '话');
    var description = String(data.description || '');
    return {
      id: id,
      title: String(data.title),
      cover: String(data.cover_url || ''),
      subtitle: bits.join(' · '),
      description: description,
    };
  },

  async chapters(argument) {
    var id = String((argument && argument.id) || '').replace(/[^0-9]/g, '');
    if (!id) return [];
    var data = await api('GET', '/comic/chapters?comicId=' + id);
    var rows = data && Array.isArray(data.list) ? data.list : [];
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (!row || row.id == null) continue;
      var title = String(row.title || ('第' + (row.order_index || i + 1) + '话'));
      if (row.is_locked) title += '（锁定）';
      out.push({ id: String(row.id), title: title });
    }
    return out;
  },

  async content(argument) {
    var chapterId = String((argument && argument.chapterId) || '').replace(/[^0-9]/g, '');
    if (!chapterId) throw new Error('缺少章节 ID');
    var data = await api('GET', '/comic/' + chapterId + '/pages');
    var chapter = data && data.chapter ? data.chapter : null;
    if (!chapter) throw new Error('这一话取不到内容');
    if (chapter.is_locked) throw new Error('这一话在源站是锁定章节');
    var pages = Array.isArray(chapter.pages) ? chapter.pages : [];
    var images = [];
    for (var i = 0; i < pages.length; i++) {
      var url = String((pages[i] && pages[i].image_path) || '').trim();
      if (url) images.push(url);
    }
    if (!images.length) throw new Error('这一话没有图片');
    return { kind: 'images', images: images };
  },
};
