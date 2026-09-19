# 参与开发

[返回首页](README.md) · [架构](docs/ARCHITECTURE.md) · [测试](TESTING.md)

## 开始之前

项目只面向 iOS 26+ iPhone，使用 SwiftUI 和 Swift Charts。请先按 [安装文档](docs/INSTALLATION.md) 在本机运行演示数据，再阅读与你修改相关的模块说明。

项目定位是数据查看中心。当前持仓没有交易操作；唯一的修改接口是经过明确确认的已平仓历史清理。功能建议应说明它如何帮助数据查看，避免把交易操作混入查看流程。

## 问题反馈

通过 [GitHub Issues](https://github.com/chendashiFFF/freq-lens-ios/issues) 提供：

- App 版本、iOS 版本；构建问题请附 Xcode 版本。
- 演示模式还是真实 API，以及 Freqtrade 版本。
- 可复现步骤、期望行为、实际行为。
- 已脱敏的截图或错误文本；接口兼容问题可附字段结构，不需要真实账户记录。

不要上传真实密码、令牌、服务器缓存、个人签名材料或含账户信息的完整测试结果包。

## 提交代码

1. 从 `main` 建立自己的功能分支。
2. 将修改限制在清晰的功能范围；按模块拆分提交。
3. 数据或网络行为变化时补充有意义的回归验证，界面变化同时检查深浅色。
4. 更新相关说明和截图，确认示例仅使用演示数据。
5. 提交 Pull Request，说明问题、最终行为、验证方式和仍存在的限制。

建议的提交范围：`core`、`analytics`、`design`、`ios`、`test`、`docs`。例如：

```text
fix(analytics): 修正跨 UTC 日后的区间缓存
feat(ios): 改进月历日期选择反馈
docs: 更新安装步骤与演示截图
```

## 修改约束

- 缺失盈亏不能转换为零；胜率分母包含持平交易。
- 区间归属按 UTC 平仓日；日历月份与全局时间范围相互独立。
- UI 更新在主 actor，统计和磁盘 I/O 放在后台。
- 切换服务器后不得展示前一服务器的晚到数据。
- 删除必须保留预览、确认、逐笔新状态检查、遇错停止和缓存失效流程。
- 网络测试使用模拟服务，不对真实账户执行删除或其他写操作。
- 不要提交 `Preview/`、`VALIDATION.md`、`xcuserdata/`、证书、描述文件或构建产物。

## 验证

```bash
xcodebuild -project FreqLens.xcodeproj -scheme FreqLens \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

git diff --check
```

请把设备名称换成实际可用的模拟器，并保持默认签名。只修改 Markdown 或截图时，检查相对链接、图片显示、事实准确性和敏感数据即可，无需重复运行无关的 App 测试。

目前测试由开发者本机运行，仓库尚未配置自动 CI；不要把已有验证记录理解为每个提交都已自动通过。
