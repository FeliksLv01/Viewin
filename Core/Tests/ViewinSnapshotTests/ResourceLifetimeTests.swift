import AppKit
import ViewinSnapshot
import XCTest

final class ResourceLifetimeTests: XCTestCase {
  @MainActor func testIdenticalPNGResourcesShareImageIdentity() throws {
    let png = try imageData(red: 1)
    let images = SnapshotImageLoader.images(from: ["solo": png, "group": png])
    XCTAssertEqual(images.count, 2)
    XCTAssertTrue(try XCTUnwrap(images["solo"]) === XCTUnwrap(images["group"]))
  }

  @MainActor func testDifferentPixelsAndDifferentSnapshotsStayIndependent() throws {
    let red = try imageData(red: 1)
    let black = try imageData(red: 0)
    let first = SnapshotImageLoader.images(from: ["red": red, "black": black])
    let second = SnapshotImageLoader.images(from: ["red": red])
    XCTAssertFalse(try XCTUnwrap(first["red"]) === XCTUnwrap(first["black"]))
    XCTAssertEqual(second.count, 1)
    XCTAssertNil(second["black"])
    XCTAssertEqual(first["red"]?.size, NSSize(width: 2, height: 2))
  }

  @MainActor func testInvalidImagesAreNotSubstituted() {
    XCTAssertTrue(SnapshotImageLoader.images(from: ["broken": Data([0, 1, 2])]).isEmpty)
  }

  func testRepeatedPickerOpenUsesCompletedScanCache() {
    var schedule = DiscoverySchedule()
    XCTAssertTrue(schedule.begin(at: 0))
    schedule.completed(at: 1)
    XCTAssertFalse(schedule.begin(at: 5))
    XCTAssertFalse(schedule.begin(at: 30))
    XCTAssertTrue(schedule.begin(at: 31))
  }

  func testManualScanBypassesCacheButRespectsCooldown() {
    var schedule = DiscoverySchedule()
    XCTAssertTrue(schedule.begin(at: 0))
    schedule.completed(at: 1)
    XCTAssertFalse(schedule.begin(at: 2, force: true))
    XCTAssertTrue(schedule.begin(at: 3, force: true))
    XCTAssertFalse(schedule.begin(at: 4, force: true))
  }

  func testCanceledAttemptDoesNotCacheAnEmptyResult() {
    var schedule = DiscoverySchedule()
    XCTAssertTrue(schedule.begin(at: 0))
    XCTAssertFalse(schedule.begin(at: 1))
    XCTAssertTrue(schedule.begin(at: 3))
  }

  @MainActor private func imageData(red: Double) throws -> Data {
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2,
      pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let pixels = try XCTUnwrap(rep.bitmapData)
    for y in 0..<2 { for x in 0..<2 {
      let offset = y * rep.bytesPerRow + x * 4
      pixels[offset] = red > 0 ? 255 : 0
      pixels[offset + 1] = 0
      pixels[offset + 2] = 0
      pixels[offset + 3] = 255
    } }
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }
}
