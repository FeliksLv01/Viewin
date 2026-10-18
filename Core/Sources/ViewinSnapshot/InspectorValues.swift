import Foundation
import ViewinProtocol

extension JSONValue {
  public var fields: [String: JSONValue] {
    if case .object(let fields) = self { return fields }
    return [:]
  }
  public var elements: [JSONValue] {
    if case .array(let values) = self { return values }
    return []
  }
  public var numericValue: Double? {
    switch self {
    case .number(let n): return n
    case .integer(let n): return Double(n)
    default: return nil
    }
  }
  /// Scalars only. Collections are rendered as rows, never serialized as JSON.
  public var inspectorText: String {
    switch self {
    case .null: return "未设置"
    case .bool(let flag): return flag ? "是" : "否"
    case .number(let number):
      return number.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
    case .integer(let number): return String(number)
    case .string(let text): return text.isEmpty ? "空字符串" : text
    case .array(let values): return "\(values.count) 项"
    case .object(let fields): return "\(fields.count) 个属性"
    }
  }

  public func containsInspectorText(_ query: String) -> Bool {
    switch self {
    case .array(let values): return values.contains { $0.containsInspectorText(query) }
    case .object(let fields):
      return fields.contains {
        $0.key.localizedCaseInsensitiveContains(query) || $0.value.containsInspectorText(query)
      }
    default: return inspectorText.localizedCaseInsensitiveContains(query)
    }
  }
}

public enum InspectorValues {
  /// Known UIKit sections hidden by default in the reference inspector. Unknown/custom sections stay visible.
  public static let defaultHiddenSections: Set<String> = [
    "b_i", "b_t", "c_h", "c_v", "l_a", "l_p", "l_s", "lb_c", "n", "s_bo", "s_ct", "s_ii", "s_s",
    "s_si", "s_z", "t_sc", "t_si", "t_ss", "tf_c", "tf_ca", "tf_cb", "tf_p", "tv_b",
    "v_co", "v_t", "v_ta",
  ]

  public static func sortedConstraints(_ values: [JSONValue]) -> [JSONValue] {
    values.enumerated().sorted { lhs, rhs in
      let a = lhs.element.fields
      let b = rhs.element.fields
      let ae = a["effective"] == .bool(true)
      let be = b["effective"] == .bool(true)
      if ae != be { return ae }
      let at = a["firstItemType"]?.numericValue ?? 0
      let bt = b["firstItemType"]?.numericValue ?? 0
      if at != bt { return at < bt }
      let aa = a["firstAttribute"]?.numericValue ?? 0
      let ba = b["firstAttribute"]?.numericValue ?? 0
      if aa != ba { return aa < ba }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  public static func rgbaText(_ fields: [String: JSONValue]) -> String {
    let channels = ["red", "green", "blue"].map { key in
      ((fields[key]?.numericValue ?? 0) * 255).formatted(
        .number.precision(.fractionLength(0...1)).grouping(.never))
    }
    let alpha = (fields["alpha"] ?? .number(1)).inspectorText
    return "rgba(\(channels.joined(separator: ", ")), \(alpha))"
  }

  /// HEX is sRGB RGBA, with 8-bit quantization. Keep the original components in the snapshot.
  public static func hexColor(_ fields: [String: JSONValue]) -> String {
    "#"
      + ["red", "green", "blue", "alpha"].map { key in
        let value = fields[key]?.numericValue ?? (key == "alpha" ? 1 : 0)
        let byte = Int((min(1, max(0, value.isFinite ? value : 0)) * 255).rounded())
        return String(format: "%02X", byte)
      }.joined()
  }

  public static func enumText(type: String?, value: JSONValue) -> String {
    guard let type, let number = value.numericValue, number >= 0, number < Double(Int.max),
      number.rounded() == number
    else { return value.inspectorText }
    let names: [String: [String]] = [
      "NSTextAlignment": ["Left", "Center", "Right", "Justified", "Natural"],
      "NSLineBreakMode": [
        "Word Wrapping", "Character Wrapping", "Clipping", "Truncate Head", "Truncate Tail",
        "Truncate Middle",
      ],
      "UIViewContentMode": [
        "Scale to Fill", "Aspect Fit", "Aspect Fill", "Redraw", "Center", "Top", "Bottom", "Left",
        "Right", "Top Left", "Top Right", "Bottom Left", "Bottom Right",
      ],
      "UILayoutConstraintAxis": ["Horizontal", "Vertical"],
      "UIStackViewDistribution": [
        "Fill", "Fill Equally", "Fill Proportionally", "Equal Spacing", "Equal Centering",
      ],
      "UIViewTintAdjustmentMode": ["Automatic", "Normal", "Dimmed"],
      "UIControlContentHorizontalAlignment": [
        "Center", "Left", "Right", "Fill", "Leading", "Trailing",
      ],
      "UIControlContentVerticalAlignment": ["Center", "Top", "Bottom", "Fill"],
      "UIScrollViewContentInsetAdjustmentBehavior": [
        "Automatic", "Scrollable Axes", "Never", "Always",
      ],
      "UITableViewStyle": ["Plain", "Grouped", "Inset Grouped"],
      "UITableViewCellSeparatorStyle": ["None", "Single Line", "Single Line Etched"],
    ]
    if type == "UIStackViewAlignment" {
      let alignment = [
        0: "Fill", 1: "Leading / Top", 2: "First Baseline", 3: "Center", 4: "Trailing / Bottom",
        5: "Last Baseline",
      ]
      if let name = alignment[Int(number)] { return "\(name) (\(Int(number)))" }
    }
    guard let list = names[type], list.indices.contains(Int(number)) else {
      return "\(type) (\(value.inspectorText))"
    }
    return "\(list[Int(number)]) (\(Int(number)))"
  }

  public static func layoutAttribute(_ value: JSONValue?) -> String {
    let names = [
      "notAnAttribute", "left", "right", "top", "bottom", "leading", "trailing", "width", "height",
      "centerX",
      "centerY", "lastBaseline", "firstBaseline", "leftMargin", "rightMargin", "topMargin",
      "bottomMargin", "leadingMargin", "trailingMargin", "centerXWithinMargins",
      "centerYWithinMargins",
    ]
    let privateNames: [Double: String] = [
      32: "minX", 33: "minY", 34: "midX", 35: "midY", 36: "maxX", 37: "maxY",
    ]
    if let n = value?.numericValue, let name = privateNames[n] {
      return name
    }
    guard let n = value?.numericValue, n >= 0, n < Double(names.count), n.rounded() == n else {
      return "attribute(\(value?.inspectorText ?? "?"))"
    }
    return names[Int(n)]
  }

  public static func constraintSummary(_ fields: [String: JSONValue]) -> String {
    func item(_ key: String) -> String {
      let object = fields[key]?.fields ?? [:]
      if object.isEmpty { return "" }
      let name = object["className"]?.inspectorText ?? "对象"
      if name.contains("_UIHostingView") { return "_UIHostingView" }
      return name
    }
    let first = "\(item("firstItem")).\(layoutAttribute(fields["firstAttribute"]))"
    let relation = fields["relation"]?.numericValue ?? 0
    let symbol = relation < 0 ? "≤" : relation > 0 ? "≥" : "="
    let constant = fields["constant"]?.inspectorText ?? "0"
    if fields["secondItem"]?.fields.isEmpty != false
      || fields["secondItem"]?.fields["objectId"] == .string("0")
      || fields["secondItemType"]?.numericValue == 1
    {
      return "\(first) \(symbol) \(constant)"
    }
    let second = "\(item("secondItem")).\(layoutAttribute(fields["secondAttribute"]))"
    let multiplier = fields["multiplier"]?.inspectorText ?? "1"
    return "\(first) \(symbol) \(second) × \(multiplier) + \(constant)"
  }
}
