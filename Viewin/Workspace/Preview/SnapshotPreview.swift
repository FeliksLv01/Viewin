import SwiftUI
import ViewinProtocol
import ViewinSnapshot

struct SnapshotPreview: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument

  var body: some View {
    Group {
      PreviewSceneContent(workspace: workspace, document: document)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Native scene state is observed separately from the right-side measurement panel.
private struct PreviewSceneContent: View {
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  var body: some View {
    Group {
      if let window = workspace.window {
        ExplodedPreview(
          contentID: workspace.contentID, workspace: workspace, document: document, window: window,
          expanded: workspace.expanded, search: workspace.search,
          selectedId: workspace.selectedId,
          hoveredId: workspace.hoveredId,
          focusRootId: workspace.focusRootId, includedIds: workspace.searchIncludedIds,
          hiddenPreviewIds: workspace.hiddenPreviewIds, showHidden: workspace.showHidden,
          bounds: workspace.showBounds, cameraState: workspace.camera,
          images: workspace.nodeImages)
      } else {
        ContentUnavailableView("没有窗口", systemImage: "macwindow")
      }
    }
  }
}
