import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

extension InspectorPanel {
  func matches(_ group: PropertyGroup) -> Bool {
    search.isEmpty || group.title.localizedCaseInsensitiveContains(search)
      || group.properties.contains { matches($0) }
  }
  func matches(_ property: NodeProperty) -> Bool {
    search.isEmpty || property.title.localizedCaseInsensitiveContains(search)
      || property.value.containsInspectorText(search)
      || (property.presentation?.sectionTitle?.localizedCaseInsensitiveContains(search) ?? false)
      || (property.presentation?.kind.localizedCaseInsensitiveContains(search) ?? false)
  }
  func icon(_ group: PropertyGroup) -> String {
    if group.id == "r" || group.id == "references" { return "link" }
    if group.id == "a" { return "arrow.left.and.right.square" }
    if group.id == "interaction" { return "hand.tap" }
    return "square.stack"
  }

  func sections(_ properties: [NodeProperty], includeAll: Bool) -> [InspectorSection] {
    var result: [InspectorSection] = []
    for property in properties
    where (includeAll || matches(property))
      && (sectionVisible(property.presentation?.sectionId) || !search.isEmpty)
    {
      let id = property.presentation?.sectionId ?? property.id
      if result.last?.id == id {
        result[result.count - 1].properties.append(property)
      } else {
        result.append(
          InspectorSection(
            id: id, title: property.presentation?.sectionTitle,
            properties: [property]))
      }
    }
    return result
  }

  @ViewBuilder func properties(_ properties: [NodeProperty], includeAll: Bool = false)
    -> some View
  {
    ForEach(sections(properties, includeAll: includeAll)) { section in
      VStack(alignment: .leading, spacing: 6) {
        let singleInline =
          section.properties.count == 1
          && ((section.properties[0].value.numericValue != nil
            && section.properties[0].presentation?.kind != "enum")
            || section.properties[0].presentation?.kind == "boolean")
        if let title = section.title, !title.isEmpty, !singleInline {
          Text(title == "Frame" ? "Frame · 父坐标" : title == "Bounds" ? "Bounds · 本地坐标" : title)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        if ["shadow", "v_s"].contains(section.id), section.properties.count == 5,
          section.properties.allSatisfy({ $0.availability == "available" })
        {
          shadow(section.properties)
        } else if section.title == "Font", section.properties.count == 2,
          section.properties.allSatisfy({ $0.availability == "available" })
        {
          HStack(spacing: 5) {
            ForEach(section.properties) { property in
              valueField(
                property.value.inspectorText,
                title: property.title == "FontSize" ? "Size" : nil
              )
              .frame(maxWidth: property.title == "FontSize" ? 76 : .infinity)
            }
          }
        } else {
          ForEach(section.properties) { property in
            propertyRow(property, sectionTitle: section.title)
          }
        }
      }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder func propertyRow(_ property: NodeProperty, sectionTitle: String?)
    -> some View
  {
    if property.availability != "available" {
      Label(property.reason ?? "暂不可用", systemImage: "info.circle").font(.caption)
        .foregroundStyle(.secondary)
    } else if property.presentation?.kind == "boolean", case .bool(let enabled) = property.value {
      HStack(spacing: 6) {
        Image(systemName: enabled ? "checkmark.square.fill" : "square")
          .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
        Text(property.title).lineLimit(2)
      }.frame(minHeight: 20).accessibilityElement(children: .ignore)
        .accessibilityLabel(property.title).accessibilityValue(enabled ? "是，只读" : "否，只读")
    } else if property.presentation?.kind == "color" {
      if property.title != sectionTitle && property.title != "ShadowColor"
        && property.title != "BorderColor"
      {
        Text(property.title).font(.caption).foregroundStyle(.secondary)
      }
      color(property.value.fields)
    } else if property.presentation?.kind == "enum" {
      if property.title != sectionTitle {
        Text(property.title).font(.caption).foregroundStyle(.secondary)
      }
      valueField(
        InspectorValues.enumText(type: property.presentation?.enumType, value: property.value))
    } else if property.value.numericValue != nil {
      valueField(property.value.inspectorText, title: property.title)
    } else if property.presentation?.kind == "classChain" {
      ForEach(Array(property.value.elements.enumerated()), id: \.offset) { _, chain in
        Text(chain.elements.map(\.inspectorText).joined(separator: " → "))
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
    } else if let kind = property.presentation?.kind,
      ["rect", "point", "size", "insets", "offset", "vector", "transform"].contains(kind),
      !property.value.fields.isEmpty
    {
      if property.title != sectionTitle {
        Text(fieldTitle(property.title)).font(.caption).foregroundStyle(.secondary)
      }
      geometryGrid(property.value.fields, keys: componentKeys(kind))
    } else {
      if property.title != sectionTitle {
        Text(fieldTitle(property.title)).font(.caption).foregroundStyle(.secondary)
      }
      if case .string(let text) = property.value {
        valueField(text.isEmpty ? "空字符串" : text, multiline: true)
      } else {
        structured(property.value)
      }
    }
  }

  func valueField(_ value: String, title: String? = nil, multiline: Bool = false)
    -> some View
  {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(value).textSelection(.enabled).lineLimit(multiline ? nil : 1)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      if let title { Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
    }.padding(.horizontal, 8).padding(.vertical, 6)
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
      .help(title.map { "\($0): \(value)" } ?? value)
  }

  func shadow(_ properties: [NodeProperty]) -> some View {
    let values = Dictionary(uniqueKeysWithValues: properties.map { ($0.id, $0.value) })
    let components = [
      ("shadowOpacity", "vl_s_o", "Opacity"), ("shadowRadius", "vl_s_r", "Radius"),
      ("shadowOffsetX", "vl_s_ow", "OffsetW"), ("shadowOffsetY", "vl_s_oh", "OffsetH"),
    ]
    return VStack(spacing: 6) {
      color((values["shadowColor"] ?? values["vl_s_c"])?.fields ?? [:])
      HStack(spacing: 5) {
        ForEach(components, id: \.0) { id, legacyID, title in
          VStack(spacing: 4) {
            Text((values[id] ?? values[legacyID])?.inspectorText ?? "—").monospacedDigit()
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, minHeight: 27)
              .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
          }.frame(maxWidth: .infinity)
        }
      }
    }
  }

  func scalar(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label).foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
    }.font(.system(size: 12))
  }

  var sectionSettings: [String: Bool] {
    (try? JSONDecoder().decode([String: Bool].self, from: sectionOverrides)) ?? [:]
  }
  func sectionVisible(_ id: String?) -> Bool {
    guard let id else { return true }
    return sectionSettings[id] ?? !InspectorValues.defaultHiddenSections.contains(id)
  }
  func sectionMenu(_ properties: [NodeProperty]) -> AnyView? {
    var seen = Set<String>()
    let sections = properties.compactMap { property -> (String, String)? in
      guard let id = property.presentation?.sectionId, seen.insert(id).inserted else { return nil }
      return (id, property.presentation?.sectionTitle ?? property.title)
    }
    guard sections.count > 1 else { return nil }
    return AnyView(
      Menu {
        ForEach(sections, id: \.0) { id, title in
          Toggle(
            title,
            isOn: Binding(
              get: { sectionVisible(id) },
              set: { value in
                var settings = sectionSettings
                settings[id] = value
                sectionOverrides = (try? JSONEncoder().encode(settings)) ?? Data()
              }))
        }
        Divider()
        Button("显示全部属性") {
          var settings = sectionSettings
          for (id, _) in sections { settings[id] = true }
          sectionOverrides = (try? JSONEncoder().encode(settings)) ?? Data()
        }
        Button("恢复默认属性") {
          var settings = sectionSettings
          for (id, _) in sections { settings.removeValue(forKey: id) }
          sectionOverrides = (try? JSONEncoder().encode(settings)) ?? Data()
        }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("管理显示属性"))
  }

}
