import AppKit
import SwiftUI
import ViewinWorkspace

/// Window-local event handling works while the tree, preview or inspector has focus.
/// No global key monitor, polling, or accessibility permission is needed.
struct MeasurementKeyboardMonitor: NSViewRepresentable {
  let workspace: WorkspaceStore
  func makeNSView(context: Context) -> KeyboardView { KeyboardView(workspace: workspace) }
  func updateNSView(_ view: KeyboardView, context: Context) {}
  static func dismantleNSView(_ view: KeyboardView, coordinator: ()) { view.stopObserving() }

  final class KeyboardView: NSView {
    weak var workspace: WorkspaceStore?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    init(workspace: WorkspaceStore) {
      self.workspace = workspace
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopObserving()
      guard let window else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) {
        [weak self, weak window] event in
        guard let self, let window, window.isKeyWindow,
          event.window == window || event.window?.parent == window || event.window == nil
        else { return event }
        if event.type == .flagsChanged {
          self.workspace?.measurementStore.send(
            .optionChanged(event.modifierFlags.contains(.option)))
        } else if event.keyCode == 53, self.workspace?.isMeasuring == true {
          self.workspace?.measurementStore.send(.stop)
          return nil
        }
        return event
      }
      observers.append(
        NotificationCenter.default.addObserver(
          forName: NSWindow.didResignKeyNotification,
          object: window, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { _ = self?.workspace?.measurementStore.send(.windowResigned) }
        })
      observers.append(
        NotificationCenter.default.addObserver(
          forName: NSWindow.didBecomeKeyNotification,
          object: window, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            _ = self?.workspace?.measurementStore.send(
              .optionChanged(NSEvent.modifierFlags.contains(.option)))
          }
        })
    }
    func stopObserving() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      observers.forEach { NotificationCenter.default.removeObserver($0) }
      observers = []
      workspace?.measurementStore.send(.windowResigned)
    }
  }
}
