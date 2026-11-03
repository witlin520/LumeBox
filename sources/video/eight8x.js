// LumeSource: {"id":"x8x8_video","name":"8x8x","version":"1.0.0","category":"video","mirrors":["https://1azm0i.qcsw2b5yf.com","https://qnzu16v.u85772s4.com","https://97nasy.uy5qvb.com"]}
//
// 站点：8x8x（成人综合站：**视频 + 小说 + 图库**，全站 18+）
// 域名：`www.8x8x.com` 只是地址发布页；真站是一条条随机子域（跳板），实测可用：
//   1azm0i.qcsw2b5yf.com / qnzu16v.u85772s4.com / 97nasy.uy5qvb.com（同一套页面，标题「8x8x - 首页」）。
//   发布页里还有 o19wxf.988ywq.com（打开只有 348B 跳转桩，没跟到底，所以没进 mirrors）。
//
// 结构（2026-10-25 实测）：
//   · 每个路径先回一个几百字节的桩页，桩页里 `<script src=/assets/app.*.js data-body-url=/tqf9qp/>`，
//     真正的 HTML 在 `data-body-url` 前缀 + 原路径（例如 `/tqf9qp/category/1/`）。
//   · 但**卡片不是服务端渲染的**：首页推荐位是 skeleton，由 `fetch('/json/recommend/rmd_'+rand)` 填充，
//     返回的是 base64url + AES-GCM 的信封（`/js/nal.js` 里的 `decJSON`，密钥在 JS 里现算），
//     沙箱没有 crypto.subtle，端口里也没有可复用的密钥路径 —— 所以本源**不直连接口**，改用 App 的网页渲染。
//   · 渲染后实测：首页 55 张卡片，结构
//       <a href="/vd/{id}/" class="card group">
//         <div class="card-img-wrap"><img class="card-img lazy" data-src="https://9m60vi.9zbtan36.com/p2/{hash}/cover.webp">
//         <div class="card-title">标题</div></a>
//     封面图床固定 `9m60vi.9zbtan36.com`，卡片和播放地址共用同一个 `{hash}`。
//   · 播放：视频条目渲染后页面里能抓到
//       https://{随机}.db9bmbe.com:{port}/v/{hash}/m3u8/index.m3u8  （实测 200，多码率 500kb 子清单）
//     但**主机名每次会话会变**，所以不拼地址，直接从渲染后的 DOM/脚本里取。
//   · 小说：同一批 `/vd/{id}/` 里混着小说条目（渲染后 title 会是「小说列表 - 8x8x」），
//     这种条目在本源里按**有声**处理：页面里找 mp3/m4a/aac/ogg → `kind:'audio'`（App 支持音频，没有文字小说阅读器，所以**绝不返回文字**）；
//     找不到音频就退图片（>=3 张）或网页播放器。视频条目仍返回 `kind:'video'`。
//   · 搜索：站点是 `/search/{关键词}/`（SPA 内部路由），本源不赌它的参数，keyword 走「渲染首页 + 本地过滤」。
var DEFAULT_BASE = 'https://1azm0i.qcsw2b5yf.com';
var MIRRORS = ['https://1azm0i.qcsw2b5yf.com', 'https://qnzu16v.u85772s4.com', 'https://97nasy.uy5qvb.com'];
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
var resolved = '';

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  return (domain || resolved || DEFAULT_BASE).replace(/\/+$/, '');
}

// 镜像探活：配置里换域名后仍然按 config 走；没配置时用缓存的可用镜像
async function ensureBase() {
  var domain = LumeSource.config && LumeSource.config.domain ? LumeSource.config.domain : '';
  if (domain || resolved) return base();
  var cached = await LumeSource.fs.readText('mirror.json');
  if (cached) {
    try {
      var saved = JSON.parse(cached);
      if (saved && saved.base && saved.at && Date.now() - saved.at < 6 * 3600 * 1000) {
        resolved = saved.base;
        return resolved;
      }
    } catch (error) {
      /* 缓存坏了重探 */
    }
  }
  for (var i = 0; i < MIRRORS.length; i++) {
    try {
      var probe = await LumeSource.http.get(MIRRORS[i] + '/', { headers: { 'User-Agent': UA, Accept: 'text/html,*/*;q=0.8' } });
      if (probe && probe.status === 200) {
        resolved = MIRRORS[i];
        await LumeSource.fs.writeText('mirror.json', JSON.stringify({ base: resolved, at: Date.now() }));
        return resolved;
      }
    } catch (error) {
      /* 换下一个 */
    }
  }
  resolved = DEFAULT_BASE;
  return resolved;
}

function decode(text) {
  return String(text == null ? '' : text)
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function render(pathOrUrl) {
  await ensureBase();
  if (!LumeSource.web || typeof LumeSource.web.render !== 'function') {
    throw new Error('NEED_WEBVIEW_VERIFY：8x8x 的列表是 JS 渲染（接口还是 AES-GCM 加密的），必须用 App 的网页渲染/网页视图打开');
  }
  var url = /^https?:\/\//i.test(pathOrUrl) ? pathOrUrl : base() + pathOrUrl;
  var result = await LumeSource.web.render({
    url: url,
    headers: { 'User-Agent': UA, Accept: 'text/html,*/*;q=0.8' },
    timeoutMs: 9000
  });
  var html = result && result.html ? String(result.html) : '';
  if (!html) throw new Error('NEED_WEBVIEW_VERIFY：8x8x 渲染没有返回内容，请在源设置里走网页视图');
  return html;
}

var CATEGORIES = [
  { id: 'home', title: '首页推荐', path: '/' },
  { id: '1', title: '大陆', path: '/category/1/' },
  { id: '2', title: '日韩', path: '/category/2/' },
  { id: '3', title: '欧美', path: '/category/3/' },
  { id: '4', title: '动漫', path: '/category/4/' },
  { id: '5', title: '三级', path: '/category/5/' }
];

function parseCards(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('<a href="/vd/');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 900);
    var idMatch = /^(\d+)\//.exec(block);
    if (!idMatch) continue;
    var id = idMatch[1];
    if (seen[id]) continue;
    var coverMatch = /(?:data-src|src)="(https?:\/\/[^"]+)"/.exec(block);
    var titleMatch = /class="card-title"[^>]*>([\s\S]{0,120}?)</.exec(block) || /alt="([^"]*)"/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    seen[id] = true;
    items.push({ id: id, title: title, cover: coverMatch ? coverMatch[1] : '', subtitle: '' });
  }
  return items;
}

function parseImages(html) {
  var images = [];
  var seen = {};
  var pattern = /<img[^>]+(?:data-src|src)="(https?:\/\/[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"/gi;
  var matched;
  while ((matched = pattern.exec(html)) !== null) {
    var url = matched[1];
    if (/logo|icon|avatar|ad[-_]|banner|placeholder/i.test(url) || seen[url]) continue;
    seen[url] = true;
    images.push(url);
  }
  return images;
}

var LumeSource = {
  id: 'x8x8_video',
  name: '8x8x',
  version: '1.0.0',
  category: 'video',
  mirrors: MIRRORS,

  async categories() {
    var list = [];
    for (var i = 0; i < CATEGORIES.length; i++) list.push({ id: CATEGORIES[i].id, title: CATEGORIES[i].title });
    return list;
  },

  async home() {
    var html = await render('/');
    var items = parseCards(html);
    if (!items.length) throw new Error('8x8x：渲染后的首页没认出卡片（站点可能改版或换了跳板域）');
    return [{ title: '首页推荐', moreUrl: 'home', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';
    var keyword = settings.keyword ? String(settings.keyword).trim().toLowerCase() : '';
    var spec = null;
    for (var i = 0; i < CATEGORIES.length; i++) if (CATEGORIES[i].id === category) spec = CATEGORIES[i];
    var path = spec ? spec.path : '/';
    if (pageNo > 1 && path !== '/') path = path.replace(/\/$/, '') + '/page/' + pageNo + '/';
    var html = await render(path);
    var items = parseCards(html);
    if (keyword) {
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(keyword) >= 0;
      });
    }
    return { items: items, hasMore: pageNo < 200 && items.length > 0 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id).replace(/[^\d]/g, '') : '';
    if (!id) return null;
    var html = await render('/vd/' + id + '/');
    var titleMatch = /<title>([\s\S]*?)<\/title>/i.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*-\s*8x8x\s*$/i, '').trim();
    if (!title) title = '作品 ' + id;
    var coverMatch = /(?:data-src|src)="(https?:\/\/[^"]+\/cover\.webp[^"]*)"/.exec(html);
    var kind = /\.m3u8|video-js|<video/i.test(html) ? '视频' : /小说/.test(title) ? '小说' : '图文';
    return {
      id: id,
      title: title,
      cover: coverMatch ? coverMatch[1] : '',
      subtitle: kind,
      description: ''
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id).replace(/[^\d]/g, '') : '';
    if (!id) return [];
    return [{ id: id, title: '正文' }];
  },

  async content(argument) {
    var id = argument && argument.chapterId ? String(argument.chapterId).replace(/[^\d]/g, '') : '';
    if (!id) id = argument && argument.id ? String(argument.id).replace(/[^\d]/g, '') : '';
    if (!id) throw new Error('8x8x：缺少条目 id');
    var pageUrl = base() + '/vd/' + id + '/';
    var html = await render('/vd/' + id + '/');

    var media = /(https?:\/\/[^"'\s<>]+\.m3u8[^"'\s<>]*)/i.exec(html);
    if (media) {
      return {
        kind: 'video',
        url: media[1].replace(/&amp;/g, '&'),
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    // 有声小说：站内的“小说”条目其实是**有声**（App 支持 kind:'audio'；文字小说 App 没阅读器，取来没用）
    var audio = /(https?:\/\/[^"'\s<>]+\.(?:mp3|m4a|aac|ogg)(?:\?[^"'\s<>]*)?)/i.exec(html);
    if (audio) {
      return {
        kind: 'audio',
        url: audio[1].replace(/&amp;/g, '&'),
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    var images = parseImages(html);
    if (images.length >= 3) {
      return { kind: 'images', images: images, headers: { Referer: base() + '/', 'User-Agent': UA } };
    }
    return { kind: 'webplayer', pageUrl: pageUrl, headers: { Referer: base() + '/', 'User-Agent': UA } };
  }
};
