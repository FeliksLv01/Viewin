import AppKit
import SwiftUI
import ViewinSnapshot

/// System popover chrome owns the arrow, material, corners and dismissal.
@MainActor final class HierarchyEventsPopover {
  private let popover = NSPopover()

  init() {
    popover.behavior = .transient
    popover.animates = false
  }

  func show(events: [EventHandlerPresentation], from row: NSView) {
    close()
    guard let window = row.window, let screen = window.screen, !row.visibleRect.isEmpty else { return }
    let windowArea = window.contentView.map { window.convertToScreen($0.convert($0.bounds, to: nil)) }
      ?? window.frame
    let usable = screen.visibleFrame.intersection(windowArea)
    guard usable.width > 80, usable.height > 100 else { return }
    let width = min(366, usable.width - 48)
    let idealHeight = events.reduce(CGFloat(0)) { height, event in
      height + 44 + CGFloat(event.subtitles.count) * 18 + event.rows.reduce(CGFloat(0)) {
        $0 + max(20, CGFloat(ceil(Double($1.value.count) / 40)) * 17)
      }
    }
    // Budget the complete content, including heading and padding, against the
    // usable screen/window intersection. NSHostingController must not grow it.
    let height = min(420, usable.height - 48, max(120, idealHeight))
    let size = NSSize(width: width, height: height)
    popover.contentViewController = NSHostingController(rootView: EventContents(events: events, size: size))
    popover.contentSize = size
    let visible = row.visibleRect
    // Use a compact anchor at the visible row's right edge. The left gutter is
    // close to the screen edge, which leaves little room for native placement.
    let anchor = NSRect(x: visible.maxX - 1, y: visible.midY - 1, width: 1, height: 2)
    popover.show(relativeTo: anchor, of: row, preferredEdge: .maxX)
  }

  func close() { popover.close() }
}

private struct EventContents: View {
  let events: [EventHandlerPresentation]
  let size: CGSize

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(events) { event in
          if event.id != events.first?.id { Divider().padding(.leading, 28).padding(.trailing, 16) }
          InspectorEventGroup(event: event)
        }
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(width: size.width, height: size.height)
  }
}

struct InspectorEventGroup: View {
  let event: EventHandlerPresentation
  var compact = false

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: event.symbol)
        .font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 14, height: 16)
      VStack(alignment: .leading, spacing: 5) {
        Text(event.title)
          .font(.system(size: event.isGesture ? 12 : 13, weight: .semibold))
          .lineLimit(1).truncationMode(.middle).help(event.title).textSelection(.enabled)
        ForEach(Array(event.subtitles.enumerated()), id: \.offset) { _, subtitle in
          Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 5) {
          ForEach(Array(event.rows.enumerated()), id: \.offset) { _, row in
            GridRow(alignment: .top) {
              Text(row.label).foregroundStyle(.secondary)
                .frame(width: compact ? 54 : 78, alignment: .trailing)
              Text(row.value).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }.font(.system(size: 12))
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, compact ? 5 : 10).padding(.leading, compact ? 0 : 8).padding(.trailing, compact ? 0 : 16)
  }
}
