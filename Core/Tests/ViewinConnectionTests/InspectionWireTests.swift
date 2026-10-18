import Foundation
@preconcurrency import Network
import XCTest
import ViewinProtocol
import ViewinTransport
import ViewinConnection

@MainActor final class InspectionWireTests: XCTestCase {
  func testRequestsUseOwnVersionedServiceAndUniqueIDs() throws {
    let first = InspectionRequest(method: "hello")
    let second = InspectionRequest(method: "capture")
    XCTAssertEqual(first.service, "app.viewin.inspection")
    XCTAssertNotEqual(first.id, second.id)
    let copy = try JSONDecoder().decode(InspectionRequest.self, from: JSONEncoder().encode(second))
    XCTAssertEqual(copy.id, second.id); XCTAssertEqual(copy.method, "capture")
  }
  func testFrameRoundTripKeepsBinaryBytesAndFrameBoundaries() async throws {
    let listener = try NWListener(using: .tcp, on: .any)
    let completed = expectation(description: "server frames")
    listener.newConnectionHandler = { incoming in
      Task { @MainActor in
        let connection = FramedConnection(accepting: incoming)
        defer { connection.close() }
        do {
          try await connection.start()
          let a = try await connection.receive(); let b = try await connection.receive()
          try await connection.send(a); try await connection.send(b)
        } catch { XCTFail("\(error)") }
        completed.fulfill()
      }
    }
    try await start(listener)
    defer { listener.cancel() }
    let connection = FramedConnection(port: listener.port!.rawValue)
    defer { connection.close() }
    try await connection.start()
    let data = Data((0..<1_100_000).map { UInt8($0 % 251) })
    try await connection.send(data); try await connection.send(Data("second".utf8))
    let first = try await connection.receive(); let second = try await connection.receive()
    XCTAssertEqual(first, data); XCTAssertEqual(String(data: second, encoding: .utf8), "second")
    await fulfillment(of: [completed], timeout: 3)
  }
  func testCaptureRejectsMismatchedRequestIdentity() async throws {
    let listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { incoming in
      Task { @MainActor in
        let connection = FramedConnection(accepting: incoming)
        defer { connection.close() }
        do {
          try await connection.start()
          _ = try await connection.receive()
          try await connection.send(JSONEncoder().encode(InspectionResponse(id: UUID())))
        } catch { XCTFail("\(error)") }
      }
    }
    try await start(listener)
    defer { listener.cancel() }
    let target = InspectionTarget(port: listener.port!.rawValue, appName: "Test", appId: "test", deviceName: "test", osVersion: "27")
    do { _ = try await InspectionClient.capture(target); XCTFail("Expected request mismatch") }
    catch { XCTAssertTrue(error.localizedDescription.contains("标识")) }
  }
  private func start(_ listener: NWListener) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready: listener.stateUpdateHandler = nil; continuation.resume()
        case .failed(let error): listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
        default: break
        }
      }
      listener.start(queue: .main)
    }
  }
}
