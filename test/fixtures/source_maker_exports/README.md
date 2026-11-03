# App 导入兼容样本

这些文件是本地 SourceMaker 导出的固定测试样本，使用 `fixture.invalid` / `media.invalid` 地址。App 测试以 MockClient 提供 `pages.json` 中的响应，验证导入器、QuickJS、内容模型、Kazumi、猫源和网页格式。

App CI 直接读取此目录，不启动 SourceMaker，也不安装其 Python 抓取或浏览器依赖。SourceMaker 的修改与测试仍在本地独立进行。

维护时可在本地准备好 SourceMaker 环境后生成候选样本：

```powershell
python tools/source_maker/make_fixtures.py build/source-maker-exports
```

核对导出变化后，只更新 App 需要的格式样本并运行 `flutter test test/source_maker_contract_test.dart`。`cat.zip.base64` 是导出 ZIP 的原始字节经过 Base64 编码，测试解码后交给真实 ZIP 导入器；其他文件保留导出的原始内容。此次快照生成于 2026-10-29。
