import ViewinSnapshot
import AppKit
import Darwin
import Observation
import OSLog
import SwiftUI
import ViewinWorkspace

@MainActor @Observable final class AgentSettingsModel {
  var destination: AgentSkillInstaller.Destination = .shared
  var root: URL?
  var status: AgentSkillInstaller.Status = .notInstalled
  var message: String?
  var failed = false
  private var bookmark: Data?
  private var authorizedRoot: URL?
  private let defaults = UserDefaults.standard
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.viewin", category: "AgentInstallation")
  let installer = AgentSkillInstaller(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/viewin"))

  var suggestedRoot: URL {
    // A sandboxed app's NSHomeDirectory points to its container, not the agent's home.
    let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) }
      ?? FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(destination.relativePath, isDirectory: true)
  }
  var displayedRoot: URL { root ?? suggestedRoot }
  private var bookmarkKey: String { "Viewin.AgentSkill.\(destination.rawValue).bookmark" }

  init() { refreshDestination() }

  func refreshDestination() {
    root = nil; bookmark = nil; authorizedRoot = nil; message = nil; failed = false; status = .notInstalled
    guard let data = defaults.data(forKey: bookmarkKey) else { return }
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
                        relativeTo: nil, bookmarkDataIsStale: &stale)
      guard !stale else { return }
      authorizedRoot = url; bookmark = data
      let suffix = defaults.string(forKey: bookmarkKey + ".suffix") ?? ""
      root = suffix.isEmpty ? url : url.appendingPathComponent(suffix, isDirectory: true)
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      status = installer.status(in: root ?? url)
    } catch {
      logger.error("Cannot resolve skill directory: \(error.localizedDescription, privacy: .public)")
    }
  }

  func chooseDirectory(installAfterSelection: Bool) {
    let panel = NSOpenPanel()
    panel.title = L10n.text("选择 Skill 安装目录")
    let suggested = displayedRoot
    panel.message = destination == .custom
      ? L10n.text("选择 skills 文件夹，将在其中安装 viewin。")
      : L10n.format("将在 %@/viewin 安装。选择其上级目录时，会自动创建缺少的文件夹。", String(describing: suggested.path))
    panel.prompt = installAfterSelection ? L10n.text("安装") : L10n.text("选择")
    panel.canChooseFiles = false; panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
    panel.showsHiddenFiles = true
    var initial = displayedRoot
    while !FileManager.default.fileExists(atPath: initial.path) && initial.path != "/" {
      initial.deleteLastPathComponent()
    }
    panel.directoryURL = initial
    guard let window = WorkspaceSettingsWindow.shared.window else { return }
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      do {
        self.bookmark = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
        let suffix: String
        if self.destination != .custom && suggested.path.hasPrefix(url.path + "/") {
          suffix = String(suggested.path.dropFirst(url.path.count + 1))
        } else { suffix = "" }
        self.defaults.set(self.bookmark, forKey: self.bookmarkKey)
        self.defaults.set(suffix, forKey: self.bookmarkKey + ".suffix")
        self.authorizedRoot = url
        self.root = suffix.isEmpty ? url : url.appendingPathComponent(suffix, isDirectory: true)
        self.message = nil; self.failed = false
        self.status = self.installer.status(in: self.root ?? url)
        if installAfterSelection { self.install() }
      } catch { self.report(error) }
    }
  }

  func install() {
    guard let root, bookmark != nil else { chooseDirectory(installAfterSelection: true); return }
    let authorization = authorizedRoot ?? root
    let accessed = authorization.startAccessingSecurityScopedResource()
    defer { if accessed { authorization.stopAccessingSecurityScopedResource() } }
    do {
      try installer.install(in: root)
      status = installer.status(in: root)
      failed = false
      message = L10n.text("Skill 已安装。若 Agent 未显示，请新建会话或重启 Agent。移动 App 后请在这里更新。")
    } catch { report(error) }
  }

  func reveal() {
    guard let root else { return }
    let authorization = authorizedRoot ?? root
    let accessed = authorization.startAccessingSecurityScopedResource()
    defer { if accessed { authorization.stopAccessingSecurityScopedResource() } }
    NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent("viewin")])
  }

  func copyCommand() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(AgentSkillInstaller.shellQuote(installer.executable.path) + " --list", forType: .string)
    failed = false; message = L10n.text("已复制 CLI 命令，可直接在终端或 Agent 中运行。")
  }

  private func report(_ error: Error) {
    failed = true; message = error.localizedDescription
    logger.error("Skill installation failed: \(error.localizedDescription, privacy: .public)")
  }
}

struct AgentSettingsView: View {
  @State private var model = AgentSettingsModel()

  var body: some View {
    Form {
      Section {
        Text(L10n.text("让 Agent 通过 CLI 查看 App 布局，无需打开 Viewin，也无需配置 MCP。"))
          .font(.callout).foregroundStyle(.secondary)
        Picker(L10n.text("安装位置"), selection: $model.destination) {
          ForEach(AgentSkillInstaller.Destination.allCases) { destination in
            Text(destination.title).tag(destination)
          }
        }.onChange(of: model.destination) { _, _ in model.refreshDestination() }
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(model.displayedRoot.appendingPathComponent("viewin").path)
              .font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if model.root == nil {
              Text(L10n.text("首次安装需选择并授权 skills 文件夹。"))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Spacer(minLength: 8)
          Button(L10n.text("选择目录…")) { model.chooseDirectory(installAfterSelection: false) }
        }
        HStack {
          Label(statusTitle, systemImage: model.status == .installed ? "checkmark.circle.fill" : "info.circle")
            .font(.callout).foregroundStyle(.secondary)
          Spacer()
          if model.status == .installed || model.status == .needsUpdate {
            Button(L10n.text("在 Finder 中显示")) { model.reveal() }
          }
          Button(model.status == .installed || model.status == .needsUpdate ? L10n.text("更新 Skill") : L10n.text("安装 Skill…")) {
            model.install()
          }.disabled(!model.installer.cliAvailable || model.status == .conflict)
        }
      } header: { Text("Agent Skill") } footer: {
        Text(L10n.text("通用目录适用于支持 ~/.agents/skills 的 Agent；Claude Code 可选择其专用目录。同一 Agent 安装一份即可。"))
      }
      Section("CLI") {
        LabeledContent(L10n.text("随 App 提供"), value: model.installer.cliAvailable ? L10n.text("已就绪") : L10n.text("缺失"))
        Button(L10n.text("复制 CLI 命令")) { model.copyCommand() }.disabled(!model.installer.cliAvailable)
      }
      if let message = model.message {
        Section {
          Text(message).font(.callout).foregroundStyle(model.failed ? Color.red : Color.secondary)
            .textSelection(.enabled)
        }
      }
    }.formStyle(.grouped)
  }

  private var statusTitle: String {
    switch model.status {
    case .notInstalled: L10n.text("尚未安装")
    case .installed: L10n.text("已安装")
    case .needsUpdate: L10n.text("需要更新")
    case .conflict: L10n.text("目录中已有同名 Skill，请更换目录")
    }
  }
}
