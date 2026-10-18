import AppKit
import Observation
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot

/// The window owns an actual NSToolbar; individual tool contents remain SwiftUI.
struct WorkspaceToolbar: NSViewRepresentable {
  let workspace: WorkspaceStore
  let openSnapshot: () -> Void
  let saveSnapshot: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(workspace: workspace, openSnapshot: openSnapshot, saveSnapshot: saveSnapshot)
  }
  func makeNSView(context: Context) -> WindowAttachment {
    let view = WindowAttachment()
    view.onWindow = { [weak coordinator = context.coordinator] window in
      coordinator?.install(on: window)
    }
    return view
  }
  func updateNSView(_ nsView: WindowAttachment, context: Context) {}

  final class WindowAttachment: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window { onWindow?(window) }
    }
  }

  @MainActor final class Coordinator: NSObject, NSToolbarDelegate {
    let workspace: WorkspaceStore
    let openSnapshot: () -> Void
    let saveSnapshot: () -> Void
    let toolbar = NSToolbar(identifier: "Viewin.InspectorToolbar")
    private var appWidthConstraint: NSLayoutConstraint?
    init(
      workspace: WorkspaceStore, openSnapshot: @escaping () -> Void,
      saveSnapshot: @escaping () -> Void
    ) {
      self.workspace = workspace
      self.openSnapshot = openSnapshot
      self.saveSnapshot = saveSnapshot
      super.init()
      toolbar.delegate = self
      toolbar.displayMode = .iconAndLabel
      toolbar.allowsUserCustomization = false
    }
    func install(on window: NSWindow) {
      guard window.toolbar !== toolbar else { return }
      window.tabbingMode = .disallowed
      window.titleVisibility = .hidden
      window.toolbarStyle = .expanded
      window.toolbar = toolbar
      // These are the system window controls; no custom traffic lights.
      for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        window.standardWindowButton(kind)?.isHidden = false
      }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [
        .init("refresh"), .init("app"), .flexibleSpace,
        .init("mode"), .init("rotation"), .init("settings"), .flexibleSpace,
        .init("scale"), .flexibleSpace, .init("measure"), .init("open"),
      ]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(
      _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      let titles = [
        "refresh": L10n.text("刷新"), "app": L10n.text("App 切换"), "mode": "2D / 3D", "rotation": L10n.text("自由旋转"),
        "settings": L10n.text("设置"), "scale": L10n.text("大小"), "measure": L10n.text("测距"), "open": L10n.text("打开"),
      ]
      guard let title = titles[id.rawValue] else { return nil }
      let item = NSToolbarItem(itemIdentifier: id)
      item.label = title
      item.paletteLabel = title
      let hosting = NSHostingView(
        rootView: ToolbarControl(
          workspace: workspace, kind: id.rawValue, openSnapshot: openSnapshot,
          saveSnapshot: saveSnapshot))
      let widths: [String: CGFloat] = [
        "refresh": 54, "app": 54, "mode": 90, "rotation": 54,
        "settings": 54, "scale": 210, "measure": 54, "open": 54,
      ]
      let width = widths[id.rawValue] ?? 54
      hosting.frame = NSRect(x: 0, y: 0, width: width, height: 30)
      item.view = hosting
      hosting.translatesAutoresizingMaskIntoConstraints = false
      let widthConstraint = hosting.widthAnchor.constraint(equalToConstant: width)
      NSLayoutConstraint.activate([
        widthConstraint,
        hosting.heightAnchor.constraint(equalToConstant: 30),
      ])
      if id.rawValue == "app" {
        appWidthConstraint = widthConstraint
        observeAppWidth()
      }
      return item
    }

    private func observeAppWidth() {
      withObservationTracking {
        appWidthConstraint?.constant = workspace.connectedTarget == nil ? 54 : 320
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in self?.observeAppWidth() }
      }
    }
  }
}
