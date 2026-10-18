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
    VStack(spacing: 0) {
      TextField("搜索属性", text: Binding(get: { search }, set: { search = $0 }))
        .textFieldStyle(.roundedBorder)
        .padding(12)
      Divider()
      if let node = workspace.selectedNode {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            if search.isEmpty || node.typeName.localizedCaseInsensitiveContains(search)
              || "Class".localizedCaseInsensitiveContains(search)
              || node.properties.contains(where: { ["c", "class"].contains($0.id) && matches($0) })
            {
              InspectorCard(inspectorStore: store, title: "Class", icon: "c.square", query: search)
              {
                scalar("类型", node.typeName)
                scalar("框架", node.frameworkTitle)
                scalar("地址", node.identifiers["objectAddress"] ?? "—")
                ForEach(node.properties.filter { ["c", "class"].contains($0.id) }) {
                  properties($0.properties)
                }
              }
            }
            let relationGroups = node.properties.filter {
              ["r", "relation", "references", "trace", "list"].contains($0.id) && matches($0)
                && ($0.id != "references"
                  || !node.properties.contains(where: { ["r", "relation"].contains($0.id) }))
            }
            if !relationGroups.isEmpty {
              InspectorCard(inspectorStore: store, title: "Relation", icon: "link", query: search) {
                ForEach(relationGroups) { properties($0.properties) }
              }
            }
            if search.isEmpty || "Layout Bounds".localizedCaseInsensitiveContains(search)
              || node.properties.contains(where: { ["l", "layout"].contains($0.id) && matches($0) })
            {
              InspectorCard(
                inspectorStore: store, title: "Layout", icon: "rectangle.dashed", query: search,
                menu: sectionMenu(
                  node.properties.filter { ["l", "layout"].contains($0.id) }.flatMap(\.properties))
              ) {
                if let geometry = node.geometry {
                  Text("窗口坐标 · \(workspace.window?.unit ?? "")").font(.caption).foregroundStyle(
                    .secondary)
                  geometryGrid(
                    [
                      "x": .number(geometry.frameInWindow.x),
                      "y": .number(geometry.frameInWindow.y),
                      "width": .number(geometry.frameInWindow.width),
                      "height": .number(geometry.frameInWindow.height),
                    ], keys: ["x", "y", "width", "height"])
                  if !node.properties.contains(where: { ["l", "layout"].contains($0.id) }) {
                    Text("Bounds · 本地坐标").font(.caption).foregroundStyle(.secondary)
                    geometryGrid(
                      [
                        "x": .number(geometry.localBounds.x), "y": .number(geometry.localBounds.y),
                        "width": .number(geometry.localBounds.width),
                        "height": .number(geometry.localBounds.height),
                      ], keys: ["x", "y", "width", "height"])
                  }
                } else {
                  Text("逻辑组件没有独立布局").foregroundStyle(.secondary)
                }
                ForEach(node.properties.filter { ["l", "layout"].contains($0.id) }) {
                  properties($0.properties)
                }
              }
            }
            ForEach(
              node.properties.filter {
                ![
                  "hierarchy", "class", "relation", "layout", "c", "l", "r", "references", "trace",
                  "list",
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
            if !node.properties.contains(where: { ["view", "v", "vl"].contains($0.id) }) {
              InspectorCard(
                inspectorStore: store, title: "View / Layer", icon: "square.3.layers.3d",
                query: search
              ) {
                scalar("隐藏", node.visibility.hidden ? "是" : "否")
                scalar("透明度", dimension(node.visibility.alpha))
              }
            }
            let relations = document.snapshot.relations.filter {
              $0.fromNodeId == node.id || $0.toNodeId == node.id
            }
            if !relations.isEmpty {
              InspectorCard(inspectorStore: store, title: "节点关联", icon: "link", query: search) {
                ForEach(Array(relations.enumerated()), id: \.offset) { _, relation in
                  let id = relation.fromNodeId == node.id ? relation.toNodeId : relation.fromNodeId
                  Button {
                    if let node = document.node(id) { workspace.select(node) }
                  } label: {
                    Label(
                      "\(relation.kind) · \(document.node(id)?.name ?? id)",
                      systemImage: "arrow.up.right")
                  }.buttonStyle(.link)
                }
              }
            }
          }.padding(10)
        }.id(node.id)
      } else {
        ContentUnavailableView(
          "选择一个节点", systemImage: "cursorarrow.click", description: Text("在层级树或预览中选择元素。"))
      }
      Divider()
      Text(
        document.snapshot.source == "fixture"
          ? "示例数据 · 只读" : "\(document.snapshot.target.appName) · 只读"
      )
      .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
    }.background(.background.secondary)
  }

}
