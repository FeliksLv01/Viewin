import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

struct InspectorCard<Content: View>: View {
  let title: String
  let icon: String
  let query: String
  var content: Content
  let menu: AnyView?
  let store: InspectorCardFeature?

  init(
    inspectorStore: InspectorFeature,
    title: String, icon: String, query: String, id: String? = nil, menu: AnyView? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.icon = icon
    self.query = query
    self.content = content()
    self.menu = menu
    let id = id ?? title
    store = inspectorStore.cards[id]
  }

  var body: some View {
    if let store {
      let expanded = query.isEmpty ? store.expanded : store.searchExpanded
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
          Button {
            store.send(query.isEmpty ? .expandedChanged(!expanded) : .searchExpandedChanged(!expanded))
          } label: {
            HStack(spacing: 6) {
              Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold)).frame(width: 10)
              Image(systemName: icon).frame(width: 14).foregroundStyle(.secondary)
              Text(L10n.text(title)).font(.system(size: 12, weight: .semibold))
              Spacer(minLength: 2)
            }.contentShape(Rectangle()).frame(minHeight: 24)
          }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(expanded ? L10n.text("已展开") : L10n.text("已收起"))
          if let menu { menu }
        }
        if expanded {
          VStack(alignment: .leading, spacing: 7) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
        }
      }.padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.35)))
        .onChange(of: query) { _, value in if !value.isEmpty { store.send(.queryChanged) } }
    }
  }
}

struct InspectorConstraintRow<Details: View>: View {
  let fields: [String: JSONValue]
  @ViewBuilder var details: Details
  @State private var showing = false
  var body: some View {
    Button {
      showing = true
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(InspectorValues.constraintSummary(fields)).font(.system(size: 11, design: .monospaced))
          .lineLimit(2).multilineTextAlignment(.leading)
        HStack {
          Text("@ \(fields["priority"]?.inspectorText ?? "—")")
          if fields["active"] == .bool(false) { Text(L10n.text("Inactive")) }
          Spacer(minLength: 0)
          Image(systemName: "info.circle")
        }.font(.caption2).foregroundStyle(.secondary)
      }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
    }.buttonStyle(.plain)
      .foregroundStyle(fields["effective"] == .bool(false) ? .secondary : .primary)
      .popover(isPresented: $showing, arrowEdge: .leading) {
        ScrollView { details.padding(14) }.frame(width: 320, height: 430)
      }
  }
}

struct InspectorSection: Identifiable {
  let id: String
  let title: String?
  var properties: [NodeProperty]
}

/// A checkerboard keeps transparent and nil colors visible on either appearance.
struct InspectorColorSwatch: View {
  let color: Color?
  var body: some View {
    Canvas { context, size in
      let cell: CGFloat = 4
      for row in 0..<4 {
        for column in 0..<4 {
          context.fill(
            Path(
              CGRect(
                x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                width: cell, height: cell)),
            with: .color((row + column).isMultiple(of: 2) ? .white : .gray.opacity(0.5)))
        }
      }
      if let color {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
      } else {
        var slash = Path()
        slash.move(to: CGPoint(x: 2, y: size.height - 2))
        slash.addLine(to: CGPoint(x: size.width - 2, y: 2))
        context.stroke(slash, with: .color(.red), lineWidth: 1)
      }
    }.clipShape(Circle()).overlay(Circle().stroke(.primary.opacity(0.15), lineWidth: 0.5))
      .accessibilityHidden(true)
  }
}
