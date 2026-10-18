import SwiftUI
import ViewinWorkspace
import ViewinSnapshot
import ViewinConnection

struct WorkspaceCommandContext {
  let workspace: WorkspaceStore
  let openSnapshot: () -> Void
}

private struct WorkspaceCommandKey: FocusedValueKey {
  typealias Value = WorkspaceCommandContext
}

extension FocusedValues {
  var workspaceCommands: WorkspaceCommandContext? {
    get { self[WorkspaceCommandKey.self] }
    set { self[WorkspaceCommandKey.self] = newValue }
  }
}

struct WorkspaceCommands: Commands {
  @FocusedValue(\.workspaceCommands) private var context

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("打开快照…") { context?.openSnapshot() }
        .keyboardShortcut("o")
        .disabled(context == nil)
      Button("保存快照…") { context?.workspace.saveSnapshot() }
        .keyboardShortcut("s")
        .disabled(context?.workspace.document == nil)
      Divider()
      Button("刷新布局") { context?.workspace.refresh() }
        .keyboardShortcut("r")
        .disabled(context?.workspace.connectedTarget == nil || context?.workspace.isCapturing == true)
    }
    CommandGroup(replacing: .appSettings) {
      Button("设置…") { if let workspace = context?.workspace ?? WorkspaceSettingsWindow.shared.workspace {
        WorkspaceSettingsWindow.shared.show(workspace: workspace)
      } }
        .keyboardShortcut(",")
        .disabled(context == nil && WorkspaceSettingsWindow.shared.workspace == nil)
    }
    CommandGroup(after: .toolbar) {
      Divider()
      Toggle("锁定测距", isOn: measurementBinding)
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .disabled(context?.workspace.document == nil)
      Picker("预览模式", selection: modeBinding) {
        Text("2D").tag("2D")
        Text("3D").tag("3D")
      }.disabled(context?.workspace.document == nil)
      Toggle("自由旋转", isOn: flag(\.freeRotation))
        .disabled(context?.workspace.document == nil)
      Toggle("显示边界", isOn: flag(\.showBounds)).disabled(context == nil)
      Picker("颜色格式", selection: colorBinding) {
        Text("RGBA").tag("rgba")
        Text("HEX").tag("hex")
      }.disabled(context == nil)
      Divider()
      Button("放大") { context?.workspace.zoom = min(1, (context?.workspace.zoom ?? 0) + 0.1) }
        .keyboardShortcut("+", modifiers: .command)
        .disabled(context?.workspace.document == nil)
      Button("缩小") { context?.workspace.zoom = max(0, (context?.workspace.zoom ?? 0) - 0.1) }
        .keyboardShortcut("-", modifiers: .command)
        .disabled(context?.workspace.document == nil)
      Button("复位视角与大小") { context?.workspace.resetCamera() }
        .keyboardShortcut("0")
        .disabled(context?.workspace.document == nil)
    }
  }

  private func flag(_ keyPath: ReferenceWritableKeyPath<WorkspaceStore, Bool>) -> Binding<Bool> {
    Binding(get: { context?.workspace[keyPath: keyPath] ?? false },
            set: { context?.workspace[keyPath: keyPath] = $0 })
  }
  private var modeBinding: Binding<String> {
    Binding(get: { context?.workspace.viewMode ?? "3D" },
            set: { context?.workspace.viewMode = $0 })
  }
  private var colorBinding: Binding<String> {
    Binding(get: { context?.workspace.inspectorStore.colorFormat ?? "rgba" },
            set: { context?.workspace.inspectorStore.send(.colorFormatChanged($0)) })
  }
  private var measurementBinding: Binding<Bool> {
    Binding(get: { context?.workspace.measurementStore.mode == .locked }, set: { value in
      guard let workspace = context?.workspace else { return }
      if value { workspace.measurementStore.send(.cancelOnKeyUpChanged(false)) }
      else { workspace.measurementStore.send(.stop) }
    })
  }
}
