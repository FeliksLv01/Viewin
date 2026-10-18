#if canImport(AppKit)
import AppKit

/// Share identical encoded screenshots without changing resource IDs or pixel fidelity.
@MainActor public enum SnapshotImageLoader {
  public static func images(from resources: [String: Data]) -> [String: NSImage] {
    var unique: [Data: NSImage] = [:]
    var result: [String: NSImage] = [:]
    for (id, data) in resources {
      if let image = unique[data] {
        result[id] = image
      } else if let image = autoreleasepool(invoking: { NSImage(data: data) }) {
        unique[data] = image
        result[id] = image
      }
    }
    return result
  }
}
#endif
