import AppKit
import SwiftUI
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

struct InspectorPanel: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  var store: InspectorFeature { workspace.inspectorStore }
  var search: String {
    get { store.search }
    nonmutating set { store.send(.searchChanged(newValue)) }
  }
  var colorFormat: String {
    get { store.colorFormat }
    nonmutating set { store.send(.colorFormatChanged(newValue)) }
  }
  var sectionOverrides: Data {
    get { store.sectionOverrides }
    nonmutating set { store.send(.sectionOverridesChanged(newValue)) }
  }

  var body: some View {
    let displayGroups = workspace.selectedNode.map { InspectorPresentation.groups(for: $0) } ?? []
    VStack(spacing: 0) {
      TextField(L10n.text("搜索属性"), text: Binding(get: { search }, set: { search = $0 }))
        .textFieldStyle(.roundedBorder)
        .padding(12)
      Divider()
      if let node = workspace.selectedNode {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            if search.isEmpty || node.typeName.localizedCaseInsensitiveContains(search)
              || "Class".localizedCaseInsensitiveContains(search)
              || displayGroups.contains(where: { ["c", "class"].contains($0.id) && matches($0) })
            {
              InspectorCard(inspectorStore: store, title: "Class", icon: "c.square", query: search)
              {
                scalar(L10n.text("类型"), node.typeName)
                scalar(L10n.text("框架"), node.frameworkTitle)
                if node.framework == "androidView" || node.framework == "compose" {

                  if let resource = node.identifiers["resourceId"] { scalar("Resource ID", resource) }
                  if let tag = node.identifiers["testTag"] { scalar("Test Tag", tag) }

                } else if let address = node.identifiers["objectAddress"] { scalar(L10n.text("地址"), address) }
                ForEach(displayGroups.filter { ["c", "class"].contains($0.id) }) {
                  properties($0.properties)
                }
              }
            }
            let relationGroups = displayGroups.filter {
              ["r", "relation", "references", "trace", "list"].contains($0.id) && matches($0)
                && ($0.id != "references"
                  || !displayGroups.contains(where: { ["r", "relation"].contains($0.id) }))
            }
            if !relationGroups.isEmpty {
              InspectorCard(inspectorStore: store, title: "Relation", icon: "link", query: search) {
                ForEach(relationGroups) { properties($0.properties) }
              }
            }
            if search.isEmpty || "Layout Bounds".localizedCaseInsensitiveContains(search)
              || displayGroups.contains(where: { ["l", "layout"].contains($0.id) && matches($0) })
            {
              InspectorCard(
                inspectorStore: store, title: "Layout", icon: "rectangle.dashed", query: search,
                menu: sectionMenu(
                  displayGroups.filter { ["l", "layout"].contains($0.id) }.flatMap(\.properties))
              ) {
                if let geometry = node.geometry {
                  Text(L10n.format("窗口坐标 · %@", String(describing: workspace.window?.unit ?? ""))).font(.caption).foregroundStyle(
                    .secondary)
                  geometryGrid(
                    [
                      "x": .number(geometry.frameInWindow.x),
                      "y": .number(geometry.frameInWindow.y),
                      "width": .number(geometry.frameInWindow.width),
                      "height": .number(geometry.frameInWindow.height),
                    ], keys: ["x", "y", "width", "height"])
                  if !displayGroups.contains(where: { ["l", "layout"].contains($0.id) }) {
                    Text(L10n.text("Bounds · 本地坐标")).font(.caption).foregroundStyle(.secondary)
                    geometryGrid(
                      [
                        "x": .number(geometry.localBounds.x), "y": .number(geometry.localBounds.y),
                        "width": .number(geometry.localBounds.width),
                        "height": .number(geometry.localBounds.height),
                      ], keys: ["x", "y", "width", "height"])
                  }
                } else {
                  Text(L10n.text("逻辑组件没有独立布局")).foregroundStyle(.secondary)
                }
                ForEach(displayGroups.filter { ["l", "layout"].contains($0.id) }) {
                  properties($0.properties)
                }
              }
            }
            ForEach(
              displayGroups.filter {
                ![
                  "hierarchy", "class", "relation", "layout", "c", "l", "r", "references", "trace",
                  "list", "rendering",
                ].contains($0.id)
                  && matches($0)
              }
            ) { group in
              InspectorCard(
                inspectorStore: store, title: group.title, icon: icon(group), query: search,
                id: group.id,
                menu: sectionMenu(group.properties)
              ) {
                properties(
                  group.properties,
                  includeAll: !search.isEmpty
                    && group.title.localizedCaseInsensitiveContains(search))
              }
            }
            if !displayGroups.contains(where: { ["view", "v", "vl"].contains($0.id) }) {
              InspectorCard(
                inspectorStore: store, title: "View / Layer", icon: "square.3.layers.3d",
                query: search
              ) {
                scalar(L10n.text("隐藏"), node.visibility.hidden ? L10n.text("是") : L10n.text("否"))
                scalar(L10n.text("透明度"), dimension(node.visibility.alpha))
              }
            }
            let relations = document.snapshot.relations.filter {
              $0.fromNodeId == node.id || $0.toNodeId == node.id
            }
            if !relations.isEmpty {
              InspectorCard(inspectorStore: store, title: L10n.text("节点关联"), icon: "link", query: search, id: "节点关联") {
                ForEach(Array(relations.enumerated()), id: \.offset) { _, relation in
                  let id = relation.fromNodeId == node.id ? relation.toNodeId : relation.fromNodeId
                  Button {
                    if let target = document.node(id) {
                      if relation.kind == "renderedByGeometry", workspace.hierarchyStore.isPreviewHidden(id) {
                        workspace.togglePreview(id)
                      }
                      workspace.selectRelated(target)
                    }
                  } label: {
                    Label(
                      "\(relationTitle(relation.kind, forward: relation.fromNodeId == node.id)) · \(document.node(id)?.name ?? id)",
                      systemImage: "arrow.up.right")
                  }.buttonStyle(.link)
                }
              }
            }
          }.padding(10)
        }.id(node.id)
      } else {
        ContentUnavailableView(
          L10n.text("选择一个节点"), systemImage: "cursorarrow.click", description: Text(L10n.text("在层级树或预览中选择元素。")))
      }
      Divider()
      Text(
        document.snapshot.source == "fixture"
          ? L10n.text("示例数据 · 只读") : L10n.format("%@ · %@ · 只读", String(describing: document.snapshot.target.appName), String(describing: buildTypeLabel))
      )
      .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
    }.background(.background.secondary)
  }

  private func relationTitle(_ kind: String, forward: Bool) -> String {
    switch kind {
    case "renderedByGeometry": forward ? L10n.text("渲染图层（几何推断）") : L10n.text("逻辑视图（几何推断）")
    case "hostedBy": forward ? L10n.text("宿主视图") : L10n.text("逻辑视图")
    default: kind
    }
  }
  private var buildTypeLabel: String {
    switch document.snapshot.target.buildType {
    case "debug": "Debug"
    case "internalRelease", "release": "Release"
    default: L10n.text("构建类型未知")
    }
  }
}
