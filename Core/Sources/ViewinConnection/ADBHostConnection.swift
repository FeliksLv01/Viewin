import Foundation
@preconcurrency import Network

/// ADB host smart socket: ASCII hex length, command, OKAY/FAIL, then a length-prefixed payload.
@MainActor enum ADBHostConnection {
  static func request(_ command: String, forwarding: Bool = false) async throws -> String {
    let connection = NWConnection(host: "127.0.0.1", port: 5037, using: .tcp)
    let timer = Task {
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { connection.cancel() }
    }
    defer { timer.cancel(); connection.cancel() }
    let commandBytes = Data(command.utf8)
    guard commandBytes.count <= 65535 else { throw CocoaError(.coderInvalidValue) }
    var frame = Data(String(format: "%04x", commandBytes.count).utf8)
    frame.append(commandBytes)
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      connection.start(queue: .global(qos: .userInitiated))
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(content: frame, completion: .contentProcessed { error in
          if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        })
      }
      try await status(connection)
      // Forwarding has an outer host status and an inner transport status.
      if forwarding { try await status(connection) }
      return String(decoding: try await payload(connection), as: UTF8.self)
    } onCancel: { connection.cancel() }
  }
  private static func status(_ connection: NWConnection) async throws {
    let status = String(decoding: try await read(4, connection), as: UTF8.self)
    if status == "FAIL" {
      let message = String(decoding: try await payload(connection), as: UTF8.self)
      throw NSError(domain: "Viewin.ADB", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    guard status == "OKAY" else { throw CocoaError(.coderReadCorrupt) }
  }
  private static func payload(_ connection: NWConnection) async throws -> Data {
    let header = try await read(4, connection)
    guard let count = Int(String(decoding: header, as: UTF8.self), radix: 16), count >= 0, count <= 65535 else {
      throw CocoaError(.coderReadCorrupt)
    }
    return try await read(count, connection)
  }
  private static func read(_ count: Int, _ connection: NWConnection) async throws -> Data {
    var result = Data()
    while result.count < count {
      try Task.checkCancellation()
      let remaining = count - result.count
      let bytes: Data = try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { bytes, _, _, error in
          if let error { continuation.resume(throwing: error) }
          else if let bytes, !bytes.isEmpty { continuation.resume(returning: bytes) }
          else { continuation.resume(throwing: CocoaError(.coderReadCorrupt)) }
        }
      }
      result.append(bytes)
    }
    return result
  }
}
