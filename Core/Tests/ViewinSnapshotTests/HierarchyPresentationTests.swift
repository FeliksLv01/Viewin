import ViewinTestSupport
import Foundation
import ViewinProtocol
import XCTest

@testable import ViewinSnapshot

final class HierarchyPresentationTests: XCTestCase {
  func testRenderingBranchIsInitiallyHiddenButCanBeShown() throws {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ExampleSnapshot.ios.data()) as? [String: Any])
    var nodes = object["nodes"] as! [[String: Any]]
    let index = try XCTUnwrap(nodes.firstIndex { $0["id"] as? String == "card" })
    nodes[index]["framework"] = "swiftuiRendering"
    nodes[index]["identifiers"] = ["renderingRoot": "true"]
    object["nodes"] = nodes
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object))
    let hierarchy = HierarchyPresentation(document: document)
    let expanded = hierarchy.initialExpansion()
    XCTAssertEqual(hierarchy.defaultHiddenPreviewIds, ["card"])
    XCTAssertFalse(hierarchy.surfaces(expanded: expanded, hiddenPreviewIds: hierarchy.defaultHiddenPreviewIds).contains { $0.node.id == "card" })
    XCTAssertTrue(hierarchy.surfaces(expanded: expanded, hiddenPreviewIds: []).contains { $0.node.id == "card" })
  }

  func testFloatingBarDefaultHidesEntireSubtreeAndCanRestore() throws {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: ExampleSnapshot.ios.data()) as? [String: Any])
    var nodes = object["nodes"] as! [[String: Any]]
    let card = try XCTUnwrap(nodes.firstIndex { $0["id"] as? String == "card" })
    nodes[card]["typeName"] = "_UIFloatingBarContainerView"
    object["nodes"] = nodes
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object))
    let hierarchy = HierarchyPresentation(document: document)
    let expanded = hierarchy.initialExpansion()
    let hidden = hierarchy.defaultHiddenPreviewIds
    XCTAssertEqual(hidden, ["card"])
    let full = hierarchy.surfaces(expanded: expanded)
    XCTAssertTrue(full.contains { $0.node.id == "card" })
    let filtered = hierarchy.surfaces(expanded: expanded, hiddenPreviewIds: hidden)
    let subtree = Set(
      document.snapshot.nodes.filter { node in
        node.id == "card" || document.ancestors(of: node).contains { $0.id == "card" }
      }.map(\.id))
    XCTAssertGreaterThan(subtree.count, 1)
    XCTAssertEqual(
      filtered.map { $0.node.id }, full.filter { !subtree.contains($0.node.id) }.map { $0.node.id })
    XCTAssertTrue(
      hierarchy.visibleIndices(expanded: expanded).contains {
        hierarchy.entries[$0].node.id == "card"
      })
    XCTAssertEqual(
      hierarchy.surfaces(expanded: expanded).map { $0.node.id }, full.map { $0.node.id })
    // Ordinary user-hidden containers still hide their whole subtree.
    XCTAssertFalse(
      hierarchy.surfaces(expanded: expanded, hiddenPreviewIds: ["root"]).contains {
        $0.node.id == "card"
      })
  }

  func testDefaultExpansionCollapsesControlsAndTheirInternals() throws {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: ExampleSnapshot.ios.data()) as? [String: Any])
    var nodes = object["nodes"] as! [[String: Any]]
    let button = try XCTUnwrap(nodes.firstIndex { $0["id"] as? String == "button" })
    nodes[button]["childIds"] = ["button-internals"]
    var child = nodes[button]
    child["id"] = "button-internals"
    child["parentId"] = "button"
    child["childIds"] = []
    nodes.append(child)
    object["nodes"] = nodes
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object))
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    var expanded = hierarchy.initialExpansion()
    XCTAssertTrue(expanded.contains("root"))
    XCTAssertFalse(expanded.contains("button"))
    XCTAssertTrue(expanded.contains("card"))
    XCTAssertFalse(
      hierarchy.visibleIndices(expanded: expanded).contains {
        hierarchy.entries[$0].node.id == "button-internals"
      })
    expanded.insert("button")
    XCTAssertTrue(
      hierarchy.visibleIndices(expanded: expanded).contains {
        hierarchy.entries[$0].node.id == "button-internals"
      })
    XCTAssertEqual(
      Set(hierarchy.visibleIndices(expanded: expanded).map { hierarchy.entries[$0].node.id }).count,
      hierarchy.visibleIndices(expanded: expanded).count)
  }

  func testCollapseHidesDescendantsAndSwitchesToGroupTexture() throws {
    let base = try ExampleSnapshot.ios.data()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
    var nodes = object["nodes"] as! [[String: Any]]
    let index = try XCTUnwrap(nodes.firstIndex { $0["id"] as? String == "card" })
    nodes[index]["imageId"] = "card-solo"
    nodes[index]["groupImageId"] = "card-group"
    object["nodes"] = nodes
    object["images"] = ["card-solo", "card-group"].map {
      [
        "id": $0, "path": "images/\($0).png", "mimeType": "image/png", "pixelWidth": 100,
        "pixelHeight": 100,
      ] as [String: Any]
    }
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object))
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    var expanded = hierarchy.initialExpansion()
    let before = hierarchy.surfaces(expanded: expanded)
    XCTAssertEqual(before.first { $0.node.id == "card" }?.imageId, "card-solo")
    let descendants = Set(
      document.snapshot.nodes.filter { document.ancestors(of: $0).contains { $0.id == "card" } }
        .map(\.id))
    XCTAssertFalse(descendants.isEmpty)
    expanded.remove("card")
    let after = hierarchy.surfaces(expanded: expanded)
    XCTAssertEqual(after.first { $0.node.id == "card" }?.imageId, "card-group")
    XCTAssertTrue(Set(after.map { $0.node.id }).isDisjoint(with: descendants))
    XCTAssertLessThan(after.count, before.count)
    expanded.insert("card")
    XCTAssertEqual(
      hierarchy.surfaces(expanded: expanded).map { $0.node.id }, before.map { $0.node.id })
    let roundTrip = try SnapshotDocument(data: JSONEncoder().encode(document.snapshot))
    XCTAssertEqual(roundTrip.node("card")?.groupImageId, "card-group")
    nodes[index]["groupImageId"] = "missing"
    object["nodes"] = nodes
    XCTAssertThrowsError(try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object)))
  }

  func testRefreshKeepsExplicitExpansionAndSearchIncludesAncestors() throws {
    let document = try ExampleSnapshot.ios.load()
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let expanded = hierarchy.initialExpansion(previous: ["card": false, "stack": true])
    XCTAssertFalse(expanded.contains("card"))
    XCTAssertTrue(expanded.contains("stack"))
    let visible = hierarchy.visibleIndices(expanded: [], search: "_descriptionLabel").map {
      hierarchy.entries[$0].node.id
    }
    XCTAssertTrue(visible.contains("details"))
    XCTAssertTrue(visible.contains("cell"))
    XCTAssertTrue(visible.contains("window"))
    XCTAssertFalse(visible.contains("button"))
  }

  func testLargeHierarchyUsesControllerRelativeExpansionLimit() throws {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: ExampleSnapshot.ios.data()) as? [String: Any])
    var prototype = (object["nodes"] as! [[String: Any]])[1]
    prototype["properties"] = []
    prototype["typeName"] = "UIView"
    prototype["kind"] = "view"
    prototype["parentId"] = "controller"
    var window = (object["nodes"] as! [[String: Any]])[0]
    window["childIds"] = ["controller"]
    var controller = prototype
    controller["id"] = "controller"
    controller["parentId"] = "window"
    controller["childIds"] = (0..<100).map { "branch-\($0)-0" }
    controller["properties"] = [
      [
        "id": "hierarchy", "title": "Hierarchy",
        "properties": [
          [
            "id": "hierarchyHints", "title": "Hints", "value": ["controllerRoot": true],
            "availability": "available",
          ]
        ],
      ]
    ]
    var nodes = [window, controller]
    for branch in 0..<100 {
      for depth in 0..<6 {
        var node = prototype
        node["id"] = "branch-\(branch)-\(depth)"
        node["parentId"] = depth == 0 ? "controller" : "branch-\(branch)-\(depth - 1)"
        node["childIds"] = depth == 5 ? [] : ["branch-\(branch)-\(depth + 1)"]
        nodes.append(node)
      }
    }
    object["nodes"] = nodes
    object["relations"] = []
    let document = try SnapshotDocument(data: JSONSerialization.data(withJSONObject: object))
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let expanded = hierarchy.initialExpansion()
    XCTAssertTrue(expanded.contains("controller"))
    XCTAssertTrue(expanded.contains("branch-0-1"))
    XCTAssertFalse(expanded.contains("branch-0-2"))
    XCTAssertEqual(hierarchy.visibleIndices(expanded: expanded).count, 302)
    XCTAssertTrue(hierarchy.initialExpansion(previous: ["branch-0-4": true]).contains("branch-0-4"))
  }

  func testDisjointSiblingsShareDepthAndHiddenAncestorsExcludeSurfaces() throws {
    let document = try ExampleSnapshot.ios.load()
    let hierarchy = HierarchyPresentation(document: document, windowId: "main")
    let surfaces = hierarchy.surfaces(expanded: Set(hierarchy.entries.map { $0.node.id }))
    for surface in surfaces {
      XCTAssertFalse(
        document.ancestors(of: surface.node).contains {
          $0.visibility.hidden || $0.visibility.alpha <= 0
        })
    }
    let root = try XCTUnwrap(surfaces.first { $0.node.id == "root" })
    let card = try XCTUnwrap(surfaces.first { $0.node.id == "card" })
    XCTAssertGreaterThan(card.level, root.level)
    // A control drawn below the card is not pushed forward by card internals.
    let button = try XCTUnwrap(surfaces.first { $0.node.id == "button" })
    XCTAssertEqual(button.level, card.level)
    XCTAssertEqual(
      surfaces.first { $0.node.id == "avatar" }?.level,
      surfaces.first { $0.node.id == "name" }?.level)
  }
}
