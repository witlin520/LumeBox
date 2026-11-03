# Rex 模块、集合与首页包

## 导入数量

默认单次导入上限为 **2000 个源**，手动导入、粘贴地址清单、订阅展开及一键同步使用相同默认值；Rex 集合最多接受 2000 项。超过数量时保留截断提示与未完整同步状态，避免把未拉到的源误当成已删除。

这是源数量上限，与单个 ZIP 源包的文件数和解压大小限制不同。重复清单仍有循环检测。

## 链接分别有什么用

| 资源 | 用途 | 在 LumeBox 中的状态 |
| --- | --- | --- |
| [Rex 模块加密](https://rexnow.tv/encrypt/) | 作者将 JavaScript 制作为 REXENC 加密模块 | 加密工具，不是订阅地址；加密不会补齐宿主运行接口 |
| [模块解密工具](https://rex-decrypt.pages.dev/) | 通过服务端将模块内容或 URL 解密为源码 | 可辅助查看源码；不是本机解密，也不是稳定可用的 App 内加载后端 |
| [rex-home](https://github.com/kenxtbecdi7690/rex-home) | Rex 首页布局包和首页模块 | 首页包与独立源不同，不能直接套用 LumeBox 的首页；公开模块脚本采用 REXENC |
| [CatPaw 集合](https://rex.openharbor.dpdns.org/api/collections/catpaw.rex) | `widgets` 集合，列出模块地址 | 集合格式可识别，模块能否运行需另行判断 |
| [路也迢迢集合](https://raw.githubusercontent.com/Darklessing/catvod/refs/heads/main/rex/Module-collection/luyett.juhewp.rex) | 玩偶聚合、TG搜模块的地址清单 | 集合格式可识别，抽查脚本为 REXENC v2 加密模块 |

## 本次文件核对

2026-10-24 核对：

- `catpaw.rex.json`：JSON 集合，包含 15 个模块条目。
- 在线 CatPaw 集合：返回 15 项，抽查前两项为 REXENC v2。
- 路也迢迢集合：返回 2 项，两份脚本均为 REXENC v2。
- `rex-home.js`：REXENC v2，标记为 A256GCM、`mkv: rex-1`。
- `RexHome-内含加密脚本.rex`：实际为 ZIP 首页包，格式 `video.fika.rex.home-package`，包含 `rex-manifest.json`、`rex-home.json`、`rex-layout.json` 和 `rex-scripts/rex-home.js`。

解密工具页面声明在服务端解密。本次仅使用公开 RexHome 模块 URL 测试，没有上传用户本地文件；接口返回 HTTP 502，错误为 `key-session 请求失败 (403)`。因此未获得明文，也没有验证这些加密模块的首页、搜索或播放效果。

## 当前怎样导入

在视频源选择页点击「+」，可选择本地集合 JSON 或粘贴模块集合 URL。集合只负责列出脚本地址，**能识别集合不等于其中的模块能运行**。

LumeBox 已有明文 Rex/Forward Widget 适配器；REXENC v2 目前能识别信封，但尚未接通内容密钥加载协议，不能直接执行。应使用作者提供的明文 Widget 源码，再检查脚本所需的宿主接口。网盘模块还可能需要账号中心、登录会话及播放协议支持，不能仅凭文件导入成功判断已适配。

Rex 首页包不按普通 ZIP 源包导入。App 会明确提示它是首页布局包，并指向模块集合或独立脚本，避免误报“缺少 lume.json”。
