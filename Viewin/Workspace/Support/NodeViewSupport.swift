import Foundation
import ViewinProtocol
import ViewinSnapshot

extension SnapshotNode {
  var sidebarDetail: String? {
    if listPositionSummary != nil { return nil }
    if case .string(let trace) = availableProperty("trace"), !trace.isEmpty { return trace }
    guard case .array(let references) = availableProperty("memberReferences") else { return nil }
    var seen = Set<String>()
    let names = references.compactMap { value -> String? in
      guard case .object(let fields) = value, case .string(let name) = fields["name"],
        !name.isEmpty, seen.insert(name).inserted
      else { return nil }
      return name
    }
    return names.isEmpty ? nil : names.joined(separator: ", ")
  }
  var iconAsset: String {
    if kind == "component" && (name.hasSuffix("Screen") || name.hasSuffix("Page")) {
      return "VIScreen"
    }
    let known = [
      "window", "view", "component", "stack", "layout", "layer", "text", "image", "button",
      "scroll",
    ]
    return "VI" + (known.contains(kind) ? kind.capitalized : "View")
  }

  var frameworkTitle: String {
    switch framework {
    case "uikit": "UIKit"
    case "swiftui": "SwiftUI"
    case "androidView": "Android View"
    case "compose": "Compose"
    default: framework
    }
  }

  func property(_ id: String) -> JSONValue? {
    properties.lazy.flatMap(\.properties).first { $0.id == id }?.value
  }
}

func dimension(_ value: Double) -> String {
  value.formatted(.number.precision(.fractionLength(0...1)))
}
