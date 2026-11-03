# 制源工具与当前 App 的协议核对

本次修正只修改制源工具和新增测试，不修改 App 的导入器、运行时或模块分类。旧 `docs/lumesource-guide.md` 包含过时的文字小说示例，不能作为当前导出契约依据。

## 导入证据与实现

| 源码证据 | 结论 | 工具实现 / 验收 |
| --- | --- | --- |
| `lib/core/session/section.dart`、`lib/core/source/source_models.dart` 的 `ChapterContent.parse` | 底层板块是 comic/video/cat；正文只接受图片、视频及音频，无 text | 拒绝 novel 工程，图片和漫画导出 `kind=images`；通过真实内容模型解析 |
| `lib/features/source/video_source_picker.dart` 的 `VideoSourceType.forSource`、`lib/core/source/source_media_hints.dart` | 有声小说是视频库内的音频类型，依赖 `mediaType=audio` 和音频载荷 | JS 身份头声明音频，输出 `kind=audio`，测试 `descriptor.isAudio` 与 `VideoContent.audioOnly` |
| `lib/core/source/source_picker_groups.dart` | 图片归漫画库，美图是展示分组，脚本头 group 不会自动设置数据库分组 | 图集直接从详情页取图；导入说明明确可手动分到美图 |
| `lib/core/source/source_package.dart`、`lib/core/js/source_engine.dart`、`lib/core/js/module_script.dart` | 模块须经包类型识别和 `ModuleScript.wrap`，不能直接当普通 JS 载入 | CommonJS `.cjs` 输出，并通过真实导入、模块转换、QuickJS 与 HTTP 桥 |
| `assets/python/lume_python.py` 的 `_dispatch`、`execute` | PY 使用 Spider 的 home/category/search/detail/player 接口，App 适配到统一模型 | 生成苹果 CMS Spider；在原样生产 CPython 宿主内验证全链路 |
| `lib/core/cat/cat_local_bundle.dart`、`lib/core/cat/cat_service.dart`、`assets/cat/bootstrap.js` | 猫源入口接收 index.js/index.config.js 的运行 ZIP；启动后请求 /config 和 /source/* | 生成 Node `start()` 服务、配置和双 MD5；用真实 ZIP 解析器及生产 bootstrap 启动验证 |
| `lib/core/source/kazumi_rule.dart`、`lib/core/net/source_import_input.dart` | Kazumi 接收规则 JSON，转换后的 ID 前缀决定标签；API 模式与 HTML XPath 分开 | 分别生成 API 与 HTML 规则；验证真实转换、导入及 API 搜索/详情/选集/内容 |
| `lib/core/web/html_home_import.dart`、`lib/core/web/web_home_sources.dart` | 网页是独立 WebHomeSource，接受 UTF-8 HTML，最大 2MB | HTML 导航快照，经真实 HTML 导入器验证 |

## 验收

`test/source_maker_contract_test.dart` 每次通过工具的 `make_fixtures.py` 生成真实输出文件，再交给 App 的 `SourceImportInput`、`SourcePackage`、`SourceRegistry`、`QuickJsSourceEngine`、`JsDataSource`、`ChapterContent`、`CatLocalBundle`、`HtmlHomeImport`。生产代码保持原样，HTTP 响应由离线快照提供。

`tools/source_maker/check_python_host.py` 注入测试网络回包后，运行原样的 `assets/python/lume_python.py`，检查生成 `.py` 的装载、分类、搜索、详情、选集和播放载荷。

`tools/source_maker/tests/test_source_maker.py` 的猫源检查使用真实 `assets/cat/bootstrap.js`，等待 `sourceStarted`，检查配置、列表、详情及播放接口，最后结束测试专属 Node 进程。

真实 App 测试发现并修正了模块 ESM 输出不适配当前转换器、视频页先提取音频的问题。当前导出选择 CommonJS，并按目标媒体类型排除无关音视频元素。

## 尚未验证的部分

没有在 iOS 设备实播或浏览任意用户网站。HTML Kazumi 仅验证规则转换与导入，其浏览器 XPath、动态页面和实际播放仍需 App 内验证。PY 支持公开 HTML 视频与苹果 CMS，漫画 PY 尚未接入 App；网页导出为导航快照。网站反爬、登录、专用加密接口及视频解析器仍可能需要逐站适配。

## 0.3 导出验收修正

之前的验证主要证明了输出格式兼容，无法证明输入网站已经被正确适配。现将源代码生成为草稿，最多抽查三条详情、选集和内容；未通过时禁止导出。输入或规则变化后清除验证状态，避免使用过期结果导出。

普通 JS / CommonJS / Node 猫源增加从网页实时读取的分类与标准 GET 表单筛选；原生 Dart 集成测试检查 `categories`、`filters` 及分类/筛选列表请求的实际路径和查询参数。苹果 CMS 没有额外筛选元数据时返回空组并报告未适配，不虚构标签。

删除“任意详情页自动产生一集播放”的兜底，避免人物或导航页伪装成可播放作品；同页媒体仅在已经识别到媒体标签时作为单集。默认展示名和导出文件名采用完整网页标题，源 ID 不变。

## 0.4 浏览器、规则与备用导出

桌面分别接入 WebView2、Playwright Edge、Selenium Edge；手动完成后继续采集，同一浏览器保持会话。单独进程隔离 Tk 与浏览器 UI，不向网页暴露 Python API。会话 Cookie 不进入导出文件，手机需单独验证。

Scrapling Selector 用于卡片识别，详情检查识别章节与图片区域；导出的 JS 使用内置有限 CSS 解析器，无需在 App 安装 Scrapling。Scrapy 用于批量入口采集，验证与导出复用同一实现。静态视频 JS 失败后才尝试 PY；只有备用实现通过后才切换导出类型，并使原 JS 草稿失效。

新增本地快照检查覆盖兄弟节点的标题与封面、真实下一页、漫画阅读区域、JSON-LD、HTML PY 和 JS→PY 切换。生产 CPython 宿主运行 HTML PY 的分类、筛选、列表、详情、选集与媒体载荷。Dart 通过真实 JS 引擎并模拟原生网页渲染 MethodChannel，验证动态 JS 的调用协议；这不等同于 iOS WebKit 实站验证。

`app.py --engine-check <report.json>` 使用临时本机 HTTP 服务，检查三种真实浏览器动态 DOM、HttpOnly 会话 Cookie、动态 JS 抽样链路、Scrapy 和批量导出。只对本地自建测试页自动继续，不对网站自动处理验证。

## 0.5 引擎与自动适应

接入 Scrapling 0.5 的 8 种同步/异步抓取与会话路径，均通过独立工作进程调用实际库；动态导出统一调用 App 的 web.render。Playwright、Selenium、WebView2 与 Scrapling 浏览器共用一段有次数、等待上限的点击/滚动脚本；同一脚本以函数源码形式写入动态源，避免只在桌面得到完整页面。App 现有 callAsyncJavaScript 支持异步脚本，无需修改原生网页桥。

Scrapling 自适应仅从通过验证的规则学习，在本地 SQLite 保存结构特征；再次识别时将重定位结果转换为普通 CSS，再进入已有验证与导出流程。不会把 SQLite 数据库和 Cookie 打包到手机，也不宣称已导入源在手机端自动适应。

引擎测试新增真实点击加载更多、等待异步接口结果、JSON 响应读取与常见敏感字段隐藏。Scrapy 验收新增任务文件、成品 SHA256 校验、暂停与断点续作。框架功能范围在 GUI 与使用说明中明确列出，不把依赖安装等同于完整 SDK 的图形化支持。
