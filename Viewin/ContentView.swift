import AppKit
import SwiftUI
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var workspace = WorkspaceStore()
  @State private var importing = false

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if let document = workspace.document {
          GeometryReader { geometry in
            HSplitView {
              HierarchySidebar(workspace: workspace, document: document)
                .frame(
                  minWidth: 240, idealWidth: 280,
                  maxWidth: max(240, min(geometry.size.width * 0.45, geometry.size.width - 682))
                )
                .background(InitialColumnWidths())
              SnapshotPreview(workspace: workspace, document: document)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
              InspectorColumn(workspace: workspace, document: document)
                .frame(
                  minWidth: 280, idealWidth: 280,
                  maxWidth: max(280, min(geometry.size.width * 0.4, geometry.size.width - 642)))
            }
          }
        } else {
          AppSelectionView(workspace: workspace, presentation: .startup,
                           openSnapshot: { importing = true }) { target in
            workspace.capture(target)
          }
        }
      }
    }
    .frame(minWidth: 1100, minHeight: 650)
    .navigationTitle("")
    .focusedSceneValue(\.workspaceCommands,
      WorkspaceCommandContext(workspace: workspace, openSnapshot: { importing = true }))
    .background(
      WorkspaceToolbar(
        workspace: workspace, openSnapshot: { importing = true },
        saveSnapshot: { workspace.saveSnapshot() }
      ).frame(
        width: 0, height: 0)
    )
    .fileImporter(
      isPresented: $importing,
      allowedContentTypes: [.viewinSnapshot, .legacyUIInspectorSnapshot, .legacyInViewSnapshot, .json, .folder]
    ) {
      result in
      switch result {
      case .success(let url): workspace.open(url)
      case .failure(let error): workspace.errorMessage = error.localizedDescription
      }
    }
    .onOpenURL { workspace.open($0) }
    .background(WorkspacePresentations(workspace: workspace))
    .background(MeasurementKeyboardMonitor(workspace: workspace).frame(width: 0, height: 0))

  }
}
