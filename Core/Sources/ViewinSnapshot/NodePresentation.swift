import ViewinProtocol

/// Shared presentation/query semantics for GUI and future CLI consumers.
/// Only properties explicitly marked available may contribute a summary.
extension SnapshotNode {
  /// Compact runtime host labels in the tree; typeName keeps the complete type for inspection.
  public var sidebarTitle: String {
    if typeName.contains("_UIHostingView") { return "_UIHostingView" }
    return name
  }
  public func availableProperty(_ id: String) -> JSONValue? {
    properties.lazy.flatMap(\.properties)
      .first { $0.id == id && $0.availability == "available" }?.value
  }

  public var textPreview: String? {
    guard case .string(let text) = availableProperty("text"), !text.isEmpty else { return nil }
    return text
  }

  public var memberReferenceNames: [String] {
    guard case .array(let references) = availableProperty("memberReferences") else { return [] }
    return references.compactMap { value in
      guard case .object(let fields) = value,
        case .string(let name) = fields["name"]
      else { return nil }
      if case .string(let owner) = fields["ownerType"] { return "\(owner).\(name)" }
      return name
    }
  }

  public var listPositionSummary: String? {
    guard case .object(let fields) = availableProperty("listPosition") else { return nil }
    if case .integer(let section) = fields["section"],
      case .integer(let item) = fields["item"]
    {
      return "[\(section), \(item)]"
    }
    if case .integer(let position) = fields["position"] { return "[\(position)]" }
    return nil
  }

  public var eventHandlerSummaries: [String] {
    eventHandlers.map { event in
      ([event.title] + event.subtitles + event.rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
    }
  }

  public var inspectionSearchText: [String] {
    [name, typeName] + Array(identifiers.values)
      + [textPreview, listPositionSummary].compactMap { $0 }
      + memberReferenceNames + eventHandlerSummaries
  }
}
