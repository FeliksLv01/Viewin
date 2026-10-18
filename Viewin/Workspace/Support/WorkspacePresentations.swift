import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

/// Presentation subscriptions live outside the three-column container.
struct WorkspacePresentations: View {
  let workspace: WorkspaceStore
  var body: some View {
    Color.clear
      .alert(
        "快照操作失败",
        isPresented: Binding(
          get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })
      ) {
        Button("好") { workspace.errorMessage = nil }
      } message: {
        Text(workspace.errorMessage ?? "")
      }
      .background(DoubleClickPrompt(workspace: workspace))
  }
}
struct DoubleClickPrompt: View {
  let workspace: WorkspaceStore
  var body: some View {
    Color.clear.alert(
      "双击节点时执行什么操作？",
      isPresented: Binding(
        get: { workspace.hierarchyStore.pendingDoubleClickId != nil },
        set: { if !$0 { workspace.hierarchyStore.send(.doubleClickChoice(nil)) } })
    ) {
      Button("展开 / 收起") { workspace.hierarchyStore.send(.doubleClickChoice("collapse")) }
      Button("聚焦") { workspace.hierarchyStore.send(.doubleClickChoice("focus")) }
      Button("取消", role: .cancel) { workspace.hierarchyStore.send(.doubleClickChoice(nil)) }
    } message: {
      Text("可以随时在侧边栏菜单中修改。")
    }
  }
}
