# Rex Widget 导入与播放适配

本轮完成 Rex 明文经典脚本的通用适配，以及 `.rex`／`.fwd` 集合解析。大师兄、采集聚合、荐片原文件均通过真实 QuickJS 的离线搜索、详情、选线、播放地址和引擎重开测试。测试中的 HTTP 全部由固定应答提供，尚未验证真实站点和 iPhone 起播。

REXENC／FWENC 只完成格式识别与明确失败提示，没有接通内容密钥或解密加载。用户提供的瓜子、花卷、TG搜，以及本次拉取的红果集合 10 个模块，仍不能据此运行。

## 使用

1. 在视频源选择器的「模块」入口导入原始 `.js`，或填写集合链接。`.rex`／`.fwd` 文件和集合 JSON 也可以从本地或剪贴板导入。
2. 大师兄、采集聚合、荐片是播放线路模块，没有影片首页；导入后在视频搜索中输入片名，再进详情、目录选择线路。
3. 在源设置的「Widget 参数」里修改脚本声明的枚举和文本参数。例如采集聚合的聚合开关和 CSV 源配置，无需改脚本。
4. 线路模块默认按电影搜索；剧集可在源设置选择类型、季、集，或直接搜索 `片名 S01E02`。留空集数时由原脚本决定返回目录还是默认集数。

有 catalog 模块的明文 Widget 按原声明提供分类、分页、筛选、搜索和 `loadDetail`。详情网址使用独立条目身份，避免被当成视频直链跳过解析。影视资料模块若没有资源解析器，会明确提示缺少可用播放资源。

## 当前支持范围

| 层 | 行为 |
| --- | --- |
| 脚本 | 经典 `WidgetMetadata = {...}`、`const/let/var WidgetMetadata`，顶层函数、词法函数；保留原脚本执行 |
| 身份 | 原生 Widget id 映射到稳定的 `rex_` 身份；文件、链接和更新沿用同一身份 |
| 集合 | JSON `widgets`、绝对／相对 URL、无 `.js` 后缀的 raw 地址；保留条目名和各自来源 URL |
| 导入一致性 | 网络订阅和本地集合共用展开器；逐条错误、循环防护及总量上限；不完整同步保留旧源 |
| 参数 | `globalParams` 默认值、枚举、输入；page／offset／count；筛选条件与 `belongTo` |
| HTTP | GET／POST／PUT／DELETE／PATCH／HEAD、params、headers、字符串／JSON／表单正文、超时、禁止跳转、JSON／文本／Base64／zlib 响应；沿用宿主 UA、队列、代理与源配置 |
| 存储 | 模块私有持久化对象存储；同步读写、keys／remove／clear；可选 TTL 秒数 |
| 共享缓存 | 按命名空间跨 Widget 共享；函数内同步读取，在宿主调用边界刷新并合并写入 |
| HTML | 基于现有 HTML 宿主的常用读取链：选择、attr／text／html／find／each／map／get／eq／children／parent 等；支持直接使用或 await |
| TMDB | `Widget.tmdb.get` 接用户现有 TMDB 配置，使用相对 API 路径，宿主密钥不直接交给脚本 |
| 播放 | catalog 详情／剧集和 stream 线路映射到现有播放契约，保留播放请求头，重开后可恢复或重新解析线路 |

大师兄的 CryptoJS AES 初始化在 Windows QuickJS 的 512KiB 堆栈下失败，1MiB 对照测试通过，因此内置 Rex 引擎使用固定 1MiB 堆栈。普通源沿用原额度；内存、指令、网络调用次数及用户设置的墙钟上限继续生效。脚本自身的 18 秒探测期限不会覆盖宿主的时间上限。

## 存储与收藏

Widget 存储独立于原有 `LumeSource.fs`。私有区和显式共享区各限制 512 项／2MiB；配置参数与参数声明另有 128KiB 限制。共享区是同板块 Rex Widget 之间的显式共享空间，不会把其他源的私有区合并进去。

条目和章节身份不嵌入 Widget 的账号参数或播放请求头。少量完整条目保存在受限的模块私有缓存中；章节在引擎重开后按父条目重新解析。清理缓存、线路顺序改变或直接条目的请求头缓存过期时，可能需要重新搜索和打开目录。

`rex.widget.*` 的参数、缓存和存储不进入配置备份或云设置导出；配置恢复也拒绝覆盖该前缀。清理站点设置会清除 Widget 私有数据、参数和共享缓存，保留参数声明以便重新配置。

## 样例与集合检查

[检查快照](evidence/rex-widget/inspection.json)包含原文件摘要和红果集合条目。快照 SHA256：`8b8d22366b40b9f1cb17b39666b531b858277b311a6c37205cc653a36211b4d6`，固定 LF 换行。

| 用户原文件 | 格式 | 本轮验证 |
| --- | --- | --- |
| 大师兄(rex).js | 明文 Widget stream | 原文件加载、CryptoJS 请求生成、搜索／详情、媒体头探测、选线、播放地址／请求头、重开 |
| 采集聚合(rex).js | 明文 Widget stream | 原文件加载、默认枚举、CSV 源配置、聚合去重、同步对象缓存命中、选线、重开 |
| 荐片(rex).js | 明文 Widget stream | 原文件加载、搜索／详情匹配、多线路、播放地址、重开 |
| 瓜子(rex).js | REXENC v2／A256GCM | 仅识别信封；未解密、未播放 |

[红果集合](https://rex.openharbor.dpdns.org/api/collections/hongguo.rex)在 2026-10-20 的检查中返回 10 个模块，包括红果漫剧、通用短剧弹幕、七猫、星芽、河马、喜番、围观、火龙、柚漫、好看；逐个拉取均为 REXENC v2。集合能展开不代表加密模块能执行。

原脚本和下载的加密正文仅在忽略目录 `.cache/rex-compat/` 保留，不随仓库分发。

## 复现

```powershell
$env:LUME_REX_SAMPLE_DIR = 'C:/Users/63089/Desktop/新建文件夹 (2)'
flutter test --no-pub test/rex_widget_test.dart test/rex_widget_native_test.dart test/rex_widget_parameters_test.dart test/rex_widget_samples_native_test.dart
flutter analyze --no-pub lib test/rex_widget_test.dart test/rex_widget_native_test.dart test/rex_widget_parameters_test.dart test/rex_widget_samples_native_test.dart
flutter test --no-pub
```

新增 Rex 用例 16 项覆盖真实 QuickJS、原文件、参数表单、持久化与共享、季集、敏感字段隔离、二进制／跳转／压缩、HTML 查询、TMDB 桥、集合上限、错误处理和 Python 格式优先级。本轮源码及新增用例静态分析无问题；全量 Flutter 回归 2084 项通过、12 项跳过，日志保存在忽略目录 `.cache/rex-compat/flutter-final2.log`。原文件缺失或原生桥不可用的环境会明确跳过对应测试。

## 仍未接通

- REXENC／FWENC 的密钥加载与解密执行；现有 [IPA 检查报告](2026-10-20_逆向-Rex-IPA-report.md)只提供静态定位，不能代替可用取钥协议或对应样本密钥。
- 依赖 Rex WebView 执行的方法、独立弹幕／字幕 Widget、其他客户端私有扩展。
- 完整 Cheerio、DOM 修改、复杂伪类等；目前 HTML 兼容仅覆盖现有宿主支持的查询子集。
- Rex 专用跨文件 ESM／CommonJS Widget 导出协议。本轮面向经典单文件 Widget；原有 Lume／Spider 的 ESM／CommonJS 多文件能力仍沿用原实现。
- 真实站点访问、实际媒体起播、iOS 生命周期和设备验收。

本轮未生成 IPA，现有安装包不含本轮代码。适配依据为 [Rex SDK](https://github.com/baranwang/rex-widget-libs)、[Forward Widget 文档](https://forward-2.gitbook.io/forward/fu-lu-er-forward-widget-kai-fa-zhe-zhi-chi)、用户脚本和 Rex IPA 的实际宿主接口。
