import ViewinSnapshot
import Foundation

/// Skill installation is independent of the workspace and never changes agent configuration files.
public struct AgentSkillInstaller {
  public enum Destination: String, CaseIterable, Identifiable, Sendable {
    case shared, codex, claudeCode, openCode, pi, custom
    public var id: String { rawValue }
    public var title: String {
      switch self {
      case .shared: L10n.text("通用（推荐）")
      case .codex: "Codex"
      case .claudeCode: "Claude Code"
      case .openCode: "OpenCode"
      case .pi: "Pi"
      case .custom: L10n.text("自定义目录")
      }
    }
    public var relativePath: String {
      switch self {
      case .shared: ".agents/skills"
      case .codex: ".codex/skills"
      case .claudeCode: ".claude/skills"
      case .openCode: ".config/opencode/skills"
      case .pi: ".pi/agent/skills"
      case .custom: ""
      }
    }
  }

  public enum Status: Equatable {
    case notInstalled, installed, needsUpdate, conflict
  }

  private struct Receipt: Codable {
    let owner: String
    let version: Int
    let cliPath: String
  }
  private static let owner = "app.viewin.agent-skill"
  private static let version = 1
  private static let receiptName = ".viewin-installation.json"
  public let executable: URL
  private let files: FileManager

  public init(executable: URL, fileManager: FileManager = .default) {
    self.executable = executable
    self.files = fileManager
  }

  public var cliAvailable: Bool { files.isExecutableFile(atPath: executable.path) }

  public func status(in root: URL) -> Status {
    let directory = root.appendingPathComponent("viewin", isDirectory: true)
    guard files.fileExists(atPath: directory.path) else { return .notInstalled }
    guard !isSymbolicLink(directory), let receipt = receipt(in: directory),
      receipt.owner == Self.owner else { return .conflict }
    guard receipt.version == Self.version, receipt.cliPath == executable.path, hasExecutablePermission(launcher(in: root)),
      let expected = try? contents() else { return .needsUpdate }
    for (path, data) in expected {
      let url = directory.appendingPathComponent(path)
      if isSymbolicLink(url) || (try? Data(contentsOf: url)) != data { return .needsUpdate }
    }
    return .installed
  }

  /// `root` is a user-authorized skills directory, not the viewin skill folder itself.
  @discardableResult public func install(in root: URL) throws -> URL {
    guard cliAvailable else { throw InstallationError.missingCLI }
    let directory = root.appendingPathComponent("viewin", isDirectory: true)
    guard status(in: root) != .conflict else { throw InstallationError.conflict }
    let content = try contents()
    // Never traverse a replaced managed subdirectory or file symlink during an update.
    for path in ["scripts", "references"] + Array(content.keys) + [Self.receiptName] {
      if isSymbolicLink(directory.appendingPathComponent(path)) {
        throw InstallationError.conflict
      }
    }
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    for (path, data) in content {
      let url = directory.appendingPathComponent(path)
      try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    }
    try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.appendingPathComponent("scripts/viewin").path)
    let receipt = Receipt(owner: Self.owner, version: Self.version, cliPath: executable.path)
    try JSONEncoder().encode(receipt).write(to: directory.appendingPathComponent(Self.receiptName), options: .atomic)
    return directory
  }

  public func launcher(in root: URL) -> URL {
    root.appendingPathComponent("viewin/scripts/viewin")
  }

  public static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }

  private func contents() throws -> [String: Data] {
    guard let source = Bundle.module.url(forResource: "viewin", withExtension: nil, subdirectory: "Skills") else {
      throw InstallationError.missingResource
    }
    let launcher = """
    #!/bin/sh
    # Managed by Viewin. Update from Settings > Agent after moving the app.
    cli=\(Self.shellQuote(executable.path))
    if [ ! -x "$cli" ]; then
      echo 'Viewin CLI unavailable. Update the skill from Viewin Settings > Agent.' >&2
      exit 127
    fi
    exec "$cli" "$@"

    """
    return [
      "SKILL.md": try Data(contentsOf: source.appendingPathComponent("SKILL.md")),
      "references/snapshot.md": try Data(contentsOf: source.appendingPathComponent("references/snapshot.md")),
      "scripts/viewin": Data(launcher.utf8),
    ]
  }

  // The app sandbox cannot execute a user-selected script, but the external
  // agent can. Inspect the POSIX mode rather than access(X_OK) in the sandbox.
  private func hasExecutablePermission(_ url: URL) -> Bool {
    guard let mode = try? files.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber else { return false }
    return mode.intValue & 0o111 != 0
  }

  private func receipt(in directory: URL) -> Receipt? {
    let url = directory.appendingPathComponent(Self.receiptName)
    guard !isSymbolicLink(url), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Receipt.self, from: data)
  }

  private func isSymbolicLink(_ url: URL) -> Bool {
    (try? files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
  }

  public enum InstallationError: LocalizedError {
    case missingCLI, missingResource, conflict
    public var errorDescription: String? {
      switch self {
      case .missingCLI: L10n.text("App 内未找到可运行的 CLI，请重新安装完整的 Viewin App。")
      case .missingResource: L10n.text("App 内缺少 Skill 模板，请重新安装 Viewin App。")
      case .conflict: L10n.text("此目录已有其他来源的 viewin Skill，或文件为符号链接。请选择其他目录，原有内容未被覆盖。")
      }
    }
  }
}
