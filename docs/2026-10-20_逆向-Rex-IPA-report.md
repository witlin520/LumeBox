# Rex 1.0.1（7）脚本兼容检查

本文记录 `407b17f` 时的静态检查结论。后续明文运行时、集合、参数与离线播放适配进展见 [Rex Widget 接入](2026-10-20_Rex-Widget接入.md)；加密内容密钥部分仍未接通。

这份 IPA 能帮助确定真实 Widget 宿主接口，但目前还没有让加密的花卷／TG搜在 LumeBox 中运行。已定位 JavaScriptCore 运行时、同步存储桥、共享缓存及 AES-GCM 内容解密函数；同时发现独立的内容密钥存储器、密钥会话客户端和远端请求路径。尚未取得样例所需的内容密钥，也未恢复完整密钥会话协议，不能将“已找到解密函数”写成“加密源已支持”。

分析日期：2026-10-20。报告类型：普通互操作逆向，`flavor=null`。检查范围见 [scope](evidence/rex-1.0.1-7/scope.md)，过程见 [timeline](evidence/rex-1.0.1-7/timeline.md)。

## 样本与方法

| 属性 | 结果 |
| --- | --- |
| 原始文件 | `D:/最近的网络IPA/Rex.1.0.1(7).PRO.ipa` |
| 大小 | 91,052,990 字节 |
| IPA SHA256 | `d75e2fdf16bd88a294bd2b36b26b37f8be5ed3737aa6f0c0ec18bc745eeb9ca6` |
| 标识／版本 | `tv.rexnow.app`／`1.0.1`／build `7` |
| 最低系统 | iOS 17.0 |
| 主程序 | ARM64 Mach-O，84,773,040 字节；`cryptid=0`，允许静态读取代码 |
| 主程序 SHA256 | `2f59b22ad7f933364f6529bb9462b15b3d2c2d7a50bfeb60eecd1061e271de1a` |
| 工具 | Python 3.14、radare2 6.2.4、Capstone 5.0.7；本机未安装 IDA |

包内存在并加载 `Frameworks/hwpatch.dylib`。这说明样本包含额外动态库，不能仅凭文件名将它当作未修改的官方发行包；本次没有确认该库的完整行为或来源。

只做静态检查，未安装或启动 App，未执行包内 JS，未发送账户、证明或密钥请求。原始文件未改动。提取的可执行文件、Cheerio 和官方模块仅保留在忽略的本机缓存中，不随仓库分发。

## 证据

机器可读结果：[analysis.json](evidence/rex-1.0.1-7/analysis.json)，SHA256：`13909db910eb9a9fd5654e53777653e82d221339b65ce19ceb241fcbff626e26`（固定 LF 换行）。

| E-id | source_ref | 观察 | content_hash |
| --- | --- | --- | --- |
| E-001 | 原始 IPA／Info.plist／Mach-O load commands | 版本、体积、`cryptid=0`、依赖和额外 dylib | 上述 IPA／主程序 SHA256；其余见 JSON |
| E-imports | 主程序符号表与间接导入表 | 引入 JavaScriptCore `JSContext`／`JSValue`、CryptoKit AES-GCM／SymmetricKey、Security `SecItem*`、NSURLSession | 主程序 SHA256 |
| E-002 | `__cstring`，约 `0x104353440`—`0x104354e9b` | 真实 Widget 运行时字符串、12 个桥接方法名 | 主程序 SHA256 |
| E-003 | Swift 类型描述符 | `ScriptContentKeyStore` 的 `loadKey`／`saveKey`／`unwrapper`／`inflight`；`ScriptKeySessionClient` 的 `environment`／`session`／`attest` | 主程序 SHA256 |
| E-004 | 主程序 `0x101e78ffc`，调用点 `0x101e79324` | 检查 32 字节内容密钥；分离末尾 16 字节认证标签；调用 CryptoKit `AES.GCM.open` | 主程序 SHA256 |
| E-005 | `0x104342fa0`、`0x104341870`、`0x104341990` | `/api/widgets/key-session` 路径、密钥会话开始／成功日志及静态引用；JSON 列出引用地址 | 主程序 SHA256 |
| E-006 | `RexScript_RexScript.bundle` | Cheerio 资源、manifest，以及 bangumi／danmu／nlsearch／rex-tmdb 四份明文官方模块 | 各资源 SHA256 见 JSON |
| E-007 | 桌面原始花卷／TG搜脚本 | 三行 REXENC，v2、`rex-1`、A256GCM，IV 12 字节、kb 60 字节；尚未解密 | 各样本 SHA256 见 JSON |

E-001／E-imports／E-002／E-003／E-005／E-006／E-007 的复现命令，从项目根目录执行：

```powershell
python tool/rex/inspect_ipa.py 'D:/最近的网络IPA/Rex.1.0.1(7).PRO.ipa' `
  --module 'C:/Users/63089/Desktop/花卷(rex).js' `
  --module 'C:/Users/63089/Desktop/TG搜(rex).js' `
  --output '.cache/rex-compat/reproduced-analysis.json'
```

工具只读 ZIP、plist、Mach-O 和加密信封，不执行脚本，不输出 IV／kb 值或密文。ADRP 字符串引用是定位候选，不能单独用来证明完整调用链。E-004 另经 ARM64 反汇编核对；本机提取副本和工具位于 `.cache/rex-compat/`，可查看关键片段：

```powershell
& '.cache/rex-compat/radare2/radare2-6.2.4-w64/bin/radare2.exe' `
  -q -c 'pd 24 @ 0x101e792ec' '.cache/rex-compat/ipa/Rex'
```

## 发现与兼容影响

| F-id | severity | evidence_ids | confidence／status | location | 结论 |
| --- | --- | --- | --- | --- | --- |
| F-001 | n/a_re | E-002, E-006 | high／validated | Widget 宿主桥 | 实际 App 的存储、共享缓存及 HTML 加载是同步接口；只照公开 SDK 的异步声明实现会漏兼容 |
| F-002 | n/a_re | E-imports, E-003, E-004, E-005, E-007 | medium／candidate | ScriptModuleCrypto／ScriptContentKeyStore／ScriptKeySessionClient | 静态证据支持“信封解析、取得内容密钥、AES-GCM 解密”的分层结构，并存在远端密钥会话；完整密钥来源及服务约束尚未验证 |
| F-003 | n/a_re | E-006 | high／validated | OfficialModules／manifest.json | `.rex` 集合与 `WidgetMetadata` 明文模块是独立的适配层，不能等同于普通 ESM／CommonJS |
| F-004 | n/a_re | E-001 | high／validated | LC_LOAD_DYLIB／hwpatch.dylib | 当前样本包含额外动态库，官方行为和样本修改行为需要区分；未分析其完整修改效果 |

实际宿主接口差异：

| 接口 | 此包观察到的行为 | LumeBox 适配要求 |
| --- | --- | --- |
| `Widget.storage` | `get/set/remove/keys/clear` 同步桥接 | 同步读取；按模块持久化隔离，不能仅替换成异步 fs |
| `Widget.sharedCache` | 显式 namespace 的跨模块同步 get/set/remove/keys | 需要与私有存储分开的共享空间；账号中心与其他模块可依赖它 |
| `Widget.http` | 异步 GET／POST／PUT／DELETE／request；参数包含 headers、params、data、allow_redirects、base64Data、decodable；GET／POST 还传 zlibMode | 沿用宿主网络配置，并匹配请求参数和响应格式 |
| `Widget.html.load` | 加载包内 Cheerio，直接返回查询函数 | 简化 CSS 查询器不等于完整 Cheerio；需要验证常用链式操作 |
| `Widget.tmdb.get` | 异步原生 TMDB 桥 | 连接用户 TMDB 配置及参数；不可假设任意 TMDB 列表项自带播放地址 |
| `Widget.i18n` | 同步本地化桥 | 支持 `WidgetMetadata.i18n` 的回退行为 |
| `WidgetMetadata`／函数 | catalog、search、stream、danmu 等模块类型；详情和资源解析入口分开 | 分别映射到分类、搜索、详情、播放；弹幕／字幕不能当作普通视频列表 |

公开参考：[Rex SDK](https://github.com/baranwang/rex-widget-libs) 与 [Forward Widget 文档](https://forward-2.gitbook.io/forward/fu-lu-er-forward-widget-kai-fa-zhe-zhi-chi)。这些资料与此包共同确定接口，不能据此推断所有客户端私有协议均兼容。

### P-001：加密加载检查路径

- `path_type=callflow`；起点为用户提供的 REXENC 文件，目标为确认跨客户端运行条件。
- E-007：识别信封版本、算法、IV 与 kb 长度。
- E-003／E-005：定位内容密钥存储器及独立密钥会话客户端；密钥会话包括 `attest` 字段。当前仅有静态证据，尚不能确定特定请求需要哪些账户／设备证明。
- E-004：解密函数接受 32 字节内容密钥，使用 AES-GCM 验证认证标签并还原正文。
- E-imports／E-002：脚本运行与 Widget 宿主桥由 JavaScriptCore／原生实现承接。
- `residual_risks`：尚未串实密钥回调到远端请求的完整数据流，未得到两个样本对应密钥，未验证明文、分类、搜索或播放；没有证据证明存在可直接移植的通用离线主密钥。

## 当前交付边界

本次完成 IPA 的静态检查、差异定位和可复现检查工具。LumeBox 现有 ESM／CommonJS、Python 和 Spider 能力没有因此自动获得 Rex Widget 协议或 REXENC 解密能力；本轮没有修改应用运行时，也没有生成安装包。

后续实现需要分别完成 `.rex` 集合导入、明文 Widget 运行时／数据映射、同步存储与共享缓存、网络／HTML／TMDB 桥，再取得可用且获授权的密钥加载协议验证加密源。花卷／TG搜继续记为未解密、未播放验证。
