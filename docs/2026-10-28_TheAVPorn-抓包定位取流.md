# TheAVPorn（theavporn.com）：借登录态抓包定位取流，免登录直连可播

2026-10-28 · `sources/video/theavporn.js`（`theavporn_video`）

## 1. 卡点与解法

这站是 KVS，但**游客**详情页只有：

```html
<div class="no-player"> <img …/> <span class="message">您的观看次数已受限,请登录后继续。登录|OR|注册</span></div>
```

KVS 的常规取流路径全部 404（`contents/videos/{dir}/{id}/{id}.mp4`、`/get_file/{id}/`、`/get_file/{id}/{file}/?rt=…`、
`/videos/{id}/`），页面里只有 `data-rt` 反盗链 token，`?mode=async&action=get_player` 回 `<failure type="invalid_params"/>`。

**解法：让用户在本机 Chrome 里登录并播放，用 CDP 抓真实请求。** 抓到：

```
REQ GET https://bytt.jb-aiwei.cc/contents/videos/79000/79091/index.m3u8?ttl=1729503406&dsc=b9cb2233db560fd07cd98ca542a1ceea
RES 200 application/vnd.apple.mpegurl
REQ GET https://bytt.jb-aiwei.cc/contents/videos/79000/79091/0007.ts      ← 分片完全不带签名
```

## 2. 关键验证：签名是装饰

| 请求 | 结果 |
|---|---|
| 带 `ttl`+`dsc` 的原始清单 | 200 · 6556 B · `#EXTM3U` |
| **去掉整段查询串** | **200 · 6556 B · `#EXTM3U`** |
| 只留 `?ttl=` | 200 |
| 分片 `0001.ts`（无签名） | 200 · 2,384,022 B |
| 另一个视频 id 78259（同规则拼） | 200 · 10950 B · `#EXTM3U` |
| `{id}_720p.mp4/index.m3u8` | 404（只有一条清晰度） |

所以 `content()` 只用 id 拼：`{CDN}/contents/videos/{dir}/{id}/index.m3u8`，`dir = floor(id/1000)*1000`，
**不需要登录、不需要 token**。CDN 主机是 `https://bytt.jb-aiwei.cc`（换域时改脚本顶部 `CDN_HOSTS`）。

## 3. 站点结构

| 用途 | 路径 |
|---|---|
| 第一页（最新） | `/new/`（24 条） |
| 第 N 页 | `/latest-updates/{N}/`（`/new/2/` 与 `/latest-updates/` 都是 404，踩过） |
| 最高评分 / 最热 | `/top-rated/`、`/most-popular/` |
| 详情 | `/video/{id}/{slug}/`（游客是 no-player，但标题/og:image 可读） |
| 卡片 | `<div class="item thumb ">` → `<a class="th" href="…/video/{id}/…" title="…" data-rt="…">` + `<img data-original="…/videos_screenshots/{dir}/{id}/385x234/1.jpg">` + `<div class="sticky_time">4:19</div>` |

## 4. 验证

```
node tools/lume-source-check.mjs sources/video/theavporn.js → PASS
home 3 块（最新/最高评分/最热）/ list 24 hasMore / detail ok / chapters 1 /
content = https://bytt.jb-aiwei.cc/contents/videos/82000/82396/index.m3u8
playable 200 · #EXTM3U · 1382 B
```

`flutter test test/source_content_rating_test.dart` 通过（`theavporn_video` 记 18+）。

## 5. 备注

- 抓包用的 Chrome 是带 `--remote-debugging-port=9400` 的独立 profile（`.tmp_probe/av-profile`），
  只在本次调试用；源码不需要任何 Cookie。
- 若以后站点开始校验 `dsc`，退回方案是把详情页交给 `webplayer`（登录态由用户在内嵌浏览器里自己维持）。
