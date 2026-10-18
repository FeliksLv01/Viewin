import SwiftUI

@main struct ViewinApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .defaultSize(width: 1280, height: 850)
    .commands { WorkspaceCommands() }
  }
}
