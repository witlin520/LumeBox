# 网页验证、源请求桥与网页播放

更新：2026-10-23。本文描述当前代码接口与本地验证结果；iOS 编译和 iPhone 实站验收仍待完成。通用接口不能证明 gaze、Cap 或其他具体站点已可搜索、可播放。

## 验证层

`assets/js/verification_probe.js` 负责只读页面检测；iOS `SourceWebController` 保留遇到挑战的同一个 WKWebView，显示人工验证窗口。现有可见 WebView 路径也使用相同探针。

识别包括 Cloudflare、极验、reCAPTCHA v2/v3、hCaptcha、腾讯防水墙、阿里云验证码、易盾、图片验证码，以及阿里云 WAF、腾讯云 WAF、加速乐、瑞数和顶象／数美／同盾的已列明特征。特征匹配是启发式判断；厂商更新或页面复用脚本可能改变结果。

未知页面结合交互容器、异常响应、验证文案与缺失业务内容进入人工等待。普通登录、公告、空结果和单独的加载文案有排除逻辑。可在验证窗口选择“这是验证页”。无可操作入口的明确计算型拦截，以及 Arkose、DataDome 和明确拒绝访问页，直接提供风险提示、重试或跳过。

每 750ms 读取一次页面，避免并发轮询。120 秒为一轮等待上限；页面失败文案不会重置期限，用户主动重试才开始新一轮。成功要求业务 DOM 恢复并结合 URL、验证凭证、Cookie／存储变化或成功文案；单独变更统计 Cookie 不会通过。

源可通过 `LumeSource.web.render` 的 `waitForSelector` 或 wait 步骤中的 selector 指定业务 DOM 特征。未声明时使用内置列表、详情、播放器和搜索等特征。

Cookie 从原生 WKHTTPCookieStore 读取，保留 domain、path、secure、httpOnly；按业务域过滤，第三方验证 iframe 的 Cookie 不会混入。任意新增／变值的 Cookie（包括随机 `__Host-*`）参与比较，不依赖固定名称。LocalStorage／SessionStorage 按 origin 保存至共享会话池，供宿主和后续页面恢复使用。Cookie 同步不等于 HTTP 客户端具备相同的 TLS、HTTP/2 或 JS 指纹。

本实现继续使用既有 QuickJS、Python 和系统 WKWebView；没有新增脚本引擎，也没有验证码识别或轨迹模拟。WKWebView 和原生 URLSession 依从系统网络／VPN 设置；规则代理是否让各请求采用相同出口仍需真机验证。

## 源接入层：已验证页面请求桥

仅 iOS 已通过人工验证并仍保留的页面可配置请求桥。源声明完整 origin 和精确路径后请求：

```js
const bridge = LumeSource.web.bridge;
await bridge.configure({
  origin: 'https://source.example',
  paths: ['/api/search']
});
const response = await bridge.request({
  url: 'https://source.example/api/search?q=example',
  method: 'GET',
  headers: {'x-source-token': token},
  timeoutMs: 6000
});
if (response.status === 200 && response.bodyText !== null) {
  const data = JSON.parse(response.bodyText);
}
```

Python 等价入口为 `lume_tools.bridge.configure(origin=..., paths=[...])` 和 `lume_tools.bridge.request(url=..., method='GET', headers={...})`。

约束同时在 Dart 和原生层检查：

- 当前源 scope、已验证页面和完全相同的 origin；只允许 GET／POST，拒绝重定向。
- 1–32 个精确路径，不支持通配符、编码路径或点路径段。
- 每页最多 2 个并发请求，超时 100–8000ms，文本请求体不超过 64KiB。
- 禁止显式 Cookie、Authorization、Origin、Referer 等凭据／浏览器身份头；会话由页面 `credentials: 'include'` 使用。
- 仅回传 JSON／纯文本，最多 512KiB；二进制或大响应返回状态、大小与标记，`bodyText` 为 null。响应头只返回 content-type、content-length、cache-control。
- 固定宿主 fetch 逻辑，不接收任意 JS。此入口不会自动生成站点私有 token，也不能任意调用站点函数。

原生最多保留两个已验证页面；源释放、内存警告、替换页面或请求原生超时会释放页面。重新遇到验证会撤销同 scope 的旧桥。页面释放后需重新验证，不能继续借用旧身份。

### 会话撤销、取消与错误

统一撤销入口位于 `WebSessionLifecycle`。清理站点数据／共享会话池、修改站点 UA、修改全局代理或 UA、保存源域名变更，以及已接入的站点退出登录导航，都会撤销相应页面能力。域名变更撤销旧、新域名；无站点记录的旧源清理会撤销全部页面能力。撤销请求桥不会主动删除其他站点的登录 Cookie。

iOS 系统网络路径变化会撤销页面能力；NWPathMonitor 不保证报告所有 VPN 规则或出口变化，因此不能据此宣称任意代理切换均已识别。隐藏请求桥进入后台即释放；正在人工验证的可见页面保留，暂停探测，回到前台按原始 120 秒期限继续或提示超时。

源释放和请求取消会通知原生关闭对应页面，并使 Dart 停止等待；即使平台迟到返回，也不导入已取消验证的存储或继续处理旧请求。请求进行中会话版本改变，同样丢弃旧结果。取消一个桥请求会关闭该源的整个桥，其余并发请求也需重新配置。

桥响应保留 HTTP 状态，并在错误状态附加 `failureKind`：401 为 `session_expired`，403 为 `source_rejected`，429 为 `rate_limited`，其他 HTTP 错误为 `upstream_http`。403 不能单凭状态确定是签名、权限、指纹还是验证问题，不能自动循环弹验证。明确的会话失效、取消和超时有独立错误码；平台错误细节不会直接拼接进请求桥提示。站点返回 200 但正文表示签名错误时，仍需源按其业务协议识别。

站点在页面内通过 XHR 自行退出、服务端撤销会话等情况，宿主无法通用判断所有站点私有状态；应结合后续 401／业务错误处理，必要时重新打开源或清理该站点会话。

### 签名与动态头

QuickJS 源可导出 `prepareRequest`（优先）或 `sign`：

```js
LumeSource.prepareRequest = async ({url, method, body, pageHtml, bridge}) => {
  return {headers: {'x-source-sign': calculateSignature(url, body)}};
};
const response = await LumeSource.http.request({
  url: 'https://source.example/api/search',
  pageHtml: savedHtml
});
```

`prepareRequest` 返回 `{headers, body}`，`sign` 仅返回 headers；原请求头合并保留，返回值不能更换目标 URL。JS 钩子在 `LumeSource.http.request/get/post` 生效，不覆盖源自行直接调用的全局 fetch。钩子内若要发普通请求，可用 `prepare:false` 避免递归。

Python spider 可提供 `prepareRequest(request)`／`prepare_request(request)` 或 `sign(request)`，由 requests 适配器在发送时调用。`request` 包含 url、method、body、pageHtml、bridge；body 为已准备的字节，当前 Python 的 pageHtml 默认为空，需源自行缓存页面参数。返回格式与 JS 一致，修改 body 会更新长度头。Python 钩子内应使用 bridge 或本地算法，避免递归调用 requests。

站点专有的 x-gaze-*、DOM token、像素证明与 WASM 逻辑需要各源单独实现维护；本次通用钩子没有附带这些站点的签名算法。

## 播放层：网页播放

通用 JS 源的 content 返回：

```js
return {
  kind: 'video',
  webPlayer: true,
  pageUrl: 'https://source.example/play/123',
  headers: {'Referer': 'https://source.example/'}
};
```

猫源 player 返回同样的 `webPlayer: true`、`pageUrl` 和其原有 header／headers；Python playerContent 返回也保留这些字段。必须提供完整 HTTP(S) 播放页地址，不能把 blob 字符串作为页面地址。

明确 `webPlayer` 时直接打开独立“网页播放”页，让站点自己的 JS／WASM 播放；不创建原生解码器。既有 `webParse`／parse=1 保留嗅探流程，并提供“改用网页播放”入口。原生自动连播遇到网页播放标记只提示，不自动混入网页播放。

页面提供返回、刷新、全屏和在浏览器打开；显示不支持原生弹幕、手势、画中画、字幕样式和进度记忆。切换全屏保留 WebView，离开页面加载空白页以停止媒体。站点页面本身的播放能力、广告、加密实现仍由站点控制。

进入后台／暂失活动状态时，对顶层页面的 video／audio 执行固定暂停逻辑，回前台不自动调用 play。跨域 iframe 或站点私有媒体实现无法由该 JS 保证暂停，必须加入真机验收。刷新初始化有防重入保护。

## 日志与导出脱敏

`SensitiveData` 在 LumeLog 输出控制台和进入缓冲前处理消息及堆栈；请求抓包缓冲也在入口重新脱敏，避免调用者遗漏。Cookie、Authorization、自定义 token、x-gaze-*、签名、账号密码等字段隐藏值；URL 移除 userInfo、查询参数及 fragment。诊断 ZIP 的字符串与结构化字段复用这些规则，并继续隐藏路径等信息。请求业务数据和实际发出的头不受日志脱敏影响。

## 验证记录与待验收

本地已通过：

- `flutter analyze`：无问题。
- 25 个相关 Flutter 测试文件，共 232 项：成功判定、会话范围、桥的限制、QuickJS 实际钩子调用、网页播放标记、取消／会话失效／脱敏、播放器后台与全屏生命周期，以及键盘、弹幕、HTML 和源设置流程回归。
- `node tool/check_verification_probe.mjs`：21 个厂商／状态样例及防误判检查。
- `node tool/check_verified_page_request.mjs`：固定 fetch、同源／路径／方法限制、Cookie 隔离、大响应和超时。
- `python tool/test_python_sources.py`：21 项，20 项通过，RSA 项因系统 Python 缺 bundled cryptography 后端跳过；签名钩子与网页标记测试通过。

Windows 上未执行 iOS 编译、RunnerTests 或 iPhone 联调。完成验收需要在 Mac 构建并在 iPhone 检查：随机 `__Host-*`、极验／腾讯人工验证、阿里云 WAF、三种运行时共享会话、规则 VPN 出口、请求桥失效与限制、页面 blob／WASM 播放及退出停止。实际站点必须逐站记录结果，不能从本地样例推导覆盖率或可播放率。

## 完整链路与原始问题验收表

下表将本地证据与真机结果分开。实站验收记录应包含 App 构建号、iOS 版本、站点／源版本、网络模式、操作时间和脱敏后的错误码；不要记录真实 Cookie、token 或签名。

| 项目 | 本地已验证 | iPhone 验收步骤与通过条件 | 实站状态 |
|---|---|---|---|
| 验证 → 搜索／分类 → 选集 → 播放 | 各阶段的会话、源桥、签名钩子及播放分流回归 | 同一源人工过验证后直接搜索／分类，进入详情选集并开始播放；全程无需重进 App；分别记录 Dart／QuickJS／Python 请求结果 | 待验收，未执行完整实站链路 |
| 验证退出与切源 | 验证取消不导入迟到会话；释放桥不等待迟到响应 | 验证中返回、跳过、切换源，再回来；窗口不重叠，旧请求不更新新页面 | 待验收 |
| 会话撤销 | 清理域、全局代理、站点 UA 与源域名变更回归 | 退出登录、清 Cookie、修改域名或代理后旧桥拒绝请求；重新验证后可恢复 | 待验收，包含站点私有 XHR 退出 |
| 后台与播放退出 | 顶层媒体暂停、前台不自动播放、退出加载空白页；全屏保留页面 | 人工验证中锁屏／回前台期限不重置；播放中后台、返回、刷新、全屏均无重复页面；退出无声音 | 待验收，重点检查跨域 iframe |
| 错误区分与脱敏 | 403 不伪装验证失败；会话／取消错误分类；日志、抓包、导出脱敏 | 分别断网、使会话过期、使用失效源签名；提示对应问题且不无限重开验证；导出不含凭据 | 待验收 |
| 弹幕匹配键盘 | `danmaku_match_sheet_test.dart` 横竖屏／焦点回归通过 | 对照原录屏输入、收起键盘、旋转、切换匹配；焦点与输入不丢失 | 待按原录屏真机复测 |
| 内置弹幕与规则 VPN | `danmaku_http_client_test.dart`、内置服务 Node 测试通过 | 同一作品同一集，VPN 关闭与规则模式分别搜索、拉弹幕；记录请求出口和错误，不能用本地服务启动成功替代上游成功 | 待联网真机复测 |
| 弹弹play 搜索／零弹幕 | `dandanplay_client_test.dart` 解析、映射与错误回归通过 | 使用确认有弹幕的作品集数搜索并匹配；区分确实零条、映射错误、凭据失败及网络失败 | 待联网真机复测 |
| HTML 点击播放推送失败 | SDK 参数兼容、作者解析器本地样例、HTTP 地址校验回归通过 | 导入原“独狼影视聚合.html”，点击原条目；作者解析出 HTTP(S) 媒体后成功进入播放，解析失败展示具体原因 | 待原文件／源接口真机复测 |

页面层测试使用平台替身，不验证 WebKit、系统 VPN、站点网络或实际解码能力。RunnerTests 新增取消后释放资源及拒绝旧桥用例，仍需 Mac 执行。
