// LumeSource: {"id":"artofzoo_video","name":"ArtOfZoo","version":"1.0.0","category":"video","mirrors":["https://artofzoo.com","https://www.artofzoo.com"]}
//
// 站点：ArtOfZoo（https://artofzoo.com，"Home of Animal Porn"，成人 zoo 题材影视品牌站，全站 18+）
// 来历：老品牌 `zooskool.com` 现在直接 302 到 artofzoo.com（两套片库并到一家）。
// 性质：**WordPress + WooCommerce 商店**，不是 tube —— 正片卖钱，页面上公开的是**官方预告片**。
//   所以本源取到的是「商品列表 + 官方 trailer」，这点写在明面上，不做"假装有全片"。
//
// 结构（2026-10-25 实测）：
//   · 商店      GET /animal-porn-shop/            15 个商品/页，分页 /animal-porn-shop/page/{n}/ （实测到 page/10）
//   · 新闻      GET /animal-porn-blog/  →  文章 /animal-porn-news/{slug}/
//   · 卡片      <a href="https://artofzoo.com/animal-porn-shop/{slug}/" class="entry-link-mask"></a>
//               <h2 class="entry-title">标题</h2>
//               <img … data-src="{封面}"（src 是 blank.gif 占位，只认 data-src）>
//   · 详情      GET /animal-porn-shop/{slug}/      标题 h1、加购按钮、描述
//   · 播放      <video class="wp-video-shortcode" …><source src="https://pkink.com/art-of-zoo-…-trailer-dog-sex-video-…mp4">
//               **远端是 pkink.com 的 mp4，Range 实测 206 video/mp4**，带 artofzoo 的 Referer 即可
//   · WP REST   `/wp-json/wc/store/products`、`/wp-json/wp/v2/product` 都是 404（没开）
var BASE_URL = 'https://artofzoo.com';
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
    .replace(/&#8211;/g, '–')
    .replace(/&#8217;/g, "'")
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
  if (status !== 200) throw new Error('ArtOfZoo：请求失败 HTTP ' + status + ' ' + url);
  return String((response && response.body) || '');
}

// 卡片：entry-link-mask 的 href + entry-title + img[data-src]
function parseItems(html) {
  var items = [];
  var seen = {};
  var blocks = html.split('class="entry-link-mask"');
  // 结构里 anchor 在块之前，所以改成按 post-id 切：data-post-id="…" … entry-link-mask
  var cards = html.split('data-post-id="');
  for (var i = 1; i < cards.length; i++) {
    var block = cards[i].slice(0, 3000);
    var hrefMatch = /<a href="(https?:\/\/[^"]+)"/.exec(block);
    if (!hrefMatch) continue;
    var href = hrefMatch[1];
    if (seen[href]) continue;
    var titleMatch = /class="entry-title"[^>]*>([\s\S]{0,200}?)<\/h2>/.exec(block);
    var title = decode(titleMatch ? titleMatch[1] : '');
    if (!title) continue;
    var coverMatch = /data-src="([^"]+)"/.exec(block);
    var dateMatch = /class="entry-date"[^>]*>([^<]{0,30})</.exec(block);
    seen[href] = true;
    items.push({
      id: absolute(href),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: dateMatch ? decode(dateMatch[1]) : ''
    });
  }
  return items;
}

var CATEGORIES = [
  { id: 'shop', title: '影片商店', path: '/animal-porn-shop/' },
  { id: 'news', title: '新闻/新品', path: '/animal-porn-blog/' }
];

var LumeSource = {
  id: 'artofzoo_video',
  name: 'ArtOfZoo',
  version: '1.0.0',
  category: 'video',
  mirrors: ['https://artofzoo.com', 'https://www.artofzoo.com'],

  async categories() {
    var list = [];
    for (var i = 0; i < CATEGORIES.length; i++) list.push({ id: CATEGORIES[i].id, title: CATEGORIES[i].title });
    return list;
  },

  async home() {
    var html = await getText('/animal-porn-shop/');
    var items = parseItems(html);
    if (!items.length) throw new Error('ArtOfZoo：商店首页没认出商品（站点可能改版）');
    return [{ title: '影片商店', moreUrl: 'shop', items: items.slice(0, 15) }];
  },

  async list(argument) {
    var settings = argument || {};
    var pageNo = Number(settings.page || 1);
    if (!pageNo || pageNo < 1) pageNo = 1;
    var category = settings.categoryId ? String(settings.categoryId).trim() : 'shop';
    var keyword = settings.keyword ? String(settings.keyword).trim().toLowerCase() : '';
    var spec = CATEGORIES[0];
    for (var i = 0; i < CATEGORIES.length; i++) if (CATEGORIES[i].id === category) spec = CATEGORIES[i];
    var path = spec.path + (pageNo > 1 ? 'page/' + pageNo + '/' : '');
    var html = await getText(path);
    var items = parseItems(html);
    if (keyword) {
      items = items.filter(function (item) {
        return String(item.title).toLowerCase().indexOf(keyword) >= 0;
      });
    }
    return { items: items, hasMore: pageNo < 40 && items.length > 0 };
  },

  async detail(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return null;
    var html = await getText(id);
    var titleMatch = /<h1[^>]*>([\s\S]{0,220}?)<\/h1>/.exec(html) || /<title>([\s\S]*?)<\/title>/.exec(html);
    var title = decode(titleMatch ? titleMatch[1] : '').replace(/\s*[–-]\s*ArtOfZoo.*$/i, '').trim();
    if (!title) return null;
    // 商品页没有 og:image／description，主图在视频海报上（<video … poster="…">），
    // 简介在 WooCommerce 的描述标签页里，都没有就留空（不编内容）。
    var coverMatch = /<video[^>]+poster="([^"]+)"/.exec(html) ||
      /<meta[^>]+property="og:image"[^>]+content="([^"]+)"/.exec(html);
    var descMatch = /woocommerce-Tabs-panel--description[\s\S]{0,4000}?<\/div>/.exec(html);
    var descText = descMatch ? decode(descMatch[0]) : '';
    var priceMatch = /woocommerce-Price-amount[^>]*>[\s\S]{0,60}?([\d.,]+)/.exec(html);
    var trailer = trailerOf(html);
    return {
      id: absolute(id),
      title: title,
      cover: coverMatch ? absolute(coverMatch[1]) : '',
      subtitle: trailer ? '官方预告片' : (priceMatch ? priceMatch[1] : '影片'),
      description: descText ? descText.slice(0, 400) : ''
    };
  },

  async chapters(argument) {
    var id = argument && argument.id ? String(argument.id) : '';
    if (!id) return [];
    var html = await getText(id);
    var trailer = trailerOf(html);
    if (trailer) return [{ id: trailer, title: '官方预告片' }];
    return [{ id: absolute(id), title: '影片页' }];
  },

  async content(argument) {
    var chapterId = argument && argument.chapterId ? String(argument.chapterId).trim() : '';
    var id = argument && argument.id ? String(argument.id).trim() : '';
    // 章节 id 直接就是 trailer 的 mp4 地址
    if (chapterId && /\.(mp4|m3u8)(\?|#|$)/i.test(chapterId)) {
      return {
        kind: 'video',
        url: chapterId,
        headers: { Referer: base() + '/', 'User-Agent': UA, Accept: '*/*' }
      };
    }
    if (!id) throw new Error('ArtOfZoo：缺少影片地址');
    var html = await getText(id);
    var trailer = trailerOf(html);
    if (trailer) {
      return {
        kind: 'video',
        url: trailer,
        headers: { Referer: absolute(id), 'User-Agent': UA, Accept: '*/*' }
      };
    }
    // 没有公开 trailer（纯付费商品）就交网页播放器
    return { kind: 'webplayer', pageUrl: absolute(id), headers: headers() };
  }
};

// 详情页里的公开 trailer：<source src="…"> 或 wp-video 的 mp4 直链（远端 pkink.com）
function trailerOf(html) {
  var sourceMatch = /<source[^>]+src="(https?:\/\/[^"]+\.mp4[^"]*)"/i.exec(html);
  if (sourceMatch) return sourceMatch[1].replace(/&amp;/g, '&').replace(/\?_=\d+$/, '');
  var pkink = /(https?:\/\/[^"'\s<>]+trailer[^"'\s<>]*\.mp4[^"'\s<>]*)/i.exec(html);
  if (pkink) return pkink[1].replace(/&amp;/g, '&').replace(/\?_=\d+$/, '');
  return '';
}
