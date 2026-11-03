# 漫画翻译配置与部署

在「设置 → 阅读与播放 → 全局翻译」选择翻译方式，也可从漫画阅读页的「翻译 → 翻译语言与引擎」进入同一份配置。

首页标题、搜索结果、漫画对白和圈选文字共用目标语言、原文语言、AI 接口和密钥。可选「系统翻译（本地）」「AI 翻译（联网）」「系统失败后用 AI 补译」。补译仅发送系统未成功翻译的文字；系统成功的译文保留。AI 补译失败时保留已有译文和原文，取消操作不会触发 AI。选择补译即允许把失败文字发送给已配置的 AI 服务。

三种方式的译文缓存分别保存，改变目标语言或 AI 接口、模型后不会误用旧配置的 AI 译文。旧系统译文缓存继续可用。密钥仍保存在本机安全存储中。

「漫画使用整图翻译服务器」是独立开关：开启时漫画图片走整图后端，标题和搜索结果仍按全局方式翻译；关闭时漫画文字跟随全局方式。

## 已拿到私人配置文件

把 `LumeBox-翻译配置.json` 发到手机，在漫画翻译设置顶部点击「导入翻译配置文件」并选择它。App 自动填写地址、模型、目标语言及密钥，切换到 AI 翻译；返回漫画即可选择当前页、本章、本系列或圈选翻译。密钥保存在系统钥匙串，不进入 App 备份。

导入入口需要包含该功能的新版 App。配置文件包含你个人的访问密钥，应仅自己保存和使用。

## 直接使用 AI 接口

1. 选择「自填 AI 接口」。
2. 填写服务商提供的完整 HTTPS Chat Completions 接口地址，通常以 `/v1/chat/completions` 结尾；模型名称按服务商文档填写。
3. 填写 API Key，点击「保存并测试 AI 翻译」。看到 `Hello → 译文` 后返回阅读页翻译。

无需自建服务器。文字先由本机 OCR 识别，只将文字发送到接口；模型须返回与输入顺序、数量一致的 JSON 字符串数组。连接测试会发送一条测试文字，可能产生服务商费用。

## 使用漫画图片翻译服务器

需准备兼容 [manga-image-translator](https://github.com/zyddnys/manga-image-translator) 的图片翻译服务。服务端安装模型、配置翻译器密钥，并提供同步 PNG 接口 `/translate/with-form/image`。

1. 打开「漫画使用整图翻译服务器」，填写服务的根地址或完整接口地址。
2. 若服务要求 Bearer Token，填写「服务器访问密钥」。密钥与 AI Key 分开保存。
3. 选择服务端已安装的 OCR 和翻译器；点击「保存并测试图片翻译」。测试会上传一张写有 Hello 的小图片，验证返回值为 PNG。

完整翻译会上传漫画图片，服务端完成识别、翻译、擦字及排版。模型部署方法以所用后端版本的官方文档为准。

## 部署 Cloudflare 网关

仓库提供 `deploy/translation-worker`，默认直接使用 Cloudflare Workers AI 的 Qwen3 多语言模型，无需另申请 AI 服务商密钥。也可改为转发到自己的 AI 或图片翻译后端。网关不运行 OCR、擦字或图片模型，不能代替图片翻译服务器。模型通过 [Workers AI binding](https://developers.cloudflare.com/workers-ai/configuration/bindings/) 调用。

在仓库根目录打开 PowerShell：

```powershell
Set-Location deploy/translation-worker
node --test worker.test.mjs
npx wrangler login
npx wrangler deploy
npx wrangler secret put ACCESS_TOKEN
```

按提示输入值：

| 名称 | 填写内容 |
| --- | --- |
| `ACCESS_TOKEN` | 自己生成的随机访问密钥，稍后填进 App 的 API Key |

部署成功后，App 的 AI 接口填「部署输出的 Worker HTTPS 地址 + `/v1/chat/completions`」，模型名填 `lumebox-translation`，App 的 API Key 填 `ACCESS_TOKEN`。也可以将这些值整理为私人连接配置文件，通过 App 导入。

Cloudflare 提供每日免费额度，额度由同一账号下的 Workers AI 共享；Free 套餐超过额度后请求失败，不会自动升级付费套餐。Paid 套餐超出免费额度会按用量计费，详见[官方价格](https://developers.cloudflare.com/workers-ai/platform/pricing/)。

如需第三方 AI 接口，将 `wrangler.jsonc` 中的 `AI_BACKEND` 改为 `proxy`，设置下列 Secrets 后重新部署：

```powershell
npx wrangler secret put AI_UPSTREAM
npx wrangler secret put AI_UPSTREAM_KEY
npx wrangler deploy
```

`AI_UPSTREAM` 填服务商完整 HTTPS Chat Completions 地址，`AI_UPSTREAM_KEY` 填服务商密钥，App 模型名改为该服务商的模型名称。

图片翻译转发可单独配置，也可以与 AI 转发使用同一个 Worker：

```powershell
npx wrangler secret put MANGA_UPSTREAM
# 仅当图片后端要求访问密钥时执行下一行：
npx wrangler secret put MANGA_UPSTREAM_TOKEN
```

`MANGA_UPSTREAM` 填图片后端完整 HTTPS `/translate/with-form/image` 地址。App 选择「漫画翻译服务器」，地址填 Worker HTTPS 根地址，服务器访问密钥填 `ACCESS_TOKEN`。图片后端自己的密钥填 `MANGA_UPSTREAM_TOKEN`。

只使用图片后端时，不需要设置 `AI_UPSTREAM` 和 `AI_UPSTREAM_KEY`。没有后端地址的接口返回「上游未配置」，不会转发到用户请求指定的网址。不能通过浏览器打开首页来判断翻译是否成功，应使用 App 内的连接测试。

## 圈选翻译

阅读页打开「翻译 → 翻译选定区域」，手指圈出对白或拖动选择区域，点击「翻译选区」。可切换「缩放浏览」移动、缩放长图，再切回圈选。译文预览满意后点击「应用到当前页」。

开启「圈选翻译」后，长按图片直接进入选区工具；关闭后恢复图片操作菜单。设备端与 AI 模式将圈内文字合并为一个对话框翻译；服务器模式仅上传裁剪后的选区，返回图片再合成回当前页。应用仅作用于本次阅读，不改写原图或下载文件。
