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
          Text(["width": "W", "height": "H", "x": "X", "y": "Y"][key] ?? key).foregroundStyle(
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
      Picker("显示格式", selection: Binding(get: { colorFormat }, set: { colorFormat = $0 })) {
        Text("RGBA").tag("rgba")
        Text("HEX").tag("hex")
      }.pickerStyle(.inline)
      Divider()
      Button("复制 RGBA") { copy(hasColor ? InspectorValues.rgbaText(fields) : "nil") }
      Button("复制 HEX") { copy(hasColor ? InspectorValues.hexColor(fields) : "nil") }
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
      .accessibilityLabel("颜色 \(description)，切换显示格式")
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  /// Recursion is erased at the boundary, so arbitrary nested data stays readable as rows.
  func structured(_ value: JSONValue, depth: Int = 0) -> AnyView {
    guard depth < 32 else { return AnyView(Text("嵌套内容过深").foregroundStyle(.secondary)) }
    switch value {
    case .array(let items):
      if !items.isEmpty && items.allSatisfy({ $0.fields["type"] == .string("constraint") }) {
        let sorted = InspectorValues.sortedConstraints(items)
        return AnyView(
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { _, item in constraint(item.fields) }
          })
      }
      return AnyView(
        VStack(alignment: .leading, spacing: 7) {
          if items.isEmpty { Text("无").foregroundStyle(.secondary) }
          ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            VStack(alignment: .leading, spacing: 4) {
              if items.count > 1 { Text("\(index + 1)").font(.caption2).foregroundStyle(.tertiary) }
              structured(item, depth: depth + 1)
            }
            if index < items.count - 1 { Divider() }
          }
        })
    case .object(let fields):
      if fields["type"] == .string("objectReference") { return AnyView(reference(fields)) }
      if fields["type"] == .string("constraint") { return AnyView(constraint(fields)) }
      if fields["type"] == .string("image") {
        if case .string(let base64) = fields["base64"], let data = Data(base64Encoded: base64),
          let image = NSImage(data: data)
        {
          return AnyView(Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 150))
        }
        return AnyView(Text("图片不可用").foregroundStyle(.secondary))
      }
      return AnyView(
        VStack(alignment: .leading, spacing: 6) {
          if fields.isEmpty { Text("无").foregroundStyle(.secondary) }
          ForEach(fields.keys.sorted(), id: \.self) { key in
            VStack(alignment: .leading, spacing: 3) {
              Text(fieldTitle(key)).font(.caption).foregroundStyle(.secondary)
              structured(fields[key]!, depth: depth + 1).padding(.leading, 8)
            }
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
        Text("None").foregroundStyle(.secondary)
      } else if let target {
        Button {
          workspace.select(target)
        } label: {
          Label(
            fields["className"]?.inspectorText ?? target.typeName, systemImage: "arrow.up.right")
        }.buttonStyle(.link)
      } else {
        Text(fields["className"]?.inspectorText ?? "对象")
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
          Text("This constraint does not affect the selected view's layout.").font(.caption)
            .foregroundStyle(.secondary)
        }
        Divider()
        Text("First Item").font(.caption.weight(.semibold))
        if let first = fields["firstItem"], first != .null { reference(first.fields) }
        scalar("First Attribute", InspectorValues.layoutAttribute(fields["firstAttribute"]))
        Text("Second Item").font(.caption.weight(.semibold))
        if let second = fields["secondItem"], second != .null {
          reference(second.fields)
        } else {
          Text("None").foregroundStyle(.secondary)
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
      "memberReferences": "成员引用", "eventHandlers": "事件与手势", "listPosition": "列表位置", "trace": "来源",
      "ownerType": "所属类型", "name": "成员名", "kind": "种类", "section": "Section", "item": "Item / Row",
      "enabled": "启用", "delegate": "Delegate", "targetActions": "Target / Action",
      "target": "Target", "action": "Action", "event": "事件", "typeName": "类型",
    ][key] ?? key
  }
}
