# Pornlulu 源：CDNLah WAF 的 PoW 自动解算

2026-10-29 · `sources/video/pornlulu.js`（`pornlulu_video`）

## 一、可达性

| 目标 | 国内直连 | 经本机代理 | 说明 |
|---|---|---|---|
| `https://www.pornlulu.net`（简体） | 302 → `goto2.cc/block` | 200（但会被 WAF 弹校验页） | 主站，`network:"proxy"` |
| `https://www.pornlulu.com`（正體） | — | 每条请求都弹校验 | 同库镜像（同 video id、同 m3u8），列进 `mirrors` |
| `https://2609.lajiao2026.com/…/index.m3u8` | **200 + `#EXTM3U`** | 200 | 播放 CDN（master → 1500kb/720p hls） |
| 封面 `fb.lj260522.top` 等 | 200 | 200 | 不需要 Referer |

`.com` 与 `.net` 是同一套数据：`/v/rxKb4K` 两边标题只差繁简，`<source>` 完全同一条
（`2609.lajiao2026.com/20261028/lM7eviz3/index.m3u8`）。

## 二、WAF：不是封锁页，是工作量验证（HTTP 492）

请求稍密就会拿到「安全防御 - 工作量验证」页（状态码 **492**），里面内嵌：

```json
{"seed":"…","difficulty":4,"verify_path":"/__cdnlah/pow/verify",
 "challenge_cookie":"_chg_waf_pow","metadata_field":"challenge_metadata","metadata_token":"…"}
```

过法是标准的哈希现金（`/__cdnlah/pow.v1.js` 的逻辑）：

1. 找一个 16 位十六进制 `nonce`，让 `sha256hex(seed + nonce)` 以 `difficulty` 个 `0` 开头
   （difficulty=4 → 前两个字节为 0，平均 ~6.5 万次）；
2. 把 `seed / nonce / redirect / challenge_cookie / challenge_metadata` 表单 POST 到 `verify_path`；
3. 校验通过回 302 并下发 `_chg_waf_pow`，`redirect` 指向的页面就是目标页。

源里的取舍：

- **SHA-256 是纯 JS 实现**（沙箱没有 crypto）：difficulty=4 时 V8 约 120ms，QuickJS 里估计
  0.3–0.6s；只在被校验的那次请求付这个成本。`verify` 与 Node `crypto` 对照过空串/abc/中文。
- **不自己管 Cookie**：App 的 `SiteSessionPool` 会把 302 上的 `Set-Cookie` 收进站点会话，
  后续请求自动带上；检查工具那边也补了同一套 per-origin cookie jar（见下）。
  源里先看「verify 跟随后的正文」，还是校验页就用刚写入的 Cookie 再 GET 一次。
- 302 的 `redirect` 由服务端按请求路径填，所以校验通过后跟到的就是刚才要的页面。

## 三、结构（逐页实测）

- 列表：`/`、`/cat/<id>?page=<N>`；排序 `/?sort=id|hits|score|likes`（分类页同样吃 `sort`）。
- 搜索：`/?q=<词>&page=<N>`（表单 `name=q`）。**搜索不吃 sort**，所以源里没声明 `filters`，
  排序做成 3 个分类入口（最新 / 最热 / 评分；实测 sort=likes 与 sort=hits 结果相同，故不单列）。
- 分类：`/category` 共 66 个（`/cat/48` 中文字幕、`/cat/13` 强奸乱伦…），`fs` 缓存 30 分钟，
  失败回落内置清单。
- 卡片：`class='col-lg-3 … item p-0 pr-1'` → `href="/v/<短id>"` + `<img src>` + `.two-lines` 标题。
- 详情：`/v/<id>`，`og:title` / `og:image`，分类从 `meta keywords` 的「标题, 分类, 站点名」里取；
  不存在的 id 返回 404 → `detail` 返回 `null`。
- 播放：`<video><source src="…index.m3u8" type="application/x-mpegURL">`，单条线路。

## 四、验证（2026-10-29，走本机代理）

```bash
node tools/lume-source-check.mjs sources/video/pornlulu.js
# PASS：home 2 块（24+24）、categories 69（3 排序 + 66 分类）、list 48、detail ok、
#       content video、playable 200 + #EXTM3U
```

**PoW 路径是单独验的**：把 `DEFAULT_BASE` 临时换成 `www.pornlulu.com`（它对每条请求都弹校验），
同一份脚本 `PASS`，日志里能看到 `触发人机校验，解 PoW 后重取：/` 与 `/?sort=hits`，
home 1.76s、list 0.2s、detail 0.57s、content video、playable 200。

分类/分页/排序/搜索首条 id 都不同：`/cat/48`→Mx95xk、`/cat/48?page=2`→K0my3M、
`/cat/48?sort=hits`→nrWPr、`/cat/48?sort=score`→A9l3m1、`/?sort=hits`→aKwP8、
搜索「巨乳」→OY2Z4l（第 2 页 →XXOWV4）、「zzzqqqxyw」→ 0 条。

顺带修的两个东西：

- **`tools/lume-source-check.mjs` 现在按 origin 记 Cookie**（跟 App 的 `SiteSessionPool` 对齐，
  含中间 302 上的 `Set-Cookie`），否则 WAF 类站点在检查工具里永远过不去、而 App 里却是好的。
- **pornbest（第一女優網）也在这个 WAF 后面**：同一时间它开始回 492（`goto2.cc` 封锁页之外的新一层），
  所以把同一套 PoW 解算并进了 `sources/video/pornbest.js`，版本 1.0.2；复验 PASS。

## 五、限制

- 必须代理（国内直连 302 到封锁页）。
- 被 WAF 弹校验时那一次请求要多花几百毫秒（解 PoW + 一次 verify POST）。
- 单条视频只有一档 m3u8（master 里就 1500kb 一路）。
- 搜索没有排序；分类页的排序只有站点给的 4 种。
- `.com` 每条请求都要校验，作镜像可用但比 `.net` 慢，日常建议用 `.net`。
