import AppKit
import SwiftUI
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

/// Switching this small container does not subscribe the workspace layout to hover events.
struct InspectorColumn: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  var body: some View {
    Group {
      if workspace.isMeasuring {
        MeasurementPanel(workspace: workspace, document: document)
      } else {
        InspectorPanel(workspace: workspace, document: document)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct MeasurementPanel: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 8) {
        Spacer(minLength: 0)
        if let selected = workspace.selectedNode {
          if let hovered = workspace.hoveredNode, hovered.id != selected.id {
            if selected.windowId != hovered.windowId {
              tutorial("rectangle.on.rectangle.slash", L10n.text("不在同一窗口"), L10n.text("请选择同一窗口中的两个图层。"))
            } else if let a = selected.geometry?.frameInWindow,
              let b = hovered.geometry?.frameInWindow,
              let diagram = MeasurementDiagram(selected: a, hovered: b)
            {
              let width = max(1, geometry.size.width - 60)
              let height = min(
                max(200, geometry.size.height * 0.8),
                max(90, diagram.union.height / diagram.union.width * width + 40))
              MeasurementDiagramView(
                diagram: diagram,
                selectedImage: image(selected), hoveredImage: image(hovered),
                selectedName: selected.sidebarTitle, hoveredName: hovered.sidebarTitle,
                unit: document.snapshot.windows.first { $0.id == selected.windowId }?.unit ?? "pt"
              ).frame(height: height).background(
                .background.secondary, in: RoundedRectangle(cornerRadius: 9))
            } else {
              tutorial("info.circle", L10n.text("无效尺寸"), invalidSize(selected, hovered))
            }
          } else {
            tutorial("cursorarrow.rays", L10n.text("悬停一个图层"), L10n.format("测量它与已选中 %@ 之间的距离。", String(describing: selected.sidebarTitle)))
          }
        } else {
          tutorial("cursorarrow.click", L10n.text("先选择一个图层"), L10n.text("然后将鼠标悬停在另一个图层上测距。"))
        }
        if workspace.measurementStore.mode == .temporary {
          Toggle(
            L10n.text("松开 Option 后退出测距"),
            isOn: Binding(
              get: { workspace.measurementStore.mode == .temporary },
              set: { workspace.measurementStore.send(.cancelOnKeyUpChanged($0)) }
            )
          ).toggleStyle(.checkbox).font(.system(size: 12))
        } else {
          Text(L10n.text("快捷键：按住 Option")).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }.padding(10).frame(width: geometry.size.width, height: geometry.size.height)
    }.accessibilityIdentifier("measurement-panel")
  }

  private func image(_ node: SnapshotNode) -> NSImage? {
    (node.groupImageId ?? node.imageId).flatMap { workspace.nodeImages[$0] }
  }
  private func tutorial(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary)
      Text(title).font(.system(size: 14, weight: .bold))
      Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(
        .center)
    }.frame(maxWidth: .infinity).padding(.horizontal, 10).padding(.vertical, 18)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
  }
  private func invalidSize(_ a: SnapshotNode, _ b: SnapshotNode) -> String {
    for node in [a, b] {
      guard let frame = node.geometry?.frameInWindow else { return L10n.format("%@ 没有布局信息。", String(describing: node.sidebarTitle)) }
      if frame.width <= 0 { return L10n.format("%@ 的宽度小于或等于 0。", String(describing: node.sidebarTitle)) }
      if frame.height <= 0 { return L10n.format("%@ 的高度小于或等于 0。", String(describing: node.sidebarTitle)) }
    }
    return L10n.text("无法测量这两个图层的布局。")
  }
}
