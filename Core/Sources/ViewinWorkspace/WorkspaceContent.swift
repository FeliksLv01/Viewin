import AppKit
import Foundation
import ViewinProtocol
import ViewinSnapshot

/// Immutable, reference-shared resources. Pointer actions never copy/decode PNGs or rebuild indexes.
public final class WorkspaceContent: @unchecked Sendable, Equatable {
  public let document: SnapshotDocument
  public let resources: [String: Data]
  public let images: [String: NSImage]
  public let hierarchy: HierarchyPresentation
  public let windows: [String: HierarchyPresentation]

  @MainActor public init(document: SnapshotDocument, resources: [String: Data] = [:]) {
    self.document = document
    self.resources = resources
    self.images = SnapshotImageLoader.images(from: resources)
    self.hierarchy = HierarchyPresentation(document: document)
    self.windows = Dictionary(
      uniqueKeysWithValues: document.snapshot.windows.map {
        ($0.id, HierarchyPresentation(document: document, windowId: $0.id))
      })
  }
  public static func == (lhs: WorkspaceContent, rhs: WorkspaceContent) -> Bool { lhs === rhs }
}
