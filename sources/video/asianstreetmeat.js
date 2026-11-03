// LumeSource: {"id":"asm_video","name":"Asian Street Meat","version":"1.0.0","category":"video","mirrors":["https://asianstreetmeat.com"]}
//
// 站点：Asian Street Meat（https://asianstreetmeat.com，东南亚街头题材老牌付费站，全站 18+）
// 性质：**会员站**，公开部分是每个现场的**官方预告片**（trailer）。本源取到的就是 trailer，
//       全片要 /join/ 付费 —— 这点写清楚，不假装有全片。
//
// 结构（2026-10-25 实测）：
//   · 首页      GET /                     首页 1.7MB，直接把每个现场的 <video> 标签铺出来
//   · 场景块    <div class="plastic_movie_v3">
//                 <video poster="https://cdn.streetmeatasia.com/photogroup/{tag}/1200.674.jpg"
//                        title="Street Meat Asia - {名字} - Asian Street Meat">
//                   <source src="https://cdn.streetmeatasia.com/photogroup/{tag}/trailor.mp4" />
//   · 目录      GET /archive.html   /gals/   /updates
//   · 播放      trailer 直链 `https://cdn.streetmeatasia.com/photogroup/{tag}/trailor.mp4`
//               （纯静态 CDN，实测可直接拉；全片在 /join/{tag}/ 后面）
//   · 其它      /join/ 是付费入口，所有场景卡片的「观看」链接都指向它
var BASE_URL = 'https://asianstreetmeat.com';
var CDN = 'https://cdn.streetmeatasia.com';
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
  if (status !== 200) throw new Error('Asian Street Meat：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

// 场景：<video poster="…/{tag}/1200.674.jpg" title="Street Meat Asia - 名字 - Asian Street Meat">
//        <source src="…/{tag}/trailor.mp4">
function parseScenes(html) {
  var items = [];
  var seen = {};
  var pattern = /<video[^>]*poster="([^"]+)"[^>]*title="([^"]*)"[\s\S]{0,400}?<source[^>]*src="([^"]+\.mp4[^"]*)"/g;
  var matched;
  while ((matched = pattern.exec(html)) !== null) {
    var poster = matched[1];
    var title = decode(matched[2]);
    var trailer = matched[3];
    var tagMatch = /\/([^\/]+)\/1200\.674\.jpg/.exec(poster);
    var tag = tagMatch ? tagMatch[1] : '';
    if (!tag || seen[tag]) continue;
    title = title.replace(/^Street Meat Asia\s*-\s*/i, '').replace(/\s*-\s*Asian Street Meat\s*$/i, '').trim();
    if (!title) title = tag;
    seen[tag] = true;
    items.push({
      id: tag,
      title: title,
      cover: poster,
      subtitle: '预告片',
      trailer: trailer
    });
  }
  return items;
}

var LumeSource = {
  id: 'asm_video',
  name: 'Asian Street Meat',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://asianstreetmeat.com'],

  async categories() {
    return [
      { id: 'home', title: '最新现场' },
      { id: 'archive', title: '全部存档' }
    ];
  },

  async home() {
    var html = await getText('/');
    var items = parseScenes(html);
    if (!items.length) throw new Error('Asian Street Meat：首页没认出场景（站点可能改版）');
    return [{ title: '最新现场', moreUrl: 'home', items: items.slice(0, 24) }];
  },

  async list(argument) {
    var settings = argument || {};
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'home';
    var keyword = settings.keyword ? String(settings.keyword).trim().toLowerCase() : '';
    var path = category === 'archive' ? '/archive.html' : '/';
    var html = await getText(path);
    var items = parseScenes(html);
    if (keyword) {
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(keyword) >= 0;
      });
    }
    return { items: items, hasMore: false };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id).trim() : '';
    if (!id) return null;
    // id 是 CDN 上的现场目录名：2019070104.nong.o 这种
    var html = await getText('/');
    var items = parseScenes(html);
    for (var i = 0; i < items.length; i++) {
      if (items[i].id === id) {
        return {
          id: id,
          title: items[i].title,
          cover: items[i].cover,
          subtitle: '官方预告片',
          description: '全片需会员（/join/' + id + '/），本源播放的是站点公开的官方预告片。'
        };
      }
    }
    return {
      id: id,
      title: id,
      cover: CDN + '/photogroup/' + id + '/1200.674.jpg',
      subtitle: '官方预告片',
      description: '全片需会员，本源播放的是站点公开的官方预告片。'
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id).trim() : '';
    if (!id) return [];
    return [{ id: CDN + '/photogroup/' + id + '/trailor.mp4', title: '官方预告片' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    if (chapterId && /\.mp4/i.test(chapterId)) {
      return {
        kind: 'video',
        url: chapterId,
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    var id = argument && argument.id ? String(argument.id).trim() : '';
    if (!id) throw new Error('Asian Street Meat：缺少现场 id');
    return {
      kind: 'video',
      url: CDN + '/photogroup/' + id + '/trailor.mp4',
      headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
    };
  }
};
