import AppKit
import SwiftUI
import ViewinProtocol
import ViewinSnapshot
import UniformTypeIdentifiers

struct HierarchySidebar: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument

  var body: some View {
    VStack(spacing: 0) {
      HierarchyControls(workspace: workspace, document: document)
      HierarchyTableContent(workspace: workspace, document: document)
      Divider()
      HStack(spacing: 6) {
        Image(systemName: "doc.text")
        Text(
          "\(document.snapshot.nodes.count) 个节点 · 协议 \(document.snapshot.protocolVersion.major).\(document.snapshot.protocolVersion.minor)"
        )
        Spacer()
      }.font(.caption).foregroundStyle(.secondary).padding(12)
    }.background(.background.secondary)
  }
}

/// Header/search never subscribe to selection, hover, or camera state.
private struct HierarchyControls: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("层级").font(.headline)
        Spacer()
        Menu {
          let levels = ["只显示窗口", "展开至控制器", "展开主要层级", "展开大部分", "全部展开"]
          ForEach(0..<levels.count, id: \.self) { level in
            Button {
              workspace.setExpansionLevel(level)
            } label: {
              if workspace.expansionLevel == level {
                Label(levels[level], systemImage: "checkmark")
              } else {
                Text(levels[level])
              }
            }
          }
          Divider()
          Picker("双击行为", selection: workspace.binding(\.doubleClickBehavior)) {
            Text("展开 / 收起").tag("collapse")
            Text("聚焦").tag("focus")
          }
          Toggle("显示隐藏的视图", isOn: workspace.binding(\.showHidden))
          Button("恢复本次隐藏的截图") { workspace.restorePreviews() }
            .disabled(workspace.hiddenPreviewIds.isEmpty)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("层级菜单")
      }.padding(.horizontal, 16).padding(.vertical, 15)
      if let root = workspace.focusRootId {
        HStack {
          Text("聚焦：\(document.node(root)?.sidebarTitle ?? root)").lineLimit(1)
          Spacer()
          Button("退出聚焦") { workspace.endScope() }
        }.font(.caption).padding(.horizontal, 12).padding(.bottom, 12)
      } else {
        HStack(spacing: 4) {
          TextField("搜索类型、文字或属性名", text: workspace.binding(\.search))
            .textFieldStyle(.roundedBorder).onExitCommand { workspace.endScope() }
          if !workspace.search.isEmpty {
            Button {
              workspace.endScope()
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("清除搜索")
          }
        }.padding(.horizontal, 12).padding(.bottom, 12)
      }
      Divider()
    }
  }
}

private struct HierarchyTableContent: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  var body: some View {
    HierarchyTable(
      contentID: workspace.contentID, workspace: workspace, document: document,
      expanded: workspace.expanded, search: workspace.search,
      selectedId: workspace.selectedId,
      hoveredId: workspace.hoveredId, focusRootId: workspace.focusRootId,
      includedIds: workspace.searchIncludedIds, hiddenPreviewIds: workspace.hiddenPreviewIds)
  }
}

/// AppKit's virtualized, fixed-height rows avoid rebuilding a SwiftUI subtree
/// (including JSON metadata and popovers) during every scroll or hover event.
