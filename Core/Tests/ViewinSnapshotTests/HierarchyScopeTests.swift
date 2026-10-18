import ViewinTestSupport
import Foundation
import XCTest

@testable import ViewinSnapshot

final class HierarchyScopeTests: XCTestCase {
  func testAllWindowsAppearAsRootsAndRuntimeHostNameStaysIntact() throws {
    let fixture = try ExampleSnapshot.ios.load()
    let data = try JSONEncoder().encode(fixture.snapshot)
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var windows = try XCTUnwrap(json["windows"] as? [[String: Any]])
    var nodes = try XCTUnwrap(json["nodes"] as? [[String: Any]])
    var overlay = windows[0]
    overlay["id"] = "overlay"
    overlay["rootNodeIds"] = ["overlay-root"]
    windows.append(overlay)
    var root = try XCTUnwrap(nodes.first(where: { $0["id"] as? String == "window" }))
    root["id"] = "overlay-root"
    root["windowId"] = "overlay"
    root["childIds"] = [String]()
    let runtimeType = "_TtGC7SwiftUI14_UIHostingViewGVS_15ModifiedContentGS1_VStack___"
    root["name"] = runtimeType
    root["typeName"] = runtimeType
    nodes.append(root)
    json["windows"] = windows
    json["nodes"] = nodes
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: json))
    let hierarchy = HierarchyPresentation(document: document)
    XCTAssertEqual(hierarchy.visibleIndices(expanded: []).map { hierarchy.entries[$0].node.id }, ["window", "overlay-root"])
    XCTAssertEqual(HierarchyPresentation(document: document, windowId: "overlay").entries.map { $0.node.id }, ["overlay-root"])
    let host = try XCTUnwrap(document.node("overlay-root"))
    XCTAssertEqual(host.sidebarTitle, "_UIHostingView")
    XCTAssertEqual(host.typeName, runtimeType)
  }

  func testFocusKeepsOnlyRootAndVisibleDescendants() throws {
    let document = try ExampleSnapshot.ios.load()
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let all = Set(hierarchy.entries.map { $0.node.id })
    let focused = hierarchy.visibleIndices(expanded: all, rootId: "card").map {
      hierarchy.entries[$0].node.id
    }
    XCTAssertEqual(focused, ["card", "avatar", "name", "email"])
    XCTAssertEqual(
      hierarchy.visibleIndices(expanded: [], rootId: "card").map { hierarchy.entries[$0].node.id },
      ["card"])
    XCTAssertFalse(
      hierarchy.surfaces(expanded: all, rootId: "card").contains { $0.node.id == "window" })
  }

  func testSearchOpensAncestorsAndRetainsMatchedSubtreeForManualExpansion() throws {
    let document = try ExampleSnapshot.ios.load()
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let result = hierarchy.searchResult("ProfileCard", expanded: hierarchy.initialExpansion())
    XCTAssertTrue(
      result.included.isSuperset(of: ["card", "avatar", "name", "email", "window", "root", "stack"])
    )
    XCTAssertFalse(result.expanded.contains("card"))
    let first = hierarchy.visibleIndices(expanded: result.expanded, includedIds: result.included)
      .map { hierarchy.entries[$0].node.id }
    XCTAssertTrue(first.contains("card"))
    XCTAssertFalse(first.contains("avatar"))
    XCTAssertFalse(first.contains("button"))
    var expanded = result.expanded
    expanded.insert("card")
    let after = hierarchy.visibleIndices(expanded: expanded, includedIds: result.included).map {
      hierarchy.entries[$0].node.id
    }
    XCTAssertTrue(after.contains("avatar"))
    XCTAssertFalse(after.contains("button"))
  }

  func testTemporaryPreviewHideHidesSubtreeWithoutChangingSidebarOrSnapshot() throws {
    let document = try ExampleSnapshot.ios.load()
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let expanded = hierarchy.initialExpansion()
    let rowsBefore = hierarchy.visibleIndices(expanded: expanded)
    let before = hierarchy.surfaces(expanded: expanded)
    let after = hierarchy.surfaces(expanded: expanded, hiddenPreviewIds: ["card"])
    XCTAssertTrue(before.contains { $0.node.id == "avatar" })
    XCTAssertFalse(after.contains { ["card", "avatar", "name", "email"].contains($0.node.id) })
    XCTAssertTrue(after.contains { $0.node.id == "button" })
    XCTAssertEqual(hierarchy.visibleIndices(expanded: expanded), rowsBefore)
    XCTAssertFalse(try XCTUnwrap(document.node("card")).visibility.hidden)
    XCTAssertEqual(
      hierarchy.surfaces(expanded: expanded).map { $0.node.id }, before.map { $0.node.id })
  }

  func testShowHiddenIsInheritedAndDoesNotOverrideTemporaryHide() throws {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: ExampleSnapshot.ios.data()) as? [String: Any])
    var nodes = object["nodes"] as! [[String: Any]]
    let card = try XCTUnwrap(nodes.firstIndex { $0["id"] as? String == "card" })
    nodes[card]["visibility"] = ["hidden": true, "alpha": 1.0]
    object["nodes"] = nodes
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object))
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let all = Set(hierarchy.entries.map { $0.node.id })
    XCTAssertFalse(hierarchy.surfaces(expanded: all).contains { $0.node.id == "avatar" })
    XCTAssertTrue(
      hierarchy.surfaces(expanded: all, showHidden: true).contains { $0.node.id == "avatar" })
    XCTAssertFalse(
      hierarchy.surfaces(expanded: all, hiddenPreviewIds: ["card"], showHidden: true).contains {
        $0.node.id == "avatar"
      })
  }

  func testGlobalExpansionLevelsHaveDistinctScopes() throws {
    let document = try ExampleSnapshot.ios.load()
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    XCTAssertEqual(
      hierarchy.visibleIndices(expanded: hierarchy.initialExpansion(level: 0)).map {
        hierarchy.entries[$0].node.id
      }, ["window"])
    XCTAssertEqual(
      hierarchy.visibleIndices(expanded: hierarchy.initialExpansion(level: 1)).map {
        hierarchy.entries[$0].node.id
      }, ["window", "root"])
    XCTAssertTrue(hierarchy.initialExpansion(level: 4).contains("cell"))
    XCTAssertEqual(
      hierarchy.visibleIndices(expanded: hierarchy.initialExpansion(level: 4)).count,
      hierarchy.entries.count)
  }
}
