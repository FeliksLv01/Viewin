import SwiftUI

@main struct ViewinApp: App {
  init() { _ = AppUpdater.shared }
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .defaultSize(width: 1280, height: 850)
    .commands { WorkspaceCommands() }
  }
}
