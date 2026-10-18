import Foundation

public enum WorkspacePreferences {
  public static func cardKey(_ id: String) -> String {
    "viewin_inspector_card_" + id.utf8.map { String(format: "%02x", $0) }.joined()
      + "_expanded"
  }

  /// Current settings win, followed by UI Inspector, then older InView preferences.
  public static func migrate(
    _ defaults: UserDefaults, legacyDomain: String? = nil, legacyDomains: [String] = []
  ) {
    for domain in legacyDomains + (legacyDomain.map { [$0] } ?? []) {
      guard let old = defaults.persistentDomain(forName: domain) else { continue }
      for (key, value) in old where defaults.object(forKey: key) == nil {
        if key.hasPrefix("uiinspector_") || key.hasPrefix("inview_")
          || key.hasPrefix("inspector.") || key == "preview.showBounds"
          || key == "hierarchy.doubleClickBehavior"
        {
          defaults.set(value, forKey: key)
        }
      }
    }
    for prefix in ["uiinspector_", "inview_"] {
      for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
        let new = "viewin_" + key.dropFirst(prefix.count)
        if defaults.object(forKey: new) == nil { defaults.set(value, forKey: new) }
      }
    }
    let keys = [
      "preview.showBounds": "viewin_preview_showBounds",
      "hierarchy.doubleClickBehavior": "viewin_hierarchy_doubleClickBehavior",
      "inspector.colorFormat": "viewin_inspector_colorFormat",
      "inspector.sectionOverrides": "viewin_inspector_sectionOverrides",
    ]
    for (old, new) in keys where defaults.object(forKey: new) == nil {
      if let value = defaults.object(forKey: old) { defaults.set(value, forKey: new) }
    }
    for (key, value) in defaults.dictionaryRepresentation()
    where key.hasPrefix("inspector.card.") && key.hasSuffix(".expanded") {
      let id = String(key.dropFirst("inspector.card.".count).dropLast(".expanded".count))
      if defaults.object(forKey: cardKey(id)) == nil { defaults.set(value, forKey: cardKey(id)) }
    }
  }
}
