import Foundation
import Observation
import ViewinSnapshot

/// Coordinates feature references and asynchronous IO; no generic store or effect runtime.
@MainActor @Observable public final class WorkspaceFeature {
  public private(set) var content: WorkspaceContent?
  public let hierarchy: HierarchyFeature
  public let preview: PreviewFeature
  public let inspector: InspectorFeature
  public let measurement: MeasurementFeature
  public let connection: ConnectionFeature
  public var errorMessage: String?
  public private(set) var openID: UUID?
  @ObservationIgnored private let client: WorkspaceClient
  @ObservationIgnored private var openTask: Task<Void, Never>?
  @ObservationIgnored private var saveTasks: [UUID: Task<Void, Never>] = [:]

  public init(
    content: WorkspaceContent? = nil, client: WorkspaceClient = .liveValue,
    defaults: UserDefaults = .standard
  ) {
    self.client = client
    hierarchy = HierarchyFeature(defaults: defaults)
    preview = PreviewFeature(defaults: defaults)
    inspector = InspectorFeature(defaults: defaults)
    measurement = MeasurementFeature()
    connection = ConnectionFeature(client: client)
    hierarchy.onSelectionChange = { [weak self] in
      guard let self else { return }
      self.measurement.selectionChanged(self.hierarchy.selectedNode != nil)
    }
    connection.willCapture = { [weak self] in self?.cancelOpen() }
    connection.didCapture = { [weak self] result in self?.accept(result) }
    if let content { install(content) }
  }
  deinit {
    openTask?.cancel()
    for task in saveTasks.values { task.cancel() }
  }

  public func install(_ content: WorkspaceContent) {
    let previousSize = hierarchy.window?.size
    self.content = content
    hierarchy.install(content)
    inspector.prepareCards(content.document)
    measurement.send(.windowResigned)
    measurement.send(.stop)
    measurement.selectionChanged(hierarchy.selectedNode != nil)
    if previousSize != hierarchy.window?.size { preview.camera.resetForNewContentSize() }
    preview.synchronizeControls()
    errorMessage = nil
  }
  public enum Action: Sendable {
    case hierarchy(HierarchyFeature.Action)
    case preview(PreviewFeature.Action)
    case measurement(MeasurementFeature.Action)
    case inspector(InspectorFeature.Action)
    case connection(ConnectionFeature.Action)
    case open(URL)
    case opened(UUID, Result<WorkspaceContent, SnapshotIssue>)
    case save(URL)
    case saveContent(WorkspaceContent, URL)
    case saved(String?)
    case errorChanged(String?)
  }
  public func send(_ action: Action) {
    switch action {
    case .hierarchy(let action): hierarchy.send(action)
    case .preview(let action): preview.send(action)
    case .measurement(let action): measurement.send(action)
    case .inspector(let action): inspector.send(action)
    case .connection(let action): connection.send(action)
    case .open(let url):
      cancelOpen()
      connection.send(.cancelCapture)
      connection.send(.stopDiscovery)
      let id = UUID()
      openID = id
      openTask = Task { [weak self, client] in
        do {
          let content = try await client.open(url)
          try Task.checkCancellation()
          self?.send(.opened(id, .success(content)))
        } catch is CancellationError {} catch {
          self?.send(.opened(id, .failure(SnapshotIssue(message: error.localizedDescription))))
        }
      }
    case .opened(let id, let result):
      guard openID == id else { return }
      openID = nil
      openTask = nil
      accept(result)
      if case .success = result { connection.connectedTarget = nil }
    case .save(let url):
      if let content { send(.saveContent(content, url)) }
    case .saveContent(let content, let url):
      let id = UUID()
      saveTasks[id] = Task { [weak self, client] in
        do {
          try await client.save(content, url)
          try Task.checkCancellation()
          self?.send(.saved(nil))
        } catch is CancellationError {} catch { self?.send(.saved(error.localizedDescription)) }
        self?.saveTasks[id] = nil
      }
    case .saved(let error), .errorChanged(let error): errorMessage = error
    }
  }
  private func accept(_ result: Result<WorkspaceContent, SnapshotIssue>) {
    switch result {
    case .success(let content): install(content)
    case .failure(let error): errorMessage = error.message
    }
  }
  private func cancelOpen() {
    openID = nil
    openTask?.cancel()
    openTask = nil
  }
}
