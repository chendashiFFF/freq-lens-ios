# 安装与连接

[返回首页](../README.md) · [使用指南](USER_GUIDE.md)

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 编译环境 | 能运行 Xcode 26.2 或更高版本的 Mac |
| 开发工具 | Xcode 26.2+，包含 iOS SDK 与模拟器运行时 |
| 目标设备 | iPhone，iOS 26.0 或更高版本；竖屏界面 |
| 第三方依赖 | 无；不需要 CocoaPods、Carthage 或额外 Swift 包 |
| 数据服务 | 你自己的 Freqtrade REST API；也可先使用内置演示数据 |

已验证环境为 Xcode 26.2、Swift 6.2.3、iOS 26.3.1 模拟器。详细结果见 [测试记录](../TESTING.md)。

## 在模拟器运行

```bash
git clone https://github.com/chendashiFFF/freq-lens-ios.git
cd freq-lens-ios
open FreqLens.xcodeproj
```

在 Xcode 顶部选择 `FreqLens` scheme 和 iPhone 模拟器，然后按 `⌘R`。首次启动会展示带“演示数据”标识的内容，不需要真实账号。

也可以使用命令行：

```bash
xcodebuild -project FreqLens.xcodeproj -scheme FreqLens \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

设备名称应替换为本机实际安装的模拟器。可用 `xcrun simctl list devices available` 查看。保持 Xcode 默认的模拟器签名，不要添加 `CODE_SIGNING_ALLOWED=NO`，否则 Keychain 相关功能或测试可能报错。

## 安装到自己的 iPhone

1. 在 Xcode Settings → Accounts 中登录自己的 Apple 账号。
2. 用数据线连接 iPhone，完成设备上的“信任此电脑”，按系统提示开启开发者模式。
3. 打开工程，选择 `FreqLens` target → Signing & Capabilities。
4. 保持 Automatically manage signing，选择自己的 Team。如默认 Bundle Identifier 无法注册，改成自己唯一的标识，例如 `com.yourname.freqlens`。
5. 在运行设备列表选择已连接的 iPhone，解锁手机，按 `⌘R`。
6. 如果系统要求信任开发者，按设备提示在设置中完成，然后重新打开 App。

运行测试时，如测试 target 提示缺少团队，也为对应测试 target 选择自己的 Team。

免费个人开发签名通常约 7 天有效，到期后需重新构建签名。付费开发者账号的可用分发方式与签名有效期取决于 Apple 规则及所选配置。仓库不包含作者的证书、描述文件或已注册设备信息。

升级时使用相同 Bundle Identifier 与签名身份覆盖安装，可以保留应用容器。模拟器和真机各有自己的容器与 Keychain，登录状态不会随构建自动迁移。更换应用标识会被系统视为另一个 App。

## Windows 能否使用

| 需求 | 可行方式 |
| --- | --- |
| 阅读、修改源码 | 在 Windows 使用 Git 与编辑器 |
| 编译 SwiftUI 工程 | 使用实体 Mac、云 Mac，或配置好的 macOS CI + Xcode |
| 安装已构建的 IPA | 使用支持 Windows 的 iOS 侧载工具，并满足工具与 Apple 的签名要求 |
| 通过 TestFlight 安装 | 维护者先完成 Apple 开发者与 App Store Connect 流程、上传测试构建并发出邀请 |

Windows 本身不能运行 Apple 的 iOS SDK。IPA 也不是双击即可安装的通用文件：它必须有适合目标设备或分发渠道的有效签名。个人设备开发版不能直接当作 TestFlight 包使用。

当前仓库没有配置云端签名构建，也没有提供 TestFlight 邀请。

## 连接 Freqtrade

先按照 [Freqtrade REST API 官方文档](https://www.freqtrade.io/en/stable/rest-api/) 启用并配置自己的 API 服务。服务器应能从手机所在网络访问。

在 App 右上角打开连接页，输入连接名称、API 地址、用户名和密码，点击连接。名称留空时使用服务器返回的机器人名称。

支持的地址形式：

```text
https://example.com
https://example.com/api/v1
https://example.com/bot
https://example.com/bot/api/v1
```

根地址和代理前缀会补齐 `/api/v1`。用户名和密码应填在单独的输入框中，不能嵌入 URL。地址不要携带查询参数或 `#` 片段；如有反向代理，应填写最终可用地址，客户端不会跟随重定向。

手机上的 `localhost` 指手机自身，不能用它访问电脑上的机器人；局域网部署应填写实际可达的服务器地址。App 支持 HTTP 以兼容自部署服务，HTTPS 可提供传输加密。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| Xcode 找不到模拟器 | 在 Xcode 设置中安装 iOS 运行时，或换成已有设备名称 |
| Signing / Team 报错 | 选择自己的 Team，检查 Bundle Identifier 和设备注册状态 |
| 无法自动打开手机上的 App | 解锁手机，检查开发者模式和开发者信任状态 |
| 登录失败 / 401 | 核对 Freqtrade API 用户名密码；令牌失效时重新连接 |
| 404 或地址无效 | 检查 `/api/v1`、反向代理前缀及最终地址是否正确 |
| 局域网连接失败 | 检查手机网络、系统“本地网络”权限和服务器监听配置 |
| 502 / 503 / 504 | 检查服务器或代理；App 会对 GET 有限重试，持续失败则提示并保留已有缓存 |
| 数据显示为 `—` | 可能缺少字段或区间数据不完整，详见 [数据口径](DATA_AND_API.md) |
| 历史清理被拒绝 | 查看错误原因；仍有未完成委托、状态改变或缺少校验字段时不会继续删除 |

[返回首页](../README.md)
