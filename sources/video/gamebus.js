// LumeSource: {"id":"gamebus_video","name":"绅游巴士","version":"1.0.0","category":"video","contentCategory":"adult","mirrors":["https://gamebus001.cc"]}
// LumeRuntime: javascript
//
// 站点：绅游巴士（https://gamebus001.cc）的视频板块 /video。同一个站还有 /comic（H 漫，见
// sources/comic/gamebus.js）与 /product（游戏下载，LumeBox 没有对应板块，不做）。
//
// 接口（来自 /assets/index-Cq4bvF8R.js，实测）：
//   · 列表 POST /api/video/page/{page}  body {"page":N,"pageSize":30,"sort":"views","keyword":""}
//            → {data:{list:[{id,title,coverUrl,vipOnly,duration,views,height,createdAt}],total}}
//            sort 实测：不传=默认（最新）、views=最多播放、hot=热门（first id 会变成 1）
//            keyword 是站内搜索（"白虎" → 1671 条）；**分类/标签参数服务端不认**（categoryId/tagId 全被忽略），
//            所以本源不列频道，只给排序 + 搜索
//   · 详情 GET  /api/video/{id} → {title, coverUrl, hlsUrl, duration, category, tags[], role, views, vipOnly, price}
//   · 分类 GET  /api/video/categorise（只有 2 个：网红福利 / 国产自拍，但没法用它过滤，故不进分类）
//
// 播放：hlsUrl 形如 https://image.gamebus001.cc/video/{日期}/{批次}/index.m3u8，
// 清单是 fMP4（#EXT-X-MAP: URI="init.mp4" + seg_000.m4s，均为相对路径），实测清单 200 +
// application/x-mpegurl、首个分片 200 + video/mp4（5.7 MB），不需要 Referer、也没有 AES key。
// vipOnly 的条目源站只有付费墙，本源直接给可读错误 + 源站页面。

var BASE_URL = 'https://gamebus001.cc';
var UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
var PAGE_SIZE = 30;

var SORTS = [
  { id: '', title: '最新' },
  { id: 'views', title: '最多播放' },
  { id: 'hot', title: '热门' },
];

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  return (domain || BASE_URL).replace(/\/+$/, '');
}

async function api(method, path, body) {
  var headers = { Accept: 'application/json', 'User-Agent': UA, Referer: base() + '/' };
  var payload = null;
  if (body != null) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  var reply = await LumeSource.http.request({
    url: base() + '/api' + path,
    method: method,
    headers: headers,
    body: payload,
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

function durationText(seconds) {
  var total = Number(seconds) || 0;
  if (!total) return '';
  var m = Math.floor(total / 60);
  var s = total % 60;
  return m + ':' + (s < 10 ? '0' + s : String(s));
}

function compact(number) {
  var value = Number(number) || 0;
  if (value >= 10000) return (value / 10000).toFixed(1).replace(/\.0$/, '') + '万';
  return String(value);
}

function mapItem(row) {
  if (!row || row.id == null) return null;
  var bits = [];
  if (row.duration) bits.push(durationText(row.duration));
  if (row.height) bits.push(row.height + 'P');
  if (row.views) bits.push(compact(row.views) + '播放');
  if (row.vipOnly) bits.push('VIP');
  return {
    id: String(row.id),
    title: String(row.title || ('视频 ' + row.id)),
    cover: String(row.coverUrl || ''),
    subtitle: bits.join(' · '),
  };
}

async function fetchList(page, keyword, sort) {
  var body = { page: page, pageSize: PAGE_SIZE };
  if (keyword) body.keyword = keyword;
  if (sort) body.sort = sort;
  var data = await api('POST', '/video/page/' + page, body);
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
  id: 'gamebus_video',
  name: '绅游巴士',
  version: '1.0.0',
  category: 'video',
  contentCategory: 'adult',
  mirrors: ['https://gamebus001.cc'],

  async categories() {
    var list = [];
    for (var i = 0; i < SORTS.length; i++) list.push({ id: 'sort:' + SORTS[i].id, title: SORTS[i].title });
    return list;
  },

  async home() {
    var boards = [];
    var latest = await fetchList(1, '', '');
    if (latest.items.length) boards.push({ title: '最新', moreUrl: 'sort:', items: latest.items.slice(0, 12) });
    var hot = await fetchList(1, '', 'views');
    if (hot.items.length) boards.push({ title: '最多播放', moreUrl: 'sort:views', items: hot.items.slice(0, 12) });
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
    return await fetchList(page, keyword, sort);
  },

  async detail(argument) {
    var id = String((argument && argument.id) || '').replace(/[^0-9]/g, '');
    if (!id) return null;
    var data = null;
    try {
      data = await api('GET', '/video/' + id);
    } catch (error) {
      return null;
    }
    if (!data || !data.title) return null;
    var bits = [];
    if (data.duration) bits.push(durationText(data.duration));
    if (data.category && data.category.name) bits.push(String(data.category.name));
    if (data.role && data.role.name) bits.push(String(data.role.name));
    if (data.views) bits.push(compact(data.views) + '播放');
    if (data.vipOnly) bits.push('源站 VIP');
    var description = String(data.description || '');
    var tags = Array.isArray(data.tags) ? data.tags.map(function (t) { return t.name; }).join(' ') : '';
    if (tags) description += (description ? '\n\n' : '') + '标签：' + tags;
    return {
      id: id,
      title: String(data.title),
      cover: String(data.coverUrl || ''),
      subtitle: bits.join(' · '),
      description: description,
    };
  },

  async chapters(argument) {
    var id = String((argument && argument.id) || '').replace(/[^0-9]/g, '');
    if (!id) return [];
    return [{ id: 'video:' + id, title: '正片（HLS）' }];
  },

  async content(argument) {
    var args = argument || {};
    var id = String(args.id || '').replace(/[^0-9]/g, '');
    if (!id) throw new Error('缺少视频 ID');
    var data = await api('GET', '/video/' + id);
    var url = String((data && data.hlsUrl) || '').trim();
    if (!url) throw new Error('这条没有播放地址（源站可能已下架）');
    if (data.vipOnly) {
      throw new Error('这条在源站是 VIP 专享，本源不代下单：' + base() + '/video/' + id);
    }
    return {
      kind: 'video',
      url: url,
      headers: { Referer: base() + '/', 'User-Agent': UA },
    };
  },
};
