// LumeSource: {"id":"betareel_video","name":"BetaTok","version":"1.0.0","category":"video","contentCategory":"adult","mirrors":["https://betareel.com"]}
// LumeRuntime: javascript
//
// 站点：BetaTok / betareel.com —— 抖音式竖屏成人短片站（Firebase 项目 paidspace-0）。
//
// 数据链路（全部实测）：
//   1) GET /api/betatok/feed  → {ok, manifestUrl, mediaBase, mediaQuery, expiresAt}
//        · manifestUrl：R2 上 manifests/betatok.json 的**预签名 URL**（AWS4，有效期约 9000s）
//        · mediaBase=/api/betatok/media/，mediaQuery=e=<到期秒>&t=<token>
//   2) manifestUrl → 一个 27 MB / 34466 条的整包 JSON：
//        {version, generatedAt, count, channels:[…], items:[{id,type,videoKey,posterKey,author,…,
//         tags[],channels[],description,timestamp,views,locked,price}], creators, stats, keys}
//      ★ 整包 27 MB 在沙箱里解析不了（64 MB 堆上限），但对象是 gzip 存的（3.7 MB），
//        **支持 Range**：只要 64 KB 压缩字节就能解出 ~550 KB 文本（约 680 条）。
//        所以本源按「窗口」工作：按需要的页数要一小段范围，用 },{"id":" 切条，只 JSON.parse 需要的那几条。
//   3) 播放：/api/betatok/media/ + videoKey + '?' + mediaQuery  → 302 到 R2 的签名 mp4（实测 206/200）。
//        加 &json=1 则返回 {ok:true,url:"<R2 签名直链>"}；本源用 302 那条，省一次往返。
//   4) 封面：/api/betatok/media/ + posterKey + '?' + mediaQuery → 200 image/jpeg（Worker 代理）。
//
// 会员锁：manifest 里 locked:true 的是付费（PPV，price 单位钻石）片，本源一律不列，避免点开就是墙。
// 搜索：站点没有搜索接口，本源在**当前窗口**里做本地过滤（窗口上限约 5.6 千条，见 MAX_BYTES）。

var BASE_URL = 'https://betareel.com';
var UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
var PAGE_SIZE = 20;
var FEED_FILE = 'feed.json';
var WINDOW_FILE = 'window.json';
var FEED_TTL_MS = 8 * 60 * 1000;
var MIN_BYTES = 65536;          // 64 KB 压缩 ≈ 550 KB 文本 ≈ 680 条
var MAX_BYTES = 262144;         // 256 KB 压缩 ≈ 2.2 MB 文本 ≈ 2.8 千条（R2 往返本身就要 1-2 秒，再大就超预算）
var BYTES_PER_ITEM = 200;       // 估窗口大小用（实测每条约 107 压缩字节，留一倍余量）
var CACHE_BYTES = 262144;       // 256 KB 压缩以内（≈2.2 MB 文本）的窗口进 fs 缓存
var WINDOW_TTL_MS = 5 * 60 * 1000;

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

// ---------------------------------------------------------------- feed 引导

async function feedInfo(force) {
  var cached = await readJson(FEED_FILE);
  if (!force && cached && cached.url && cached.base && cached.query) {
    var exp = Number(cached.exp || 0);
    if (!exp || exp > Date.now() + 120000) return cached;
  }
  var reply = await LumeSource.http.get(base() + '/api/betatok/feed', {
    headers: { Accept: 'application/json', Referer: base() + '/' },
  });
  var status = reply ? reply.status : 0;
  if (status === 403 || status === 503) {
    throw new Error('NEED_WEBVIEW_VERIFY：betareel 被 Cloudflare 挡下（HTTP ' + status + '）');
  }
  if (status !== 200) throw new Error('引导接口失败：HTTP ' + status);
  var body = null;
  try {
    body = JSON.parse(reply.body ? String(reply.body) : '');
  } catch (error) {
    body = null;
  }
  if (!body || !body.manifestUrl || !body.mediaBase || !body.mediaQuery) {
    throw new Error('引导接口返回异常：' + String(reply.body || '').slice(0, 120));
  }
  var info = {
    url: String(body.manifestUrl),
    base: String(body.mediaBase),
    query: String(body.mediaQuery),
    exp: Number(body.expiresAt) || Date.now() + FEED_TTL_MS,
  };
  await writeJson(FEED_FILE, info);
  return info;
}

// ------------------------------------------------------------ manifest 窗口

async function sliceText(info, bytes) {
  // 首页/浅页的窗口（≤128 KB 压缩 ≈ 1.1 MB 文本）缓存起来：清单下载一次要 2 秒上下，
  // 详情、选集、播放都复用同一段窗口，没必要每个入口都重下一次。
  if (bytes <= CACHE_BYTES) {
    var cached = await readJson(WINDOW_FILE);
    if (cached && cached.text && Number(cached.bytes) >= bytes && Date.now() - Number(cached.at) < WINDOW_TTL_MS) {
      return String(cached.text);
    }
  }
  var reply = await LumeSource.http.get(info.url, {
    headers: {
      Range: 'bytes=0-' + (bytes - 1),
      Accept: 'application/json',
      'User-Agent': UA,
    },
  });
  var status = reply ? reply.status : 0;
  if (status !== 200 && status !== 206) throw new Error('清单拉取失败：HTTP ' + status);
  var text = reply && reply.body ? String(reply.body) : '';
  if (bytes <= CACHE_BYTES && text) await writeJson(WINDOW_FILE, { at: Date.now(), bytes: bytes, text: text });
  return text;
}

// 从窗口文本里切出条目 JSON 文本、频道表和总数
function sliceWindow(text, limit) {
  var channels = [];
  var chAt = text.indexOf('"channels":[');
  if (chAt >= 0) {
    var chEnd = text.indexOf(']', chAt);
    if (chEnd > chAt) {
      try {
        channels = JSON.parse(text.slice(chAt + 11, chEnd + 1));
      } catch (error) {
        channels = [];
      }
    }
  }
  var totalMatch = /"count":\s*(\d+)/.exec(text);
  var total = totalMatch ? Number(totalMatch[1]) : 0;

  var chunks = [];
  var at = text.indexOf('"items":[');
  if (at >= 0) {
    var from = at + 9;
    var re = /\},\{"id":"/g;
    re.lastIndex = from;
    var marks = [];
    var matched;
    while ((matched = re.exec(text)) !== null && marks.length < limit * 2 + 8) {
      marks.push(matched.index);
    }
    for (var i = 0; i < marks.length && chunks.length < limit; i++) {
      chunks.push(text.slice(from, marks[i] + 1));
      from = marks[i] + 2;
    }
    // 窗口正好覆盖到数组末尾时，最后一条以 '}' + ']' 收尾，也带上
    if (chunks.length < limit) {
      var tailEnd = text.lastIndexOf('}');
      if (tailEnd > from) {
        var tail = text.slice(from, tailEnd + 1);
        if (tail.indexOf('"id":"') > 0 && text.slice(tailEnd + 1, tailEnd + 3).indexOf(']') === 0) chunks.push(tail);
      }
    }
  }
  return { channels: channels, total: total, chunks: chunks };
}

function parseChunk(chunk) {
  try {
    var item = JSON.parse(chunk);
    return item && item.id ? item : null;
  } catch (error) {
    return null;
  }
}

function isPlayable(item) {
  return !!item && !item.locked && !!item.videoKey;
}

function textOf(item) {
  var tags = Array.isArray(item.tags) ? item.tags.join(' ') : '';
  var channels = Array.isArray(item.channels) ? item.channels.join(' ') : '';
  return (
    String(item.description || '') + ' ' + tags + ' ' + channels + ' ' + String(item.author || '') + ' ' + String(item.id || '')
  ).toLowerCase();
}

function posterUrl(info, item) {
  if (!item || !item.posterKey) return '';
  return base() + info.base + item.posterKey + '?' + info.query;
}

function videoUrl(info, item) {
  if (!item || !item.videoKey) return '';
  return base() + info.base + item.videoKey + '?' + info.query;
}

function mapItem(info, item) {
  if (!item) return null;
  var bits = [];
  if (item.author) bits.push('@' + String(item.author));
  if (item.views) bits.push(Number(item.views) + ' 播放');
  var channels = Array.isArray(item.channels) ? item.channels : [];
  if (channels.length) bits.push(channels[0]);
  var description = String(item.description || '').trim();
  return {
    id: String(item.id),
    title: description ? description.slice(0, 60) : '无标题 · ' + String(item.author || item.id),
    cover: posterUrl(info, item),
    subtitle: bits.join(' · '),
  };
}

// 拉到够 page*size 条可播放的窗口；有频道/关键词过滤时一次要满 MAX_BYTES，并扫更多条
async function loadWindow(need, filtered) {
  var info = await feedInfo(false);
  var bytes = filtered ? MAX_BYTES : Math.max(MIN_BYTES, Math.min(MAX_BYTES, need * BYTES_PER_ITEM));
  var text = await sliceText(info, bytes);
  // 过滤模式下窗口里能有上万条，得多切一些出来才能在过滤后凑满一页
  var limit = filtered ? 4000 : need * 2 + 8;
  var window = sliceWindow(text, limit);
  return { info: info, window: window };
}

async function findItem(id) {
  var info = await feedInfo(false);
  var bytes = MIN_BYTES;
  for (var round = 0; round < 5; round++) {
    var text = await sliceText(info, bytes);
    var window = sliceWindow(text, 4000);
    for (var i = 0; i < window.chunks.length; i++) {
      var item = parseChunk(window.chunks[i]);
      if (item && String(item.id) === String(id)) return { info: info, item: item };
    }
    if (bytes >= MAX_BYTES) break;
    bytes = Math.min(bytes * 2, MAX_BYTES);
  }
  return null;
}

var LumeSource = {
  id: 'betareel_video',
  name: 'BetaTok',
  version: '1.0.0',
  category: 'video',
  contentCategory: 'adult',
  mirrors: ['https://betareel.com'],

  async categories() {
    var list = [{ id: 'all', title: '全部' }];
    try {
      var info = await feedInfo(false);
      var text = await sliceText(info, MIN_BYTES);
      var window = sliceWindow(text, 1);
      var channels = window.channels || [];
      for (var i = 0; i < channels.length; i++) {
        var slug = String(channels[i] || '').trim();
        if (slug) list.push({ id: 'ch:' + slug, title: slug });
      }
    } catch (error) {
      /* 频道拉不到就只给「全部」 */
    }
    return list;
  },

  async home() {
    var boards = [];
    try {
      var loaded = await loadWindow(PAGE_SIZE, false);
      var items = [];
      for (var i = 0; i < loaded.window.chunks.length && items.length < 12; i++) {
        var item = parseChunk(loaded.window.chunks[i]);
        if (!isPlayable(item)) continue;
        var mapped = mapItem(loaded.info, item);
        if (mapped) items.push(mapped);
      }
      if (items.length) boards.push({ title: '最新', moreUrl: 'all', items: items });
    } catch (error) {
      /* 首页失败就交给分类页 */
    }
    return boards;
  },

  async filters() {
    var options = [{ id: '', title: '全部频道' }];
    try {
      var info = await feedInfo(false);
      var text = await sliceText(info, MIN_BYTES);
      var window = sliceWindow(text, 1);
      var channels = (window.channels || []).slice(0, 60);
      for (var i = 0; i < channels.length; i++) {
        var slug = String(channels[i] || '').trim();
        if (slug) options.push({ id: slug, title: slug });
      }
    } catch (error) {
      /* 空筛选即可 */
    }
    return { groups: [{ id: 'channel', title: '频道', options: options }] };
  },

  async list(argument) {
    var args = argument || {};
    var page = Number(args.page || 1);
    if (!page || page < 1) page = 1;
    var keyword = String(args.keyword == null ? '' : args.keyword).trim().toLowerCase();
    var categoryId = String(args.categoryId == null ? '' : args.categoryId).trim();
    var filters = args.filters || {};
    var channel = String(filters.channel || '').trim();
    if (/^ch:/.test(categoryId)) channel = categoryId.slice(3);

    var need = page * PAGE_SIZE;
    var loaded = await loadWindow(Math.min(need, 600), !!channel || !!keyword);
    var info = loaded.info;
    var chunks = loaded.window.chunks;

    var picked = [];
    for (var i = 0; i < chunks.length; i++) {
      var item = parseChunk(chunks[i]);
      if (!isPlayable(item)) continue;
      if (channel) {
        var itemChannels = Array.isArray(item.channels) ? item.channels : [];
        if (itemChannels.indexOf(channel) < 0) continue;
      }
      if (keyword && textOf(item).indexOf(keyword) < 0) continue;
      picked.push(item);
      if (picked.length >= need + PAGE_SIZE) break;
    }

    var start = (page - 1) * PAGE_SIZE;
    var items = [];
    for (var p = start; p < picked.length && items.length < PAGE_SIZE; p++) {
      var mapped = mapItem(info, picked[p]);
      if (mapped) items.push(mapped);
    }
    var hasMore = picked.length > start + PAGE_SIZE || (loaded.window.total > need && !channel && !keyword);
    return { items: items, hasMore: hasMore };
  },

  async detail(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return null;
    var found = await findItem(id);
    if (!found) return null;
    var item = found.item;
    var bits = [];
    if (item.author) bits.push('@' + String(item.author));
    if (item.views) bits.push(Number(item.views) + ' 播放');
    if (item.locked) bits.push('付费锁定');
    var channels = Array.isArray(item.channels) ? item.channels.join(' · ') : '';
    var tags = Array.isArray(item.tags) ? item.tags.join(' ') : '';
    var description = String(item.description || '');
    if (channels) description += (description ? '\n\n' : '') + '频道：' + channels;
    if (tags) description += (description ? '\n' : '') + '标签：' + tags;
    return {
      id: String(item.id),
      title: String(item.description || '').slice(0, 60) || '无标题 · ' + String(item.author || item.id),
      cover: posterUrl(found.info, item),
      subtitle: bits.join(' · '),
      description: description,
    };
  },

  async chapters(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) return [];
    var found = await findItem(id);
    if (!found) return [{ id: 'video', title: '正片' }];
    return [{ id: 'video', title: found.item.locked ? '正片（源站付费）' : '正片' }];
  },

  async content(argument) {
    var id = String((argument && argument.id) || '').trim();
    if (!id) throw new Error('缺少条目 ID');
    var found = await findItem(id);
    if (!found) throw new Error('清单窗口里找不到这条（站点清单太大，只能翻当前窗口内的内容）');
    var item = found.item;
    if (item.locked) {
      throw new Error('这条是源站付费内容（' + (Number(item.price) || 0) + ' 钻石解锁），本源不代下单');
    }
    var url = videoUrl(found.info, item);
    if (!url) throw new Error('这条没有视频地址');
    return { kind: 'video', url: url, headers: { Referer: base() + '/', 'User-Agent': UA } };
  },
};
