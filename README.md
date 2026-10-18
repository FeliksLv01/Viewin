# Viewin

面向人和 Agent 的布局检查工具。macOS 客户端使用 SwiftUI 三栏、系统 NSToolbar、NSTableView 层级树与 SceneKit 2D/3D 预览。

当前已实现自己的 UIKit SDK、版本化通信协议和无需打开 GUI 的采集 CLI。不再编入 LookinServer、LookinShared 或 PeerTalk；Lookin / LookInside 作为交互与后续采集技术的研究参考。SwiftUI 当前可检查 UIKit 宿主视图，逻辑树、Android 真实采集、USB、无线配对和完整 Agent 安装仍待实现。

## 仓库与目录

本仓库只维护 macOS 产品。移动端 SDK、Demo、协议规范独立维护在同级 `ViewinSDK` 仓库。

```text
WorkSpace/
├─ InView/                       # 当前 macOS 仓库，产品名 Viewin
│  ├─ Viewin.xcodeproj
│  ├─ Viewin/               # SwiftUI / AppKit 界面
│  ├─ Core/                      # 桌面端状态、连接、快照与 CLI
│  └─ Config/
└─ ViewinSDK/               # 独立 Git 仓库
   ├─ Package.swift              # iOS SDK 与桌面共享协议产品入口
   ├─ ios/
   ├─ android/
   ├─ protocol/
   ├─ examples/ios/
   └─ docs/
```

开发时请将两个仓库检出到同一父目录，SDK 目录名为 `ViewinSDK`。Xcode 工程引用 `../ViewinSDK`，Core 引用 `../../ViewinSDK`；无需修改绝对路径。当前未配置 SDK 远程地址，独立克隆本仓库时还需单独获取 SDK 仓库。

SDK 接入只选择 `ViewinSDK` 产品；`ViewinProtocol`、`ViewinTransport` 是桌面与 SDK 共用的实现模块。桌面内部包唯一第三方依赖为 ZIPFoundation 0.9.20。

## 运行

打开 `../ViewinSDK/examples/ios/ViewinDemo.xcodeproj`，在模拟器运行 Demo。Demo 显式调用：

```swift
import ViewinSDK
try Viewin.start() // 默认仅监听 127.0.0.1:48721
// Viewin.stop()
```

随后打开 `Viewin.xcodeproj`，运行 Mac App。启动后会直接查找可检查的 App：首次只发现一个时自动读取并进入检查界面；发现多个时在主体区域显示预览卡片，点击进入。未发现时提供连接帮助、重新查找和打开快照入口。检查过程中可从工具栏切换 App。已移除离线示例入口及生产包中的示例资源。

SDK 不使用 `#if DEBUG` 自动禁用，内部 Release 包可按相同方式显式开启；发布包应由接入方的构建配置决定是否包含/启用它。当前连接已验证到模拟器，不代表物理设备 USB 或无线已实现。

```sh
swift run --package-path Core viewin --list
swift run --package-path Core viewin --port 48721 --output capture.viewin
```

CLI 直接连接 SDK，不启动图形 App。默认快照为 `.viewin` ZIP 归档，JSON + 去重 PNG；`--format json` 导出调试目录。兼容读取旧 `.uiinspector` / `.inview` 快照。

## 状态与验证

已移除官方 TCA 库及其所有传递依赖，保留按功能拆分状态和 Action 的单向数据流，使用原生 Observation、Swift Concurrency 和独立任务取消。相机、层级、检查器与逐张属性卡片各自观察。显示名、Bundle ID、版本与图标名均由 `Config/*.xcconfig` 配置。

```sh
swift test --package-path Core
```

Xcode 构建输出统一通过 xcbeautify。测试数据只位于测试支持 target，不随 App 打包。iOS framework 分发产物一律使用 Git LFS。
