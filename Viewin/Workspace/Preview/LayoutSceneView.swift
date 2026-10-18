import AppKit
import SceneKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

final class LayoutSceneView: SCNView {
  var onSelect: ((String) -> Void)?
  var onDoubleClick: ((String) -> Void)?
  var onHover: ((String?) -> Void)?
  var makeDrag: ((Bool) -> PreviewCamera.Drag?)?
  var onDrag: ((PreviewCamera.Drag, Double, Double) -> Void)?
  var onScroll: ((Double, Double, Bool) -> Void)?
  var onMagnify: ((Double) -> Void)?
  var onNavigate: ((UInt16) -> Void)?
  var onAppearanceChange: (() -> Void)?
  private var start: NSPoint?
  private var drag: PreviewCamera.Drag?
  private var moved = false
  private var spaceHeld = false
  override var acceptsFirstResponder: Bool { true }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didResignKeyNotification, object: nil)
    if let window {
      NotificationCenter.default.addObserver(
        self, selector: #selector(cancelInteraction), name: NSWindow.didResignKeyNotification,
        object: window)
    }
  }
  @objc private func cancelInteraction() {
    spaceHeld = false
    start = nil
    drag = nil
    window?.invalidateCursorRects(for: self)
  }
  override func resignFirstResponder() -> Bool {
    cancelInteraction()
    return super.resignFirstResponder()
  }
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: spaceHeld ? .openHand : .arrow)
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 49 {
      spaceHeld = true
      onHover?(nil)
      window?.invalidateCursorRects(for: self)
    } else if (123...126).contains(event.keyCode) {
      onNavigate?(event.keyCode)
    } else {
      super.keyDown(with: event)
    }
  }
  override func keyUp(with event: NSEvent) {
    if event.keyCode == 49 {
      spaceHeld = false
      window?.invalidateCursorRects(for: self)
    } else {
      super.keyUp(with: event)
    }
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    backgroundColor =
      dark
      ? NSColor(red: 19 / 255, green: 20 / 255, blue: 21 / 255, alpha: 1)
      : NSColor(white: 249 / 255, alpha: 1)
    onAppearanceChange?()
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self))
  }
  private func node(at event: NSEvent) -> String? {
    let point = convert(event.locationInWindow, from: nil)
    return hitTest(
      point,
      options: [
        .categoryBitMask: 1, .searchMode: SCNHitTestSearchMode.closest.rawValue,
        .ignoreHiddenNodes: true,
      ]
    ).first?.node.name
  }
  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    start = event.locationInWindow
    drag = makeDrag?(spaceHeld)
    moved = false
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start, let drag else { return }
    let x = event.locationInWindow.x - start.x
    let y = start.y - event.locationInWindow.y
    if hypot(x, y) > 3 { moved = true }
    if moved { onDrag?(drag, x, y) }
  }
  override func mouseUp(with event: NSEvent) {
    if !moved, !spaceHeld, let id = node(at: event) {
      if event.clickCount == 2 {
        onDoubleClick?(id)
      } else if event.clickCount == 1 {
        onSelect?(id)
      }
    }
    start = nil
    drag = nil
  }
  override func mouseMoved(with event: NSEvent) { onHover?(spaceHeld ? nil : node(at: event)) }
  override func mouseExited(with event: NSEvent) { onHover?(nil) }
  override func magnify(with event: NSEvent) {
    if event.phase == .changed { onMagnify?(Double(event.magnification)) }
  }
  override func scrollWheel(with event: NSEvent) {
    onScroll?(event.deltaX, event.deltaY, event.modifierFlags.contains(.command))
  }
}
