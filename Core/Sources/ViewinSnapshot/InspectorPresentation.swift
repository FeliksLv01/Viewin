import Foundation
import ViewinProtocol

/// Human-facing projection only. Archives and CLI keep the original runtime data.
public enum InspectorPresentation {
  public static func groups(for node: SnapshotNode) -> [PropertyGroup] {
    let projected = node.properties.compactMap { group -> PropertyGroup? in
      guard !["rendering", "hierarchy", "swiftuiSupport"].contains(group.id) else { return nil }
      let fields = group.properties.compactMap { property -> NodeProperty? in
        let diagnosticIDs: Set<String>
        switch group.id {
        case "swiftui": diagnosticIDs = ["captureBackend", "swiftuiType", "geometryStatus"]
        case "compose": diagnosticIDs = ["backend"]
        case "swiftuiRendering": diagnosticIDs = ["displayListId", "identityScope", "bindingSource", "layerDisplayListId", "backingLayerAddress"]
        default: diagnosticIDs = group.id.hasPrefix("modifier:") ? ["modifierType"] : []
        }
        if diagnosticIDs.contains(property.id) { return nil }
        if group.id == "viewHolder", property.id == "listPosition" { return nil }
        if group.id == "compose", ["callChain", "isPlaced"].contains(property.id) { return nil }
        if group.id == "semantics" {
          let visible = ["Text", "EditableText", "ContentDescription", "Role", "Disabled", "Focused", "Selected", "StateDescription", "ToggleableState", "Heading", "IsTraversalGroup", "ProgressBarRangeInfo", "CollectionInfo", "CollectionItemInfo", "HorizontalScrollAxisRange", "VerticalScrollAxisRange"]
          if !visible.contains(property.id) { return nil }
          if ["CollectionInfo", "CollectionItemInfo", "ProgressBarRangeInfo", "HorizontalScrollAxisRange", "VerticalScrollAxisRange"].contains(property.id), case .string = property.value { return nil }
          if ["TestTag", "IndexForKey", "GetTextLayoutResult", "GetScrollViewportLength", "SetTextSubstitution",
              "ClearTextSubstitution", "ShowTextSubstitution", "ScrollByOffset"].contains(property.id)
            || property.value.fields["hasAction"] != nil { return nil }
        }
        if node.framework == "swiftui", property.id.hasPrefix("value.") || group.id.hasPrefix("modifier:") {
          guard let title = swiftUITitles[property.title] else { return nil }
          return copy(property, title: title, value: property.value)
        }
        if group.id == "parameters", ["modifier", "content", "onTextLayout"].contains(property.id) { return nil }
        if group.id == "modifiers", case .array(let values) = property.value {
          let modifiers = values.compactMap { value -> JSONValue? in
            let fields = value.fields
            guard case .string(let name) = fields["name"], !name.hasPrefix("Root"), name != "rootModifier" else { return nil }
            let properties = fields["properties"]?.fields.filter { key, value in
              !["onClick", "onLongClick", "interactionSource", "indicationNodeFactory"].contains(key)
                && value != .null && !isTypeSummary(value)
            } ?? [:]
            let primary = fields["value"].flatMap { $0 != .null && !isTypeSummary($0) ? $0 : nil }
            guard !properties.isEmpty || primary != nil else { return nil }
            var output: [String: JSONValue] = ["name": .string(name), "properties": .object(properties)]
            if let primary { output["value"] = primary }
            return .object(output)
          }
          guard !modifiers.isEmpty else { return nil }
          return copy(property, value: .array(modifiers))
        }
        if ["parameters", "semantics"].contains(group.id), !["text", "Text", "EditableText", "ContentDescription", "hint"].contains(property.id), isTypeSummary(property.value) { return nil }
        var value = property.value
        if group.id == "parameters", case .object(let fields) = value {
          value = .object(fields.filter { $0.value != .null && !isTypeSummary($0.value) })
          if value.fields.isEmpty { return nil }
        }
        if group.id == "parameters", value == .null { return nil }
        if ["maxLines", "numberOfLines"].contains(property.id), value == .integer(2_147_483_647) { value = .string(L10n.text("不限")) }
        return copy(property, value: value)
      }
      guard !fields.isEmpty else { return nil }
      let title = group.id == "semantics" ? L10n.text("语义与状态") : group.id == "parameters" ? L10n.text("组件属性")
        : group.id == "modifiers" ? "Modifiers" : group.id == "layoutParams" ? "Layout Parameters" : group.title
      return .init(id: group.id, title: title, properties: fields)
    }
    var output: [PropertyGroup] = []
    for group in projected {
      if group.id.hasPrefix("modifier:"), output.contains(where: {
        $0.id.hasPrefix("modifier:") && $0.title == group.title
          && $0.properties.map(\.title) == group.properties.map(\.title)
          && $0.properties.map(\.value) == group.properties.map(\.value)
      }) { continue }
      output.append(group)
    }
    return output
  }

  private static func copy(_ p: NodeProperty, title: String? = nil, value: JSONValue) -> NodeProperty {
    .init(id: p.id, title: title ?? p.title, value: value, availability: p.availability,
          reason: p.reason, presentation: p.presentation)
  }
  private static func isTypeSummary(_ value: JSONValue) -> Bool {
    guard case .string(let text) = value else { return false }
    return text.hasPrefix("androidx.") || text.contains("$$ExternalSyntheticLambda")
  }
  private static let swiftUITitles: [String: String] = [
    "storage.anyTextStorage.key.key": "Text", "storage.verbatim": "Text",
    "provider.base.name": "Image", "provider.base.location": "Location", "provider.base.decorative": "Decorative",
    "_tree.root.alignment": "Alignment", "_tree.root.spacing": "Spacing", "spacing": "Spacing", "maxWidth": "Max Width", "minWidth": "Min Width",
    "maxHeight": "Max Height", "minHeight": "Min Height", "width": "Width", "height": "Height",
    "alignment.horizontal": "Horizontal Alignment", "alignment.vertical": "Vertical Alignment",
    "style.provider.base.opacity": "Opacity", "shape.style": "Corner Style", "eoFill": "Even-Odd Fill",
  ]
}
