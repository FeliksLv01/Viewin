import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

extension InspectorPanel {
  func componentKeys(_ kind: String) -> [String] {
    switch kind {
    case "rect": return ["x", "y", "width", "height"]
    case "point": return ["x", "y"]
    case "size": return ["width", "height"]
    case "insets": return ["top", "left", "bottom", "right"]
    case "vector": return ["dx", "dy"]
    case "offset": return ["horizontal", "vertical"]
    default: return ["a", "b", "c", "d", "tx", "ty"]
    }
  }
  func geometryGrid(_ fields: [String: JSONValue], keys: [String]) -> some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
      ForEach(keys, id: \.self) { key in
        HStack {
          Text(["width": "W", "height": "H", "x": "X", "y": "Y"][key] ?? L10n.text(key)).foregroundStyle(
            .secondary)
          Spacer(minLength: 4)
          Text(fields[key]?.inspectorText ?? "—").monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 11)).padding(6).background(
          .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
      }
    }
  }
  func color(_ fields: [String: JSONValue]) -> some View {
    let hasColor = !fields.isEmpty
    let r = fields["red"]?.numericValue ?? 0
    let g = fields["green"]?.numericValue ?? 0
    let b = fields["blue"]?.numericValue ?? 0
    let a = fields["alpha"]?.numericValue ?? 1
    let description =
      hasColor
      ? (colorFormat == "hex" ? InspectorValues.hexColor(fields) : InspectorValues.rgbaText(fields))
      : "nil"
    return Menu {
      Picker(L10n.text("显示格式"), selection: Binding(get: { colorFormat }, set: { colorFormat = $0 })) {
        Text("RGBA").tag("rgba")
        Text("HEX").tag("hex")
      }.pickerStyle(.inline)
      Divider()
      Button(L10n.text("复制 RGBA")) { copy(hasColor ? InspectorValues.rgbaText(fields) : "nil") }
      Button(L10n.text("复制 HEX")) { copy(hasColor ? InspectorValues.hexColor(fields) : "nil") }
    } label: {
      Text("")
    }.menuStyle(.borderlessButton).menuIndicator(.hidden)
      .frame(maxWidth: .infinity, minHeight: 30)
      // AppKit's borderless menu flattens custom labels. Keep its hit target and
      // accessibility, and draw the swatch/value above it without intercepting input.
      .opacity(0.02)
      .overlay {
        HStack(spacing: 7) {
          InspectorColorSwatch(color: hasColor ? Color(red: r, green: g, blue: b, opacity: a) : nil)
            .frame(width: 16, height: 16)
          Text(description).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
          Spacer(minLength: 2)
          Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 30)
          .contentShape(Rectangle())
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
          .allowsHitTesting(false).accessibilityHidden(true)
      }
      .accessibilityLabel(L10n.format("颜色 %@，切换显示格式", String(describing: description)))
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  /// Recursion is erased at the boundary, so arbitrary nested data stays readable as rows.
  func structured(_ value: JSONValue, depth: Int = 0) -> AnyView {
    guard depth < 32 else { return AnyView(Text(L10n.text("嵌套内容过深")).foregroundStyle(.secondary)) }
    switch value {
    case .array(let items):
      if items.allSatisfy({ $0.fields.isEmpty && $0.elements.isEmpty }) {
        return AnyView(Text(items.map(\.inspectorText).joined(separator: ", "))
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true))
      }
      if !items.isEmpty && items.allSatisfy({ $0.fields["type"] == .string("constraint") }) {
        let sorted = InspectorValues.sortedConstraints(items)
        return AnyView(
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in constraint(item.fields) }
          })
      }
      return AnyView(
        VStack(alignment: .leading, spacing: 7) {
          if items.isEmpty { Text(L10n.text("无")).foregroundStyle(.secondary) }
          ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            VStack(alignment: .leading, spacing: 4) {
              if items.count > 1 && item.fields["name"] == nil { Text("\(index + 1)").font(.caption2).foregroundStyle(.tertiary) }
              structured(item, depth: depth + 1)
            }
            if index < items.count - 1 { Divider() }
          }
        })
    case .object(let fields):
      if Set(["red", "green", "blue"]).isSubset(of: Set(fields.keys)) {
        return AnyView(color(fields))
      }
      for (keys, kind) in [(["x", "y", "width", "height"], "rect"), (["top", "left", "bottom", "right"], "insets"), (["x", "y"], "point"), (["width", "height"], "size")] {
        if Set(keys) == Set(fields.keys) {
          return AnyView(geometryGrid(fields, keys: componentKeys(kind)))
        }
      }
      if case .string(let name) = fields["name"], case .object(let values) = fields["properties"] {
        return AnyView(VStack(alignment: .leading, spacing: 5) {
          Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
          if let value = fields["value"] { structured(value, depth: depth + 1) }
          ForEach(values.keys.sorted(), id: \.self) { key in
            if values[key] != fields["value"] {
              propertyRow(.init(id: key, title: fieldTitle(key), value: values[key]!, availability: "available", reason: nil), sectionTitle: nil, depth: depth + 1)
            }
          }
        })
      }
      if case .string(let owner) = fields["ownerType"], case .string(let name) = fields["name"], fields["kind"] == .string("ivar") {
        return AnyView(Text("(\(owner) *) → \(name)").font(.system(size: 11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true))
      }
      if fields["type"] == .string("objectReference") { return AnyView(reference(fields)) }
      if fields["type"] == .string("constraint") { return AnyView(constraint(fields)) }
      if fields["type"] == .string("image") {
        if case .string(let base64) = fields["base64"], let data = Data(base64Encoded: base64),
          let image = NSImage(data: data)
        {
          return AnyView(Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 150))
        }
        return AnyView(Text(L10n.text("图片不可用")).foregroundStyle(.secondary))
      }
      return AnyView(
        VStack(alignment: .leading, spacing: 6) {
          if fields.isEmpty { Text(L10n.text("无")).foregroundStyle(.secondary) }
          ForEach(fields.keys.sorted(), id: \.self) { key in
            propertyRow(.init(id: key, title: fieldTitle(key), value: fields[key]!, availability: "available", reason: nil), sectionTitle: nil, depth: depth + 1)
          }
        })
    default:
      return AnyView(
        Text(value.inspectorText).textSelection(.enabled).fixedSize(
          horizontal: false, vertical: true))
    }
  }
  func reference(_ fields: [String: JSONValue]) -> some View {
    let id = fields["objectId"]?.inspectorText ?? ""
    let address = fields["address"]?.inspectorText ?? ""
    let target = document.snapshot.nodes.first {
      $0.id == id || $0.identifiers["viewObjectId"] == id || $0.identifiers["layerObjectId"] == id
    }
    return VStack(alignment: .leading, spacing: 4) {
      if id == "0" {
        Text(L10n.text("None")).foregroundStyle(.secondary)
      } else if let target {
        Button {
          workspace.select(target)
        } label: {
          Label(
            fields["className"]?.inspectorText ?? target.typeName, systemImage: "arrow.up.right")
        }.buttonStyle(.link)
      } else {
        Text(fields["className"]?.inspectorText ?? L10n.text("对象"))
      }
      if id != "0" {
        Text(address).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(
          .enabled)
      }
    }
  }
  func constraint(_ fields: [String: JSONValue]) -> some View {
    InspectorConstraintRow(fields: fields) {
      VStack(alignment: .leading, spacing: 10) {
        Text(InspectorValues.constraintSummary(fields)).font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
        if fields["effective"] == .bool(false) {
          Text(L10n.text("This constraint does not affect the selected view's layout.")).font(.caption)
            .foregroundStyle(.secondary)
        }
        Divider()
        Text(L10n.text("First Item")).font(.caption.weight(.semibold))
        if let first = fields["firstItem"], first != .null { reference(first.fields) }
        scalar("First Attribute", InspectorValues.layoutAttribute(fields["firstAttribute"]))
        Text(L10n.text("Second Item")).font(.caption.weight(.semibold))
        if let second = fields["secondItem"], second != .null {
          reference(second.fields)
        } else {
          Text(L10n.text("None")).foregroundStyle(.secondary)
        }
        scalar("Second Attribute", InspectorValues.layoutAttribute(fields["secondAttribute"]))
        ForEach(
          [
            "multiplier", "constant", "priority", "active", "effective", "shouldBeArchived",
            "identifier",
          ], id: \.self
        ) { key in
          scalar(key, fields[key]?.inspectorText ?? "—")
        }
      }
    }
  }
  func fieldTitle(_ key: String) -> String {
    [
      "memberReferences": L10n.text("成员引用"), "eventHandlers": L10n.text("事件与手势"), "listPosition": L10n.text("列表位置"), "trace": L10n.text("来源"),
      "fontSize": "Size", "fontWeight": "Weight", "letterSpacing": "Letter Spacing", "lineHeight": "Line Height", "color": "Color", "style": "Text Style", "text": "Text",
      "ownerType": L10n.text("所属类型"), "name": L10n.text("成员名"), "kind": L10n.text("种类"), "section": "Section", "item": "Item / Row",
      "enabled": L10n.text("启用"), "delegate": "Delegate", "targetActions": "Target / Action",
      "target": "Target", "action": "Action", "event": L10n.text("事件"), "typeName": L10n.text("类型"),
    ][key] ?? L10n.text(key)
  }
}
