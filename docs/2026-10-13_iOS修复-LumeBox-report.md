# LumeBox iOS 问题修复对照（2026-10-13）

本轮修复了无障碍导航下控制栏消失、测速误报及跳转异常无提示的问题，并保留上一轮网络请求头和 Cookie 修复。已有提交 `41d779f` 已处理 MPV 销毁、漫画导入后数据库关闭、弹幕持久化及提示文案问题。

**当前环境为 Windows，没有运行 Xcode、iOS 模拟器或 iPhone。系统无障碍接口空树、MPV 暂停态跳转未更新仍未完成原生复测。自动化测试通过不能代替这些验收。** 原始复测记录保持原样，本文另记当前状态。

## 对照原始清单

| 原始编号 | 当前实现与证据 | 验收状态 |
|---|---|---|
| P0-1 MPV 销毁崩溃 | `41d779f` 删除抢先销毁视频输出，交给 media_kit 的 Player 释放链；回归用例包含静态守卫 | 已有代码修复，仍需 iOS 原生验证 |
| P1-2 漫画导入后库关闭 | 探索页按 revision 原位刷新，不关闭借用的板块管理器；现有行为测试通过 | 自动化回归通过 |
| P1-3 系统无障碍空树 | 本轮只修复可确认的控制栏自动隐藏问题：启用 accessibleNavigation 后保持可见，运行中开启也恢复隐藏控件 | 控制栏修复已验证；系统空树未解决 |
| P2-4 弹幕开关未保存 | 库就绪前的用户设置不被覆盖，并补落库；现有行为测试通过 | 自动化回归通过 |
| P2-5 网页视图文案不符 | 已改为手动点击提示，保持手动验证设计 | 自动化回归通过 |
| O-1 偶发 90 秒不起播 | 原记录后续未复现，本轮没有据此改动解码和缓冲策略 | 未定性 |
| O-2 MPV 暂停时前进 10 秒不动 | 本轮增加内核拒绝 seek 时的错误捕获、日志及失败提示；不伪造新位置，不强制恢复播放 | 错误反馈已验证；原现象仍需原生复测 |
| O-3 测速无读数 | 原实现已有失败提示；本轮排除错误状态码与 HTML 验证页，并覆盖源的小写 Range 头 | 自动化回归通过；站点拒绝探测时仍如实失败 |

## 本轮证据 → 问题 → 修复路径

| 证据 | 问题 | 修复路径 |
|---|---|---|
| E-01：`test/http_header_regression_test.dart` 在修复前两条均失败 | 小写 UA 被覆盖，旧、新验证 Cookie 重复发送 | `lib/core/net/lume_http.dart` 统一需合并的头名，按配置、脚本、验证会话合并 Cookie |
| E-02：`test/player_full_feature_test.dart` 覆盖启用无障碍导航、播放中开启及关闭 | 自动隐藏会移除正在导航的控件 | `lib/features/video/video_player_page.dart` 订阅 MediaQuery 无障碍导航变化，取消隐藏计时并恢复控制栏 |
| E-03：`test/player_speed_response_test.dart` 覆盖 403/404/500 大响应、200 HTML、206 媒体及小写 Range | 错误页也可能被当成测速成功；源自带 Range 干扰探测范围 | `lib/features/video/player_speed_meter.dart` 校验状态码与类型，替换所有大小写 Range |
| E-04：`test/player_full_feature_test.dart` 用抛异常的播放器模拟拒绝跳转 | unawaited seek 异常未被处理，用户没有失败反馈 | `_seekBy` 等待内核调用，捕获异常并记录原位置与目标位置；只对仍活动的播放器显示失败提示 |

## 验证命令

在项目根目录运行：

```powershell
flutter analyze --no-pub
flutter test --no-pub test/http_header_regression_test.dart test/player_speed_response_test.dart test/ios_retest_regressions_test.dart test/player_full_feature_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
git diff --check
```

全量测试输出保存于 `.tmp_shots/ios-fixes-all-tests.log`（本地忽略目录）。缺少 QuickJS 原生库或外部源资源的用例会注明原因并跳过。

本轮结果：静态分析无问题；全量测试 **1314 通过、178 跳过、0 失败**；`git diff --check` 无空白错误。修改留在工作区，未提交、未打包。

## iOS 验收步骤

1. 使用包含当前工作区修改的新构建。MPV 正常起播后切换到 AVPlayer、MDK，再分别进入 MPV 并退出播放页；每次等待至少 15 秒，检查是否崩溃。
2. VoiceOver 关闭时启动并播放视频，再开启 VoiceOver；读取返回键、底部导航与播放器控件。进入全屏等待超过 5 秒，控件应保持可读。退出播放页后确认整个应用的系统无障碍树是否恢复或仍为空。
3. MPV 暂停于非零时间，点前进、后退 10 秒，核对真实位置与画面，确认仍是暂停态。若失败，保存播放日志和系统日志；没有异常提示不代表原生 seek 已完成。
4. 配置失效的验证 Cookie，再通过手动网页视图取得新会话；重试源请求，确认只使用最新同名 Cookie。站点本身的挑战、连接重置和超时仍需单独判断。
5. 从空漫画源导入订阅，关闭结果弹窗；确认探索页刷新。关闭弹幕后退出、重开播放页，确认开关保持。

原始记录引用的是另一台 Mac 上的证据目录。该目录未在本机提供，本轮未重新读取原始 `.ips`、XCTest 结果包或系统日志，相关结论沿用用户提供的记录并保留此限制。
