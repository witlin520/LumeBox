# 三个站补完：AV仓库 / 好色TV / ReddXXX（含 CF 站的 webplayer 打法）

2026-10-28 · 本轮交付 `sources/video/jizeyy.js`、`sources/video/hsex.js`、`sources/video/reddxxx.js`

## 1. AV仓库（jizeyy.com）—— 取流找到了，直链正确

Typecho + 主题 `yingshierhao`。详情页里只有一个「高清」按钮：

```html
<a href="https://www.jizeyy.com/video/23443.html?action=get&p=1"><button>高清</button></a>
```

这个 `action=get&p=1` 页里嵌着解析器地址：

```
https://www.jizeyy.com/usr/themes/yingshierhao/jx.php?url=https://play4.laoyacdn.com/20240205/udYIYzmR/index.m3u8&zimu=
```

`url=` 后面 URL 解码就是真·m3u8。实测：

| 项 | 结果 |
|---|---|
| `?action=get&p=1` | 200，含上述地址；`p=2..5` 无地址（只配一条线路） |
| `play4.laoyacdn.com/…/index.m3u8` | 解析到 `156.224.42.198`，**本机出口 ECONNRESET**（换网络可播） |
| `jx.php?url=…` | 200，返回「默认解析」播放器页（兜底线路） |
| 分类 | `/gccm/ /rhzh/ /zwzm /snsw /jrll /tjzp /llmt /mxhl`，21 条/页，翻页 `/mxhl/2/` |
| 卡片 | `<a href="…/video/{id}.html" class="video-post">` + `data-xurl` 封面 + `<h5>` 标题 |

源里 `content()` 返回直链 + `qualities` 两条（直连 / 网页解析）。列表 20 条、`hasMore` 正常、封面能取到。

## 2. 好色TV（hsex.men）—— 列表直连，播放交给内嵌浏览器

| 层 | 实测 |
|---|---|
| 列表 | `list-1.htm`、`top7_list-1.htm`、`top_list-1.htm`、`5min_list-1.htm`、`long_list-1.htm` **纯 HTTP 200**（48 条/页）；搜索 `search.htm?search=…&sort=new` 40 条 |
| 卡片 | `video-{id}.htm` + `https://i.hdcdn.store/thumb/{id}.webp`（开放）+ 时长 + `<h5>` 标题 |
| 详情 | `video-{id}.htm` **一律 Cloudflare 挑战**（403 + `Just a moment…`，换 UA/Cookie 无效；真实 Chrome 能过） |
| 播放 | 真实地址是 CDN 逐条签名：`https://cdn.hdcdn.store/{expiry}/{token}/hls/{id}/index.m3u8`；`/hls/{id}/index.m3u8` 直试 **403**，令牌不可推导 |

所以：列表/封面走 HTTP，`content()` 返回 `kind: webplayer` = `https://hsex.men/video-{id}.htm`，由 App 内嵌浏览器过 CF 后播放（这正是「打开浏览器」那一步）。签名 CDN 地址实测可播（浏览器里取到 `…/hls/1255444/index.m3u8` → 200 + `#EXTM3U`）。

## 3. ReddXXX（reddxxx.com）—— 全站 Turnstile，但 sitemap 没被拦

| 入口 | 结果 |
|---|---|
| `/`、`/rss/`、`/feed/`、`/api/v1/videos`、`/?feed=rss2` | 全部 403 + Cloudflare 挑战 |
| **`/sitemap.xml`** | **200（1.4 MB）**，sitemapindex，含 `/sitemap-videos/{N}`，N = 0（最新）→ 4213 |
| `/sitemap-videos/0` | 200（1.0 MB），33–44 个 `<url>`，每条带 `<loc>`（帖子页）、`<lastmod>`、`<video:thumbnail_loc>`、`<video:title>` |
| 缩略图 CDN | `cdn4..7.reddxxx.com/*.jpeg` **200 image/jpeg**（开放） |

所以列表直接用 sitemap 当分页（一页 = 一个分片，实测一页能解析出 **1004** 条，因为分片按 1000 URL 切但 `<url>` 数多于 video 条目），播放走 `webplayer`（帖子页 URL），交给内嵌浏览器过 Turnstile。

## 4. 验证

```
node tools/lume-source-check.mjs sources/video/jizeyy.js    → 入口全绿，playable 报 fetch failed
  home 3 块 / list 20 hasMore / detail ok / content = https://play4.laoyacdn.com/…/index.m3u8
  （CDN 在测机出口被 RST，属网络侧；地址本身由源站页面解出，脚本用 qualities 给了 jx.php 兜底）

node tools/lume-source-check.mjs sources/video/hsex.js      → PASS
  home 3 块（最新/周榜/月榜）/ list 24 hasMore / detail ok /
  content = https://hsex.men/video-1255444.htm（webplayer）

node tools/lume-source-check.mjs sources/video/reddxxx.js   → PASS
  home 12 条 / list 1004 条 hasMore / detail ok / content = 帖子页 URL（webplayer）

flutter test test/source_content_rating_test.dart → 通过（三个 id 均 18+）
```

## 5. 环境坑（踩过，记下来）

- 本地 `tools/lume-source-check.mjs` 在 vm 沙箱里跑 `fetch` 时，**只设大写 `HTTPS_PROXY` 不生效**，要同时给 `https_proxy` / `ALL_PROXY` + `NODE_USE_ENV_PROXY=1`，否则像 hsex.men 这种必须走代理的站会表现为 `TypeError: fetch failed`（10s 直连超时）。
- 源里拼 URL 时注意 `sectionPath()` 返回没有前导 `/`，`base() + path` 会拼成 `https://hsex.menlist-1.htm` → 立即 `fetch failed`；已在 `fetchHtml()` 里统一补 `/`。
- `theavporn.com` 仍缺一口气：详情页对游客显示「您的观看次数已受限,请登录后继续」，KVS 的 `contents/videos`、`get_file`、`data-rt` 各种变体全 404 —— 需要登录态或新 IP 才能看到真正的分发域，故本轮仍未建源。
