import Foundation
import ViewinProtocol
import ViewinSnapshot
import ViewinTransport

public struct InspectionTarget: Identifiable, Sendable, Equatable {
  public var id: UInt16 { port }
  public let port: UInt16
  public let appName: String
  public let appId: String
  public let deviceName: String
  public let osVersion: String
  public let appIconPNG: Data?
  public let screenshotPNG: Data?
  public init(
    port: UInt16, appName: String, appId: String, deviceName: String, osVersion: String,
    appIconPNG: Data? = nil, screenshotPNG: Data? = nil
  ) {
    self.port = port
    self.appName = appName
    self.appId = appId
    self.deviceName = deviceName
    self.osVersion = osVersion
    self.appIconPNG = appIconPNG
    self.screenshotPNG = screenshotPNG
  }
}
public struct InspectionCapture: Sendable {
  public let document: SnapshotDocument
  public let images: [String: Data]
}
@MainActor public enum InspectionClient {
  public static func discoverSimulators() async -> [InspectionTarget] {
    await discover(ports: Array(InspectionWire.simulatorPorts)) { port in
      try? await target(port: port, timeout: 1)
    }
  }

  static func discover(
    ports: [UInt16],
    probe: @escaping @MainActor @Sendable (UInt16) async -> InspectionTarget?
  ) async -> [InspectionTarget] {
    await withTaskGroup(of: InspectionTarget?.self) { group in
      for port in ports {
        group.addTask { await probe(port) }
      }
      var result: [InspectionTarget] = []
      for await target in group {
        if let target { result.append(target) }
      }
      return Task.isCancelled ? [] : result.sorted { $0.port < $1.port }
    }
  }

  public static func target(port: UInt16, timeout: TimeInterval = 2) async throws
    -> InspectionTarget
  {
    let connection = FramedConnection(port: port)
    let timer = Task {
      try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
      if !Task.isCancelled { connection.close() }
    }
    defer {
      timer.cancel()
      connection.close()
    }
    try await connection.start(timeout: min(0.5, timeout))
    let response = try await exchange(
      InspectionRequest(method: "hello"), on: connection, timeout: .seconds(2))
    guard let target = response.target, Set(response.imageIds).count == response.imageIds.count,
      response.imageIds.allSatisfy({ ["app-icon", "app-preview"].contains($0) })
    else {
      throw TransportError("目标信息无效。")
    }
    var previews: [String: Data] = [:]
    for id in response.imageIds { previews[id] = try await connection.receive() }
    return InspectionTarget(
      port: port, appName: target.appName, appId: target.appId,
      deviceName: target.deviceName, osVersion: target.osVersion,
      appIconPNG: previews["app-icon"], screenshotPNG: previews["app-preview"])
  }
  public static func capture(_ target: InspectionTarget) async throws -> InspectionCapture {
    let connection = FramedConnection(port: target.port)
    defer { connection.close() }
    try await connection.start()
    let timeout = Task {
      try? await Task.sleep(for: .seconds(30))
      if !Task.isCancelled { connection.close() }
    }
    defer { timeout.cancel() }
    let response = try await exchange(
      InspectionRequest(method: "capture"), on: connection, timeout: .seconds(30))
    guard let snapshot = response.snapshot else { throw TransportError("采集响应缺少层级。") }
    let document = try SnapshotDocument(data: JSONEncoder().encode(snapshot))
    guard Set(response.imageIds).count == response.imageIds.count,
      Set(response.imageIds) == Set(snapshot.images.map(\.id))
    else { throw TransportError("图片清单与快照不一致。") }
    var images: [String: Data] = [:]
    for id in response.imageIds { images[id] = try await connection.receive() }
    return InspectionCapture(document: document, images: images)
  }
  private static func exchange(
    _ request: InspectionRequest, on connection: FramedConnection, timeout: Duration
  ) async throws -> InspectionResponse {
    let timer = Task {
      try? await Task.sleep(for: timeout)
      if !Task.isCancelled { connection.close() }
    }
    defer { timer.cancel() }
    try await connection.send(JSONEncoder().encode(request))
    let response = try JSONDecoder().decode(
      InspectionResponse.self, from: await connection.receive())
    guard response.service == InspectionWire.service, response.version == InspectionWire.version,
      response.id == request.id
    else { throw TransportError("Viewin 协议或请求标识不匹配。") }
    if let error = response.error { throw TransportError(error) }
    return response
  }
}
