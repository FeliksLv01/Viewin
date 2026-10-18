import ViewinTestSupport
import Foundation
import ViewinProtocol
@testable import ViewinSnapshot
import XCTest
import ZIPFoundation

final class SnapshotArchiveTests: XCTestCase {
  private let image = Data("unique PNG-like payload used only for archive integrity testing".utf8)

  func testRoundTripPreservesIDsAndStoresDuplicateImagesOnce() throws {
    try temporary { url in
      let doc = try document()
      try SnapshotArchive.write(document: doc, images: ["a": image, "b": image], to: url)
      let result = try SnapshotArchive.read(from: url)
      XCTAssertEqual(result.document.snapshot, doc.snapshot)
      XCTAssertEqual(result.images, ["a": image, "b": image])
      let archive = try Archive(url: url, accessMode: .read)
      XCTAssertEqual(Array(archive).filter { $0.path.hasPrefix("images/") }.count, 1)
      XCTAssertEqual(archive["snapshot.json"]?.isCompressed, true)
    }
  }

  func testLegacyArchivesRemainReadable() throws {
    for format in ["app.uiinspector.snapshot", "app.inview.snapshot"] {
      try temporary { url in
        let doc = try document()
        try SnapshotArchive.write(document: doc, images: ["a": image, "b": image], to: url)
        let archive = try Archive(url: url, accessMode: .update)
        let entry = try XCTUnwrap(archive["manifest.json"])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["format"] = format
        try archive.remove(entry)
        try add("manifest.json", data: JSONSerialization.data(withJSONObject: json), archive: archive)
        XCTAssertEqual(try SnapshotArchive.read(from: url).document.snapshot, doc.snapshot)
      }
    }
  }

  func testMissingImageFailsWithoutReplacingExistingFile() throws {
    try temporary { url in
      let original = Data("existing file".utf8)
      try original.write(to: url)
      XCTAssertThrowsError(try SnapshotArchive.write(document: document(), images: [:], to: url))
      XCTAssertEqual(try Data(contentsOf: url), original)
    }
  }

  func testExistingSnapshotIsAtomicallyReplaced() throws {
    try temporary { url in
      let doc = try document()
      try SnapshotArchive.write(document: doc, images: ["a": image, "b": image], to: url)
      let changed = Data("replacement".utf8)
      try SnapshotArchive.write(document: doc, images: ["a": changed, "b": changed], to: url)
      XCTAssertEqual(try SnapshotArchive.read(from: url).images["a"], changed)
    }
  }

  func testUnsupportedManifestVersionIsRejected() throws {
    try temporary { url in
      let archive = try Archive(url: url, accessMode: .create)
      let data = Data(#"{"format":"app.viewin.snapshot","version":99,"snapshot":"snapshot.json","images":{}}"#.utf8)
      try add("manifest.json", data: data, archive: archive)
      XCTAssertThrowsError(try SnapshotArchive.read(from: url))
    }
  }

  func testUnsafeAndDuplicatePathsAreRejected() throws {
    for paths in [["../outside"], ["/absolute"], ["a\\b"], ["same", "same"]] {
      try temporary { url in
        let archive = try Archive(url: url, accessMode: .create)
        for path in paths { try add(path, data: Data([1]), archive: archive) }
        XCTAssertThrowsError(try SnapshotArchive.read(from: url))
      }
    }
  }

  func testCorruptedStoredImageFailsChecksum() throws {
    try temporary { url in
      try SnapshotArchive.write(document: document(), images: ["a": image, "b": image], to: url)
      var bytes = try Data(contentsOf: url)
      let range = try XCTUnwrap(bytes.range(of: image))
      bytes[range.lowerBound + 4] ^= 0xFF
      try bytes.write(to: url)
      XCTAssertThrowsError(try SnapshotArchive.read(from: url))
    }
  }

  func testJSONLargerThan20MBIsAccepted() throws {
    var data = try JSONEncoder().encode(ExampleSnapshot.ios.load().snapshot)
    data.append(Data(repeating: 32, count: 20_000_001))
    XCTAssertEqual(try SnapshotDocument(data: data).snapshot.nodes.count, 15)
  }

  func testSingleResourceLargerThan20MBRoundTrips() throws {
    try temporary { url in
      let large = Data(repeating: 7, count: 20_000_001)
      try SnapshotArchive.write(document: document(), images: ["a": large, "b": large], to: url)
      let read = try SnapshotArchive.read(from: url)
      XCTAssertEqual(read.images["a"], large)
      XCTAssertEqual(read.images["b"], large)
    }
  }

  private func document() throws -> SnapshotDocument {
    let fixture = try ExampleSnapshot.ios.load()
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.snapshot)) as? [String: Any])
    json["images"] = ["a", "b"].map {
      ["id": $0, "path": "images/\($0).png", "mimeType": "image/png", "pixelWidth": 1, "pixelHeight": 1] as [String: Any]
    }
    return try SnapshotDocument(data: JSONSerialization.data(withJSONObject: json))
  }

  private func add(_ path: String, data: Data, archive: Archive) throws {
    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, count in
      data.subdata(in: Int(offset)..<min(Int(offset) + count, data.count))
    }
  }

  private func temporary(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("test.viewin"))
  }
}
