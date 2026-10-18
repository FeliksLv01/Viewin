import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

final class OutlineTable: NSTableView {
  var minimumContentWidth: CGFloat = 0 { didSet { resizeColumn() } }
  override func layout() {
    super.layout()
    resizeColumn()
  }
  private func resizeColumn() {
    guard let column = tableColumns.first, let scroll = enclosingScrollView else { return }
    let width = max(minimumContentWidth, scroll.contentSize.width)
    if abs(column.width - width) > 0.5 { column.width = width }
    if abs(frame.width - width) > 0.5 { setFrameSize(NSSize(width: width, height: frame.height)) }
  }
  var keyboardAction: ((Bool, Bool) -> Void)?
  var hoverAction: ((Int) -> Void)?
  var contextMenu: ((Int) -> NSMenu?)?
  var baseDepth = 0
  let guide = CAShapeLayer()
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    guide.lineWidth = 1
    guide.lineDashPattern = [2, 2]
    guide.fillColor = nil
    guide.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.3).cgColor
    layer?.addSublayer(guide)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
        owner: self))
  }
  override func mouseMoved(with event: NSEvent) {
    hoverAction?(row(at: convert(event.locationInWindow, from: nil)))
  }
  override func mouseExited(with event: NSEvent) { hoverAction?(-1) }
  override func menu(for event: NSEvent) -> NSMenu? {
    contextMenu?(row(at: convert(event.locationInWindow, from: nil)))
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 123 || event.keyCode == 124 {
      keyboardAction?(event.keyCode == 124, event.modifierFlags.contains(.option))
    } else {
      super.keyDown(with: event)
    }
  }
}

final class MenuCommand: NSObject {
  let action: () -> Void
  init(_ action: @escaping () -> Void) { self.action = action }
  @objc func invokeAction() { action() }
}

final class HoverRow: NSTableRowView {
  var hovered = false { didSet { needsDisplay = true } }
  override func drawBackground(in dirtyRect: NSRect) {
    super.drawBackground(in: dirtyRect)
    if hovered && !isSelected {
      NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
      bounds.fill()
    }
  }
}

final class HierarchyCell: NSTableCellView {
  let disclosure = NSButton()
  let eventButton = EventMarker()
  let icon = NSImageView()
  let title = NSTextField(labelWithString: "")
  var depth = 0
  var disclose: (() -> Void)?
  var showEvents: (() -> Void)?
  override init(frame: NSRect) {
    super.init(frame: frame)
    disclosure.isBordered = false
    disclosure.setButtonType(.momentaryChange)
    disclosure.target = self
    disclosure.action = #selector(discloseNode)
    eventButton.target = self
    eventButton.action = #selector(openEvents)
    title.lineBreakMode = .byTruncatingTail
    title.maximumNumberOfLines = 1
    for view in [eventButton, disclosure, icon, title] { addSubview(view) }
    textField = title
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var backgroundStyle: NSView.BackgroundStyle {
    didSet { eventButton.selected = backgroundStyle == .emphasized }
  }
  func configure(_ row: HierarchyTable.Coordinator.Row, expanded: Bool) {
    depth = row.depth
    let symbol = expanded ? "chevron.down" : "chevron.right"
    disclosure.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
    disclosure.isHidden = row.node.childIds.isEmpty
    disclosure.setAccessibilityLabel("展开或折叠 \(row.node.name)")
    icon.image = NSImage(named: row.node.iconAsset)
    icon.contentTintColor =
      row.node.framework == "swiftui" || row.node.framework == "compose"
      ? .systemBlue : .secondaryLabelColor
    let text = NSMutableAttributedString(
      string: row.node.sidebarTitle,
      attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
    if !row.detail.isEmpty {
      text.append(
        NSAttributedString(
          string: "  " + row.detail,
          attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
          ]))
    }
    title.attributedStringValue = text
    toolTip = row.tooltip
    alphaValue = row.hidden ? 0.45 : 1
    eventButton.isHidden = row.events.isEmpty
    eventButton.toolTip = "\(row.events.count) 个事件或手势"
    eventButton.setAccessibilityLabel("\(row.node.name) 的事件与手势")
    needsLayout = true
  }
  func setPreviewHidden(_ hidden: Bool) {
    // configure restores the ordinary/actually-hidden appearance before each reuse.
    if hidden { alphaValue = 0.45 }
  }
  func highlightSearch(_ query: String) {
    guard !query.isEmpty else { return }
    let text = NSMutableAttributedString(attributedString: title.attributedStringValue)
    let range = (text.string as NSString).range(of: query, options: .caseInsensitive)
    if range.location != NSNotFound {
      text.addAttribute(
        .backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
      title.attributedStringValue = text
    }
  }
  override func layout() {
    super.layout()
    // Keep the event affordance in the row's left gutter, with Lookin's 3pt insets.
    eventButton.frame = NSRect(x: 3, y: 3, width: 10, height: max(0, bounds.height - 6))
    let x = 16 + CGFloat(depth) * 13
    disclosure.frame = NSRect(x: x, y: (bounds.height - 18) / 2, width: 14, height: 18)
    icon.frame = NSRect(x: x + 20, y: (bounds.height - 16) / 2, width: 16, height: 16)
    title.frame = NSRect(
      x: x + 43, y: (bounds.height - 17) / 2, width: max(0, bounds.width - x - 49), height: 17)
  }
  @objc private func discloseNode() { disclose?() }
  @objc private func openEvents() { showEvents?() }
}

final class EventMarker: NSButton {
  var hovered = false { didSet { needsDisplay = true } }
  var selected = false { didSet { needsDisplay = true } }
  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false
    setButtonType(.momentaryChange)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }
  override func mouseEntered(with event: NSEvent) { hovered = true }
  override func mouseExited(with event: NSEvent) { hovered = false }
  override func draw(_ dirtyRect: NSRect) {
    (selected ? NSColor.white : NSColor.systemBlue.withAlphaComponent(hovered ? 1 : 0.5)).setFill()
    let width: CGFloat = hovered ? 8 : 5
    NSBezierPath(
      roundedRect: NSRect(
        x: (bounds.width - width) / 2, y: 0, width: width, height: bounds.height),
      xRadius: width / 2, yRadius: width / 2
    ).fill()
  }
}
