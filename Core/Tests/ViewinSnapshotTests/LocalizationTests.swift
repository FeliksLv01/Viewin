import Foundation
import XCTest
import ViewinProtocol
@testable import ViewinSnapshot

final class LocalizationTests: XCTestCase {
  func testBothLanguagesResolveBundledStrings() {
    XCTAssertEqual(L10n.text("设置", locale: Locale(identifier: "en")), "Settings")
    XCTAssertEqual(L10n.text("设置", locale: Locale(identifier: "zh-Hans")), "设置")
    XCTAssertEqual(L10n.text("设置", locale: Locale(identifier: "zh-CN")), "设置")
    XCTAssertEqual(L10n.text("设置", locale: Locale(identifier: "fr")), "Settings")
  }

  func testCompiledCatalogHasCompleteLanguagesAndMatchingPlaceholders() throws {
    func strings(_ language: String) throws -> [String: String] {
      let directory = try XCTUnwrap(Bundle.module.url(forResource: language, withExtension: "lproj"))
      let file = directory.appendingPathComponent("Localizable.strings")
      return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: String])
    }
    let english = try strings("en"), chinese = try strings("zh-Hans")
    XCTAssertEqual(Set(english.keys), Set(chinese.keys))
    XCTAssertFalse(english.isEmpty)
    for (key, value) in english {
      XCTAssertFalse(value.isEmpty, key)
      XCTAssertEqual(value.components(separatedBy: "%@").count, chinese[key]?.components(separatedBy: "%@").count, key)
    }
  }

  func testLocalizedFormattingPreservesRuntimeTextAndArgumentOrder() {
    let app = "My App 设置 %s"
    XCTAssertEqual(L10n.format("检查 %@，%@，%@", app, "iPhone", "iOS 27", locale: Locale(identifier: "en")),
                   "Inspect My App 设置 %s, iPhone, iOS 27")
    XCTAssertEqual(L10n.format("窗口坐标 · %@", "pt", locale: Locale(identifier: "zh-Hans")), "窗口坐标 · pt")
    XCTAssertEqual(JSONValue.string("设置").inspectorText, "设置")
    XCTAssertEqual(L10n.text("MyCustomView"), "MyCustomView")
  }
}
