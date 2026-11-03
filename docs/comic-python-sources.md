# 漫画 Python 源

漫画板块可从「源管理 → 导入」选择 `.py` 文件，或粘贴 Python 源代码。需要包含 Python 运行环境及漫画 PY 支持的新版本 App；导入不会自动安装额外依赖。

## 声明与接口

脚本可用 `# LumeSource:` JSON 注释声明 `id`、`name`、`version` 和 `category: "comic"`。没有声明板块的普通 Python 脚本按导入入口归属；明确声明 `video` 的脚本不能当作漫画源导入。

使用 `Spider` 协议：

| 接口 | 内容 |
| --- | --- |
| `homeVideoContent`、`categoryContent` 或 `searchContent` | 用 `vod_id`、`vod_name`、`vod_pic` 返回漫画条目 |
| `detailContent(ids)` | 返回漫画详情；`vod_play_url` 用「章节名$章节地址」表示章节，多章以 `#` 分隔 |
| `imageContent(chapter_id)` | 返回非空图片列表 `images`，按阅读顺序排列 |

`imageContent` 也支持 `getImageContent`、`chapterContent`、`getChapterContent` 别名。已有 `playerContent` 返回图片列表的脚本同样兼容。视频或网页地址不能代替漫画图片。

## 图片与请求头

`images` 可以是图片 URL 字符串列表，或包含 `url`、`headers` 的对象列表。支持相对章节网址的图片路径，仅接受 HTTP(S)。

所有图片共用的请求头放在 `headers`；逐图请求头放在 `imageHeaders`，以图片网址为键。每张图片的独立请求头会覆盖公共同名字段，适合需要 Referer 的站点。

漫画和视频的 Python 运行上下文、网络客户端与脚本存储分别隔离，同名源不会互相覆盖。

## 验证

`python tool/test_python_sources.py` 检查生产 Python 宿主的章节与图片返回、请求头、非法图片拒绝及原有视频兼容性。

`flutter test test/python_source_channel_test.dart test/source_packages_test.dart test/source_script_import_test.dart test/source_import_input_test.dart` 检查导入识别、漫画引擎、图片载荷转换和跨板块网络隔离。此验证不代替 iOS 真机阅读测试。
