import Foundation

/// Shared UI strings for SwiftUI, AppKit, and errors. Runtime app data is never translated.
public enum L10n {
  // Resolve explicitly so the standalone CLI uses the same languages as the app,
  // even though a command-line executable has no localized main bundle.
  private static let preferredBundle = localizedBundle(
    preferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages)

  public static func text(_ key: String, locale: Locale? = nil) -> String {
    let bundle = locale.map { localizedBundle(preferences: [$0.identifier]) } ?? preferredBundle
    return NSLocalizedString(key, bundle: bundle, comment: "")
  }

  public static func format(_ key: String, _ arguments: String..., locale: Locale? = nil) -> String {
    String(format: text(key, locale: locale), locale: locale ?? .current, arguments: arguments)
  }

  private static func localizedBundle(preferences: [String]) -> Bundle {
    let language = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferences).first ?? "en"
    return Bundle.module.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? .module
  }
}
