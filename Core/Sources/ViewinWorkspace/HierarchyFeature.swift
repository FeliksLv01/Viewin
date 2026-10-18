import Foundation
import Observation
import ViewinProtocol
import ViewinSnapshot

@MainActor @Observable public final class HierarchyFeature {

  public var content: WorkspaceContent?
  public var selectedId: String? {
    didSet {
      if let selectedId, let node = document?.node(selectedId) { windowId = node.windowId }
    }
  }
  public var windowId = "main"
  public var searchText = ""
  public var searchQuery: String { searchText.filter { !$0.isWhitespace } }
  public var searchIncludedIds: Set<String>?
  public var focusRootId: String?
  public var expansionBeforeScope: Set<String>?
  public var hoveredId: String?
  public var hiddenPreviewIds = Set<String>()
  public var showHidden = false
  public var expansionLevel = 3
  public var doubleClickBehavior: String {
    didSet {
      defaults.set(doubleClickBehavior, forKey: "viewin_hierarchy_doubleClickBehavior")
    }
  }
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored public var onSelectionChange: (() -> Void)?
  public var pendingDoubleClickId: String?
  public var expanded = Set<String>()
  public var document: SnapshotDocument? { content?.document }
  public var hierarchy: HierarchyPresentation? { content?.hierarchy }
  public var previewHierarchy: HierarchyPresentation? { content?.windows[windowId] }
  public var selectedNode: SnapshotNode? { selectedId.flatMap { document?.node($0) } }
  public var window: SnapshotWindow? { document?.snapshot.windows.first { $0.id == windowId } }
  public init(content: WorkspaceContent? = nil, defaults: UserDefaults = .standard) {
    self.defaults = defaults
    doubleClickBehavior =
      defaults.string(forKey: "viewin_hierarchy_doubleClickBehavior") ?? "ask"
    if let content { install(content) }
  }
  public func select(_ node: SnapshotNode) {
    selectedId = node.id
    if let document { expanded.formUnion(document.ancestors(of: node).map(\.id)) }
  }

  public func hover(_ id: String?) {
    if hoveredId != id { hoveredId = id }
  }

  public var visibleHierarchyIndices: [Int] {
    hierarchy?.visibleIndices(
      expanded: expanded, rootId: focusRootId, includedIds: searchIncludedIds) ?? []
  }

  fileprivate func applySearch(_ text: String) {
    searchText = text
    let query = searchQuery
    if query.isEmpty {
      if focusRootId == nil { endScope() }
      return
    }
    if expansionBeforeScope == nil { expansionBeforeScope = expanded }
    focusRootId = nil
    let result = hierarchy?.searchResult(query, expanded: expansionBeforeScope ?? expanded)
    searchIncludedIds = result?.included ?? []
    expanded = result?.expanded ?? expanded
    selectedId = nil
    hoveredId = nil
  }

  public func focus(_ id: String) {
    if expansionBeforeScope == nil { expansionBeforeScope = expanded }
    searchText = ""
    searchIncludedIds = nil
    focusRootId = id
    selectedId = id
    hoveredId = nil
  }

  public func endScope() {
    let wasSearch = focusRootId == nil
    if let saved = expansionBeforeScope { expanded = saved }
    if wasSearch, let selectedNode, let document {
      expanded.formUnion(document.ancestors(of: selectedNode).map(\.id))
    }
    expansionBeforeScope = nil
    searchText = ""
    searchIncludedIds = nil
    focusRootId = nil
    hoveredId = nil
  }

  public func setExpansionLevel(_ level: Int) {
    expansionLevel = level
    expanded = (content?.windows ?? [:]).values.reduce(into: Set<String>()) {
      $0.formUnion($1.initialExpansion(level: level))
    }
  }

  public func isPreviewHidden(_ id: String) -> Bool {
    guard let node = document?.node(id), let document else { return false }
    return hiddenPreviewIds.contains(id)
      || document.ancestors(of: node).contains {
        hiddenPreviewIds.contains($0.id)
      }
  }

  public func togglePreview(_ id: String) {
    if isPreviewHidden(id), let node = document?.node(id), let document {
      for ancestor in [node] + document.ancestors(of: node) {
        hiddenPreviewIds.remove(ancestor.id)
      }
    } else {
      hiddenPreviewIds.insert(id)
    }
  }

  public func toggleExpansion(_ id: String) {
    guard let node = document?.node(id), !node.childIds.isEmpty else { return }
    if expanded.contains(id) {
      expanded.remove(id)
    } else {
      expanded.insert(id)
    }
  }

  public func navigateSelection(_ key: UInt16) {
    guard let hierarchy, let selectedId else { return }
    let visible = visibleHierarchyIndices
    guard let row = visible.firstIndex(where: { hierarchy.entries[$0].node.id == selectedId })
    else { return }
    let node = hierarchy.entries[visible[row]].node
    switch key {
    case 125, 126:
      let next = row + (key == 125 ? 1 : -1)
      if visible.indices.contains(next) {
        self.selectedId = hierarchy.entries[visible[next]].node.id
      }
    case 123:
      if !node.childIds.isEmpty && expanded.contains(node.id) {
        toggleExpansion(node.id)
      } else if let parent = node.parentId {
        if expanded.contains(parent) { toggleExpansion(parent) }
        self.selectedId = parent
      }
    case 124:
      if !node.childIds.isEmpty && !expanded.contains(node.id) {
        toggleExpansion(node.id)
      } else if let next = visible.dropFirst(row + 1).first(where: {
        !hierarchy.entries[$0].hidden
      }
      ) {
        self.selectedId = hierarchy.entries[next].node.id
      }
    default: break
    }
  }

  public func expandSubtree(_ id: String, fully: Bool = false) {
    guard let hierarchy, let index = hierarchy.positions[id] else { return }
    let entry = hierarchy.entries[index]
    for child in hierarchy.entries[index..<entry.subtreeEnd] where !child.node.childIds.isEmpty {
      if fully || !child.prefersCollapse || entry.prefersCollapse {
        expanded.insert(child.node.id)
      }
    }
  }

  public func collapseSubtree(_ id: String) {
    guard let hierarchy, let index = hierarchy.positions[id] else { return }
    for entry in hierarchy.entries[(index + 1)..<hierarchy.entries[index].subtreeEnd] {
      expanded.remove(entry.node.id)
    }
  }

  public func install(_ content: WorkspaceContent) {
    pendingDoubleClickId = nil
    let document = content.document
    if expansionBeforeScope != nil { endScope() }
    let keepingState = self.document?.snapshot.sessionId == document.snapshot.sessionId
    let previous =
      keepingState
      ? Dictionary(
        uniqueKeysWithValues: (self.document?.snapshot.nodes ?? []).map {
          ($0.id, expanded.contains($0.id))
        }) : [:]
    let previousSelection = keepingState ? selectedId : nil
    let previousWindow = windowId
    self.content = content
    windowId =
      keepingState && content.windows[previousWindow] != nil
      ? previousWindow : document.snapshot.windows.first?.id ?? ""
    selectedId =
      previousSelection.flatMap { document.node($0)?.id }
      ?? previewHierarchy?.entries.last(where: { $0.controllerRoot })?.node.id
      ?? document.roots(in: windowId).first?.id
    expanded = content.windows.values.reduce(into: Set<String>()) {
      $0.formUnion($1.initialExpansion(previous: previous))
    }
    searchText = ""
    searchIncludedIds = nil
    focusRootId = nil
    hiddenPreviewIds = content.hierarchy.defaultHiddenPreviewIds
    hoveredId = nil
  }

  public enum Action: Sendable {
    case select(String?)
    case reveal(String)
    case hover(String?)
    case searchChanged(String)
    case focus(String)
    case endScope
    case expansionLevelChanged(Int)
    case toggleExpansion(String)
    case expandSubtree(String, fully: Bool)
    case collapseSubtree(String)
    case navigate(UInt16)
    case togglePreview(String)
    case restorePreviews
    case showHiddenChanged(Bool)
    case doubleClicked(String)
    case doubleClickChoice(String?)
    case doubleClickBehaviorChanged(String)
  }
  public func send(_ action: Action) {
    defer { onSelectionChange?() }
    switch action {
    case .select(let id): self.selectedId = id
    case .reveal(let id): if let node = self.document?.node(id) { self.select(node) }
    case .hover(let id): self.hover(id)
    case .searchChanged(let value): self.applySearch(value)
    case .focus(let id): self.focus(id)
    case .endScope: self.endScope()
    case .expansionLevelChanged(let level): self.setExpansionLevel(level)
    case .toggleExpansion(let id): self.toggleExpansion(id)
    case .expandSubtree(let id, let fully): self.expandSubtree(id, fully: fully)
    case .collapseSubtree(let id): self.collapseSubtree(id)
    case .navigate(let key): self.navigateSelection(key)
    case .togglePreview(let id): self.togglePreview(id)
    case .restorePreviews: self.hiddenPreviewIds = []
    case .showHiddenChanged(let value): self.showHidden = value
    case .doubleClickBehaviorChanged(let value):
      doubleClickBehavior = value
    case .doubleClicked(let id):
      if self.doubleClickBehavior == "ask" {
        self.pendingDoubleClickId = id
      } else if self.doubleClickBehavior == "focus" {
        self.focus(id)
      } else {
        self.toggleExpansion(id)
      }
    case .doubleClickChoice(let choice):
      defer { self.pendingDoubleClickId = nil }
      guard let id = self.pendingDoubleClickId, let choice else { return }
      doubleClickBehavior = choice
      if choice == "focus" { self.focus(id) } else { self.toggleExpansion(id) }
    }
  }
}
