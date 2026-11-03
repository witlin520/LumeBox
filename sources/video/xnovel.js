// LumeSource: {"id":"xnovel_audiobook","name":"夜读小说听书","version":"1.0.0","category":"video","group":"听书","mirrors":["https://x-novel.com"]}
//
// 站点：夜读小说（https://x-novel.com，成人小说站，全站 18+；与 xChina 共用 upload.xchina.io 音频 CDN）
// 本源专门做**有声小说**那一路（就是 https://x-novel.com/tag/audio 这个标签页）。
//
// 结构（2026-10-25 逐页实测，全部走本机代理出口）：
//   · 有声列表  /tag/audio[/{页}]             第 1 页不带页码，第 2 页 /tag/audio/2（60 页）
//   · 排序      /tag/audio?sort=hot|rating|comment|words（翻页叠成 /tag/audio/2?sort=hot）
//   · 全部小说  /novels[/{页}]                同一套卡片，只是没有 🎧 角标
//   · 搜索      /search?q={关键词}[&page=N]   服务端渲染结果，24 条/页
//   · 卡片      <a href="/novel/{slug}" class="list-card" title="标题" data-novel-id="{书号}">
//                 <span class="list-card-chapter-pill">4章</span>
//                 <img src="/assets/cover/{书号}.webp">
//                 <div class="tooltip-meta">4 章 · 1.9万字</div>
//                 <div class="list-card-title">标题</div> <div class="list-card-author">作者</div>
//                 <div class="list-card-series">系列</div>
//                 有声条目多一个 <span class="list-card-audio-badge">🎧</span>
//   · 详情      /novel/{slug}                 h1.tk-h1 标题、og:image 封面、og:description 简介、
//                                             「作者：/系列：/章节：N 章」三行元信息、
//                                             章节目录在 #preview-mobile-chapters-modal 的 <ul> 里
//                                             （每条 <a href="/novel/{slug}/{n}"><span>第 N 章</span><span>上</span></a>）
//   · 播放      /novel/{slug}/{n}?mode=audio → <audio id="audio-player" src="https://upload.xchina.io/mp3/{书号}/{n}.mp3">
//               实测 206 + audio/mpeg，**带不带 Referer 都能播**、无签名无加密；
//               路径按书号+章序可预测，但脚本仍以页面里的 <audio src> 为准（不猜）。
//   · 没有配音的普通小说：章节页里没有 <audio> → 直接报「这一章没有语音版」。App 没有文字小说阅读器，
//     取文字过来是死数据，所以**不返回 kind:'text'**（2026-10-25 按用户口径改）。
var BASE_URL = 'https://x-novel.com';
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
    .replace(/&#0?39;/g, "'")
    .replace(/&#(\d+);/g, function (all, code) {
      return String.fromCharCode(Number(code));
    })
    .replace(/&nbsp;/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function headers(extra) {
  var result = {
    'User-Agent': UA,
    Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    Referer: base() + '/'
  };
  for (var key in extra || {}) result[key] = extra[key];
  return result;
}

async function fetchPage(target) {
  var url = /^https?:\/\//i.test(target) ? target : base() + (String(target).charAt(0) === '/' ? target : '/' + target);
  var response = await LumeSource.http.get(url, { headers: headers() });
  var status = response ? response.status : 0;
  var text = String((response && response.body) || '');
  // 注意：正常页面里也会有 Cloudflare 的 /cdn-cgi/challenge-platform/scripts/jsd/main.js 探针，
  // 所以不能拿 challenge-platform 当被拦信号，只认挑战页自己的特征（短页面 + 这些文案）。
  if (status === 403 || status === 503 || status === 521 ||
      (text.length < 60000 && /cf-chl-|Just a moment|Attention Required|<title>\s*请稍候/i.test(text))) {
    throw new Error('NEED_WEBVIEW_VERIFY：夜读小说被源站 WAF 拦住（HTTP ' + status + '），请给本源配代理或在源设置里走网页视图');
  }
  if (status !== 200) throw new Error('夜读小说页面打不开：HTTP ' + status + ' ' + url);
  return { html: text, url: url };
}

// 列表页卡片：<a href="/novel/{slug}" class="list-card" title="…"> … </a>
function parseItems(pageHtml) {
  var items = [];
  var seen = {};
  var pattern = /<a\b([^>]*)>([\s\S]{0,1600}?)<\/a>/g;
  var matched;
  while ((matched = pattern.exec(pageHtml)) !== null) {
    var attrs = matched[1];
    if (attrs.indexOf('list-card') < 0) continue;
    var hrefMatch = /href="(\/novel\/[a-z0-9]+)"/i.exec(attrs);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (seen[href]) continue;
    var body = matched[2];
    var titleMatch = /title="([^"]*)"/i.exec(attrs) || /class="list-card-title"[^>]*>([\s\S]*?)<\/div>/i.exec(body);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /<img[^>]+src="([^"]+)"/i.exec(body);
    var authorMatch = /class="list-card-author"[^>]*>([\s\S]*?)<\/div>/i.exec(body);
    var seriesMatch = /class="list-card-series"[^>]*>([\s\S]*?)<\/div>/i.exec(body);
    var metaMatch = /class="tooltip-meta"[^>]*>([\s\S]*?)<\/div>/i.exec(body);
    var parts = [];
    if (body.indexOf('list-card-audio-badge') >= 0) parts.push('🎧 有声');
    if (metaMatch) parts.push(decode(metaMatch[1]));
    if (authorMatch && decode(authorMatch[1])) parts.push(decode(authorMatch[1]));
    if (seriesMatch && decode(seriesMatch[1])) parts.push('系列 · ' + decode(seriesMatch[1]));
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: absolute(coverMatch ? coverMatch[1] : ''),
      subtitle: parts.join(' · ')
    });
  }
  return items;
}

function hasNextPage(pageHtml) {
  return /<a[^>]+href="[^"]*"[^>]*>\s*下一页/.test(pageHtml) || /rel="next"/.test(pageHtml);
}

// 分类：有声三档排序 + 全部小说（都走站内自己的列表页，不拼参数假地址）
var CATEGORIES = [
  { id: 'audio', title: '有声小说', path: '/tag/audio' },
  { id: 'audio:hot', title: '有声 · 最热', path: '/tag/audio?sort=hot' },
  { id: 'audio:rating', title: '有声 · 好评', path: '/tag/audio?sort=rating' },
  { id: 'audio:words', title: '有声 · 字数', path: '/tag/audio?sort=words' },
  { id: 'new', title: '全部小说', path: '/novels' }
];

function listPath(categoryId, pageNo) {
  var found = null;
  for (var i = 0; i < CATEGORIES.length; i++) {
    if (CATEGORIES[i].id === categoryId) found = CATEGORIES[i];
  }
  var item = found || CATEGORIES[0];
  var query = '';
  var path = item.path;
  var mark = path.indexOf('?');
  if (mark >= 0) {
    query = path.slice(mark);
    path = path.slice(0, mark);
  }
  if (pageNo > 1) path = path + '/' + pageNo;
  return path + query;
}

function slugOf(id) {
  var matched = /\/novel\/([a-z0-9]+)/i.exec(String(id || ''));
  if (matched) return matched[1];
  return '';
}

// 章节目录只认「章节目录」弹窗里那段 <ul>，别把导航栏的「📖 阅读 / 🎧 听书」按钮当章节。
function chapterRegion(pageHtml) {
  var start = pageHtml.indexOf('preview-mobile-chapters-title');
  if (start < 0) return pageHtml;
  var end = pageHtml.indexOf('</ul>', start);
  return pageHtml.slice(start, end < 0 ? Math.min(pageHtml.length, start + 200000) : end);
}

// 章节目录：/novel/{slug}/{n} 里的「第 N 章 + 章名」
function chaptersOf(pageHtml, slug) {
  var chapters = [];
  var seen = {};
  var region = chapterRegion(pageHtml);
  var pattern = new RegExp('<a[^>]+href="/novel/' + slug + '/(\\d+)"[^>]*>([\\s\\S]{0,300}?)</a>', 'g');
  var matched;
  while ((matched = pattern.exec(region)) !== null) {
    var number = matched[1];
    var inner = matched[2];
    var spans = inner.match(/<span[^>]*>([\s\S]*?)<\/span>/g) || [];
    var label = '';
    var name = '';
    if (spans.length) label = decode(spans[0].replace(/<[^>]+>/g, ''));
    if (spans.length > 1) name = decode(spans[spans.length - 1].replace(/<[^>]+>/g, ''));
    if (label && !/第\s*\d+\s*章|序章|楔子|后记|番外|尾声/.test(label)) {
      // 不是章节标签（例如按钮文案）：把 label 当名字，标题回落到章序
      name = label;
      label = '';
    }
    var title = label || '第 ' + number + ' 章';
    if (name && name !== label) title = title + ' · ' + name;
    var id = base() + '/novel/' + slug + '/' + number;
    if (seen[id]) continue;
    seen[id] = true;
    chapters.push({ id: id, title: title });
  }
  return chapters;
}

// 正文（没有配音的章节用）：<article id="read-article"> 里的段落
function textOf(pageHtml) {
  var start = pageHtml.indexOf('id="read-article"');
  if (start < 0) return '';
  var end = pageHtml.indexOf('</article>', start);
  var block = pageHtml.slice(start, end < 0 ? Math.min(pageHtml.length, start + 400000) : end);
  var parts = [];
  var pattern = /<p[^>]*>([\s\S]*?)<\/p>/gi;
  var matched;
  while ((matched = pattern.exec(block)) !== null) {
    var line = decode(matched[1]);
    if (line) parts.push(line);
  }
  return parts.join('\n\n');
}

function mediaHeaders() {
  return { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' };
}

async function chapterPage(slug, number) {
  var url = base() + '/novel/' + slug + '/' + number + '?mode=audio';
  return fetchPage(url);
}

var LumeSource = {
  id: 'xnovel_audiobook',
  name: '夜读小说听书',
  version: '1.0.0',
  category: 'video',
  group: '听书',
  mirrors: ['https://x-novel.com'],

  async categories() {
    var list = [];
    for (var i = 0; i < CATEGORIES.length; i++) list.push({ id: CATEGORIES[i].id, title: CATEGORIES[i].title });
    return list;
  },

  async home() {
    var boards = [];
    var plans = [
      { path: listPath('audio', 1), title: '有声小说 · 最新', more: 'audio' },
      { path: listPath('audio:hot', 1), title: '有声小说 · 最热', more: 'audio:hot' },
      { path: listPath('new', 1), title: '最新小说', more: 'new' }
    ];
    for (var i = 0; i < plans.length; i++) {
      try {
        var page = await fetchPage(plans[i].path);
        var items = parseItems(page.html);
        if (items.length) boards.push({ title: plans[i].title, moreUrl: plans[i].more, items: items.slice(0, 24) });
      } catch (error) {
        if (i === 0) throw error;
      }
    }
    if (!boards.length) throw new Error('夜读小说：首页没认出条目（站点可能改版）');
    return boards;
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var keyword = settings.keyword ? String(settings.keyword).trim() : '';
    var category = settings.categoryId ? String(settings.categoryId).trim() : '';
    if (keyword) {
      // 站点搜索：/search?q=…&page=N（服务端渲染，结果页也有 🎧 角标可判断是否有配音）
      var target = '/search?q=' + encodeURIComponent(keyword) + (pageNo > 1 ? '&page=' + pageNo : '');
      var result = await fetchPage(target);
      return { items: parseItems(result.html), hasMore: hasNextPage(result.html) };
    }
    var page = await fetchPage(listPath(category || 'audio', pageNo));
    return { items: parseItems(page.html), hasMore: hasNextPage(page.html) };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    var slug = slugOf(id);
    if (!slug) return null;
    var page = await fetchPage('/novel/' + slug);
    var html = page.html;
    var titleMatch = /<h1[^>]*class="[^"]*tk-h1[^"]*"[^>]*>([\s\S]*?)<\/h1>/i.exec(html) || /<title>([\s\S]*?)<\/title>/i.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*[-|｜].*$/, '').trim();
    if (!title) return null;
    var coverMatch = /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i.exec(html);
    var descMatch = /<meta[^>]+property="og:description"[^>]+content="([^"]*)"/i.exec(html);
    var authorMatch = /作者：<\/span>[\s\S]{0,200}?>([^<]{1,40})</.exec(html);
    var seriesMatch = /系列：<\/span>[\s\S]{0,200}?>([^<]{1,60})</.exec(html);
    var countMatch = /章节：<\/span>[\s\S]{0,200}?([\d]+\s*章)/.exec(html);
    var audio = /<span[^>]*list-card-audio-badge|<audio[^>]+src="/.test(html) || /听书/.test(html);
    var parts = [];
    if (audio) parts.push('🎧 有声');
    if (authorMatch) parts.push('作者 · ' + decode(authorMatch[1]));
    if (seriesMatch) parts.push('系列 · ' + decode(seriesMatch[1]));
    if (countMatch) parts.push(decode(countMatch[1]));
    return {
      id: base() + '/novel/' + slug,
      title: title,
      cover: absolute(coverMatch ? coverMatch[1] : ''),
      subtitle: parts.join(' · '),
      description: decode(descMatch ? descMatch[1] : '')
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    var slug = slugOf(id);
    if (!slug) return [];
    var page = await fetchPage('/novel/' + slug);
    var chapters = chaptersOf(page.html, slug);
    if (!chapters.length) throw new Error('这本书没有可读章节：' + slug);
    return chapters;
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var slug = slugOf(chapterId || (argument && argument.id));
    var number = null;
    var matched = /\/novel\/[a-z0-9]+\/(\d+)/i.exec(chapterId);
    if (matched) number = matched[1];
    if (!slug || !number) throw new Error('缺少章节地址');
    var page = await chapterPage(slug, number);
    var audioMatch = /<audio[^>]+src="([^"]+)"/i.exec(page.html);
    if (audioMatch) {
      return { kind: 'audio', url: absolute(decode(audioMatch[1])), headers: mediaHeaders() };
    }
    // 没有配音的章节：App 没有文字小说阅读器（用户口径：文字小说取来没用），所以不返回 kind:'text'，
    // 直接给出可诊断的错误；列表里这类作品仍然能看到，只是点开会提示「没有语音版」。
    throw new Error('这一章没有语音版（本站该作品是文字章节，App 不支持文字小说）：' + slug + ' / ' + number);
  }
};
