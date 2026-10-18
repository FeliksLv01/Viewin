import Foundation
import Observation

/// Stable per-card reference: expanding a disclosure only notifies that card's readers.
@MainActor @Observable public final class InspectorCardFeature: Identifiable {
  public let id: String
  public var expanded: Bool {
    didSet { defaults.set(expanded, forKey: WorkspacePreferences.cardKey(id)) }
  }
  public var searchExpanded = true
  @ObservationIgnored private let defaults: UserDefaults
  public init(id: String, defaultExpanded: Bool, defaults: UserDefaults = .standard) {
    self.id = id
    self.defaults = defaults
    expanded = defaults.object(forKey: WorkspacePreferences.cardKey(id)) as? Bool ?? defaultExpanded
  }
  public enum Action: Sendable {
    case expandedChanged(Bool)
    case searchExpandedChanged(Bool)
    case queryChanged
  }
  public func send(_ action: Action) {
    switch action {
    case .expandedChanged(let value): expanded = value
    case .searchExpandedChanged(let value): searchExpanded = value
    case .queryChanged: searchExpanded = true
    }
  }
}
