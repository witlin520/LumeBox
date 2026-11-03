// LumeSource: {"id":"jiuse91_video","name":"91PORNY 九色","version":"1.0.0","category":"video","mirrors":["https://91porny.com"]}
//
// 站点：91PORNY / 九色（https://91porny.com，中文成人视频站：**国产自拍 + 偷拍 + 麻豆/星空/天美/精东/兔子/蜜桃/SWAG 厂牌 + 日韩AV**，全站 18+）
//
// 结构（2026-10-25 实测，服务端渲染）：
//   · 首页        GET /                       卡片混着两套路由（见下）
//   · 精选列表    GET /vod?page={n}           24 张/页，卡片 → `/vod/view/{slug}`
//   · 厂牌列表    GET /videos/categories/{名}  名：madou / xingkong / jingdong / tianmei / tuzi / swag / mitao / unpixelated / hd
//   · 自拍详情    GET /video/view/{hash}       （首页那批「原创/自拍」走这条）
//   · 厂牌详情    GET /videos/view/{id}/{slug}/
//   · 卡片        <div class="colVideoList"><div class="video-elem">
//                   <a href="/video/view/{hash}" class="display d-block">
//                     <div class="img" style="background-image: url('//int.ucloud165.xyz/thumb/{id}.jpg')">
//                     <small class="layer"> 00:03:36</small></a>
//                   <a class="title ..." href="…">标题</a>
//   · 播放        **必须带 Referer=https://91porny.com/**，否则站点回「非法请求！」。
//                 带 Referer 后页面里就有直链 m3u8，实测：
//                   https://cdn2.jiuse3.cloud/s/{过期时间}/{签名}/hls/{id}/index.m3u8   → 200 application/vnd.apple.mpegurl
//                   https://cdn22.jiuse3.cloud/2026/10/17/{hash}/index.m3u8?t=…&m=…      → 200
//                 签名带过期（`t=`），所以每次播放都重新拉详情页；`&amp;` 要还原成 `&`。
//   · 厂牌详情页   /videos/view/… 的页面 HTML 里**没有** m3u8（播放器走 JS），这类条目退回网页播放器。
var BASE_URL = 'https://91porny.com';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

var STUDIOS = [
  ['madou', '麻豆传媒'], ['xingkong', '星空传媒'], ['tianmei', '天美传媒'],
  ['jingdong', '精东影业'], ['tuzi', '兔子先生'], ['swag', 'SWAG'],
  ['mitao', '蜜桃影像'], ['unpixelated', '无码'], ['hd', '高清']
];

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
    'Accept-Language': 'zh-CN,zh;q=0.9',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function getText(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  if (status !== 200) throw new Error('91PORNY：请求失败 HTTP ' + status + ' ' + url);
  var body = String((response && response.body) || '');
  if (body.indexOf('非法请求') >= 0) throw new Error('91PORNY：被反爬拦了（需要 Referer），换镜像或稍后再试');
  return body;
}

function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('class="video-elem"');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 1200);
    var hrefMatch = /href="((?:https?:\/\/[^"]+)?\/(?:video|videos|vod)\/view\/[^"]+)"/.exec(block);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (seen[href]) continue;
    var titleMatch = /class="title[^"]*"[^>]*>([\s\S]{0,200}?)<\/a>/.exec(block) ||
      /alt="([^"]{2,200})"/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /background-image:\s*url\('([^']+)'\)/.exec(block) || /data-src="([^"]+)"/.exec(block);
    var durMatch = /class="layer"[^>]*>([^<]{0,12})</.exec(block);
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: durMatch ? decode(durMatch[1]) : ''
    });
  }
  return items;
}

var LumeSource = {
  id: 'jiuse91_video',
  name: '91PORNY 九色',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://91porny.com'],

  async categories() {
    var list = [
      { id: 'home', title: '首页' },
      { id: 'vod', title: '精选' }
    ];
    for (var i = 0; i < STUDIOS.length; i++) list.push({ id: 'studio:' + STUDIOS[i][0], title: STUDIOS[i][1] });
    return list;
  },

  async home() {
    var html = await getText('/');
    var items = parseItems(html);
    if (!items.length) throw new Error('91PORNY：首页没认出卡片（站点可能改版）');
    return [{ title: '最新更新', moreUrl: 'home', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'home';
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var path;
    if (keyword) {
      // 站点搜索是前端交互，没有稳定的 GET 入口；这里退成首页本地过滤，不编地址。
      path = '/';
    } else if (category === 'vod') {
      path = '/vod' + (pageNo > 1 ? '?page=' + pageNo : '');
    } else if (category.indexOf('studio:') === 0) {
      path = '/videos/categories/' + category.slice(7) + (pageNo > 1 ? '?page=' + pageNo : '');
    } else {
      path = '/' + (pageNo > 1 ? '?page=' + pageNo : '');
    }
    var html = await getText(path);
    var items = parseItems(html);
    if (keyword) {
      var lower = keyword.toLowerCase();
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(lower) >= 0;
      });
    }
    return { items: items, hasMore: items.length >= 18 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var html = await getText(id);
    var titleMatch = /<title>([\s\S]*?)<\/title>/i.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*-\s*91视频.*$/i, '').replace(/\s*-\s*蝌蚪窝.*$/i, '').trim();
    if (!title) return null;
    var coverMatch = /background-image:\s*url\('([^']+)'\)/.exec(html) ||
      /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/.exec(html);
    var descMatch = /<meta[^>]+name="description"[^>]+content="([^"]*)"/.exec(html);
    return {
      id: absolute(id),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: '视频',
      description: decode(descMatch ? descMatch[1] : '').slice(0, 300)
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return [];
    return [{ id: absolute(id), title: '正片' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id).trim() : '';
    var target = chapterId || id;
    if (!target) throw new Error('91PORNY：缺少视频地址');
    var pageUrl = absolute(target);
    var html = await getText(pageUrl);
    var media = /(https?:\/\/[^"'\s<>]+\.m3u8[^"'\s<>]*)/i.exec(html) ||
      /(https?:\/\/[^"'\s<>]+\.mp4[^"'\s<>]*)/i.exec(html);
    if (media) {
      return {
        kind: 'video',
        url: media[1].replace(/&amp;/g, '&'),
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    // 厂牌详情页（/videos/view/…）播放器走 JS，取不到直链 → 网页播放器
    return { kind: 'webplayer', pageUrl: pageUrl, headers: headers() };
  }
};
