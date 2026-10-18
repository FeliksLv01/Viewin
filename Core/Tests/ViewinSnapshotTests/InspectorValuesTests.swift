import ViewinProtocol
import ViewinSnapshot
import XCTest

final class InspectorValuesTests: XCTestCase {
  func testDefaultSectionsAndConstraintOrdering() {
    XCTAssertTrue(InspectorValues.defaultHiddenSections.contains("l_s"))
    XCTAssertFalse(InspectorValues.defaultHiddenSections.contains("l_f"))
    XCTAssertFalse(InspectorValues.defaultHiddenSections.contains("sec_ctm"))
    let values: [JSONValue] = [
      .object(["effective": .bool(false), "firstItemType": .integer(0)]),
      .object([
        "effective": .bool(true), "firstItemType": .integer(2), "firstAttribute": .integer(7),
      ]),
      .object([
        "effective": .bool(true), "firstItemType": .integer(2), "firstAttribute": .integer(1),
      ]),
    ]
    XCTAssertEqual(InspectorValues.sortedConstraints(values), [values[2], values[1], values[0]])
    XCTAssertEqual(InspectorValues.layoutAttribute(.integer(32)), "minX")
    XCTAssertTrue(InspectorValues.layoutAttribute(.number(1e100)).hasPrefix("attribute("))
  }

  func testRGBAAndHexPreserveAlphaAndClampOnlyDisplay() {
    let color: [String: JSONValue] = [
      "red": .number(1), "green": .number(0.5), "blue": .number(0), "alpha": .number(0.6),
    ]
    XCTAssertEqual(InspectorValues.rgbaText(color), "rgba(255, 127.5, 0, 0.6)")
    XCTAssertEqual(InspectorValues.hexColor(color), "#FF800099")
    XCTAssertEqual(
      InspectorValues.hexColor(["red": .number(2), "green": .number(-1)]), "#FF0000FF")
    XCTAssertEqual(color["green"], .number(0.5))
  }

  func testEnumNamesUseIOSValuesAndPreserveUnknown() {
    XCTAssertEqual(
      InspectorValues.enumText(type: "NSTextAlignment", value: .integer(4)), "Natural (4)")
    XCTAssertEqual(
      InspectorValues.enumText(type: "UIStackViewAlignment", value: .integer(5)),
      "Last Baseline (5)")
    XCTAssertEqual(
      InspectorValues.enumText(type: "FutureEnum", value: .integer(8)), "FutureEnum (8)")
  }
  func testNoCollectionIsPrintedAsJSONAndSearchFindsNestedText() {
    let value = JSONValue.object(["targets": .array([.object(["action": .string("tappedCard:")])])])
    XCTAssertEqual(value.inspectorText, L10n.format("%@ 个属性", "1"))
    XCTAssertTrue(value.containsInspectorText("TappedCard"))
    XCTAssertFalse(value.containsInspectorText("missing"))
  }
  func testConstraintSummaryUsesIOSAttributeNumbers() {
    let fields: [String: JSONValue] = [
      "firstItem": .object(["className": .string("UILabel")]), "firstAttribute": .integer(7),
      "secondItem": .null, "relation": .integer(-1), "constant": .number(100),
    ]
    XCTAssertEqual(InspectorValues.constraintSummary(fields), "UILabel.width ≤ 100")
    XCTAssertEqual(InspectorValues.layoutAttribute(.integer(12)), "firstBaseline")
  }
}
