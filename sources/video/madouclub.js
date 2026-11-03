// LumeSource: {"id":"madou_club_video","name":"麻豆社","version":"1.0.0","category":"video","mirrors":["https://madou.club"]}
//
// 站点：麻豆社（https://madou.club，「专注国产剧情中文对白小电影」，全站 18+）
// 性质：**国产厂牌聚合站**（自述「一个收集华人国语成人影片的小破站，所有视频无需下载，在线免费播放」）
//   聚合 30+ 厂牌：麻豆传媒 / 麻豆番外篇 / 麻豆花絮 / HongKongDoll / PsychopornTW / 91制片厂 / 果冻传媒 /
//   蜜桃影像 / 天美传媒 / 皇家华人 / 兔子先生 / 星空无限传媒 / 爱豆 / 麻豆导演系列 / 大象传媒 / 猫爪影像 /
//   精东影业 / 杏吧 / 乐播传媒 / 草莓 / 抖阴 / SA国际传媒 / 起点传媒 / 性视界 / 大鸟十八 / 小鹏奇啪行 …
//
// 结构（2026-10-25 实测，服务端渲染）：
//   · 首页      GET /                     卡片：`<article class="excerpt"><a class="thumbnail" href="https://madou.club/{slug}.html">`
//   · 翻页      GET /page/{n}             （实测 page/2 正常，22 张卡片）
//   · 厂牌      GET /category/{slug}      （slug 是 urlencode 的中文，如 hongkongdoll、%e6%8a%96%e9%98%b4）
//   · 榜单      GET /likes  /week  /month
//   · 卡片      <article class="excerpt excerpt-c5">
//                 <a class="thumbnail" href="…/{slug}.html"><img src="…/thumb.png" data-src="{封面}" class="thumb"></a>
//                 <h2><a href="…">{标题}</a></h2>
//                 <footer>…<span class="post-view">观看(61.61K)</span></footer></article>
//               只认 data-src（src 是占位 thumb.png）。
//   · 详情      GET /{slug}.html          标题 <title>、播放器是 **iframe**：
//                 `<iframe height=720 width=1280 src=https://dash.madou.club/share/{videoId} …>`
//   · 播放      GET https://dash.madou.club/share/{videoId} → 页内脚本：
//                 var m3u8 = '/videos/{videoId}/index.m3u8';
//                 var token = "eyJ…";（**JWT 只有 100 秒有效期**：iat→exp 差 100）
//               → 播放地址 = `https://dash.madou.club` + m3u8 + `?token=` + token
//               实测 **200 application/vnd.apple.mpegurl（4388B）**；**必须现取现用**（过 100 秒就回
//               「对不起，您没有权限」404），所以 content() 每次都重新走 详情 → share → 取 token。
//   · 防盗链      播放器脚本里 antiurl=https://madou.club（parent 必须是本站），本源统一带
//               `Referer: https://madou.club/`。
var BASE_URL = 'https://madou.club';
var DASH_URL = 'https://dash.madou.club';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

// 首页导航里的厂牌（兜底用）
var KNOWN_CATEGORIES = [
  ['madou', '麻豆传媒'], ['91zhizuo', '91制片厂'], ['guodong', '果冻传媒'],
  ['tianmei', '天美传媒'], ['xingkong', '星空无限传媒'], ['jingdong', '精东影业'],
  ['mitao', '蜜桃影像'], ['hongkongdoll', 'HongKongDoll'], ['tuzi', '兔子先生']
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
  if (status !== 200) throw new Error('麻豆社：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('<article class="excerpt');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 1400);
    var hrefMatch = /<a[^>]+class="thumbnail"[^>]+href="([^"]+)"/.exec(block) ||
      /<h2><a[^>]+href="([^"]+)"/.exec(block);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (seen[href]) continue;
    var titleMatch = /<h2><a[^>]*>([\s\S]{0,200}?)<\/a><\/h2>/.exec(block) || /alt="([^"]{2,200})"/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /data-src="([^"]+)"/.exec(block);
    var viewMatch = /class="post-view"[^>]*>([^<]{0,24})</.exec(block);
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: viewMatch ? decode(viewMatch[1]) : ''
    });
  }
  return items;
}

// 详情页 → share iframe 地址
function shareUrlOf(html) {
  var matched = /src=(https:\/\/dash\.madou\.club\/share\/[A-Za-z0-9]+)/.exec(html) ||
    /src="(https:\/\/dash\.madou\.club\/share\/[A-Za-z0-9]+)"/.exec(html);
  return matched ? matched[1] : '';
}

var LumeSource = {
  id: 'madou_club_video',
  name: '麻豆社',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://madou.club'],

  async categories() {
    var list = [
      { id: 'home', title: '首页' },
      { id: 'likes', title: '点赞榜' },
      { id: 'week', title: '7天热门' },
      { id: 'month', title: '30天热门' }
    ];
    try {
      var html = await getText('/');
      var pattern = /href="https:\/\/madou\.club\/category\/([^"]+)"[^>]*>([^<]{1,20})</g;
      var matched;
      var seen = {};
      while ((matched = pattern.exec(html)) !== null) {
        var slug = matched[1];
        var title = decode(matched[2]);
        if (!slug || !title || seen[slug]) continue;
        seen[slug] = true;
        list.push({ id: 'cat:' + slug, title: title });
      }
    } catch (error) {
      for (var i = 0; i < KNOWN_CATEGORIES.length; i++) {
        list.push({ id: 'cat:' + KNOWN_CATEGORIES[i][0], title: KNOWN_CATEGORIES[i][1] });
      }
    }
    return list;
  },

  async home() {
    var html = await getText('/');
    var items = parseItems(html);
    if (!items.length) throw new Error('麻豆社：首页没认出卡片（站点可能改版）');
    return [{ title: '热门推荐', moreUrl: 'home', items: items.slice(0, 22) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'home';
    var keyword = settings.keyword ? String(settings.keyword).trim().toLowerCase() : '';
    var path;
    if (category === 'likes' || category === 'week' || category === 'month') {
      path = '/' + category;
    } else if (category.indexOf('cat:') === 0) {
      path = '/category/' + category.slice(4);
    } else {
      path = '/';
    }
    if (pageNo > 1) path = path.replace(/\/+$/, '') + '/page/' + pageNo;
    var html = await getText(path);
    var items = parseItems(html);
    if (keyword) {
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(keyword) >= 0;
      });
    }
    return { items: items, hasMore: items.length >= 18 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var html = await getText(id);
    var titleMatch = /<title>([\s\S]*?)<\/title>/i.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/-\s*麻豆社\s*$/, '').trim();
    if (!title) return null;
    var coverMatch = /data-src="([^"]+)"/.exec(html) ||
      /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/.exec(html);
    var descMatch = /<meta[^>]+name="description"[^>]+content="([^"]*)"/.exec(html);
    return {
      id: absolute(id),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: '国语剧情',
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
    var pageUrl = absolute(chapterId || id);
    if (!pageUrl) throw new Error('麻豆社：缺少作品地址');
    // 每次都重新走：详情页 → share 页 → m3u8 + token（token 只有 100 秒）
    var detailHtml = await getText(pageUrl);
    var shareUrl = shareUrlOf(detailHtml);
    if (!shareUrl) {
      return { kind: 'webplayer', pageUrl: pageUrl, headers: headers() };
    }
    var shareHtml = await getText(shareUrl);
    var pathMatch = /var\s+m3u8\s*=\s*'([^']+)'/.exec(shareHtml);
    var tokenMatch = /var\s+token\s*=\s*"([^"]+)"/.exec(shareHtml);
    if (!pathMatch) {
      return { kind: 'webplayer', pageUrl: shareUrl, headers: headers() };
    }
    var mediaUrl = DASH_URL + pathMatch[1];
    if (tokenMatch && tokenMatch[1]) mediaUrl = mediaUrl + '?token=' + tokenMatch[1];
    return {
      kind: 'video',
      url: mediaUrl,
      headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
    };
  }
};
