import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

/// HSplitView owns resizing. Apply the initial widths once after its native views attach.
struct InitialColumnWidths: NSViewRepresentable {
  func makeNSView(context: Context) -> InitialWidthsView { InitialWidthsView() }
  func updateNSView(_ view: InitialWidthsView, context: Context) {}

  final class InitialWidthsView: NSView {
    private weak var initializedSplit: NSSplitView?
    private var pending = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      needsLayout = true
    }
    override func layout() {
      super.layout()
      guard initializedSplit == nil, !pending else { return }
      pending = true
      // Let SwiftUI finish restoring the window's size before positioning dividers.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.pending = false
        self.applyInitialWidths()
      }
    }
    private func applyInitialWidths() {
      var ancestor = superview
      while let view = ancestor {
        if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count == 3 {
          guard split !== initializedSplit, split.bounds.width >= 922 else { return }
          initializedSplit = split
          split.setPosition(280, ofDividerAt: 0)
          split.setPosition(split.bounds.width - 281, ofDividerAt: 1)
          return
        }
        ancestor = view.superview
      }
    }
  }
}
