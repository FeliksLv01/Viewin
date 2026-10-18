import XCTest
import ViewinProtocol
@testable import ViewinSnapshot

final class EventHandlerPresentationTests: XCTestCase {
  func testMultipleActionsAndGestureMetadataStayStructured() throws {
    let value: JSONValue = .object([
      "typeName": .string("MyTap"), "handlerType": .string("gesture"), "enabled": .bool(false),
      "delegate": .string("Controller (0x123)"), "inheritedRecognizerName": .string("UITapGestureRecognizer"),
      "memberReferences": .array([.object(["name": .string("_tap"), "ownerType": .string("Controller")])]),
      "targetActions": .array([
        .object(["target": .string("First"), "action": .string("first:")]),
        .object(["target": .string("Second"), "action": .string("second:")]),
      ]),
    ])
    let event = try XCTUnwrap(EventHandlerPresentation(id: 0, value: value))
    XCTAssertTrue(event.isGesture)
    XCTAssertEqual(event.subtitles, ["Inherits from UITapGestureRecognizer", "(Controller *) → _tap"])
    XCTAssertEqual(event.rows.map(\.label), ["Enabled", "Delegate", "Target 1", "Action 1", "Target 2", "Action 2"])
    XCTAssertEqual(event.rows.map(\.value), ["NO", "Controller (0x123)", "First", "first:", "Second", "second:"])
  }

  func testUnavailableIsDifferentFromKnownEmptyOrLegacyMissing() throws {
    var fields: [String: JSONValue] = ["typeName": .string("UITapGestureRecognizer")]
    let legacy = try XCTUnwrap(EventHandlerPresentation(id: 0, value: .object(fields)))
    XCTAssertEqual(legacy.rows.last?.value, "未采集")
    fields["delegate"] = .null
    fields["targetActions"] = .array([])
    let empty = try XCTUnwrap(EventHandlerPresentation(id: 0, value: .object(fields)))
    XCTAssertEqual(empty.rows.map(\.value), ["未采集", "nil", "nil", "NULL"])
    fields["targetActionsAvailability"] = .string("unavailable")
    let unavailable = try XCTUnwrap(EventHandlerPresentation(id: 0, value: .object(fields)))
    XCTAssertEqual(unavailable.rows.last?.value, "不可用")
  }

  func testOldControlSnapshotGetsNamedEventAndEditingIcon() throws {
    let control = try XCTUnwrap(EventHandlerPresentation(id: 0, value: .object([
      "typeName": .string("UIControl"), "event": .integer(64),
      "target": .string("Controller"), "action": .string("tap:"),
    ])))
    XCTAssertEqual(control.title, "UIControlEventTouchUpInside")
    XCTAssertFalse(control.isGesture)
    XCTAssertEqual(control.rows.map(\.value), ["Controller", "tap:"])
    let editing = try XCTUnwrap(EventHandlerPresentation(id: 0, value: .object([
      "typeName": .string("UIControl"), "eventName": .string("UIControlEventEditingChanged"),
    ])))
    XCTAssertEqual(editing.symbol, "keyboard")
  }
}
