import ViewinSnapshot
import AppKit
import SwiftUI
import ViewinWorkspace

/// Both settings entry points reuse a normal, independently closable window.
@MainActor final class WorkspaceSettingsWindow: NSWindowController {
  static let shared = WorkspaceSettingsWindow()
  private(set) weak var workspace: WorkspaceStore?

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = L10n.text("Viewin 设置")
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.center()
    window.setFrameAutosaveName("Viewin.Settings")
    super.init(window: window)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show(workspace: WorkspaceStore) {
    guard let window else { return }
    self.workspace = workspace
    window.contentViewController = NSHostingController(rootView: WorkspaceSettingsView(workspace: workspace))
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
  }
}

private struct WorkspaceSettingsView: View {
  let workspace: WorkspaceStore

  var body: some View {
    TabView {
      general.tabItem { Label(L10n.text("通用"), systemImage: "gearshape") }
      UpdateSettingsView().tabItem { Label(L10n.text("更新"), systemImage: "arrow.down.circle") }
      AgentSettingsView().tabItem { Label("Agent", systemImage: "terminal") }
    }.frame(width: 540, height: 480)
  }

  private var general: some View {
    Form {
      Section(L10n.text("视图")) {
        Toggle(L10n.text("显示边界"), isOn: workspace.binding(\.showBounds))
        HStack {
          Slider(value: workspace.binding(\.layerSpacing), in: 0...1) { Text(L10n.text("层间距")) }
          Text("\(Int(workspace.layerSpacing * 100))")
            .monospacedDigit().frame(width: 28, alignment: .trailing)
        }.disabled(workspace.viewMode != "3D")
        Button(L10n.text("复位视角与大小")) { workspace.resetCamera() }
      }
      Section(L10n.text("检查器")) {
        Picker(L10n.text("颜色格式"), selection: Binding(
          get: { workspace.inspectorStore.colorFormat },
          set: { workspace.inspectorStore.send(.colorFormatChanged($0)) }
        )) {
          Text("RGBA").tag("rgba")
          Text("HEX").tag("hex")
        }.pickerStyle(.segmented)
          .accessibilityLabel(L10n.text("全局颜色格式"))
      }
    }
    .formStyle(.grouped)
  }
}
