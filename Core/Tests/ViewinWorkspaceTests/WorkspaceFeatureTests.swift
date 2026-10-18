import Foundation
import Observation
import XCTest
import ViewinConnection
import ViewinSnapshot
import ViewinTestSupport
@testable import ViewinWorkspace

@MainActor final class WorkspaceFeatureTests: XCTestCase {
  private final class Counter: @unchecked Sendable { var value = 0 }
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "ViewinTests.\(UUID())")! }
  private func workspace() throws -> WorkspaceFeature {
    WorkspaceFeature(content: try WorkspaceContent(document: ExampleSnapshot.ios.load()), client: .testValue, defaults: defaults())
  }
  func testStartupHasNoOfflineContent() {
    let state = WorkspaceFeature(client: .testValue, defaults: defaults())
    XCTAssertNil(state.content)
    XCTAssertNil(state.hierarchy.selectedId)
  }
  func testCameraAndHoverDoNotInvalidateUnrelatedSubscriptions() throws {
    let state = try workspace()
    let changes = Counter(); let tree = Counter()
    withObservationTracking {
      _ = state.content; _ = state.inspector.search; _ = state.connection.targets
      _ = state.preview.controls.mode; _ = state.preview.controls.zoom
      _ = state.preview.controls.layerSpacing; _ = state.hierarchy.selectedNode
    } onChange: { changes.value += 1 }
    withObservationTracking { _ = state.hierarchy.hoveredId } onChange: { tree.value += 1 }
    for _ in 0..<500 { state.preview.send(.scroll(x: 1, y: 1, command: false)) }
    state.hierarchy.send(.hover("button"))
    XCTAssertEqual(changes.value, 0)
    XCTAssertEqual(tree.value, 1)
    XCTAssertTrue(state.content === state.hierarchy.content)
    state.hierarchy.send(.select("button"))
    XCTAssertEqual(changes.value, 1)
  }
  func testInspectorEditsDoNotInvalidatePreviewOrTree() throws {
    let state = try workspace(); let changes = Counter()
    withObservationTracking {
      _ = state.hierarchy.selectedId; _ = state.hierarchy.expanded; _ = state.preview.camera
    } onChange: { changes.value += 1 }
    state.inspector.send(.searchChanged("Frame")); state.inspector.send(.colorFormatChanged("hex"))
    XCTAssertEqual(changes.value, 0)
  }
  func testMeasurementTracksSelectionAndHoverAndSurvivesBothPreviewModes() throws {
    let state = try workspace()
    state.measurement.send(.toggleLock)
    state.hierarchy.send(.select("button")); state.hierarchy.send(.hover("card"))
    state.preview.send(.modeChanged(.twoD)); state.preview.send(.modeChanged(.threeD))
    XCTAssertEqual(state.hierarchy.selectedId, "button")
    XCTAssertEqual(state.measurement.mode, .locked)
    state.hierarchy.send(.select(nil))
    XCTAssertFalse(state.measurement.isActive)
  }
  func testDoubleClickBothSourcesUseSavedPolicyAndPreserveScope() throws {
    let state = try workspace().hierarchy
    state.send(.doubleClicked("card")); XCTAssertEqual(state.pendingDoubleClickId, "card")
    state.send(.doubleClickChoice("collapse")); XCTAssertFalse(state.expanded.contains("card"))
    state.send(.doubleClicked("card")); XCTAssertTrue(state.expanded.contains("card"))
    state.send(.doubleClickBehaviorChanged("focus")); state.send(.doubleClicked("card"))
    XCTAssertEqual(state.focusRootId, "card"); state.send(.endScope)
    XCTAssertNil(state.focusRootId); XCTAssertTrue(state.expanded.contains("card"))
  }
  func testCancelledDiscoveryIgnoresLateResultAndKeepsCooldown() {
    var client = WorkspaceClient.testValue; client.now = { 10 }
    let state = ConnectionFeature(client: client)
    state.send(.discover(force: false)); let id = state.scanID!
    state.send(.stopDiscovery); state.send(.discovered(id, [target]))
    XCTAssertTrue(state.targets.isEmpty)
    state.send(.discover(force: true)); XCTAssertNil(state.scanID)
  }
  func testSupersededFileResponseCannotReplaceContent() throws {
    let state = try workspace(); let original = state.content
    let content = try WorkspaceContent(document: ExampleSnapshot.android.load())
    state.send(.opened(UUID(), .success(content)))
    XCTAssertTrue(state.content === original)
  }
  func testCardDisclosureIsIsolatedFromOtherCardsAndInspector() throws {
    let state = try workspace().inspector
    let first = try XCTUnwrap(state.cards["Class"])
    let other = try XCTUnwrap(state.cards["Layout"])
    let changes = Counter()
    withObservationTracking { _ = other.expanded; _ = state.colorFormat; _ = state.search; _ = state.cards["Layout"] } onChange: { changes.value += 1 }
    first.send(.expandedChanged(!first.expanded))
    XCTAssertEqual(changes.value, 0)
    first.send(.searchExpandedChanged(false)); first.send(.queryChanged)
    XCTAssertTrue(first.searchExpanded)
  }
  func testPreferencesMigrationPreservesExistingValuesAndCardIDs() {
    let settings = defaults()
    settings.set(false, forKey: "inview_preview_showBounds")
    settings.set("hex", forKey: "inview_inspector_colorFormat")
    settings.set(true, forKey: "inspector.card.Layout.a/b.expanded")
    WorkspacePreferences.migrate(settings)
    XCTAssertEqual(settings.object(forKey: "viewin_preview_showBounds") as? Bool, false)
    XCTAssertEqual(settings.string(forKey: "viewin_inspector_colorFormat"), "hex")
    XCTAssertTrue(settings.bool(forKey: WorkspacePreferences.cardKey("Layout.a/b")))
    XCTAssertFalse(WorkspacePreferences.cardKey("Layout.a/b").contains("."))
    settings.set("rgba", forKey: "viewin_inspector_colorFormat")
    WorkspacePreferences.migrate(settings)
    XCTAssertEqual(settings.string(forKey: "viewin_inspector_colorFormat"), "rgba")
  }
  func testUIInspectorPreferencesMigrateWithoutOverwritingViewinChoices() {
    let settings = defaults()
    let domain = "ViewinLegacyTests.\(UUID())"
    defer { settings.removePersistentDomain(forName: domain) }
    settings.setPersistentDomain([
      "uiinspector_preview_showBounds": false,
      "uiinspector_inspector_colorFormat": "hex",
      "uiinspector_inspector_card_4c61796f7574_expanded": false,
    ], forName: domain)
    settings.set("rgba", forKey: "viewin_inspector_colorFormat")
    WorkspacePreferences.migrate(settings, legacyDomains: [domain])
    XCTAssertEqual(settings.object(forKey: "viewin_preview_showBounds") as? Bool, false)
    XCTAssertEqual(settings.string(forKey: "viewin_inspector_colorFormat"), "rgba")
    XCTAssertEqual(settings.object(forKey: WorkspacePreferences.cardKey("Layout")) as? Bool, false)
  }
  private var target: InspectionTarget { .init(port: 48721, appName: "Demo", appId: "demo", deviceName: "Simulator", osVersion: "27") }
  func testCaptureResponseInstallsOneSharedContentAndStaleResponseIsIgnored() async throws {
    let content = try WorkspaceContent(document: ExampleSnapshot.ios.load())
    var client = WorkspaceClient.testValue; client.capture = { _ in content }
    let state = WorkspaceFeature(client: client, defaults: defaults())
    state.connection.send(.capture(target))
    for _ in 0..<200 where state.connection.isCapturing { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertFalse(state.connection.isCapturing)
    XCTAssertTrue(state.content === content); XCTAssertTrue(state.hierarchy.content === content)
    XCTAssertEqual(state.connection.connectedTarget, target)
    state.connection.send(.captured(UUID(), .success(try WorkspaceContent(document: ExampleSnapshot.android.load()))))
    XCTAssertTrue(state.content === content)
  }
  func testEmptyDiscoveryCacheDoesNotHideNewlyStartedApps() {
    var client = WorkspaceClient.testValue; client.now = { 4 }
    let state = ConnectionFeature(client: client)
    _ = state.schedule.begin(at: 0); state.schedule.completed(at: 1)
    state.send(.discover(force: false)); XCTAssertNotNil(state.scanID)
    state.send(.discovered(state.scanID!, []))
    state.send(.discover(force: false)); XCTAssertNil(state.scanID)
  }
  func testSuccessfulDiscoveryStillUsesThirtySecondCache() {
    var client = WorkspaceClient.testValue; client.now = { 4 }
    let state = ConnectionFeature(client: client)
    state.targets = [target]; _ = state.schedule.begin(at: 0); state.schedule.completed(at: 1)
    state.send(.discover(force: false)); XCTAssertNil(state.scanID)
  }
  func testStartupDiscoveryAutomaticallyCapturesSingleApp() throws {
    let state = ConnectionFeature(client: .testValue)
    state.send(.discover(force: false, autoSelectSingle: true))
    let request = try XCTUnwrap(state.scanID)
    state.send(.discovered(request, [target]))
    XCTAssertTrue(state.isCapturing)
    XCTAssertEqual(state.capturingTarget, target)
    state.send(.cancelCapture)
  }
  func testDiscoveryKeepsChoiceForMultipleAppsAndToolbarRefresh() throws {
    let second = InspectionTarget(port: 48722, appName: "Second", appId: "second",
                                  deviceName: "Simulator", osVersion: "27")
    for (autoSelect, targets) in [(true, [target, second]), (false, [target]), (true, [])] {
      let state = ConnectionFeature(client: .testValue)
      state.send(.discover(force: false, autoSelectSingle: autoSelect))
      let request = try XCTUnwrap(state.scanID)
      state.send(.discovered(request, targets))
      XCTAssertFalse(state.isCapturing)
      XCTAssertEqual(state.targets, targets)
    }
  }
  func testPreferencesPersistAcrossFeatureInstances() {
    let settings = defaults()
    let state = PreviewFeature(defaults: settings); state.send(.boundsChanged(false))
    XCTAssertFalse(PreviewFeature(defaults: settings).showBounds)
    let inspector = InspectorFeature(defaults: settings); inspector.send(.colorFormatChanged("hex"))
    XCTAssertEqual(InspectorFeature(defaults: settings).colorFormat, "hex")
  }
}
