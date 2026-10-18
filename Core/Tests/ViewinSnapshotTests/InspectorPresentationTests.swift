import ViewinProtocol
import ViewinSnapshot
import XCTest

final class InspectorPresentationTests: XCTestCase {
  private func property(_ id: String, _ value: JSONValue, title: String? = nil) -> NodeProperty {
    .init(id: id, title: title ?? id, value: value, availability: "available", reason: nil)
  }
  private func node(_ framework: String, _ groups: [PropertyGroup]) -> SnapshotNode {
    .init(id: "node", windowId: "window", parentId: nil, childIds: [], framework: framework,
          kind: "component", typeName: "Component", name: "Component", identifiers: [:], geometry: nil,
          visibility: .init(hidden: false, alpha: 1), properties: groups, sourceLocation: nil,
          imageId: nil, groupImageId: nil)
  }
  func testDiagnosticsAreNotPresentedButRawSnapshotAndCustomAttributesRemain() {
    let groups: [PropertyGroup] = [
      .init(id: "compose", title: "Compose", properties: [property("backend", .string("composition")), property("layoutDirection", .string("Ltr"))]),
      .init(id: "rendering", title: "Rendering", properties: [property("imageSource", .string("crop"))]),
      .init(id: "custom", title: "Custom", properties: [property("backend", .string("Customer backend"))]),
    ]
    let original = node("compose", groups)
    let projected = InspectorPresentation.groups(for: original)
    XCTAssertEqual(projected.map(\.id), ["compose", "custom"])
    XCTAssertEqual(projected[0].properties.map(\.id), ["layoutDirection"])
    XCTAssertEqual(projected[1].properties.first?.value, .string("Customer backend"))
    XCTAssertEqual(original.properties, groups)
  }
  func testTextAndPublicStateSurviveTypeSummaryFiltering() {
    let original = node("compose", [
      .init(id: "parameters", title: "Parameters", properties: [
        property("text", .string("androidx.example.literal.Text")), property("maxLines", .integer(2_147_483_647)),
        property("modifier", .string("androidx.compose.ui.Modifier$Companion")),
        property("state", .string("androidx.compose.foundation.lazy.LazyListState")),
      ]),
      .init(id: "semantics", title: "Semantics", properties: [
        property("Role", .string("Button")), property("Focused", .bool(false)),
        property("IndexForKey", .string("e20")), property("Shape", .string("dt")),
      ]),
    ])
    let groups = InspectorPresentation.groups(for: original)
    XCTAssertEqual(groups[0].properties.map(\.id), ["text", "maxLines"])
    XCTAssertEqual(groups[0].properties[0].value, .string("androidx.example.literal.Text"))
    XCTAssertEqual(groups[0].properties[1].value, .string(L10n.text("不限")))
    XCTAssertEqual(groups[1].properties.map(\.id), ["Role", "Focused"])
  }
  func testSwiftUIKeepsTextAndLayoutWithoutExposingReflectionPaths() {
    let original = node("swiftui", [
      .init(id: "swiftui", title: "SwiftUI", properties: [
        property("value.1", .string("SwiftUI inside UIKit"), title: "storage.anyTextStorage.key.key"),
        property("value.2", .integer(8), title: "_tree.root.spacing"),
        property("value.3", .integer(1), title: "__taps._value"),
      ]),
    ])
    let values = InspectorPresentation.groups(for: original)[0].properties
    XCTAssertEqual(values.map(\.title), ["Text", "Spacing"])
    XCTAssertEqual(values[0].value, .string("SwiftUI inside UIKit"))
  }
  func testModifiersRetainUsableColorAndEnabledStateWithoutRuntimePlumbing() {
    let original = node("compose", [.init(id: "modifiers", title: "Modifiers", properties: [property("modifiers", .array([
      .object(["name": .string("clickable"), "type": .string("ClickElement"), "properties": .object([
        "enabled": .bool(false), "onClick": .string("app.Screen$$ExternalSyntheticLambda0"), "interactionSource": .null,
      ])]),
      .object(["name": .string("RootFocusTarget"), "properties": .object([:])]),
    ]))])])
    let values = InspectorPresentation.groups(for: original)[0].properties[0].value.elements
    XCTAssertEqual(values.count, 1)
    XCTAssertNil(values[0].fields["type"])
    XCTAssertEqual(values[0].fields["properties"], .object(["enabled": .bool(false)]))
  }
  func testComposeActionHasTheSameReadablePresentationAsThePopover() throws {
    let event = try XCTUnwrap(EventHandlerPresentation(id: 0, value: .object([
      "type": .string("Compose.OnClick"), "origin": .string("composeSemantics"),
      "eventName": .string("OnClick"), "enabled": .bool(false), "handlerDescription": .string("Update counter"),
    ])))
    XCTAssertEqual(event.title, "OnClick")
    XCTAssertEqual(event.rows.map(\.label), ["Enabled", "Action"])
    XCTAssertEqual(event.rows.map(\.value), ["NO", "Update counter"])
  }
}
