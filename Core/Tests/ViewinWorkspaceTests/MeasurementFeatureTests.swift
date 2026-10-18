import Observation
import XCTest
import ViewinSnapshot
import ViewinTestSupport
@testable import ViewinWorkspace

@MainActor final class MeasurementFeatureTests: XCTestCase {
  func testOptionHoldAndReleaseIsTemporary() {
    let state = MeasurementFeature(); state.selectionChanged(true)
    state.send(.optionChanged(true)); XCTAssertEqual(state.mode, .temporary)
    state.send(.optionChanged(false)); XCTAssertEqual(state.mode, .off)
  }
  func testTemporaryCanBeLockedAndReleaseOrWindowChangeDoesNotUnlockIt() {
    let state = MeasurementFeature(); state.selectionChanged(true)
    state.send(.optionChanged(true)); state.send(.cancelOnKeyUpChanged(false))
    state.send(.optionChanged(false)); state.send(.windowResigned)
    XCTAssertEqual(state.mode, .locked)
    state.send(.toggleLock); XCTAssertEqual(state.mode, .off)
  }
  func testWindowDeactivationClearsHeldOptionAndTemporaryMode() {
    let state = MeasurementFeature(); state.selectionChanged(true); state.send(.optionChanged(true))
    state.send(.windowResigned); XCTAssertFalse(state.optionHeld); XCTAssertEqual(state.mode, .off)
  }
  func testOptionWithoutSelectionDoesNotStartButButtonCanShowTutorial() {
    let state = MeasurementFeature(); state.send(.optionChanged(true)); XCTAssertEqual(state.mode, .off)
    state.send(.toggleLock); XCTAssertEqual(state.mode, .locked)
  }
  func testRecursivePreviewHidingDimsDescendantsAndRestoringChildRestoresAncestors() throws {
    let content = try WorkspaceContent(document: ExampleSnapshot.ios.load())
    let state = HierarchyFeature(content: content)
    state.hiddenPreviewIds = ["card"]
    let child = try XCTUnwrap(content.document.children(of: try XCTUnwrap(content.document.node("card"))).first)
    XCTAssertTrue(state.isPreviewHidden(child.id)); state.send(.togglePreview(child.id))
    XCTAssertFalse(state.isPreviewHidden("card")); XCTAssertFalse(state.isPreviewHidden(child.id))
  }
  func testMeasurementHoverDoesNotInvalidateInspectorOrCameraOrRootContent() throws {
    let content = try WorkspaceContent(document: ExampleSnapshot.ios.load())
    let state = WorkspaceFeature(content: content, client: .testValue)
    let counter = Counter()
    withObservationTracking { _ = state.content; _ = state.hierarchy.selectedNode; _ = state.preview.camera; _ = state.inspector.search } onChange: { counter.value += 1 }
    state.measurement.send(.toggleLock)
    for id in ["card", "button", "root", "window"] { state.hierarchy.send(.hover(id)) }
    XCTAssertEqual(counter.value, 0); XCTAssertEqual(state.measurement.mode, .locked)
  }
  private final class Counter: @unchecked Sendable { var value = 0 }
}
