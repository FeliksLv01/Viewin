import AppKit
import SwiftUI

/// System popover chrome owns the arrow, material, corners and dismissal.
@MainActor final class HierarchyEventsPopover {
  private let popover = NSPopover()

  init() {
    popover.behavior = .transient
    popover.animates = false
  }

  func show(events: [String], from row: NSView) {
    close()
    guard let window = row.window, let screen = window.screen, !row.visibleRect.isEmpty else { return }
    let windowArea = window.contentView.map { window.convertToScreen($0.convert($0.bounds, to: nil)) }
      ?? window.frame
    let usable = screen.visibleFrame.intersection(windowArea)
    guard usable.width > 80, usable.height > 100 else { return }
    let width = min(366, usable.width - 48)
    let charactersPerLine = max(1, Int((width - 36) / 7.2))
    let lines = events.reduce(0) { total, event in
      total + event.components(separatedBy: "\n").reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(charactersPerLine)))) }
    }
    let idealHeight = CGFloat(lines) * 18 + CGFloat(max(0, events.count - 1)) * 12 + 66
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
  let events: [String]
  let size: CGSize

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("事件与手势").font(.headline)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(events.enumerated()), id: \.offset) { _, event in
            Text(event)
              .font(.system(size: 12, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(maxHeight: .infinity)
    }
    .padding(18)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }
}
