# 开发与发布

本文面向参与 Viewin 开发和版本发布的维护者。

## 源码构建

需要 Xcode 27、`xcbeautify` 和配套的 `ViewinSDK` 目录。Sparkle 和 ZIPFoundation 由 Swift Package Manager 获取。

```text
workspace/
├── Viewin/                  # 本仓库；目录名也可以保留为 InView
│   ├── Viewin.xcodeproj
│   ├── Viewin/               # SwiftUI / AppKit 界面、预览与资源
│   ├── Core/                 # 快照、连接、功能状态和 CLI
│   ├── Config/               # App 标识、版本、签名权限与更新配置
│   └── scripts/              # CLI 打包与版本发布工具
└── ViewinSDK/                # 独立 SDK、协议和 iOS / Android Demo
```

SDK 目录必须命名为 `ViewinSDK` 并放在同一父目录。当前 SDK 远程分发尚未配置，单独克隆桌面仓库还不足以构建。

打开 `Viewin.xcodeproj`，选择 Viewin scheme 和本地开发签名团队，然后运行。命令行构建示例：

```sh
set -o pipefail
xcodebuild -project Viewin.xcodeproj -scheme Viewin \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/viewin build 2>&1 | xcbeautify

swift test --package-path Core --scratch-path .build/viewin-core

# 从源码运行 CLI
swift run --package-path Core --scratch-path .build/viewin-core viewin --list
```

沙盒和 Sparkle 的本地调试建议使用 Apple Development 签名。Xcode 的 Embed CLI 阶段会把 CLI 和语言资源一起打包进 App。

`Config/Base.xcconfig` 管理正式 App 名称、Bundle ID、版本号和更新验证公钥；`Debug.xcconfig` 覆盖开发版名称与 Bundle ID。版本升级不需要直接编辑 `.pbxproj`。

内部采用 Observation 与单向数据流，按连接、层级、预览、测距和检查器拆分状态；不依赖 TCA。运行时日志使用系统 Logger。

## 发布版本

正式发布需要 Developer ID 签名、公证，以及与 App 中公钥对应的 Sparkle 更新私钥。开发证书签名的测试包不能直接作为正式更新发布。

1. 更新 `Config/Base.xcconfig` 的展示版本和递增构建号。
2. 在 Xcode 中 Archive，并以 Developer ID 方式导出、公证和装订票据。
3. 使用发布工具生成 ZIP、签名和 `appcast.xml`，核对版本、更新说明及下载地址。
4. 创建 GitHub Release 草稿，上传安装包和 `appcast.xml`；完成检查后再公开发布。
5. 用已安装的旧版本验证“检查更新 → 下载 → 安装 → 重启”，确认 CLI 仍可使用。

发布工具使用本地钥匙串账号 `app.viewin.updates`。首次配置的公钥位于 `Config/Base.xcconfig`，私钥只保存在钥匙串中；换机发布时需要安全迁移同一把密钥。

```sh
# 只在本地生成归档和 appcast，不上传
python3 scripts/release.py prepare /path/to/exported/Viewin.app \
  --notes /path/to/release-notes.md --output work/release-v0.1.0

# 远端已有对应版本 tag 后，上传为草稿；不会自动公开发布
python3 scripts/release.py draft work/release-v0.1.0
```

`prepare` 检查 Developer ID 签名、公证装订票据、公钥、版本和 CLI 是否完整，再生成 ZIP 与签名后的 appcast。`draft` 核对文件摘要和下载地址，且要求远端 tag 已存在，不会替你推送源码或覆盖已有 Release。

更新私钥和证书不属于源码。`work/`、设计源文件、调研资料及本地构建目录不应提交；iOS framework / xcframework 分发产物使用 Git LFS。
