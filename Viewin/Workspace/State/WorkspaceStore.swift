import AppKit
import Observation
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace
import UniformTypeIdentifiers

/// AppKit command/binding adapter over independent native observable feature references.
@MainActor final class WorkspaceStore {
  let menuState = WorkspaceMenuState()
  let store: WorkspaceFeature
  let hierarchyStore: HierarchyFeature
  let previewStore: PreviewFeature
  let inspectorStore: InspectorFeature
  let connectionStore: ConnectionFeature
  let measurementStore: MeasurementFeature

  init() {
    let suffix = Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true ? ".debug" : ""
    WorkspacePreferences.migrate(
      .standard,
      legacyDomains: ["com.felikslv.UIInspector" + suffix, "com.felikslv.InView" + suffix])
    let store = WorkspaceFeature()
    self.store = store
    hierarchyStore = store.hierarchy
    previewStore = store.preview
    inspectorStore = store.inspector
    connectionStore = store.connection
    measurementStore = store.measurement
  }
  var targets: [InspectionTarget] { connectionStore.targets }
  var connectedTarget: InspectionTarget? { connectionStore.connectedTarget }
  var isScanning: Bool { connectionStore.isScanning }
  var isCapturing: Bool { connectionStore.isCapturing }
  var document: SnapshotDocument? { store.content?.document }
  var contentID: ObjectIdentifier? { store.content.map(ObjectIdentifier.init) }
  var nodeImages: [String: NSImage] { store.content?.images ?? [:] }
  var selectedId: String? {
    get { hierarchyStore.selectedId }
    set { store.send(.hierarchy(.select(newValue))) }
  }
  var windowId: String { hierarchyStore.windowId }
  var search: String {
    get { hierarchyStore.searchText }
    set { store.send(.hierarchy(.searchChanged(newValue))) }
  }
  var searchQuery: String { hierarchyStore.searchQuery }
  var searchIncludedIds: Set<String>? { hierarchyStore.searchIncludedIds }
  var focusRootId: String? { hierarchyStore.focusRootId }
  var hoveredId: String? { hierarchyStore.hoveredId }
  var hiddenPreviewIds: Set<String> { hierarchyStore.hiddenPreviewIds }
  var showHidden: Bool {
    get { hierarchyStore.showHidden }
    set { store.send(.hierarchy(.showHiddenChanged(newValue))) }
  }
  var expansionLevel: Int { hierarchyStore.expansionLevel }
  var doubleClickBehavior: String {
    get { hierarchyStore.doubleClickBehavior }
    set { store.send(.hierarchy(.doubleClickBehaviorChanged(newValue))) }
  }
  var expanded: Set<String> { hierarchyStore.expanded }
  var hierarchy: HierarchyPresentation? { hierarchyStore.content?.hierarchy }
  var previewHierarchy: HierarchyPresentation? { hierarchyStore.previewHierarchy }
  var showBounds: Bool {
    get { previewStore.showBounds }
    set { store.send(.preview(.boundsChanged(newValue))) }
  }
  var camera: PreviewCamera { previewStore.camera }
  var zoom: Double {
    get { previewStore.controls.zoom }
    set { store.send(.preview(.zoomChanged(newValue))) }
  }
  var viewMode: String {
    get { previewStore.controls.mode.rawValue }
    set { store.send(.preview(.modeChanged(PreviewCamera.Mode(rawValue: newValue) ?? .threeD))) }
  }
  var freeRotation: Bool {
    get { previewStore.controls.freeRotation }
    set { store.send(.preview(.freeRotationChanged(newValue))) }
  }
  var layerSpacing: Double {
    get { previewStore.controls.layerSpacing }
    set { store.send(.preview(.spacingChanged(newValue))) }
  }
  var isMeasuring: Bool { measurementStore.isActive }
  var hoveredNode: SnapshotNode? { hoveredId.flatMap { document?.node($0) } }
  var errorMessage: String? {
    get { store.errorMessage }
    set { store.send(.errorChanged(newValue)) }
  }
  var selectedNode: SnapshotNode? { hierarchyStore.selectedNode }
  var window: SnapshotWindow? { hierarchyStore.window }
  var visibleHierarchyIndices: [Int] { hierarchyStore.visibleHierarchyIndices }

  func binding<Value>(_ keyPath: ReferenceWritableKeyPath<WorkspaceStore, Value>) -> Binding<Value>
  {
    Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
  }
  func discoverTargets(force: Bool = false, autoSelectSingle: Bool = false) {
    connectionStore.send(.discover(force: force, autoSelectSingle: autoSelectSingle))
  }
  func stopDiscovery() { connectionStore.send(.stopDiscovery) }
  func capture(_ target: InspectionTarget) { connectionStore.send(.capture(target)) }
  func refresh() {
    if let target = connectedTarget {
      capture(target)
    }
  }
  func open(_ url: URL) { store.send(.open(url)) }
  func select(_ node: SnapshotNode) { hierarchyStore.send(.reveal(node.id)) }
  func selectRelated(_ node: SnapshotNode) {
    if searchIncludedIds?.contains(node.id) == false { search = "" }
    if let root = focusRootId, root != node.id,
       document?.ancestors(of: node).contains(where: { $0.id == root }) == false { endScope() }
    select(node)
  }
  func hover(_ id: String?) {
    guard hoveredId != id else { return }
    hierarchyStore.send(.hover(id))
  }
  func focus(_ id: String) { hierarchyStore.send(.focus(id)) }
  func endScope() { hierarchyStore.send(.endScope) }
  func doubleClick(_ id: String) { hierarchyStore.send(.doubleClicked(id)) }
  func setExpansionLevel(_ level: Int) { hierarchyStore.send(.expansionLevelChanged(level)) }
  func togglePreview(_ id: String) { hierarchyStore.send(.togglePreview(id)) }
  func restorePreviews() { hierarchyStore.send(.restorePreviews) }
  func toggleExpansion(_ id: String) { hierarchyStore.send(.toggleExpansion(id)) }
  func navigateSelection(_ key: UInt16) { hierarchyStore.send(.navigate(key)) }
  func expandSubtree(_ id: String, fully: Bool = false) {
    hierarchyStore.send(.expandSubtree(id, fully: fully))
  }
  func collapseSubtree(_ id: String) { hierarchyStore.send(.collapseSubtree(id)) }
  func isPreviewHidden(_ id: String) -> Bool { hierarchyStore.isPreviewHidden(id) }
  func toggleMeasurement() { measurementStore.send(.toggleLock) }
  func resetCamera() { previewStore.send(.reset) }
  func drag(_ start: PreviewCamera.Drag, x: Double, y: Double) {
    previewStore.send(.drag(start, x: x, y: y))
  }
  func scroll(x: Double, y: Double, command: Bool) {
    guard x != 0 || y != 0 else { return }
    previewStore.send(.scroll(x: x, y: y, command: command))
  }
  func magnify(_ amount: Double) {
    guard amount != 0 else { return }
    previewStore.send(.magnify(amount))
  }

  func saveSnapshot() {
    guard let content = store.content else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.viewinSnapshot]
    panel.nameFieldStringValue =
      content.document.snapshot.target.appName.replacingOccurrences(of: "/", with: "-")
      + ".viewin"
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      // Capture the document being saved when the panel opened, even if the user changes targets.
      self?.store.send(.saveContent(content, url))
    }
  }
}

/// App selection presentation is separate from inspection state.
@MainActor @Observable final class WorkspaceMenuState {
  var appPickerPresented = false
}
