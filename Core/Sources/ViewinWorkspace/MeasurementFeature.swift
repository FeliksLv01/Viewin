import Foundation
import Observation

@MainActor @Observable public final class MeasurementFeature {
  public enum Mode: Equatable, Sendable { case off, temporary, locked }

  public var mode = Mode.off
  public var optionHeld = false
  public var hasSelection = false
  public var isActive: Bool { mode != .off }
  public init() {}

  /// Selection is a projection of HierarchyFeature, never a second measurement anchor.
  public func selectionChanged(_ available: Bool) {
    guard hasSelection != available else { return }
    hasSelection = available
    if !available { mode = .off } else if optionHeld && mode == .off { mode = .temporary }
  }

  public enum Action: Sendable {
    case toggleLock
    case optionChanged(Bool)
    case cancelOnKeyUpChanged(Bool)
    case windowResigned
    case stop
  }
  public func send(_ action: Action) {
    switch action {
    case .toggleLock: self.mode = self.isActive ? .off : .locked
    case .optionChanged(let held):
      guard self.optionHeld != held else { return }
      self.optionHeld = held
      if self.mode != .locked { self.mode = held && self.hasSelection ? .temporary : .off }
    case .cancelOnKeyUpChanged(let cancel):
      self.mode = cancel && self.optionHeld ? .temporary : (cancel ? .off : .locked)
    case .windowResigned:
      self.optionHeld = false
      if self.mode == .temporary { self.mode = .off }
    case .stop: self.mode = .off
    }
  }
}
