// LumeSource: {"id":"hentai2w","name":"Hentai2W","version":"1.0.0","category":"video","mirrors":["https://hentai2w.com"]}
//
// 站点：Hentai2W（https://hentai2w.com，成人动画 / 番剧流派，RTA 标注 18+）
// 结构：Laravel + Inertia + Vue（Vite 打包）。**没有公开的 vod JSON 接口，但每页都把整份
// 数据塞进 `<script data-page="app" type="application/json">` 里**，所以照常抓 HTML 就能拿到
// 结构化数据（比正则抠 DOM 稳得多）。路由：
//   · 首页    /                        → props.spotlight / newEpisodes / sections
//   · 浏览    /browse?sort=&tags[]=&page=N → props.series（分页，total/last_page/current_page）
//   · 搜索    /search?q=关键词&page=N   → 同上，props.series
//   · 剧集    /series/{slug}            → props.series + props.episodes（选集）
//   · 单集    /watch/{episodeId}        → props.playlist（播放清单地址）
//   · 播放    /stream/{episodeId}/master.m3u8  ← HLS 主清单（实测 200 + #EXTM3U）
//
// 两个必须处理的点：
// 1) **年龄门**：站上所有资源在未过门时会 302 到 /age-gate。过门方式与浏览器一致：
//    GET /age-gate 拿 XSRF-TOKEN + 会话 Cookie → POST /age-gate（带 X-XSRF-TOKEN）→
//    服务端下发 age_confirmed Cookie。脚本把这份 Cookie 缓存在 LumeSource.fs（6 小时），
//    并在返回播放地址时用 headers.Cookie 一并交给播放内核。
// 2) **播放地址按 episodeId 可预测**：/stream/{episodeId}/master.m3u8（已用 3 个不同集验证），
//    所以选集 id 直接就是播放地址，点开即播、不再多发请求。
//
// 注：本站直连会被 Cloudflare 拦，需要给本源配代理（与欧乐 / 华视同理）。
var BASE_URL = 'https://hentai2w.com';
var UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  return (domain || BASE_URL).replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text;
}

function decode(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// 页面里的 Inertia 数据：<script data-page="app" type="application/json">{…}</script>
function propsOf(html) {
  var at = html.indexOf('<script data-page="app"');
  if (at < 0) return null;
  var open = html.indexOf('>', at);
  if (open < 0) return null;
  var close = html.indexOf('</script>', open);
  if (close < 0) return null;
  try {
    var page = JSON.parse(html.slice(open + 1, close));
    return page && page.props ? page.props : null;
  } catch (error) {
    return null;
  }
}

// ---------------------------------------------------------------- Cookie 处理
// 响应头里可能有多条 set-cookie（宿主可能合并成一条，Expires 里还带逗号），
// 所以按「名字=」的边界切，而不是简单按逗号切。
function splitSetCookie(raw) {
  var text = String(raw || '');
  if (!text) return [];
  var parts = text.split(/,(?=\s*[A-Za-z0-9_\-]+=)/);
  return parts;
}

function absorb(jar, response) {
  var raw = [];
  var headers = response && response.headers ? response.headers : {};
  for (var key in headers) {
    if (String(key).toLowerCase() === 'set-cookie') raw.push(String(headers[key]));
  }
  if (response && response.setCookie && response.setCookie.length) {
    for (var i = 0; i < response.setCookie.length; i++) raw.push(String(response.setCookie[i]));
  }
  for (var r = 0; r < raw.length; r++) {
    var rows = splitSetCookie(raw[r]);
    for (var j = 0; j < rows.length; j++) {
      var pair = String(rows[j]).split(';')[0].trim();
      var at = pair.indexOf('=');
      if (at > 0) jar[pair.slice(0, at).trim()] = pair.slice(at + 1).trim();
    }
  }
  return jar;
}

function cookieString(jar) {
  var parts = [];
  for (var key in jar) {
    if (jar[key]) parts.push(key + '=' + jar[key]);
  }
  return parts.join('; ');
}

function headers(cookie, extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/json;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
    Referer: base() + '/'
  };
  if (cookie) result.Cookie = cookie;
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function send(url, options) {
  var settings = options || {};
  var response = await LumeSource.http.request({
    url: /^https?:\/\//i.test(url) ? url : base() + url,
    method: settings.method || 'GET',
    headers: settings.headers || headers(''),
    body: settings.body
  });
  return response;
}

// ---------------------------------------------------------------- 年龄门
var GATE_TTL_MS = 6 * 3600 * 1000;

async function ensureGate() {
  var cached = await LumeSource.fs.readText('gate.json');
  if (cached) {
    try {
      var saved = JSON.parse(cached);
      if (saved && saved.at && Date.now() - saved.at < GATE_TTL_MS && saved.jar && saved.jar.age_confirmed) {
        return saved.jar;
      }
    } catch (error) {
      /* 缓存坏了就重新过门 */
    }
  }
  var jar = {};
  var first = await send('/age-gate');
  absorb(jar, first);
  var xsrf = '';
  try {
    xsrf = decodeURIComponent(jar['XSRF-TOKEN'] || '');
  } catch (error) {
    xsrf = jar['XSRF-TOKEN'] || '';
  }
  // 走 Inertia 的 POST：它回 409（版本不匹配）而不是 302，**409 是最终响应**，
  // 所以 set-cookie 能被脚本读到（表单 POST 会 302 跳走，中间跳转的 Cookie 读不到）。
  var second = await send('/age-gate', {
    method: 'POST',
    headers: headers(cookieString(jar), {
      'Content-Type': 'application/json',
      Accept: 'text/html, application/xhtml+xml',
      'X-Inertia': 'true',
      'X-Inertia-Version': '',
      'X-Requested-With': 'XMLHttpRequest',
      'X-XSRF-TOKEN': xsrf,
      Referer: base() + '/age-gate'
    }),
    body: JSON.stringify({ confirm: true, age: 18 })
  });
  absorb(jar, second);
  if (!jar.age_confirmed) {
    // 退路：传统表单提交（跳转后 Cookie 由宿主会话池接管，脚本侧只能靠宿主自动带）。
    var third = await send('/age-gate', {
      method: 'POST',
      headers: headers(cookieString(jar), {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-XSRF-TOKEN': xsrf,
        Referer: base() + '/age-gate'
      }),
      body: 'confirm=1&age=18'
    });
    absorb(jar, third);
  }
  if (!jar.age_confirmed) {
    throw new Error('Hentai2W 年龄门未通过（拿不到 age_confirmed Cookie）');
  }
  await LumeSource.fs.writeText('gate.json', JSON.stringify({ jar: jar, at: Date.now() }));
  return jar;
}

async function fetchProps(path) {
  var jar = await ensureGate();
  var response = await send(path, { headers: headers(cookieString(jar)) });
  var status = response ? response.status : 0;
  if (status === 403 || status === 503) {
    throw new Error('NEED_WEBVIEW_VERIFY：Hentai2W 触发了 Cloudflare 人机校验（HTTP ' + status + '），请在源设置里走网页视图或给本源配置代理');
  }
  if (status !== 200) throw new Error('Hentai2W 页面打不开：HTTP ' + status + ' ' + path);
  var props = propsOf(response.body || '');
  if (props) {
    absorb(jar, response);
    return { props: props, jar: jar };
  }
  // 会话过期 → 重新过门再试一次
  await LumeSource.fs.remove('gate.json');
  var retryJar = await ensureGate();
  var retry = await send(path, { headers: headers(cookieString(retryJar)) });
  var retryProps = retry && retry.status === 200 ? propsOf(retry.body || '') : null;
  if (!retryProps) {
    throw new Error('Hentai2W 页面结构变了：' + path + ' 里没有 Inertia 数据（可能需要重新过年龄门）');
  }
  absorb(retryJar, retry);
  return { props: retryProps, jar: retryJar };
}

// ---------------------------------------------------------------- 数据映射
function tagNames(tags) {
  if (Array.isArray(tags)) {
    return tags
      .map(function (tag) {
        return typeof tag === 'string' ? tag : tag && (tag.name || tag.slug) ? String(tag.name || tag.slug) : '';
      })
      .filter(function (name) {
        return !!name;
      });
  }
  return [];
}

function itemOf(row) {
  if (!row || !row.slug) return null;
  var subtitleParts = [];
  if (row.episodes_count) subtitleParts.push(Number(row.episodes_count) + ' 集');
  if (row.rating_avg) subtitleParts.push('★ ' + row.rating_avg);
  var tags = tagNames(row.tags);
  if (tags.length) subtitleParts.push(tags.slice(0, 2).join('/'));
  return {
    id: base() + '/series/' + row.slug,
    title: decode(row.title || ''),
    cover: absolute(row.cover_url || ''),
    subtitle: subtitleParts.join(' · ')
  };
}

function itemsOf(rows) {
  var items = [];
  for (var i = 0; i < (rows || []).length; i++) {
    var item = itemOf(rows[i]);
    if (item) items.push(item);
  }
  return items;
}

function slugOf(id) {
  var text = String(id == null ? '' : id).trim();
  var matched = /\/series\/([^/?#]+)/.exec(text);
  if (matched) return matched[1];
  if (/^https?:\/\//i.test(text)) return '';
  return text.replace(/^\/+/, '');
}

var SORTS = [
  { id: 'sort:new', title: '最新', sort: 'new' },
  { id: 'sort:popular', title: '热门', sort: 'popular' },
  { id: 'sort:rating', title: '评分', sort: 'rating' },
  { id: 'sort:title', title: '名称', sort: 'title' }
];

var LumeSource = {
  id: 'hentai2w',
  name: 'Hentai2W',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://hentai2w.com'],

  async categories() {
    var cached = await LumeSource.fs.readText('classes.json');
    if (cached) {
      try {
        var hit = JSON.parse(cached);
        if (hit && hit.length) return hit;
      } catch (error) {
        /* 缓存坏了就重抓 */
      }
    }
    var list = [];
    for (var i = 0; i < SORTS.length; i++) list.push({ id: SORTS[i].id, title: SORTS[i].title });
    try {
      var page = await fetchProps('/browse');
      var groups = page.props.tagGroups || {};
      var genres = groups.genre || [];
      for (var g = 0; g < genres.length && g < 24; g++) {
        var row = genres[g];
        if (!row || !row.slug || !row.name) continue;
        list.push({ id: 'tag:' + row.slug, title: '类型 · ' + decode(row.name) });
      }
    } catch (error) {
      /* 拿不到标签就用排序项，不影响浏览 */
    }
    if (list.length) await LumeSource.fs.writeText('classes.json', JSON.stringify(list));
    return list;
  },

  async home() {
    var page = await fetchProps('/');
    var props = page.props;
    var boards = [];

    var spotlight = itemsOf(props.spotlight);
    if (spotlight.length) boards.push({ title: '精选推荐', items: spotlight.slice(0, 18) });

    var fresh = [];
    var episodes = props.newEpisodes || [];
    for (var i = 0; i < episodes.length; i++) {
      var episode = episodes[i];
      var series = episode && episode.series;
      if (!series || !series.slug) continue;
      fresh.push({
        id: base() + '/series/' + series.slug,
        title: decode(series.title || '') + (episode.title ? ' · ' + decode(episode.title) : ''),
        cover: absolute(episode.thumbnail_url || series.cover_url || '')
      });
    }
    if (fresh.length) boards.push({ title: '最近更新', moreUrl: 'sort:new', items: fresh.slice(0, 18) });

    var sections = props.sections || [];
    for (var s = 0; s < sections.length && boards.length < 4; s++) {
      var section = sections[s];
      var items = itemsOf(section.series);
      if (items.length) {
        boards.push({ title: decode(section.title || '推荐'), moreUrl: 'sort:new', items: items.slice(0, 18) });
      }
    }
    return boards;
  },

  async list(argument) {
    var pageNo = argument && argument.page ? Number(argument.page) : 1;
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = argument && argument.keyword ? String(argument.keyword).trim() : '';
    var category = argument && argument.categoryId ? String(argument.categoryId).trim() : '';
    var path;
    if (keyword) {
      path = '/search?q=' + encodeURIComponent(keyword) + '&page=' + pageNo;
    } else if (category.indexOf('tag:') === 0) {
      path = '/browse?tags[]=' + encodeURIComponent(category.slice(4)) + '&page=' + pageNo;
    } else if (category.indexOf('sort:') === 0) {
      path = '/browse?sort=' + encodeURIComponent(category.slice(5)) + '&page=' + pageNo;
    } else {
      path = '/browse?page=' + pageNo;
    }
    var page = await fetchProps(path);
    var box = page.props.series || {};
    var rows = Array.isArray(box.data) ? box.data : Array.isArray(box) ? box : [];
    var current = Number(box.current_page || pageNo);
    var last = Number(box.last_page || current);
    return { items: itemsOf(rows), hasMore: rows.length > 0 && current < last };
  },

  async detail(argument) {
    var slug = slugOf(argument && argument.id);
    if (!slug) return null;
    var page = await fetchProps('/series/' + encodeURIComponent(slug));
    var series = page.props.series;
    if (!series || !series.title) return null;
    var tags = tagNames(series.tags);
    var episodes = page.props.episodes || [];
    var subtitleParts = [];
    if (episodes.length) subtitleParts.push(Number(episodes.length) + ' 集');
    if (tags.length) subtitleParts.push(tags.slice(0, 3).join(' / '));
    if (series.release_year) subtitleParts.push(String(series.release_year));
    var description = decode(series.description || '');
    if (description === 'Nothing yet!') description = '';
    return {
      id: base() + '/series/' + series.slug,
      title: decode(series.title),
      cover: absolute(series.cover_url || ''),
      subtitle: subtitleParts.join(' · '),
      description: description
    };
  },

  async chapters(argument) {
    var slug = slugOf(argument && argument.id);
    if (!slug) return [];
    var page = await fetchProps('/series/' + encodeURIComponent(slug));
    var episodes = page.props.episodes || [];
    var chapters = [];
    for (var i = 0; i < episodes.length; i++) {
      var episode = episodes[i];
      if (!episode || !episode.id) continue;
      // 播放地址按 episodeId 可预测（已实测），选集 id 直接就是 m3u8，点开即播。
      chapters.push({
        id: base() + '/stream/' + episode.id + '/master.m3u8',
        title: decode(episode.title || '') || '第 ' + (episode.number || i + 1) + ' 集'
      });
    }
    if (!chapters.length) throw new Error('这部剧没有可播放的选集：' + slug);
    return chapters;
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id) : '';
    var target = chapterId;
    if (target && target.indexOf('/watch/') >= 0) {
      var watchId = /\/watch\/(\d+)/.exec(target);
      target = watchId ? base() + '/stream/' + watchId[1] + '/master.m3u8' : '';
    }
    if (!target) {
      var slug = slugOf(id);
      if (!slug) throw new Error('缺少播放地址');
      var page = await fetchProps('/series/' + encodeURIComponent(slug));
      var episodes = page.props.episodes || [];
      if (!episodes.length || !episodes[0].id) throw new Error('这部剧没有可播放的选集：' + slug);
      target = base() + '/stream/' + episodes[0].id + '/master.m3u8';
    }
    if (!/\.(m3u8|mp4|flv|mpd)(\?|#|$)/i.test(target)) {
      return { kind: 'webplayer', pageUrl: absolute(target), headers: headers('') };
    }
    var jar = await ensureGate();
    var cookie = cookieString(jar);
    // 顺手探一次播放清单：能拿到 #EXTM3U 就交给原生播放内核（把年龄门 Cookie 一起带过去）。
    var probe = await send(target, {
      headers: headers(cookie, { Accept: 'application/vnd.apple.mpegurl,*/*', Referer: base() + '/' })
    });
    var body = probe && probe.body ? String(probe.body) : '';
    if (probe && probe.status === 200 && body.indexOf('#EXTM3U') >= 0) {
      return {
        kind: 'video',
        url: target,
        headers: { Referer: base() + '/', 'User-Agent': UA, Cookie: cookie }
      };
    }
    // 没过门或被拦：交给网页播放器（带着会话 Cookie 打开单集页）。
    var watchPage = base() + '/watch/' + (/\/stream\/(\d+)\//.exec(target) || ['', ''])[1];
    return {
      kind: 'webplayer',
      pageUrl: watchPage,
      headers: { Referer: base() + '/', 'User-Agent': UA, Cookie: cookie }
    };
  }
};
