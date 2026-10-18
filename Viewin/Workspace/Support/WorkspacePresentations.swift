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
        L10n.text("快照操作失败"),
        isPresented: Binding(
          get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })
      ) {
        Button(L10n.text("好")) { workspace.errorMessage = nil }
      } message: {
        Text(L10n.text(workspace.errorMessage ?? ""))
      }
      .background(DoubleClickPrompt(workspace: workspace))
  }
}
struct DoubleClickPrompt: View {
  let workspace: WorkspaceStore
  var body: some View {
    Color.clear.alert(
      L10n.text("双击节点时执行什么操作？"),
      isPresented: Binding(
        get: { workspace.hierarchyStore.pendingDoubleClickId != nil },
        set: { if !$0 { workspace.hierarchyStore.send(.doubleClickChoice(nil)) } })
    ) {
      Button(L10n.text("展开 / 收起")) { workspace.hierarchyStore.send(.doubleClickChoice("collapse")) }
      Button(L10n.text("聚焦")) { workspace.hierarchyStore.send(.doubleClickChoice("focus")) }
      Button(L10n.text("取消"), role: .cancel) { workspace.hierarchyStore.send(.doubleClickChoice(nil)) }
    } message: {
      Text(L10n.text("可以随时在侧边栏菜单中修改。"))
    }
  }
}
