import CryptoKit
import Foundation
import ViewinProtocol
import ZIPFoundation

/// A portable single-file snapshot. The ZIP container is an implementation detail,
/// while JSON remains the versioned model shared by all collectors and agents.
public enum SnapshotArchive {
  private struct Manifest: Codable {
    let format: String
    let version: Int
    let snapshot: String
    let images: [String: String]
  }
  public struct Contents: Sendable {
    public let document: SnapshotDocument
    public let images: [String: Data]
    public init(document: SnapshotDocument, images: [String: Data]) {
      self.document = document
      self.images = images
    }
  }
  private static let maximumBytes = 276_000_000

  public static func write(document: SnapshotDocument, images: [String: Data], to url: URL) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).viewin.tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try writeContents(document: document, images: images, to: temporary)
    if FileManager.default.fileExists(atPath: url.path) {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: url)
    }
  }

  private static func writeContents(document: SnapshotDocument, images: [String: Data], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let snapshot = try encoder.encode(document.snapshot)
    var aliases: [String: String] = [:]
    var blobs: [String: Data] = [:]
    var total = snapshot.count
    for resource in document.snapshot.images {
      guard let data = images[resource.id], data.count <= maximumBytes else {
        throw SnapshotIssue(message: "快照缺少图片或图片过大：\(resource.id)")
      }
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let path = "images/\(digest).\((resource.path as NSString).pathExtension)"
      aliases[resource.path] = path
      if blobs[path] == nil {
        total += data.count
        guard total <= maximumBytes else { throw SnapshotIssue(message: "快照资源超过大小上限。") }
        blobs[path] = data
      }
    }
    let manifest = Manifest(format: "app.viewin.snapshot", version: 1,
                            snapshot: "snapshot.json", images: aliases)
    let archive = try Archive(url: url, accessMode: .create)
    func add(_ path: String, _ data: Data, method: CompressionMethod) throws {
      try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                           compressionMethod: method) { offset, count in
        let start = Int(offset)
        return data.subdata(in: start..<min(start + count, data.count))
      }
    }
    try add("manifest.json", encoder.encode(manifest), method: .deflate)
    try add("snapshot.json", snapshot, method: .deflate)
    for path in blobs.keys.sorted() { try add(path, blobs[path]!, method: .none) }
  }

  public static func read(from url: URL) throws -> Contents {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= maximumBytes else { throw SnapshotIssue(message: "快照文件过大。") }
    let archive = try Archive(url: url, accessMode: .read)
    var paths = Set<String>()
    var total: UInt64 = 0
    for entry in archive {
      try Task.checkCancellation()
      guard entry.type == .file, validPath(entry.path), paths.insert(entry.path).inserted,
            paths.count <= 20_010 else { throw SnapshotIssue(message: "快照包含非法或重复的资源路径。") }
      guard entry.uncompressedSize <= UInt64(maximumBytes) else {
        throw SnapshotIssue(message: "快照资源过大：\(entry.path)")
      }
      total += entry.uncompressedSize
      guard total <= UInt64(maximumBytes) else { throw SnapshotIssue(message: "快照解压大小超过上限。") }
    }
    func extract(_ path: String, limit: Int) throws -> Data {
      guard let entry = archive[path], entry.uncompressedSize <= UInt64(limit) else {
        throw SnapshotIssue(message: "快照资源缺失或过大：\(path)")
      }
      var data = Data()
      let checksum = try archive.extract(entry) { chunk in
        try Task.checkCancellation()
        guard chunk.count <= limit - data.count else { throw SnapshotIssue(message: "快照资源解压超过上限。") }
        data.append(chunk)
      }
      guard checksum == entry.checksum, data.count == Int(entry.uncompressedSize) else {
        throw SnapshotIssue(message: "快照资源校验失败：\(path)")
      }
      return data
    }
    let manifest = try JSONDecoder().decode(Manifest.self, from: extract("manifest.json", limit: 2_000_000))
    guard ["app.viewin.snapshot", "app.uiinspector.snapshot", "app.inview.snapshot"].contains(manifest.format), manifest.version == 1,
          manifest.snapshot == "snapshot.json" else { throw SnapshotIssue(message: "不支持的 Viewin 文件格式。") }
    let document = try SnapshotDocument(data: extract(manifest.snapshot, limit: maximumBytes))
    var loaded: [String: Data] = [:]
    var images: [String: Data] = [:]
    for resource in document.snapshot.images {
      try Task.checkCancellation()
      guard let path = manifest.images[resource.path], validPath(path), path.hasPrefix("images/") else {
        throw SnapshotIssue(message: "快照图片引用无效：\(resource.id)")
      }
      if loaded[path] == nil { loaded[path] = try extract(path, limit: maximumBytes) }
      images[resource.id] = loaded[path]
    }
    return Contents(document: document, images: images)
  }

  private static func validPath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
      && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
        !$0.isEmpty && $0 != "." && $0 != ".."
      }
  }
}
