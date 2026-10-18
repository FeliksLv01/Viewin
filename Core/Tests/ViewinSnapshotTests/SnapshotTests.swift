import ViewinTestSupport
import Foundation
import XCTest
import ViewinProtocol
@testable import ViewinSnapshot

final class SnapshotTests: XCTestCase {
    func testNodeImageReferencesMustResolveAndSurviveRoundTrip() throws {
        let invalid = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            nodes[0]["imageId"] = "solo-window"
            object["nodes"] = nodes
        }
        XCTAssertThrowsError(try SnapshotDocument(data: invalid))
        let valid = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            nodes[0]["imageId"] = "solo-window"
            object["nodes"] = nodes
            object["images"] = [["id": "solo-window", "path": "images/window.png", "mimeType": "image/png", "pixelWidth": 10, "pixelHeight": 10]]
        }
        let document = try SnapshotDocument(data: valid)
        XCTAssertEqual(document.node("window")?.imageId, "solo-window")
        XCTAssertEqual(try SnapshotDocument(data: JSONEncoder().encode(document.snapshot)).node("window")?.imageId, "solo-window")
    }

    func testMeasurementUsesFrameEdgesAndOverlappingAxesHaveZeroGap() {
        let a = LayoutRect(x: 10, y: 20, width: 100, height: 50)
        let b = LayoutRect(x: 130, y: 40, width: 30, height: 40)
        let gap = LayoutMeasurement(from: a, to: b)
        XCTAssertEqual(gap.horizontalGap, 20)
        XCTAssertEqual(gap.verticalGap, 0)
        XCTAssertEqual(LayoutMeasurement(from: b, to: a).horizontalGap, 20)
        XCTAssertEqual(LayoutMeasurement(from: a, to: a).horizontalGap, 0)
        let below = LayoutRect(x: 10, y: 100, width: 100, height: 10)
        XCTAssertEqual(LayoutMeasurement(from: a, to: below).verticalGap, 30)
    }

    func testExplodedProjectionRotationSeparationAndSelection() throws {
        let document = try ExampleSnapshot.ios.load()
        let window = try XCTUnwrap(document.snapshot.windows.first)
        func project(yaw: Double = 0, spacing: Double = 36) -> [ProjectedPlane] {
            ExplodedLayout.project(document: document, window: window,
                viewport: LayoutSize(width: 800, height: 900), yaw: yaw, pitch: 0, spacing: spacing, zoom: 1)
        }
        let planes = project()
        XCTAssertFalse(planes.contains { $0.nodeId == "screen" }) // no invented geometry
        let button = try XCTUnwrap(planes.first { $0.nodeId == "button" })
        let center = LayoutPoint(x: button.corners.map(\.x).reduce(0, +) / 4,
                                 y: button.corners.map(\.y).reduce(0, +) / 4)
        XCTAssertEqual(ExplodedLayout.hitTest(center, planes: planes), "button")
        XCTAssertNotEqual(project(yaw: 0.6).first { $0.nodeId == "button" }?.corners, button.corners)
        XCTAssertTrue(project(spacing: 0).allSatisfy { $0.depth == 0 })
        XCTAssertGreaterThan(project(spacing: 80).first { $0.nodeId == "button" }!.depth, button.depth)
        XCTAssertNil(ExplodedLayout.hitTest(LayoutPoint(x: -100, y: -100), planes: planes))
    }

    private func modified(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ExampleSnapshot.ios.data()) as? [String: Any])
        change(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testBothPlatformsRoundTripAndPreserveMixedFrameworks() throws {
        for example in ExampleSnapshot.allCases {
            let document = try example.load()
            XCTAssertEqual(try SnapshotDocument(data: JSONEncoder().encode(document.snapshot)).snapshot, document.snapshot)
            XCTAssertEqual(Set(document.snapshot.nodes.map(\.framework)).count, 2)
            XCTAssertEqual(document.snapshot.source, "fixture")
        }
    }

    func testLogicalNodeAndCrossTreeRelation() throws {
        let document = try ExampleSnapshot.ios.load()
        XCTAssertNil(document.node("screen")?.geometry)
        XCTAssertEqual(document.snapshot.relations.first?.fromNodeId, "button")
        XCTAssertEqual(document.node("layer")?.parentId, "root")
    }

    func testInspectionSummariesAndSearchUseAvailableMetadata() throws {
        let ios = try ExampleSnapshot.ios.load()
        XCTAssertEqual(ios.node("cell")?.listPositionSummary, "[0, 2]")
        XCTAssertEqual(ios.node("details")?.memberReferenceNames, ["ProfileCell._descriptionLabel"])
        XCTAssertEqual(ios.find("_descriptionLabel", in: "main").map(\.id), ["details"])
        XCTAssertEqual(ios.find("showDetails:", in: "main").map(\.id), ["cell"])
        XCTAssertEqual(ios.find("Hello, Viewin", in: "main").map(\.id), ["heading"])
        let android = try ExampleSnapshot.android.load()
        XCTAssertEqual(android.node("cell")?.listPositionSummary, "[2]")
        let data = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            let index = nodes.firstIndex { $0["id"] as? String == "cell" }!
            var groups = nodes[index]["properties"] as! [[String: Any]]
            for g in groups.indices {
                var properties = groups[g]["properties"] as! [[String: Any]]
                for p in properties.indices { properties[p]["availability"] = "unavailable" }
                groups[g]["properties"] = properties
            }
            nodes[index]["properties"] = groups
            object["nodes"] = nodes
        }
        let unavailable = try SnapshotDocument(data: data)
        XCTAssertNil(unavailable.node("cell")?.listPositionSummary)
        XCTAssertTrue(unavailable.node("cell")?.eventHandlerSummaries.isEmpty == true)
    }

    func testFractionalCaptureTimestampIsAccepted() throws {
        let data = try modified { $0["capturedAt"] = "2026-10-18T03:00:00.123Z" }
        XCTAssertEqual(try SnapshotDocument(data: data).snapshot.capturedAt, "2026-10-18T03:00:00.123Z")
    }

    func testVeryDeepHierarchyIsRejectedBeforeQueries() throws {
        let data = try modified { object in
            let template = (object["nodes"] as! [[String: Any]])[0]
            object["nodes"] = (0...130).map { index -> [String: Any] in
                var node = template
                node["id"] = index == 0 ? "window" : "node-\(index)"
                node["parentId"] = index == 0 ? NSNull() : (index == 1 ? "window" : "node-\(index - 1)") as Any
                node["childIds"] = index == 130 ? [] : ["node-\(index + 1)"]
                return node
            }
            object["relations"] = []
        }
        XCTAssertThrowsError(try SnapshotDocument(data: data))
    }

    func testHitTestIsWindowScopedAndDeepestFirst() throws {
        let document = try ExampleSnapshot.ios.load()
        XCTAssertEqual(document.hitTest(x: 100, y: 375, in: "main").first?.id, "button")
        XCTAssertTrue(document.hitTest(x: 100, y: 375, in: "other").isEmpty)
    }

    func testRotatedPolygonRejectsBoundingBoxOnlyHit() throws {
        let data = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            let index = nodes.firstIndex { $0["id"] as? String == "button" }!
            var geometry = nodes[index]["geometry"] as! [String: Any]
            geometry["frameInWindow"] = ["x": 0, "y": 0, "width": 100, "height": 100]
            geometry["cornersInWindow"] = [["x": 50, "y": 0], ["x": 100, "y": 50], ["x": 50, "y": 100], ["x": 0, "y": 50]]
            nodes[index]["geometry"] = geometry
            object["nodes"] = nodes
        }
        let document = try SnapshotDocument(data: data)
        XCTAssertFalse(document.hitTest(x: 5, y: 5, in: "main").contains { $0.id == "button" })
        XCTAssertTrue(document.hitTest(x: 50, y: 50, in: "main").contains { $0.id == "button" })
    }

    func testAncestorVisibilityAndClipping() throws {
        let hidden = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            let index = nodes.firstIndex { $0["id"] as? String == "stack" }!
            nodes[index]["visibility"] = ["hidden": true, "alpha": 1]
            object["nodes"] = nodes
        }
        XCTAssertFalse(try SnapshotDocument(data: hidden).hitTest(x: 100, y: 375, in: "main").contains { $0.id == "button" })
        let clipped = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            let index = nodes.firstIndex { $0["id"] as? String == "details" }!
            var geometry = nodes[index]["geometry"] as! [String: Any]
            geometry["frameInWindow"] = ["x": 40, "y": 600, "width": 310, "height": 144]
            geometry["cornersInWindow"] = [["x": 40, "y": 600], ["x": 350, "y": 600], ["x": 350, "y": 744], ["x": 40, "y": 744]]
            nodes[index]["geometry"] = geometry; object["nodes"] = nodes
        }
        XCTAssertFalse(try SnapshotDocument(data: clipped).hitTest(x: 100, y: 680, in: "main").contains { $0.id == "details" })
    }

    func testDanglingReferencesAndDuplicateIdsAreRejected() throws {
        let dangling = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            nodes[0]["childIds"] = ["missing"]; object["nodes"] = nodes
        }
        XCTAssertThrowsError(try SnapshotDocument(data: dangling))
        let duplicate = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            nodes.append(nodes[0]); object["nodes"] = nodes
        }
        XCTAssertThrowsError(try SnapshotDocument(data: duplicate))
    }

    func testDisconnectedCycleIsRejected() throws {
        let cycle = try modified { object in
            var nodes = object["nodes"] as! [[String: Any]]
            let a = nodes.firstIndex { $0["id"] as? String == "heading" }!
            let b = nodes.firstIndex { $0["id"] as? String == "subtitle" }!
            let stack = nodes.firstIndex { $0["id"] as? String == "stack" }!
            nodes[a]["parentId"] = "subtitle"; nodes[a]["childIds"] = ["subtitle"]
            nodes[b]["parentId"] = "heading"; nodes[b]["childIds"] = ["heading"]
            nodes[stack]["childIds"] = (nodes[stack]["childIds"] as! [String]).filter { !["heading", "subtitle"].contains($0) }
            object["nodes"] = nodes
        }
        XCTAssertThrowsError(try SnapshotDocument(data: cycle))
    }

    func testImageTraversalIsRejected() throws {
        let data = try modified { object in
            object["images"] = [["id": "image", "path": "../secret.png", "mimeType": "image/png", "pixelWidth": 1, "pixelHeight": 1]]
        }
        XCTAssertThrowsError(try SnapshotDocument(data: data))
    }

    func testForwardFieldsAndKindsAndMajorVersionRejection() throws {
        let data = try modified { object in
            object["futureField"] = ["enabled": true]
            object["protocolVersion"] = ["major": 0, "minor": 2]
            var nodes = object["nodes"] as! [[String: Any]]
            nodes[0]["kind"] = "future-container"; object["nodes"] = nodes
        }
        XCTAssertEqual(try SnapshotDocument(data: data).node("window")?.kind, "future-container")
        let incompatible = try modified { $0["protocolVersion"] = ["major": 1, "minor": 0] }
        XCTAssertThrowsError(try SnapshotDocument(data: incompatible))
    }

    func testJSONPropertyValuesPreserveTheirTypes() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"available":true,"empty":null,"offset":{"x":1.5},"children":[1,"two"]}"#.utf8))
        guard case .object(let properties) = value else { return XCTFail("Expected object") }
        XCTAssertEqual(properties["available"], .bool(true))
        XCTAssertEqual(properties["empty"], .null)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
}
