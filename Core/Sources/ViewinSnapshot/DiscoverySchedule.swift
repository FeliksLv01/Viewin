import Foundation

/// Monotonic timestamps, supplied by the host, keep UI lifecycle events from causing scan bursts.
public struct DiscoverySchedule: Sendable, Equatable {
  private var lastAttempt: TimeInterval?
  private var lastCompletion: TimeInterval?
  public init() {}

  public mutating func begin(at now: TimeInterval, force: Bool = false) -> Bool {
    if let lastAttempt, now - lastAttempt < 3 { return false }
    if !force, let lastCompletion, now - lastCompletion < 30 { return false }
    lastAttempt = now
    return true
  }

  public mutating func completed(at now: TimeInterval) { lastCompletion = now }
}
