import Foundation
import Observation
import OSLog
import Sparkle
import SwiftUI
import ViewinSnapshot

/// Sparkle owns scheduling, preferences, download verification, and installation.
@MainActor @Observable final class AppUpdater {
  static let shared = AppUpdater()
  private let controller: SPUStandardUpdaterController
  private var observations: [NSKeyValueObservation] = []
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.viewin", category: "Updates")
  private(set) var canCheck = false
  private(set) var automaticChecks = false
  private(set) var lastCheck: Date?
  let enabled: Bool
  let configured: Bool

  private init() {
    let info = Bundle.main.infoDictionary ?? [:]
    enabled = (info["ViewinUpdatesEnabled"] as? String) == "YES"
    let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
    let key = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
    configured = feed?.scheme == "https" && feed?.host != nil && key?.count == 32
    controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    guard enabled && configured else { return }
    let updater = controller.updater
    observations = [
      updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
        let value = updater.canCheckForUpdates
        Task { @MainActor [weak self] in self?.canCheck = value }
      },
      updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
        let value = updater.automaticallyChecksForUpdates
        Task { @MainActor [weak self] in self?.automaticChecks = value }
      },
      updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
        let value = updater.lastUpdateCheckDate
        Task { @MainActor [weak self] in self?.lastCheck = value }
      },
    ]
    controller.startUpdater()
  }

  func check() {
    guard canCheck else { return }
    logger.info("User requested an update check")
    controller.checkForUpdates(nil)
  }

  func setAutomaticChecks(_ value: Bool) {
    guard enabled && configured else { return }
    controller.updater.automaticallyChecksForUpdates = value
  }
}

struct UpdateSettingsView: View {
  private let updater = AppUpdater.shared
  var body: some View {
    Form {
      Section {
        LabeledContent(L10n.text("当前版本"), value: version)
        Toggle(L10n.text("自动检查更新"), isOn: Binding(
          get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }
        )).disabled(!updater.enabled || !updater.configured)
        if let date = updater.lastCheck {
          LabeledContent(L10n.text("上次检查")) { Text(date, format: .dateTime) }
        }
        Button(L10n.text("检查更新…")) { updater.check() }.disabled(!updater.canCheck)
      } header: { Text(L10n.text("软件更新")) } footer: {
        Text(!updater.enabled ? L10n.text("Debug 构建不执行应用更新。请在正式版中检查更新。")
             : !updater.configured ? L10n.text("更新源尚未配置完成。")
             : L10n.text("更新通过 GitHub Releases 分发，并验证更新签名。自动检查使用 Sparkle 的调度，无需持续扫描。"))
      }
    }.formStyle(.grouped)
  }
  private var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "\(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
  }
}
