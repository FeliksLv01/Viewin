import Foundation
import ViewinProtocol

/// A snapshot-scoped preorder index. Expansion and search reuse it instead of
/// rebuilding ancestor chains and inspecting every property's JSON on each row draw.
public struct HierarchyPresentation: Sendable {
  public struct Entry: Sendable {
    public let node: SnapshotNode
    public let depth: Int
    public let subtreeEnd: Int
    public let hidden: Bool
    public let prefersCollapse: Bool
    public let noPreview: Bool
    public let controllerRoot: Bool
    public let searchText: [String]
  }
  public struct Surface: Sendable {
    public let node: SnapshotNode
    public let level: Int
    public let imageId: String?
  }
  public let entries: [Entry]
  public let positions: [String: Int]

  /// Default-hidden system overlay roots; their full subtree uses normal hiding semantics.
  public static func isDefaultHiddenRoot(_ node: SnapshotNode) -> Bool {
    node.typeName == "_UIFloatingBarContainerView"
      || (node.framework == "swiftuiRendering" && node.identifiers["renderingRoot"] == "true")
  }

  public var defaultHiddenPreviewIds: Set<String> {
    Set(entries.filter { Self.isDefaultHiddenRoot($0.node) }.map { $0.node.id })
  }

  public init(document: SnapshotDocument, windowId: String? = nil) {
    var output: [Entry] = []
    var positions: [String: Int] = [:]
    func walk(_ node: SnapshotNode, depth: Int, hidden: Bool, collapsed: Bool, noPreview: Bool) {
      let start = output.count
      let hints: [String: JSONValue]
      if case .object(let value) = node.availableProperty("hierarchyHints") {
        hints = value
      } else {
        hints = [:]
      }
      let hidden = hidden || node.visibility.hidden || node.visibility.alpha <= 0
      let preferred =
        collapsed || hints["prefersCollapse"] == .bool(true)
        || ["text", "image", "button"].contains(node.kind)
        || ["UINavigationBar", "UITabBar"].contains(node.typeName)
      let noPreview = noPreview || hints["noPreview"] == .bool(true)
      let controller = hints["controllerRoot"] == .bool(true)
      let search = node.inspectionSearchText
      positions[node.id] = start
      output.append(
        Entry(
          node: node, depth: depth, subtreeEnd: 0, hidden: hidden,
          prefersCollapse: preferred, noPreview: noPreview,
          controllerRoot: controller, searchText: search))
      for child in document.children(of: node) {
        walk(child, depth: depth + 1, hidden: hidden, collapsed: preferred, noPreview: noPreview)
      }
      output[start] = Entry(
        node: node, depth: depth, subtreeEnd: output.count, hidden: hidden,
        prefersCollapse: preferred, noPreview: noPreview,
        controllerRoot: controller, searchText: search)
    }
    for root in document.snapshot.windows.filter({ windowId == nil || $0.id == windowId }).flatMap({
      document.roots(in: $0.id)
    }) {
      walk(root, depth: 0, hidden: false, collapsed: false, noPreview: false)
    }
    entries = output
    self.positions = positions
  }

  public func visibleIndices(
    expanded: Set<String>, search: String = "", rootId: String? = nil,
    includedIds: Set<String>? = nil
  ) -> [Int] {
    if !search.isEmpty {
      var matches = Set<Int>()
      for index in entries.indices
      where entries[index].searchText.contains(where: {
        $0.localizedCaseInsensitiveContains(search)
      }) {
        var cursor: Int? = index
        while let current = cursor {
          if !matches.insert(current).inserted { break }
          cursor = entries[current].node.parentId.flatMap { positions[$0] }
        }
      }
      return entries.indices.filter(matches.contains)
    }
    var output: [Int] = []
    var index = rootId.flatMap { positions[$0] } ?? 0
    let end = rootId.flatMap { positions[$0] }.map { entries[$0].subtreeEnd } ?? entries.count
    while index < end {
      if includedIds == nil || includedIds!.contains(entries[index].node.id) {
        output.append(index)
      }
      index = expanded.contains(entries[index].node.id) ? index + 1 : entries[index].subtreeEnd
    }
    return output
  }

  /// Lookin's default expansion index is 3 (most), capped at 2 above 300 nodes.
  /// Keep explicit states on refresh; newly seen objects use the default policy.
  public func initialExpansion(previous: [String: Bool] = [:], level: Int? = nil) -> Set<String> {
    let level = level ?? (entries.count > 300 ? 2 : 3)
    if level == 0 { return [] }
    if level == 4 {
      return Set(entries.filter { !$0.node.childIds.isEmpty && !$0.noPreview }.map { $0.node.id })
    }
    let limited = level == 2 || level == 1
    let transitions = entries.indices.filter {
      entries[$0].depth == 1 && entries[$0].node.typeName == "UITransitionView"
    }
    var decisions = previous
    // The last transition branch is the active one, just as in Lookin.
    for index in transitions where decisions[entries[index].node.id] == nil {
      decisions[entries[index].node.id] = index == transitions.last
    }
    for entry in entries where decisions[entry.node.id] == nil && !entry.controllerRoot {
      if entry.hidden || entry.prefersCollapse || entry.noPreview {
        decisions[entry.node.id] = false
      }
    }
    if limited {
      let controllers = entries.indices.filter { entries[$0].controllerRoot }
      for index in controllers.reversed() {
        let controller = entries[index]
        var parent = controller.node.parentId
        while let id = parent, let position = positions[id] {
          if decisions[id] == nil { decisions[id] = true }
          parent = entries[position].node.parentId
        }
        let firstChild = controller.node.childIds.first.flatMap { positions[$0] }.map {
          entries[$0].node.typeName
        }
        let forward =
          level == 1 ? 0 : (["UITableView", "UICollectionView"].contains(firstChild ?? "") ? 2 : 3)
        for child in entries[index..<controller.subtreeEnd] where decisions[child.node.id] == nil {
          if child.depth < controller.depth + forward { decisions[child.node.id] = true }
        }
      }
      // Generic/non-UIKit snapshots have no UIViewController metadata.
      if controllers.isEmpty {
        for entry in entries where decisions[entry.node.id] == nil {
          decisions[entry.node.id] = entry.depth < (level == 1 ? 1 : 3)
        }
      }
    }
    var result = Set<String>()
    for entry in entries where !entry.node.childIds.isEmpty {
      if decisions[entry.node.id] ?? !limited { result.insert(entry.node.id) }
    }
    return result
  }

  /// Match Lookin: visible overlapping surfaces advance one level; disjoint
  /// siblings share a level. Collapsed nodes use their complete group image.
  public func surfaces(
    expanded: Set<String>, search: String = "", rootId: String? = nil,
    includedIds: Set<String>? = nil, hiddenPreviewIds: Set<String> = [], showHidden: Bool = false
  ) -> [Surface] {
    var output: [Surface] = []
    var excluded = Set<Int>()
    for id in hiddenPreviewIds {
      if let index = positions[id] {
        excluded.formUnion(index..<entries[index].subtreeEnd)
      }
    }
    for index in visibleIndices(
      expanded: expanded, search: search, rootId: rootId, includedIds: includedIds)
    {
      let entry = entries[index]
      guard !entry.hidden || showHidden, !entry.noPreview, !excluded.contains(index),
        let frame = entry.node.geometry?.frameInWindow,
        frame.width > 0, frame.height > 0
      else { continue }
      var level = 0
      for other in output {
        guard let b = other.node.geometry?.frameInWindow else { continue }
        if frame.x < b.x + b.width && frame.x + frame.width > b.x
          && frame.y < b.y + b.height && frame.y + frame.height > b.y
        {
          level = max(level, other.level + 1)
        }
      }
      let collapsed = entry.node.childIds.isEmpty || !expanded.contains(entry.node.id)
      output.append(
        Surface(
          node: entry.node, level: level,
          imageId: collapsed ? entry.node.groupImageId ?? entry.node.imageId : entry.node.imageId))
    }
    return output
  }

  /// Search keeps matched subtrees available, opens ancestors and initially
  /// collapses matches. Users can then expand a matched node, as in Lookin.
  public func searchResult(_ text: String, expanded: Set<String>) -> (
    included: Set<String>, expanded: Set<String>
  ) {
    var included = Set<String>()
    var expansion = expanded
    for index in entries.indices
    where entries[index].searchText.contains(where: { $0.localizedCaseInsensitiveContains(text) }) {
      var parent = entries[index].node.parentId
      while let id = parent, let position = positions[id] {
        included.insert(id)
        expansion.insert(id)
        parent = entries[position].node.parentId
      }
      for entry in entries[index..<entries[index].subtreeEnd] {
        included.insert(entry.node.id)
        expansion.remove(entry.node.id)
      }
    }
    return (included, expansion)
  }
}
