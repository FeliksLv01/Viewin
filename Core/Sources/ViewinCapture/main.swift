import Foundation
import ViewinConnection
import ViewinSnapshot

@main struct CaptureCommand {
  @MainActor static func main() async {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      if args.contains("--help") {
        writeOutput(
          "viewin [--list] [--port PORT] [--output FILE.viewin] [--format viewin|json]"
        )
        writeOutput(
          "Default: one .viewin snapshot. --format json exports a diagnostic JSON + images folder."
        )
        return
      }
      let format =
        args.firstIndex(of: "--format").flatMap {
          $0 + 1 < args.count ? args[$0 + 1] : nil
        } ?? "viewin"
      guard ["viewin", "json"].contains(format) else {
        throw SnapshotIssue(message: "不支持的格式，请使用 viewin 或 json。")
      }
      let port = args.firstIndex(of: "--port").flatMap {
        $0 + 1 < args.count ? UInt16(args[$0 + 1]) : nil
      }
      let targets: [InspectionTarget]
      if let port {
        targets = [try await InspectionClient.target(port: port)]
      } else {
        targets = await InspectionClient.discoverSimulators()
      }
      if args.contains("--list") {
        for target in targets { writeOutput("\(target.port)\t\(target.appName)\t\(target.deviceName)") }
        return
      }
      guard let target = targets.first else {
        throw SnapshotIssue(message: "没有找到前台 Viewin SDK App。请先运行 Demo。")
      }
      let destination =
        args.firstIndex(of: "--output").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        ?? "snapshot"
      let capture = try await InspectionClient.capture(target)
      var url = URL(fileURLWithPath: destination)
      if format == "viewin" {
        if url.pathExtension.lowercased() != "viewin" {
          url.appendPathExtension("viewin")
        }
        try SnapshotArchive.write(document: capture.document, images: capture.images, to: url)
      } else {
        try FileManager.default.createDirectory(
          at: url.appendingPathComponent("images"), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(capture.document.snapshot).write(
          to: url.appendingPathComponent("snapshot.json"))
        for (id, data) in capture.images {
          try data.write(to: url.appendingPathComponent("images/\(id).png"))
        }
      }
      writeOutput(
        "Captured \(capture.document.snapshot.nodes.count) nodes, \(capture.images.count) images from \(target.appName) -> \(url.path)"
      )
    } catch {
      FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  /// Command results belong on stdout so terminals and agents can consume them.
  private static func writeOutput(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }
}
