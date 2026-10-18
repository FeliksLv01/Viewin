import XCTest
@testable import ViewinConnection

@MainActor final class DiscoveryTests: XCTestCase {
  func testProbesStartTogetherAndResultsAreSorted() async {
    let started = expectation(description: "Every probe starts before any finishes")
    started.expectedFulfillmentCount = 3
    var releases: [UInt16: CheckedContinuation<InspectionTarget?, Never>] = [:]
    var released = false
    let scan = Task {
      await InspectionClient.discover(ports: [3, 1, 2]) { port in
        guard !released else { return nil }
        return await withCheckedContinuation { continuation in
          releases[port] = continuation
          started.fulfill()
        }
      }
    }
    await fulfillment(of: [started], timeout: 1)
    released = true
    for port: UInt16 in [3, 2, 1] {
      releases[port]?.resume(returning: port == 2 ? nil : InspectionTarget(
        port: port, appName: "Test", appId: "test", deviceName: "Simulator", osVersion: "27"))
    }
    let targets = await scan.value
    XCTAssertEqual(targets.map(\.port), [1, 3])
  }
}
