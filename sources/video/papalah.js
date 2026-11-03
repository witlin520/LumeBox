// LumeSource: {"id":"papalah_video","name":"啪啪啦","version":"1.0.0","category":"video","mirrors":["https://www.papalah.com"]}
//
// 站点：啪啪啦（成人视频，PHP 7.4 + Cloudflare 前置，2026-10-25 实测）
//
// 无登录墙：列表 / 详情 / 播放页全部裸访问 200，只发了一个 PHPSESSID 和 country/visit_count 三个
// 无害 cookie（不像 90漫画那样有首访 cookie 闸门），不需要维护 cookie。
//
// 路由：
//   · 列表    /                     最新，20 条/页，翻页 ?page=N（共 2560 页）
//             /hot                 熱門          · /favorite 人氣收藏   · /top 排行榜
//             /tag/{标签}           标签页，翻页同样是 ?page=N
//             /?q={关键词}          搜索（站点 /lib/alljs.js 里 $('.btnSearch').click →
//                                   redirect('./?q='+$('.txtSearch').val())）
//   · 详情    /v/{vid}/{slug}       注意 {vid} 是**播放页 id**（108847），和卡片 <a data-id>
//                                   上的数据库 id（1254105）不是一个东西，本源只用 URL 里的那个。
//
// 列表卡片（服务端直出，懒加载图片）：
//   <div class="col-md-3 col-xs-6 item">
//     <a href="v/108847/{slug}" data-id="1254105" title="标题">
//       <div class="v-thumb-outer">
//         <span class="btn-watch-later" data-id="108847" data-name="标题"
//               data-link="v/108847/{slug}"
//               data-thumb="https://media.aiailah.com/uploads/3b/…jpg" data-duration="01:12">…
//         <picture class="v-thumb">
//           <source data-srcset="…webp" type="image/webp">
//           <img class="v-thumb lazy" data-src="…jpg" src="images/loading.gif" …></picture>
//         <div class="v-duration">01:12</div></div></a>
//     <a href="v/108847/{slug}" …><div class="v-name">标题</div></a>
//   </div>
//   封面在 media.aiailah.com（webp 源 + jpg 兜底），实测裸访问 200，不挑 Referer。
//
// **播放地址是逆出来的（不是 webplayer 兜底）**：
//   详情页把 <video id="my-video"><source src="" type="video/mp4"> 留空，然后在页内一段
//   IIFE 里现场拼回真地址：
//     (function(){
//        const _0da50142 = ["0","https%3A","dd779201",…];   ← 打散成 12 段的字符串碎块
//        const _a6ac7548 = [11,0,6,7,5,10,4,1,9,8,2,3];      ← 还原顺序的置换表
//        let _132532af = '';
//        for (let _ddbfc428 = 0; _ddbfc428 < _a6ac7548.length; _ddbfc428++) {
//            _132532af += _0da50142[_a6ac7548.indexOf(_ddbfc428)];   // 反查下标
//        }
//        let _ae0168d2 = decodeURIComponent(_132532af);
//        _ae0168d2 = _ae0168d2.replace('_b77dd0', '');             ← 抹掉一段噪声尾巴
//        const v = document.getElementById('my-video');
//        v.querySelector('source').src = _ae0168d2;
//     })();
//   即：把字符串数组按「置换表反查」重排 → decodeURIComponent → replace 掉一个噪声片段。
//   实测两种成品都见过：
//     ① 碎块里带 "https%3A" / "media.sslah.com" 的 → 拼出
//        https://media.sslah.com/videos/1e/1edd7792010ba3410dc281fe3b0368b8.mp4（9 MB）
//     ② 碎块里没有主机名（只有 "videos%2" / "F2f%2F2f" 这种）→ 拼出站内相对路径
//        videos/2f/2f94de7ef1f780890e4d10da4dde8b91.mp4，要按页面的
//        <base href="https://www.papalah.com/"> 解析成 https://www.papalah.com/videos/…mp4（77 MB）
//   两种 curl 都取到 206 / video/mp4 / ftypisom 头，**不需要 Referer**。
//   变量名每页随机，所以本源不硬编码名字：正则抓那段 IIFE，把里面的数组按
//   「有引号 = 字符串表 / 纯数字 = 置换表」认出来，再照抄同一套运算（decodeURIComponent
//   + .replace(第一参, 第二参)），最后 resolveMedia() 兼顾绝对 / 相对两种结果。
//   任何一步对不上（改版、或 source 被服务端直填但拿不到主域名）就老老实实退回
//   { kind:'webplayer', pageUrl }，绝不编地址。
//
// 备注：/lib/api.php?method=getRelatedVideos&token=… 之类只用于「换一批推荐」，与播放无关，
// 本源不碰。

var DEFAULT_BASE = 'https://www.papalah.com';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

var FIXED_CATEGORIES = [
  { id: 'latest', title: '最新' },
  { id: 'hot', title: '熱門' },
  { id: 'favorite', title: '人氣收藏' }
];

function base() {
  var domain = LumeSource.config && LumeSource.config.domain ? String(LumeSource.config.domain) : '';
  return (domain || DEFAULT_BASE).replace(/\/+$/, '');
}

function absolute(url) {
  var text = String(url == null ? '' : url).trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  if (text.indexOf('//') === 0) return 'https:' + text;
  if (text.charAt(0) === '/') return base() + text;
  return base() + '/' + text.replace(/^\.\//, '');
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
  };
  for (var key in extra || {}) if (extra[key] != null) result[key] = extra[key];
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
    .replace(/&nbsp;/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function wait(ms) {
  return new Promise(function (resolve) {
    setTimeout(resolve, ms);
  });
}

async function get(target) {
  var url = absolute(target);
  var status = 0;
  for (var attempt = 0; attempt < 3; attempt++) {
    var response = await LumeSource.http.request({
      url: url,
      method: 'GET',
      headers: headers({ Referer: base() + '/' })
    });
    status = response ? response.status : 0;
    var text = String((response && response.body) || '');
    if ((status === 403 || status === 503) && /Just a moment|cf-chl-|challenge-platform/i.test(text)) {
      throw new Error('NEED_WEBVIEW_VERIFY：啪啪啦 被 Cloudflare 挑战页拦住（HTTP ' + status + '），请给本源配代理或走网页视图');
    }
    if (status === 200) return text;
    // 520/521/522/524：Cloudflare 说源站没正常回包，等一会儿再试
    if (status >= 500) {
      await wait(250 + attempt * 350);
      continue;
    }
    throw new Error('啪啪啦 页面打不开：HTTP ' + status + ' ' + url);
  }
  throw new Error('啪啪啦 页面打不开：HTTP ' + status + '（源站抖动，已重试 3 次）' + url);
}

// ------------------------------------------------------------------ 列表解析
function parseCards(pageHtml) {
  var items = [];
  var seen = {};
  var chunks = String(pageHtml).split('class="col-md-3 col-xs-6 item"');
  for (var i = 1; i < chunks.length; i++) {
    var chunk = chunks[i].slice(0, 2500);
    var hrefMatch = /<a href="(?:\.\/)?v\/(\d+)\/([^"]*)"/i.exec(chunk);
    if (!hrefMatch) continue;
    var vid = hrefMatch[1];
    var slug = hrefMatch[2];
    if (seen[vid]) continue;
    var titleMatch = /data-name="([^"]*)"/i.exec(chunk);
    if (!titleMatch) titleMatch = /<div class="v-name">([\s\S]*?)<\/div>/i.exec(chunk);
    if (!titleMatch) titleMatch = /alt="([^"]*)"/i.exec(chunk);
    var title = titleMatch ? decode(titleMatch[1]) : '';
    if (!title) continue;
    var coverMatch = /data-thumb="([^"]*)"/i.exec(chunk) ||
      /<img[^>]*data-src="([^"]+)"/i.exec(chunk) ||
      /<img[^>]*src="([^"]+)"/i.exec(chunk);
    var cover = coverMatch ? decode(coverMatch[1]) : '';
    if (/loading\.gif|blank\./i.test(cover)) cover = '';
    var durationMatch = /class="v-duration">([^<]*)</i.exec(chunk) ||
      /data-duration="([^"]*)"/i.exec(chunk);
    seen[vid] = true;
    items.push({
      id: absolute('v/' + vid + '/' + slug),
      title: title,
      cover: cover ? absolute(cover) : '',
      subtitle: durationMatch ? decode(durationMatch[1]) : ''
    });
  }
  return items;
}

function hasNextPage(pageHtml, pageNo) {
  var pattern = new RegExp('[?&](?:amp;)?page=' + (pageNo + 1) + '(?!\\d)');
  return pattern.test(pageHtml);
}

function tagsOf(pageHtml) {
  var tags = [];
  var seen = {};
  var pattern = /<a href="[^"]*\/tag\/([^"\/]+)"[^>]*title="([^"]*)"/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var name = decode(matched[2]) || decode(matched[1]);
    if (!name || seen[name]) continue;
    seen[name] = true;
    tags.push(name);
  }
  return tags;
}

// ------------------------------------------------------------------ 播放地址还原
function indexOfNumber(list, value) {
  for (var i = 0; i < list.length; i++) if (list[i] === value) return i;
  return -1;
}

// 把页内那段 IIFE 抄一遍：字符串表按置换表反查重排 → decodeURIComponent → replace 噪声
function unfoldVideoUrl(pageHtml) {
  var html = String(pageHtml || '');
  var block = /\(function\s*\(\)\s*\{([\s\S]*?)querySelector\(\s*['"]source['"]\s*\)\.src\s*=[^;]*;/.exec(html);
  if (!block) return '';
  var body = block[1];

  var strings = null;
  var table = null;
  var assignment = /(?:const|let|var)\s+[\w$]+\s*=\s*(\[[\s\S]*?\])\s*;/g;
  var matched;
  while ((matched = assignment.exec(body)) !== null) {
    var raw = matched[1];
    if (/^\s*\[\s*['"]/.test(raw)) {
      if (strings) continue;
      var list = [];
      var quoted = /'([^']*)'|"([^"]*)"/g;
      var piece;
      while ((piece = quoted.exec(raw)) !== null) list.push(piece[1] != null ? piece[1] : piece[2]);
      if (list.length) strings = list;
    } else if (!table) {
      var numbers = raw.match(/-?\d+/g);
      if (numbers && numbers.length) {
        table = [];
        for (var i = 0; i < numbers.length; i++) table.push(Number(numbers[i]));
      }
    }
  }
  if (!strings || !table) return '';

  var joined = '';
  for (var k = 0; k < table.length; k++) {
    var position = indexOfNumber(table, k);
    if (position < 0 || position >= strings.length) continue;
    joined += strings[position];
  }
  if (!joined) return '';

  var url = joined;
  try {
    url = decodeURIComponent(joined);
  } catch (error) {
    url = joined;
  }
  var replaceCall = /\.replace\(\s*'([^']*)'\s*,\s*'([^']*)'\s*\)/.exec(body);
  if (replaceCall && replaceCall[1]) url = url.replace(replaceCall[1], replaceCall[2]);
  if (!/\.(mp4|m3u8|webm|flv)(\?|#|$)/i.test(url)) return '';
  return url;
}

// 拼出来的既可能是绝对地址（碎块里含 "https%3A" → decodeURIComponent 得到
// https://media.sslah.com/videos/1e/….mp4），也可能是**站内相对路径**
// （碎块里没有主机名，"videos%2F2f%2F2f…" → "videos/2f/2f….mp4"），后者要按页面
// 的 <base href="https://www.papalah.com/"> 解析。两种实测都有，都得处理。
function resolveMedia(url, pageHtml) {
  var text = String(url || '').trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) return text;
  var baseMatch = /<base[^>]+href="([^"]+)"/i.exec(String(pageHtml || ''));
  var root = baseMatch ? decode(baseMatch[1]) : base() + '/';
  if (text.charAt(0) === '/') {
    var origin = /^(https?:\/\/[^\/]+)/i.exec(root);
    return (origin ? origin[1] : base()) + text;
  }
  return root.replace(/\/+$/, '') + '/' + text.replace(/^\.\//, '');
}

// 页内已经写好 <source src="…"> 的情况直接拿（有的片服务端直填）
function inlineSource(pageHtml) {
  var matched = /<video[^>]*id="my-video"[\s\S]{0,400}?<source[^>]*src="([^"]*)"/i.exec(pageHtml);
  return matched ? String(matched[1] || '').trim() : '';
}

function mediaHeaders() {
  return {
    Referer: base() + '/',
    'User-Agent': UA,
    Accept: '*/*'
  };
}

function idOf(argument) {
  return argument && argument.id ? String(argument.id).trim() : '';
}

var LumeSource = {
  id: 'papalah_video',
  name: '啪啪啦',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://www.papalah.com'],

  async categories() {
    var list = [];
    for (var i = 0; i < FIXED_CATEGORIES.length; i++) {
      list.push({ id: FIXED_CATEGORIES[i].id, title: FIXED_CATEGORIES[i].title });
    }
    // 标签墙放后面：抓不到就只留三个固定入口，不影响使用
    try {
      var tagHtml = await get('/tag-list');
      var tags = tagsOf(tagHtml).slice(0, 40);
      for (var j = 0; j < tags.length; j++) list.push({ id: 'tag/' + tags[j], title: tags[j] });
    } catch (error) {
      /* 忽略：标签只是锦上添花 */
    }
    return list;
  },

  async home() {
    var boards = [];
    var latest = parseCards(await get('/?page=1'));
    if (latest.length) boards.push({ title: '最新上架', moreUrl: 'latest', items: latest.slice(0, 18) });
    try {
      var hot = parseCards(await get('/hot?page=1'));
      if (hot.length) boards.push({ title: '熱門影片', moreUrl: 'hot', items: hot.slice(0, 18) });
    } catch (error) {
      if (!boards.length) throw error;
    }
    if (!boards.length) throw new Error('啪啪啦：首页没认出条目（站点可能改版）');
    return boards;
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'latest';

    var path;
    if (keyword) {
      path = '/?q=' + encodeURIComponent(keyword) + '&page=' + pageNo;
    } else if (category.indexOf('tag/') === 0) {
      path = '/tag/' + encodeURIComponent(category.slice(4)) + '?page=' + pageNo;
    } else if (category === 'hot' || category === 'favorite') {
      path = '/' + category + '?page=' + pageNo;
    } else {
      path = '/?page=' + pageNo;
    }

    var pageHtml = await get(path);
    var items = parseCards(pageHtml);
    return { items: items, hasMore: items.length > 0 && hasNextPage(pageHtml, pageNo) };
  },

  async detail(argument) {
    var id = idOf(argument);
    if (!id) return null;
    var pageHtml = await get(id);

    var titleMatch = /<meta property="og:title" content="([^"]*)"/i.exec(pageHtml) ||
      /<div class="v-title"[^>]*>([\s\S]*?)<\/div>/i.exec(pageHtml) ||
      /<title>([\s\S]*?)<\/title>/i.exec(pageHtml);
    var title = titleMatch ? decode(titleMatch[1]) : '';
    if (!title) return null;
    title = title.replace(/\s*-\s*免費自拍A片[\s\S]*$/, '').replace(/\s*\|\s*啪啪啦\s*$/, '').trim();

    var coverMatch = /<meta property="og:image" content="([^"]*)"/i.exec(pageHtml) ||
      /<video[^>]*poster="([^"]+)"/i.exec(pageHtml);
    var cover = coverMatch ? absolute(decode(coverMatch[1])) : '';

    var parts = [];
    var duration = /<div class="v-duration">([^<]*)</i.exec(pageHtml);
    if (duration) parts.push(decode(duration[1]));
    var tags = tagsOf(pageHtml).slice(0, 4);
    if (tags.length) parts.push(tags.join(' / '));

    var descMatch = /<meta property="og:description" content="([^"]*)"/i.exec(pageHtml);
    var description = descMatch ? decode(descMatch[1]) : '';

    return {
      id: absolute(id),
      title: title,
      cover: cover,
      subtitle: parts.join(' · '),
      description: description
    };
  },

  async chapters(argument) {
    var id = idOf(argument);
    if (!id) return [];
    // 单片站点：一集「正片」，id 就是详情页地址，content() 从这个页面里还原播放地址
    return [{ id: absolute(id), title: '正片' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var target = chapterId || idOf(argument);
    if (!target) throw new Error('啪啪啦：缺少详情页地址');

    var pageHtml = await get(target);

    var direct = inlineSource(pageHtml);
    if (direct) {
      var directUrl = resolveMedia(direct, pageHtml);
      if (directUrl) return { kind: 'video', url: directUrl, headers: mediaHeaders() };
    }

    var unfolded = unfoldVideoUrl(pageHtml);
    if (unfolded) {
      var url = resolveMedia(unfolded, pageHtml);
      if (url) return { kind: 'video', url: url, headers: mediaHeaders() };
    }

    // 逆不出来就老实交给网页播放器，绝不编地址
    return { kind: 'webplayer', pageUrl: absolute(target), headers: headers({ Referer: base() + '/' }) };
  }
};
