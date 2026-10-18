<p align="center">
  <a href="https://github.com/FeliksLv01/Viewin">
    <img src=".github/images/viewin-icon.png" width="112" height="112" alt="Viewin icon" />
  </a>
</p>

<h1 align="center">Viewin</h1>

<p align="center"><a href="README.md">English</a> · 简体中文</p>

<p align="center"><strong>看清 App 的视图层级、布局与属性。</strong></p>
<p align="center">面向开发者和 AI Agent 的移动端布局检查工具。</p>
<p align="center">UIKit · SwiftUI · Android View / XML · Jetpack Compose</p>

<p align="center">
  <a href="https://github.com/FeliksLv01/Viewin/releases">下载与版本记录</a> ·
  <a href="#开始使用">快速开始</a> ·
  <a href="#cli-与-agent-skill">CLI / Agent Skill</a> ·
  <a href="https://github.com/FeliksLv01/Viewin/issues">反馈问题</a>
</p>

<p align="center">
  <img src=".github/images/viewin-overview.png" alt="Viewin：UIKit 与 SwiftUI 层级树、3D 布局预览和属性检查器" width="1200" />
</p>

<p align="center"><sub>UIKit 与 SwiftUI 混合界面的真实采集快照：层级树、3D 预览和结构化检查器。</sub></p>

> 当前处于早期开发阶段，尚未发布首个安装包。移动端 SDK 已[独立开源](https://github.com/FeliksLv01/ViewinSDK)，Android Maven 制品托管在公开 GitHub 仓库；SwiftPM 在版本标签发布前可使用 main 分支。以下说明区分已经实现的能力与仍待验证的部分。

## 能做什么

- **查看实际层级**：三栏布局、可调整宽度的层级树与检查器，搜索、聚焦、展开和收起节点。
- **理解布局关系**：2D / 3D 切换、自由旋转、触控板缩放、边界与层间距设置，侧边栏和预览同步选中。
- **读取结构化属性**：布局、可见性、颜色、字体、阴影、成员引用、列表位置，以及框架特有的属性分组。颜色支持 RGBA / HEX。
- **检查事件与手势**：只读查看已采集的 recognizer、控件事件、Target / Action 或语义操作信息。
- **测量图层距离**：选中一个图层，再悬停另一个图层；支持 2D / 3D、按住 Option 临时测距和按钮锁定。
- **保存与共享快照**：将层级、属性和图片保存为单个 `.viewin` 文件，之后无需连接设备即可打开。
- **让 Agent 使用相同数据**：通过 CLI 发现 App、采集快照或导出 JSON / 图片，不要求打开桌面 App，也不依赖 MCP。

界面支持简体中文和英文，跟随 macOS 系统或单 App 语言设置。运行时采集到的文字、类型名和属性 API 名保留原样。

## 支持范围

| 框架 | 当前能力 | 需要注意 |
| --- | --- | --- |
| UIKit | View / Layer 层级、属性、截图、手势与控件事件、Table / Collection 列表位置 | Debug 与内部 Release 可显式启用；部分系统绘制效果不能完整重现 |
| SwiftUI | 可读逻辑树、已识别的 Modifier 与静态手势、渲染图层关联 | 当前适配并实测 iOS 27 模拟器；Release 能力以实际读取结果为准，失败时回退宿主层级 |
| Android View / XML | View 树、布局参数、resource ID、状态、截图、RecyclerView / AdapterView 位置 | RecyclerView 包含 Adapter、LayoutManager、ViewHolder 与绑定位置；XML 文件和行号不提供 |
| Jetpack Compose | Debug 下的布局节点、参数、Modifier 和 Semantics | 内部 Release 可降级为 Semantics；Lazy 列表只采集已放置节点；尚无独立绘制层纹理 |

**3D 预览不代表每一个逻辑节点都有独立图片。** SwiftUI 只有成功关联的部分叶子节点使用真实 CALayer 纹理；其余节点和 Compose 可能只提供收起子树时的宿主合成裁切。展开的逻辑容器显示边框，不重复贴整张子树图片。

缺失信息、部分采集和不支持的能力会在快照中记录。SwiftUI 私有运行时结构、混淆和框架版本变化都可能影响采集结果。

## 开始使用

### 1. 安装桌面 App

桌面端最低要求 **macOS 15.6**。首个正式安装包发布后，可从 [GitHub Releases](https://github.com/FeliksLv01/Viewin/releases) 下载并放入“应用程序”目录。

### 2. 在自己的 App 中启用 SDK

桌面 App 和移动端 SDK 是两个独立仓库。本仓库不包含移动端采集代码。接入方式见 [ViewinSDK](https://github.com/FeliksLv01/ViewinSDK)：iOS 使用 SwiftPM，Android 使用 [Maven 依赖](https://github.com/FeliksLv01/ViewinSDK/blob/main/android/README.md)，无需导入 SDK 源码模块。

**iOS**：选择 `ViewinSDK` 产品，在 App 启动时调用。检查 SwiftUI 时，应在首个 SwiftUI 宿主创建前启动。

```swift
import ViewinSDK

try Viewin.start()
// Viewin.stop()
```

SDK 最低 iOS 15。可通过 `buildType: .debug` 或 `.internalRelease` 声明构建类型；它是诊断信息，不保证某项采集能力一定可用。Debug 和内部 Release 都由宿主显式决定是否集成、启用 SDK。

**Android**：添加 [SDK Maven 仓库](https://github.com/FeliksLv01/ViewinSDK/blob/main/android/README.md)后，依赖 `io.github.felikslv01.viewin:viewin-sdk:0.1.0`，或 Compose 模块 `io.github.felikslv01.viewin:viewin-compose:0.1.0`。在 `Application.onCreate` 中启动。普通 View 宿主依赖 `viewin-sdk`；Compose 宿主选择包含基础 SDK 的可选模块 `viewin-compose`，并在首次 `setContent` 前启动。

```kotlin
Viewin.start(
    this,
    buildType = if (BuildConfig.DEBUG) Viewin.BuildType.DEBUG
                else Viewin.BuildType.INTERNAL_RELEASE
)
// Viewin.stop()
```

Android 最低 API 29。当前 Compose 适配基于 UI / tooling-data 1.10.6；更多版本需要逐步验证。

### 3. 连接并检查

保持目标 App 在前台，打开 Viewin。启动页会显示找到的 App；仅找到一个时自动读取，多个时点击预览进入。检查期间可在工具栏切换 App，也可以打开已保存的快照。

| 连接方式 | 当前状态 |
| --- | --- |
| iOS 模拟器 | 已验证，本机直连 SDK |
| Android 模拟器 | 已验证，自动发现并建立 ADB 转发 |
| Android USB 真机 | 连接路径已实现，需要授权 USB 调试；尚未完成真机实测 |
| iOS USB 真机 | 待实现 |
| 无线发现与配对 | 待实现 |

SDK 默认只监听 `127.0.0.1:48721`。Android 需要先通过 Android Studio 或 `adb start-server` 启动本机 ADB 服务。Viewin 直接与 ADB 服务通信，按需发现设备和建立转发，无需桌面 App 启动外部 ADB 进程。

找不到 App 时，先确认 SDK 已启动、目标 App 位于前台，以及 Android 的 ADB 服务和设备授权正常，再点击重新查找。

## CLI 与 Agent Skill

桌面 App 内附带 CLI。打开 **设置 → Agent**，可以安装或更新 `viewin` Skill，并复制 CLI 命令。安装 Skill 后，Agent 能在不打开 Viewin 的情况下检查 App。

- 默认目录为 `~/.agents/skills/viewin`，也可选择 Codex、Claude Code、OpenCode、Pi 的目录或自定义目录。
- 首次安装通过系统文件夹选择器授权目录；之后保存安全书签，便于直接更新。
- 不修改 Agent 的 MCP 或权限配置，不覆盖其他来源的同名 Skill。
- 启动脚本使用 App 内 CLI 的完整路径，不要求用户安装 Swift / Xcode 或配置 PATH。
- 移动桌面 App 后，需要在设置中更新 Skill。Agent 未显示新 Skill 时，可以新建会话或重启 Agent。

CLI 的使用方式如下；这里假设 App 位于 `/Applications/Viewin.app`：

```sh
# 查看可连接的 App：输出端口、App 名称和设备名
"/Applications/Viewin.app/Contents/Helpers/viewin" --list

# 指定目标，保存单文件快照
"/Applications/Viewin.app/Contents/Helpers/viewin" \
  --port 48721 --output capture.viewin

# 导出便于 Agent 分析的 snapshot.json 和 images/ 目录
"/Applications/Viewin.app/Contents/Helpers/viewin" \
  --port 48721 --format json --output capture-data
```

`--list` 中 Android 目标的端口可能是自动分配的 ADB 本地转发端口，请使用实际输出。未指定 `--port` 时，采集默认使用发现的第一个目标；有多个 App 时应明确指定端口。

当前 CLI 提供发现和采集，不提供点击、执行手势或修改运行时属性。

## 快照格式

`.viewin` 是 ZIP 归档，包含：

```text
capture.viewin
├── manifest.json        # 格式版本与图片路径映射
├── snapshot.json        # 层级、布局、属性、能力和采集状态
└── images/              # 按内容去重的图片
```

JSON 使用压缩存储；PNG 不重复压缩，图片按内容去重。CLI 的 JSON 导出模式则直接生成可读取的目录。桌面端兼容读取旧的 `.inview` / `.uiinspector` 快照。

## 应用更新

正式版通过 [Sparkle 2](https://sparkle-project.org/) 检查、下载并安装更新，更新文件托管在本仓库的 GitHub Releases。

- App 菜单提供“检查更新…”，设置中可开关自动检查。
- 默认关闭自动检查；开启后由 Sparkle 调度，不额外常驻轮询。
- 更新源为最新正式 Release 的 `appcast.xml`，下载地址指向具体版本的安装包。
- 更新使用 EdDSA 签名验证；私钥保存在发布者本地钥匙串，不提交到仓库。
- Debug 构建禁用自更新，避免被正式版覆盖。

**首次发布前，线上更新源尚不可用。** 本地构建通过不代表已经完成线上下载、替换和重启的升级验证。

## 实现参考与依赖

交互与采集思路参考 [Lookin](https://github.com/QMUI/Lookin)、[LookInside](https://github.com/LookInsideApp/LookInside) 和 [CodeLocator](https://github.com/bytedance/CodeLocator)。Viewin 使用独立 SDK 和协议，不编入这些项目的运行时代码。

桌面端第三方依赖为 [Sparkle](https://github.com/sparkle-project/Sparkle) 与 [ZIPFoundation](https://github.com/weichsel/ZIPFoundation)。
