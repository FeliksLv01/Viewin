import Foundation
import Observation
import ViewinConnection
import ViewinSnapshot

@MainActor @Observable public final class ConnectionFeature {
  public var targets: [InspectionTarget] = []
  public var connectedTarget: InspectionTarget?
  public private(set) var scanID: UUID?
  public private(set) var captureID: UUID?
  public private(set) var capturingTarget: InspectionTarget?
  public var schedule = DiscoverySchedule()
  public var isScanning: Bool { scanID != nil }
  public var isCapturing: Bool { captureID != nil }
  @ObservationIgnored private let client: WorkspaceClient
  @ObservationIgnored private var autoSelectSingle = false
  @ObservationIgnored private var discoveryTask: Task<Void, Never>?
  @ObservationIgnored private var captureTask: Task<Void, Never>?
  @ObservationIgnored public var willCapture: (() -> Void)?
  @ObservationIgnored public var didCapture: ((Result<WorkspaceContent, SnapshotIssue>) -> Void)?
  public init(client: WorkspaceClient = .liveValue) { self.client = client }
  deinit {
    discoveryTask?.cancel()
    captureTask?.cancel()
  }
  public enum Action: Sendable {
    case discover(force: Bool, autoSelectSingle: Bool = false)
    case stopDiscovery
    case capture(InspectionTarget)
    case cancelCapture
    case discovered(UUID, [InspectionTarget])
    case captured(UUID, Result<WorkspaceContent, SnapshotIssue>)
  }
  public func send(_ action: Action) {
    switch action {
    case .discover(let force, let autoSelectSingle):
      guard !isScanning, !isCapturing,
        schedule.begin(at: client.now(), force: force || targets.isEmpty)
      else { return }
      let id = UUID()
      scanID = id
      self.autoSelectSingle = autoSelectSingle
      discoveryTask?.cancel()
      discoveryTask = Task { [weak self, client] in
        let targets = await client.discover()
        guard !Task.isCancelled else { return }
        self?.send(.discovered(id, targets))
      }
    case .stopDiscovery:
      autoSelectSingle = false
      scanID = nil
      discoveryTask?.cancel()
      discoveryTask = nil
    case .discovered(let id, let targets):
      guard scanID == id else { return }
      let shouldEnter = autoSelectSingle && targets.count == 1
      autoSelectSingle = false
      self.targets = targets
      scanID = nil
      discoveryTask = nil
      schedule.completed(at: client.now())
      if shouldEnter, let target = targets.first { send(.capture(target)) }
    case .capture(let target):
      guard !isCapturing else { return }
      willCapture?()
      send(.stopDiscovery)
      let id = UUID()
      captureID = id
      capturingTarget = target
      captureTask = Task { [weak self, client] in
        do {
          let content = try await client.capture(target)
          try Task.checkCancellation()
          self?.send(.captured(id, .success(content)))
        } catch is CancellationError {} catch {
          self?.send(.captured(id, .failure(SnapshotIssue(message: error.localizedDescription))))
        }
      }
    case .cancelCapture:
      captureID = nil
      capturingTarget = nil
      captureTask?.cancel()
      captureTask = nil
    case .captured(let id, let result):
      guard captureID == id else { return }
      if case .success = result { connectedTarget = capturingTarget }
      captureID = nil
      capturingTarget = nil
      captureTask = nil
      didCapture?(result)
    }
  }
}
