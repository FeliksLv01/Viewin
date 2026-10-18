import Foundation
import Observation
import ViewinSnapshot

@MainActor @Observable public final class InspectorFeature {
  public var search = ""
  public var colorFormat: String {
    didSet { defaults.set(colorFormat, forKey: "viewin_inspector_colorFormat") }
  }
  public var sectionOverrides: Data {
    didSet { defaults.set(sectionOverrides, forKey: "viewin_inspector_sectionOverrides") }
  }
  public private(set) var cards: [String: InspectorCardFeature] = [:]
  @ObservationIgnored private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    colorFormat = defaults.string(forKey: "viewin_inspector_colorFormat") ?? "rgba"
    sectionOverrides = defaults.data(forKey: "viewin_inspector_sectionOverrides") ?? Data()
    prepareCards(nil)
  }
  public func prepareCards(_ document: SnapshotDocument?) {
    let ids = Set(
      ["Class", "Relation", "Layout", "View / Layer", "节点关联"]
        + (document?.snapshot.nodes.flatMap { $0.properties.map(\.id) } ?? []))
    cards = cards.filter { ids.contains($0.key) }
    for id in ids where cards[id] == nil {
      cards[id] = InspectorCardFeature(id: id, defaultExpanded: id != "Class", defaults: defaults)
    }
  }
  public enum Action: Sendable {
    case searchChanged(String)
    case colorFormatChanged(String)
    case sectionOverridesChanged(Data)
  }
  public func send(_ action: Action) {
    switch action {
    case .searchChanged(let value): if search != value { search = value }
    case .colorFormatChanged(let value): colorFormat = value
    case .sectionOverridesChanged(let value): sectionOverrides = value
    }
  }
}
