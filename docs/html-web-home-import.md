# 导入 HTML 网页主页

视频源选择器支持导入自包含的 HTML 页面，并为用户提供的三份页面接入 `fm` 兼容接口。此功能在当前 main 的基础上重新实现，保留现有原生导航及弹幕修复。

需要安装包含本次代码的新版本；旧安装包不会自动增加导入入口。本次只交付代码，不生成 IPA。

## 在 App 中导入

1. 把“各大平台直播合集.html”“lzxwwogg.html”“玩偶聚合.html”保存到手机的“文件”应用。
2. 打开视频板块的源选择器，切换到“网页”。
3. 点击“网页主页”旁的文件上传按钮，选中一个或多个 HTML 文件。也可以从添加菜单选择“网页主页 → 导入 HTML 文件”。
4. 点击导入后的卡片打开页面。卡片设置可以改名、删除；长按仍可排序。

同一内容重复导入会跳过，已改过的名称会保留。HTML 正文保存进 App 的视频设置库，后续不依赖原文件路径。文件需为 UTF-8 编码的 `.html` 或 `.htm`，每份不超过 2 MB；页面引用的在线 API、图片、脚本仍需联网。不同文件的收藏、历史和缓存分开保存，删除页面时清理其状态。

## 页面能使用哪些能力

| 接口 | 当前行为 |
| --- | --- |
| `fm.req(url, options)` | 使用 App 网络层请求 HTTP(S)，支持方法、请求头、正文、文本或 JSON 响应及超时，保留真实 HTTP 状态码 |
| `fm.res(url, options)` | 返回当前页面的资源转发地址，用于带 Referer / User-Agent 的图片等资源 |
| `fm.play(url, title, options)` | HTTP 媒体直链交给现有播放器，并传递请求头 |
| `fm.vodInline(detail)` | 选择指定剧集或首项，调用页面提供的 resolver，再交给现有播放器；当前使用独立播放页 |
| `fm.cache.get/set/remove` | 按页面及 scope 保存缓存 |
| `localStorage` | 恢复并镜像页面通过 setItem / removeItem / clear 写入的状态 |
| `fm.ui.getViewport/setChrome/restoreChrome` | 查询安全区、切换普通/铺满模式并发送 fmviewport 事件；铺满模式保留“网页工具”退出入口 |
| `fm.pan.play` / `push://` | 分享链接进入现有内置网页解析页，提取码可复制；检测到媒体后可交给播放器 |
| `fm.config` / `fm.pan.check` | 自动网盘有效性检测关闭，检查结果返回 uncertain，避免误删搜索结果 |

网盘分享需要用户在网页中完成其要求的登录或提取步骤；本次没有新增自动网盘直链解析器。磁力链接提供复制入口，播放器暂不能直接播放。直播流实际支持的格式仍取决于当前播放内核，尤其是 FLV。

## 验证与证据

`test/html_home_session_test.dart` 验证实际本地 HTTP 会话的注入顺序、请求与资源转发、来源校验、请求头、播放分发、页面状态隔离、关闭及数据库重开。`test/video_source_picker_test.dart` 验证批量导入、部分失败、重复文件、改名删除，以及普通 URL 添加和取消编辑。相关源、导航、搜索、键盘、窄屏及播放器回归另有 234 项通过。

对用户提供的三份文件执行了真实解码、标题提取及 SDK 检查，解析了 7 段作者内联脚本，结果通过。这些检查没有请求作者页面的远程 API，因此不能据此判断所有直播平台和网盘资源可用，也没有替代 iPhone 的 WKWebView 验收。

在项目根目录重现：

```powershell
flutter analyze --no-pub lib/core/web lib/features/web/web_home_page.dart lib/features/source/video_source_picker.dart
flutter test --no-pub test/html_home_session_test.dart test/web_home_sources_test.dart test/video_source_picker_test.dart
$env:LUME_HTML_HOME_DIR = Join-Path $env:USERPROFILE 'Desktop'
flutter test --no-pub tool/html_home_files_smoke_test.dart
node tool/check_html_home_sdk.mjs build/html-home-checks/sdk.js "$env:LUME_HTML_HOME_DIR/各大平台直播合集.html" "$env:LUME_HTML_HOME_DIR/lzxwwogg.html" "$env:LUME_HTML_HOME_DIR/玩偶聚合.html"
```

生成的检查记录位于 `build/html-home-checks/`，原始 HTML 不加入仓库。代码与上述测试支持“可导入并提供所列兼容接口”的结论；下一步在新包中实测三份页面的打开、收藏持久化、直播起播、网盘登录以及铺满后退出和播放器返回。

## 实现边界

普通 URL 主页继续使用原有 WebView，不注入兼容 SDK。本地页面使用只绑定 `127.0.0.1` 的临时会话，带随机路径，RPC 校验 Origin 和 Host；页面关闭时取消请求并释放服务。每项缓存上限 256 KB、每页面状态上限 2 MB、单次网络响应上限 8 MB。网络请求沿用 App 的网络设置，不修改系统代理或原有源运行时。
