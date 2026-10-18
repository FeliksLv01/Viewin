import ViewinProtocol

public struct EventHandlerPresentation: Sendable, Equatable, Identifiable {
  public struct Row: Sendable, Equatable {
    public let label: String
    public let value: String
  }
  public let id: Int
  public let title: String
  public let isGesture: Bool
  public let subtitles: [String]
  public let rows: [Row]
  public var symbol: String {
    isGesture ? "hand.tap" : (title.contains("Editing") ? "keyboard" : "cursorarrow.click")
  }

  init?(id: Int, value: JSONValue) {
    guard case .object(let fields) = value, case .string(let type) = fields["typeName"] else { return nil }
    func text(_ key: String) -> String? {
      guard case .string(let value) = fields[key] else { return nil }
      return value
    }
    self.id = id
    isGesture = text("handlerType") == "gesture" || text("origin") == "gestureRecognizer"
      || type.contains("GestureRecognizer")
    if let name = text("eventName") { title = name }
    else if !isGesture, case .integer(let event) = fields["event"] {
      let names: [Int64: String] = [1: "TouchDown", 2: "TouchDownRepeat", 4: "TouchDragInside",
        8: "TouchDragOutside", 16: "TouchDragEnter", 32: "TouchDragExit", 64: "TouchUpInside",
        128: "TouchUpOutside", 256: "TouchCancel", 4096: "ValueChanged", 8192: "PrimaryActionTriggered",
        16384: "MenuActionTriggered", 65536: "EditingDidBegin", 131072: "EditingChanged",
        262144: "EditingDidEnd", 524288: "EditingDidEndOnExit"]
      title = names[event].map { "UIControlEvent\($0)" } ?? "UIControlEvent(\(event))"
    } else { title = type }
    var subtitles: [String] = []
    if let inherited = text("inheritedRecognizerName") { subtitles.append("Inherits from \(inherited)") }
    if case .array(let references) = fields["memberReferences"] {
      for case .object(let reference) in references {
        if case .string(let owner) = reference["ownerType"], case .string(let name) = reference["name"] {
          subtitles.append("(\(owner) *) → \(name)")
        }
      }
    }
    self.subtitles = subtitles
    var rows: [Row] = []
    if isGesture {
      let enabled: String
      if case .bool(let value) = fields["enabled"] { enabled = value ? "YES" : "NO" }
      else { enabled = "未采集" }
      rows.append(.init(label: "Enabled", value: enabled))
      rows.append(.init(label: "Delegate", value: fields["delegate"] == .null ? "nil" : text("delegate") ?? "未采集"))
    }
    if text("targetActionsAvailability") == "unavailable" {
      rows.append(.init(label: "Target / Action", value: text("targetActionsReason") ?? "不可用"))
    } else if case .array(let pairs) = fields["targetActions"] {
      if pairs.isEmpty {
        rows.append(.init(label: "Target", value: "nil"))
        rows.append(.init(label: "Action", value: "NULL"))
      }
      for (index, pair) in pairs.enumerated() {
        guard case .object(let values) = pair else { continue }
        let suffix = pairs.count > 1 ? " \(index + 1)" : ""
        rows.append(.init(label: "Target\(suffix)", value: values["target"].flatMap { $0 == .null ? nil : $0.displayText } ?? "nil"))
        rows.append(.init(label: "Action\(suffix)", value: values["action"].flatMap { $0 == .null ? nil : $0.displayText } ?? "NULL"))
      }
    } else if fields["target"] != nil || fields["action"] != nil {
      rows.append(.init(label: "Target", value: text("target") ?? "nil"))
      rows.append(.init(label: "Action", value: text("action") ?? "NULL"))
    } else {
      rows.append(.init(label: "Target / Action", value: "未采集"))
    }
    self.rows = rows
  }
}

extension SnapshotNode {
  public var eventHandlers: [EventHandlerPresentation] {
    guard case .array(let handlers) = availableProperty("eventHandlers") else { return [] }
    return handlers.enumerated().compactMap { EventHandlerPresentation(id: $0.offset, value: $0.element) }
  }
}
