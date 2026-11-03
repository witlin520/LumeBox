// LumeSource: {"id":"jipian3_video","name":"三级片","version":"1.0.0","category":"video","mirrors":["https://3jipian.cc"]}
//
// 站点：三级片（https://3jipian.cc，标题「当前最热港台三级片/台湾三级片/香港三级片 - 福利看片」，
// 成人影视聚合站：**三级片 + 港台 + 传媒原创 + 素人 + 麻豆/糖心/果冻/天美/星空/蜜桃 + 网黄 + 日韩FC2 + 欧美 + 动漫**，全站 18+）
//
// 结构（2026-10-25 实测，服务端渲染，不用渲染不用解接口）：
//   · 分类        GET /category/cate{N}/           实测 cate13~cate67 共 55 个（传媒原创/素人自摄/麻豆热剧/糖心/果冻/
//                 天使映画/天美/星空/蜜桃/网黄/桥本香菜/刘玥/玩偶姐姐/台北娜娜/柚子猫/日韩/FC2无码/素人AV/JK制服/
//                 家庭禁忌/欧美…/动漫/MMD/性爱教学…）
//   · 翻页        GET /category/cate{N}/{page}/    实测第 2 页 title=「家庭禁忌-第2页」（`?page=2` 无效，别用）
//   · 搜索        GET /search-page/?wd={关键词}    实测 20 条/页
//   · 卡片        <div class="bst-card"><a href="/video/{id}/" aria-label="标题">
//                   <div class="bst-card-cover"><img lazy data-src="{封面}" data-cover="…/loading.jpg">
//                 只认 data-src（data-cover 是占位图）。
//   · 详情        GET /video/{id}/                 标题 <title>、简介 meta[name=description]
//   · 播放        **窗口变量 `window.__ARCHIVE_PLAYER__`**：
//                   {"rawPath":"/video/2026-03-19/20/{vid}/{hash}.m3u8",
//                    "cdnLine":"https://d2qyuoh1tjbp7d.cloudfront.net", "posterImg":"…"}
//                 → 播放地址 = cdnLine + rawPath，实测 **200 application/vnd.apple.mpegurl（49KB）**
//                 该 m3u8 是 **AES-128** 加密（`#EXT-X-KEY:METHOD=AES-128,URI="/keyhome/video.key"`），
//                 密钥实测可取：`https://{cdn}/keyhome/video.key` → 200 / 16 字节（播放器会自己解）。
//   · 图/链       封面走 CloudFront `d2qyuoh1tjbp7d.cloudfront.net`，不带 Referer 也能取。
var BASE_URL = 'https://3jipian.cc';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

// 首页导航里的 55 个分类（实测抓取），留作兜底
var KNOWN_CATEGORIES = [
  ['cate13', '传媒原创'], ['cate14', '素人自摄'], ['cate15', '麻豆热剧'], ['cate16', '糖心系列'],
  ['cate17', '果冻精选'], ['cate18', '天使映画'], ['cate19', '天美热作'], ['cate20', '星空夜欲'],
  ['cate21', '蜜桃诱惑'], ['cate22', '网黄'], ['cate36', '日韩'], ['cate37', '精选推荐'],
  ['cate38', 'FC2无码'], ['cate39', '淫妻母狗'], ['cate40', '中文字幕'], ['cate41', '素人AV'],
  ['cate42', 'JK制服'], ['cate43', '口爆内射'], ['cate44', '师生乱欲'], ['cate45', '御姐足交'],
  ['cate46', '家庭禁忌'], ['cate47', '欧美'], ['cate51', '欧美熟女'], ['cate55', '动漫'],
  ['cate57', 'MMD热舞'], ['cate59', '性爱教学']
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
  if (status !== 200) throw new Error('三级片：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('class="bst-card"');
  for (var i = 1; i < blocks.length; i++) {
    var block = blocks[i].slice(0, 1200);
    var hrefMatch = /href="\/video\/(\d+)\/"/.exec(block);
    if (!hrefMatch) continue;
    var id = hrefMatch[1];
    if (seen[id]) continue;
    var labelMatch = /aria-label="([^"]{2,200})"/.exec(block);
    var title = decode(labelMatch ? labelMatch[1] : '');
    if (!title) {
      var altMatch = /alt="([^"]{2,200})"/.exec(block);
      title = decode(altMatch ? altMatch[1] : '');
    }
    if (!title) continue;
    var coverMatch = /data-src="([^"]+)"/.exec(block);
    seen[id] = true;
    items.push({ id: id, title: title, cover: coverMatch ? absolute(coverMatch[1]) : '', subtitle: '' });
  }
  return items;
}

// __ARCHIVE_PLAYER__ → {cdnLine, rawPath, posterImg}
function archivePlayer(html) {
  var matched = /window\.__ARCHIVE_PLAYER__\s*=\s*(\{[\s\S]{0,4000}?\})\s*;?\s*<\/script>/.exec(html) ||
    /window\.__ARCHIVE_PLAYER__\s*=\s*(\{[\s\S]{0,4000}?\})\s*;\s*\n/.exec(html);
  if (!matched) return null;
  try {
    return JSON.parse(matched[1]);
  } catch (error) {
    return null;
  }
}

var LumeSource = {
  id: 'jipian3_video',
  name: '三级片',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://3jipian.cc'],

  async categories() {
    var list = [{ id: 'home', title: '首页推荐' }];
    try {
      var html = await getText('/');
      var pattern = /<a[^>]+href="\/category\/(cate\d+)\/"[^>]*>([^<]{1,16})<\/a>/g;
      var matched;
      var seen = {};
      while ((matched = pattern.exec(html)) !== null) {
        var id = matched[1];
        var title = String(matched[2]).replace(/[^\u4e00-\u9fa5A-Za-z0-9]/g, '').trim();
        if (!title || title === '更多' || seen[id]) continue;
        seen[id] = true;
        list.push({ id: id, title: title });
      }
    } catch (error) {
      for (var i = 0; i < KNOWN_CATEGORIES.length; i++) {
        list.push({ id: KNOWN_CATEGORIES[i][0], title: KNOWN_CATEGORIES[i][1] });
      }
    }
    if (list.length <= 1) {
      for (var j = 0; j < KNOWN_CATEGORIES.length; j++) {
        list.push({ id: KNOWN_CATEGORIES[j][0], title: KNOWN_CATEGORIES[j][1] });
      }
    }
    return list;
  },

  async home() {
    var html = await getText('/');
    var items = parseItems(html);
    if (!items.length) throw new Error('三级片：首页没认出卡片（站点可能改版）');
    return [{ title: '最新推荐', moreUrl: 'home', items: items.slice(0, 20) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var path;
    if (keyword) {
      path = '/search-page/?wd=' + encodeURIComponent(keyword) + (pageNo > 1 ? '&page=' + pageNo : '');
    } else if (category && /^cate\d+$/.test(category)) {
      path = '/category/' + category + '/' + (pageNo > 1 ? pageNo + '/' : '');
    } else {
      path = '/' + (pageNo > 1 ? 'category/cate37/' + pageNo + '/' : '');
      if (pageNo === 1) path = '/';
    }
    var html = await getText(path);
    var items = parseItems(html);
    return { items: items, hasMore: items.length >= 18 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id).replace(/[^\d]/g, '') : '';
    if (!id) return null;
    var html = await getText('/video/' + id + '/');
    var titleMatch = /<title>([\s\S]*?)<\/title>/i.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*-\s*三级片\s*$/, '').trim();
    if (!title) return null;
    var player = archivePlayer(html);
    var cover = player && player.posterImg ? player.posterImg : '';
    if (!cover) {
      var coverMatch = /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/.exec(html) ||
        /data-src="([^"]+)"/.exec(html);
      cover = coverMatch ? coverMatch[1] : '';
    }
    var descMatch = /<meta[^>]+name="description"[^>]+content="([^"]*)"/.exec(html);
    return {
      id: id,
      title: title,
      cover: cover ? absolute(cover) : '',
      subtitle: '视频',
      description: decode(descMatch ? descMatch[1] : '').slice(0, 300)
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id).replace(/[^\d]/g, '') : '';
    if (!id) return [];
    return [{ id: id, title: '正片' }];
  },

  async content(argument) {
    var id = argument && argument.chapterId ? String(argument.chapterId).replace(/[^\d]/g, '') : '';
    if (!id) id = argument && argument.id ? String(argument.id).replace(/[^\d]/g, '') : '';
    if (!id) throw new Error('三级片：缺少视频 id');
    var pageUrl = base() + '/video/' + id + '/';
    var html = await getText('/video/' + id + '/');
    var player = archivePlayer(html);
    if (player && player.rawPath) {
      var cdn = String(player.cdnLine || '').replace(/\/+$/, '');
      var path = String(player.rawPath);
      var url = /^https?:\/\//i.test(path) ? path : cdn + path;
      return {
        kind: 'video',
        url: url,
        headers: { Referer: pageUrl, 'User-Agent': UA, Accept: '*/*' }
      };
    }
    // 兜底：页面里直接出现 m3u8/mp4 的情况
    var direct = /(https?:\/\/[^"'\s<>]+\.(?:m3u8|mp4)[^"'\s<>]*)/i.exec(html);
    if (direct) {
      return { kind: 'video', url: direct[1].replace(/\\\//g, '/'), headers: { Referer: pageUrl, 'User-Agent': UA, Accept: '*/*' } };
    }
    return { kind: 'webplayer', pageUrl: pageUrl, headers: headers() };
  }
};
