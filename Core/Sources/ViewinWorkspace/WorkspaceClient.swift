import Foundation
import ViewinConnection
import ViewinSnapshot

public struct WorkspaceClient: Sendable {
  public var discover: @Sendable () async -> [InspectionTarget]
  public var capture: @Sendable (InspectionTarget) async throws -> WorkspaceContent
  public var open: @Sendable (URL) async throws -> WorkspaceContent
  public var save: @Sendable (WorkspaceContent, URL) async throws -> Void
  public var now: @Sendable () -> TimeInterval
}

extension WorkspaceClient {
  public static let liveValue = Self(
    discover: { await InspectionClient.discoverDevices() },
    capture: { target in
      let capture = try await InspectionClient.capture(target)
      try Task.checkCancellation()
      return await WorkspaceContent(document: capture.document, resources: capture.images)
    },
    open: { url in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let task = Task.detached {
        if ["viewin", "uiinspector", "inview"].contains(url.pathExtension.lowercased()) {
          return try SnapshotArchive.read(from: url)
        }
        let folder = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
        let file = folder ? url.appendingPathComponent("snapshot.json") : url
        let document = try SnapshotDocument(data: Data(contentsOf: file))
        var images: [String: Data] = [:]
        var bytes = 0
        for resource in document.snapshot.images {
          try Task.checkCancellation()
          let path = file.deletingLastPathComponent().appendingPathComponent(resource.path)
          let size =
            ((try? FileManager.default.attributesOfItem(atPath: path.path)[.size]) as? NSNumber)?
            .intValue ?? 0
          guard bytes + size <= 256_000_000 else { continue }
          if let data = try? Data(contentsOf: path) {
            images[resource.id] = data
            bytes += data.count
          }
        }
        return SnapshotArchive.Contents(document: document, images: images)
      }
      let payload = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      try Task.checkCancellation()
      return await WorkspaceContent(document: payload.document, resources: payload.images)
    },
    save: { content, url in
      try await Task.detached {
        try SnapshotArchive.write(document: content.document, images: content.resources, to: url)
      }.value
    },
    now: { ProcessInfo.processInfo.systemUptime }
  )
  public static let testValue = Self(
    discover: { [] }, capture: { _ in throw SnapshotIssue(message: "Unimplemented capture") },
    open: { _ in throw SnapshotIssue(message: "Unimplemented open") },
    save: { _, _ in throw SnapshotIssue(message: "Unimplemented save") }, now: { 0 })
}
