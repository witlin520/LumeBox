// LumeSource: {"id":"fakehub_video","name":"FakeHub","version":"1.0.0","category":"video","mirrors":["https://www.fakehub.com"]}
//
// 站点：FakeHub（https://www.fakehub.com，品牌合集站：**PublicAgent（户外搭讪）**、FakeTaxi、FakeHospital、
// FakeAgent 等，全站 18+）。`publicagent.com` 本身只是这个网络的**落地页**（React SPA，全是广告和 /join），
// 真正有免费片源的是 fakehub.com 的场景页 → 所以「户外」这一档用本源覆盖。
//
// 结构（2026-10-25 实测）：
//   · 首页      GET /                         卡片 `<a href="/scene/{id}/{slug}" title="{标题}">`
//   · 全部场景  GET /scenes[?page=N]
//   · 模特页    GET /modelprofile/{id}/{slug}
//   · 场景页    GET /scene/{id}/{slug}        页面里带官方预览 mp4：
//                 https://prog-public-ht.project1content.com/{a/b/c/…}/video/{hash}.mp4   → 实测 206 video/mp4
//   · 封面      media-public-ht.project1content.com/…/poster/poster_01.jpg
//   · 注意      `publicagent.com` 与 `voyeur-house.tv` 都不在这里面：
//               publicagent.com 是纯落地页（无片源）；voyeur-house.tv 是付费摄像头平台（无公开片库）。
var BASE_URL = 'https://www.fakehub.com';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

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
    .replace(/&#0?39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function getText(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  if (status !== 200) throw new Error('FakeHub：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('href="/scene/');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 2500);
    var idMatch = /^(\d+)\/([^"']+)/.exec(block);
    if (!idMatch) continue;
    var id = idMatch[1];
    if (seen[id]) continue;
    var titleMatch = /title="([^"]{2,200})"/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) title = String(idMatch[2]).replace(/-/g, ' ');
    var posterMatch = /srcSet="(https:\/\/media-public-ht\.project1content\.com\/[^"]+)"/.exec(block) ||
      /src="(https:\/\/media-public-ht\.project1content\.com\/[^"]+)"/.exec(block);
    seen[id] = true;
    items.push({
      id: '/scene/' + id + '/' + idMatch[2],
      title: title,
      cover: posterMatch ? posterMatch[1] : '',
      subtitle: ''
    });
  }
  return items;
}

// 场景页里官方预览 mp4
function previewOf(html) {
  var matched = /(https:\/\/prog-public-ht\.project1content\.com\/[^"'\s<>]+\.mp4)/.exec(html);
  return matched ? matched[1] : '';
}

var LumeSource = {
  id: 'fakehub_video',
  name: 'FakeHub',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.fakehub.com'],

  async categories() {
    return [
      { id: 'latest', title: '最新' },
      { id: 'scenes', title: '全部场景' }
    ];
  },

  async home() {
    var html = await getText('/');
    var items = parseItems(html);
    if (!items.length) throw new Error('FakeHub：首页没认出场景（站点可能改版）');
    return [{ title: '最新', moreUrl: 'latest', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'latest';
    var keyword = settings.keyword ? String(settings.keyword).trim().toLowerCase() : '';
    var path = category === 'scenes' ? '/scenes' + (pageNo > 1 ? '?page=' + pageNo : '') : '/';
    var html = await getText(path);
    var items = parseItems(html);
    if (keyword) {
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(keyword) >= 0;
      });
    }
    return { items: items, hasMore: items.length >= 12 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var html = await getText(id);
    var titleMatch = /<h1[^>]*>([\s\S]{0,200}?)<\/h1>/.exec(html) ||
      /<meta[^>]+property="og:title"[^>]+content="([^"]+)"/.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title || /^Likes$/i.test(title) || /LATEST/i.test(title)) {
      // 页面标题常是导航文案，退回 URL 里的 slug
      var slugMatch = /\/scene\/\d+\/([^\/]+)/.exec(id);
      title = slugMatch ? decode(slugMatch[1].replace(/-/g, ' ')) : id;
    }
    var posterMatch = /(https:\/\/media-public-ht\.project1content\.com\/[^"'\s<>]+poster_01\.jpg)/.exec(html);
    var descMatch = /<meta[^>]+name="description"[^>]+content="([^"]*)"/.exec(html);
    return {
      id: absolute(id),
      title: title,
      cover: posterMatch ? posterMatch[1] : '',
      subtitle: '官方预览',
      description: decode(descMatch ? descMatch[1] : '').slice(0, 300)
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return [];
    var html = await getText(id);
    var preview = previewOf(html);
    if (preview) return [{ id: preview, title: '官方预览' }];
    return [{ id: absolute(id), title: '场景页' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id).trim() : '';
    if (chapterId && /\.mp4/i.test(chapterId) && chapterId.indexOf('project1content.com') >= 0) {
      return {
        kind: 'video',
        url: chapterId,
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    if (!id) throw new Error('FakeHub：缺少场景地址');
    var html = await getText(id);
    var preview = previewOf(html);
    if (preview) {
      return {
        kind: 'video',
        url: preview,
        headers: { Referer: absolute(id), 'User-Agent': UA, Accept: '*/*' }
      };
    }
    return { kind: 'webplayer', pageUrl: absolute(id), headers: headers() };
  }
};
