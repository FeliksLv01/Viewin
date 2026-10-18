import Foundation

/// On-demand ADB forwarding for authorized USB devices and Android emulators.
/// Talks to the local ADB server; works inside the Mac App Sandbox.
/// No external executable, network pairing, background polling, or device shell.
@MainActor public final class AndroidBridge {
  public static let shared = AndroidBridge()

  public func ports() async -> [UInt16] {
    guard let devices = try? await ADBHostConnection.request("host:devices")
    else { return [] }
    guard !Task.isCancelled else { return [] }
    let serials = Self.readySerials(devices)
    let existing = (try? await ADBHostConnection.request("host:list-forward")) ?? ""
    let valid = Set(existing.split(separator: "\n").map(String.init))
    var active: [String: UInt16] = [:]
    for serial in serials.prefix(8) {
      for remote in 48721...48726 {
        guard !Task.isCancelled else { return [] }
        let key = "\(serial):\(remote)"
        let reusable = valid.compactMap { line -> UInt16? in
          let fields = line.split(whereSeparator: \.isWhitespace)
          guard fields.count == 3, fields[0] == serial, fields[2] == "tcp:\(remote)", fields[1].hasPrefix("tcp:") else { return nil }
          return UInt16(fields[1].dropFirst(4))
        }.sorted().first
        if let local = reusable {
          active[key] = local
        } else if let output = try? await ADBHostConnection.request("host-serial:\(serial):forward:tcp:0;tcp:\(remote)", forwarding: true),
          let local = UInt16(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
          active[key] = local
        }
      }
    }
    return active.values.sorted()
  }

  static func readySerials(_ output: String) -> [String] {
    output.split(separator: "\n").compactMap { line in
      let parts = line.split(whereSeparator: \.isWhitespace)
      guard parts.count >= 2, parts[1] == "device", parts[0] != "List" else { return nil }
      return String(parts[0])
    }
  }
}
