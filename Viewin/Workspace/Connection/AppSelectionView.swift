import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

struct TargetAppIcon: View {
  let data: Data?
  var body: some View {
    if let data, let image = NSImage(data: data) {
      Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 2))
    } else {
      Image(systemName: "app").resizable().scaledToFit().foregroundStyle(.secondary)
    }
  }
}

struct AppSelectionView: View {
  enum Presentation { case startup, popover }
  let workspace: WorkspaceStore
  var presentation: Presentation = .popover
  var openSnapshot: (() -> Void)? = nil
  let select: (InspectionTarget) -> Void
  @State private var showingHelp = false

  private var isStartup: Bool { presentation == .startup }

  private var popoverWidth: CGFloat {
    workspace.targets.isEmpty
      ? 280 : min(660, max(280, CGFloat(workspace.targets.count) * 174 + 24))
  }

  private var title: String {
    if workspace.isCapturing { return L10n.text("正在读取 App 布局…") }
    if workspace.isScanning && workspace.targets.isEmpty { return L10n.text("正在查找可以连接的 App…") }
    if workspace.targets.isEmpty { return L10n.text("没有发现可以连接的 App") }
    return L10n.format("找到 %@ 个活跃的 App", String(describing: workspace.targets.count))
  }

  var body: some View {
    VStack(spacing: 5) {
      HStack(spacing: 7) {
        if workspace.isScanning || workspace.isCapturing { ProgressView().controlSize(.small) }
        Text(title).font(.system(size: isStartup ? 20 : 14, weight: isStartup ? .medium : .regular))
      }.padding(.top, 12)
      if !workspace.targets.isEmpty {
        Text(L10n.text("点击下列图像进入")).font(.system(size: 12)).foregroundStyle(.secondary)
        if isStartup {
          GeometryReader { geometry in
            let columns = min(workspace.targets.count,
              max(1, Int((geometry.size.width - 32 + 20) / 193)))
            let width = CGFloat(columns) * 173 + CGFloat(columns - 1) * 20
            ScrollView {
              LazyVGrid(columns: Array(repeating: GridItem(.fixed(173)), count: columns), spacing: 20) {
                ForEach(workspace.targets) { target in
                  AppSelectionCard(target: target, isSelected: workspace.connectedTarget?.id == target.id
                    && workspace.connectedTarget?.appId == target.appId) { select(target) }
                    .disabled(workspace.isCapturing)
                }
              }
              .frame(width: width)
              .padding(16)
              .frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.basedOnSize)
          }
          .frame(maxWidth: 900, maxHeight: 370)
        } else {
          ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 1) {
              ForEach(workspace.targets) { target in
                AppSelectionCard(target: target, isSelected: workspace.connectedTarget?.id == target.id
                    && workspace.connectedTarget?.appId == target.appId) { select(target) }
                  .disabled(workspace.isCapturing)
              }
            }.frame(minWidth: popoverWidth - 24).padding(.horizontal, 12)
          }.scrollBounceBehavior(.basedOnSize).fixedSize(horizontal: false, vertical: true)
        }
      } else if isStartup && !workspace.isScanning {
        Text(L10n.text("请打开集成了 ViewinSDK 的 App，然后重新查找。"))
          .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 24)
      }
      HStack(spacing: 16) {
        Button(L10n.text("看不到你的 App？")) { showingHelp.toggle() }
          .buttonStyle(.link)
          .popover(isPresented: $showingHelp) {
            VStack(alignment: .leading, spacing: 10) {
              Text(L10n.text("连接 App")).font(.headline)
              Text(L10n.text("将集成了 ViewinSDK 的 App 保持在前台，然后重新查找。支持 iOS 模拟器、Android 模拟器和已授权的 Android USB 设备。"))
              Text(L10n.text("Android 需先启动 Android Studio 或 ADB 服务，并授权 USB 调试。连接时自动建立转发。"))
                .foregroundStyle(.secondary)
              Button(L10n.text("重新查找")) {
                showingHelp = false
                workspace.discoverTargets(force: true)
              }.disabled(workspace.isScanning)
            }.font(.system(size: 12)).padding(16).frame(width: 270)
          }
        Button {
          workspace.discoverTargets(force: true)
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless).disabled(workspace.isScanning || workspace.isCapturing)
        .help(L10n.text("重新查找 App")).accessibilityLabel(L10n.text("重新查找 App"))
        if let openSnapshot {
          Divider().frame(height: 12)
          Button(L10n.text("打开快照…"), action: openSnapshot).buttonStyle(.link)
        }
      }.font(.system(size: 12)).padding(.top, 5).padding(.bottom, 12)
    }
    .frame(width: isStartup ? nil : popoverWidth)
    .frame(maxWidth: isStartup ? .infinity : nil, maxHeight: isStartup ? .infinity : nil)
    .onAppear { workspace.discoverTargets(autoSelectSingle: isStartup) }
    .onDisappear { workspace.stopDiscovery() }
  }
}

struct AppSelectionCard: View {
  let target: InspectionTarget
  var isSelected = false
  let select: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: select) {
      VStack(spacing: 10) {
        Group {
          if let data = target.screenshotPNG, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
          } else {
            ContentUnavailableView(L10n.text("截图不可用"), systemImage: "iphone")
          }
        }.frame(width: 120, height: 220)
        HStack(spacing: 6) {
          Image(systemName: "iphone.gen3").font(.system(size: 24)).foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(target.deviceName).font(.system(size: 12)).lineLimit(1)
            Text(target.osDescription)
              .font(.system(size: 11)).foregroundStyle(.secondary)
          }
        }
      }.padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 8)
        .frame(width: 173)
        .background(
          isSelected ? Color.accentColor.opacity(0.10)
            : hovering ? Color.primary.opacity(0.06) : .clear,
          in: RoundedRectangle(cornerRadius: 4)
        )
        .overlay {
          if isSelected {
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5)
          }
        }
        .overlay(alignment: .topTrailing) {
          if isSelected {
            Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
              .foregroundStyle(.white, Color.accentColor).font(.system(size: 15))
              .padding(7).accessibilityHidden(true)
          }
        }
        .contentShape(Rectangle())
    }.buttonStyle(.plain).onHover { hovering = $0 }
      .accessibilityLabel(L10n.format("检查 %@，%@，%@", String(describing: target.appName), String(describing: target.deviceName), String(describing: target.osDescription)))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
      .help(target.appName)
  }
}
