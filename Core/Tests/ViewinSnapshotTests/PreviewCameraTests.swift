import XCTest

@testable import ViewinSnapshot

final class PreviewCameraTests: XCTestCase {
  func testLookinDefaultsAndPerspectiveScale() {
    let camera = PreviewCamera()
    XCTAssertEqual(camera.mode, .threeD)
    XCTAssertEqual(camera.yaw, 0.6)
    XCTAssertEqual(camera.pitch, 0)
    XCTAssertTrue(camera.freeRotation)
    XCTAssertEqual(camera.scale, 0.27)
    XCTAssertEqual(camera.focalLength, 73.217, accuracy: 0.00001)
    XCTAssertEqual(camera.layerDistance, 0.254, accuracy: 0.00001)
  }
  func testFreeRotationOffOnlyLocksVerticalAngle() {
    var camera = PreviewCamera()
    camera.drag(camera.beginDrag(translating: false), x: 20, y: 50)
    XCTAssertEqual(camera.yaw, 0.8, accuracy: 0.00001)
    XCTAssertEqual(camera.pitch, 0.2, accuracy: 0.00001)
    camera.setFreeRotation(false)
    XCTAssertEqual(camera.pitch, 0)
    XCTAssertTrue(camera.animated)
    camera.drag(camera.beginDrag(translating: false), x: 50, y: 500)
    XCTAssertEqual(camera.yaw, 1.3, accuracy: 0.00001)
    XCTAssertEqual(camera.pitch, 0)
    XCTAssertFalse(camera.animated)
    camera.setFreeRotation(true)
    XCTAssertEqual(camera.yaw, 1.3, accuracy: 0.00001)
    XCTAssertEqual(camera.pitch, -0.05)
  }
  func testModeSwitchRestoresRotationWithoutChangingScaleOrTranslation() {
    var camera = PreviewCamera()
    camera.scale = 0.4
    camera.drag(camera.beginDrag(translating: true), x: 70, y: -30)
    camera.drag(camera.beginDrag(translating: false), x: -100, y: 75)
    let before = camera
    camera.setMode(.twoD)
    XCTAssertEqual(camera.yaw, 0)
    XCTAssertEqual(camera.pitch, 0)
    XCTAssertEqual(camera.layerDistance, 0.01)
    XCTAssertEqual(camera.scale, before.scale)
    XCTAssertEqual(camera.translationX, before.translationX)
    XCTAssertEqual(camera.translationY, before.translationY)
    camera.drag(camera.beginDrag(translating: false), x: 100, y: 100)
    XCTAssertEqual(camera.yaw, 0)
    camera.setMode(.threeD)
    XCTAssertEqual(camera.yaw, before.yaw)
    XCTAssertEqual(camera.pitch, before.pitch)
    XCTAssertEqual(camera.scale, before.scale)
    XCTAssertEqual(camera.translationX, before.translationX)
  }
  func testNearFrontRotationGetsMinimumYawAndLockedModeRestoresFlatPitch() {
    var camera = PreviewCamera()
    camera.drag(camera.beginDrag(translating: false), x: -59, y: 80)
    camera.setMode(.twoD)
    camera.setFreeRotation(false)
    camera.setMode(.threeD)
    XCTAssertEqual(camera.yaw, 0.18)
    XCTAssertEqual(camera.pitch, 0)
    camera.drag(camera.beginDrag(translating: false), x: -20, y: 0)
    camera.setMode(.twoD)
    camera.setMode(.threeD)
    XCTAssertEqual(camera.yaw, -0.18)
  }
  func testDragUsesStartPositionAndCanRotateBeyondVerticalQuarterTurn() {
    var camera = PreviewCamera()
    let drag = camera.beginDrag(translating: false)
    camera.drag(drag, x: 10, y: 10)
    camera.drag(drag, x: 100, y: 500)
    XCTAssertEqual(camera.yaw, 1.6, accuracy: 0.00001)
    XCTAssertEqual(camera.pitch, 2, accuracy: 0.00001)
    camera.drag(drag, x: 1000, y: 2000)
    XCTAssertGreaterThanOrEqual(camera.yaw, -.pi)
    XCTAssertLessThanOrEqual(camera.yaw, .pi)
    XCTAssertGreaterThanOrEqual(camera.pitch, -.pi)
    XCTAssertLessThanOrEqual(camera.pitch, .pi)
  }
  func testSpaceDragAndWheelPanInBothModesWithoutChangingRotation() {
    for mode in [PreviewCamera.Mode.twoD, .threeD] {
      var camera = PreviewCamera()
      camera.setMode(mode)
      let yaw = camera.yaw
      let pitch = camera.pitch
      camera.scale = 0.5
      let start = camera.beginDrag(translating: true)
      camera.drag(start, x: 100, y: 50)
      XCTAssertEqual(camera.translationX, 0.54, accuracy: 0.00001)
      XCTAssertEqual(camera.translationY, -0.27, accuracy: 0.00001)
      camera.drag(start, x: 200, y: 100)
      XCTAssertEqual(camera.translationX, 1.08, accuracy: 0.00001)
      camera.scroll(x: 10, y: -10, command: false)
      XCTAssertEqual(camera.translationX, 1.34, accuracy: 0.00001)
      XCTAssertEqual(camera.translationY, -0.28, accuracy: 0.00001)
      XCTAssertEqual(camera.scale, 0.5)
      XCTAssertEqual(camera.yaw, yaw)
      XCTAssertEqual(camera.pitch, pitch)
    }
  }
  func testCommandWheelAndPinchUseLookinNormalizedScaleAndClamp() {
    var camera = PreviewCamera()
    camera.scroll(x: 100, y: -20, command: true)
    XCTAssertEqual(camera.scale, 0.37, accuracy: 0.00001)
    XCTAssertEqual(camera.translationX, 0)
    camera.magnify(0.1)
    XCTAssertEqual(camera.scale, 0.4, accuracy: 0.00001)
    camera.magnify(100)
    XCTAssertEqual(camera.scale, 1)
    camera.scroll(x: 0, y: 1000, command: true)
    XCTAssertEqual(camera.scale, 0)
    XCTAssertEqual(camera.focalLength, 20)
  }
  func testResetAndContentResizeHaveSeparateBehavior() {
    var camera = PreviewCamera()
    camera.scale = 0.8
    camera.drag(camera.beginDrag(translating: true), x: 100, y: 100)
    camera.resetForNewContentSize()
    XCTAssertEqual(camera.scale, 0.27)
    XCTAssertNotEqual(camera.translationX, 0)
    camera.setMode(.twoD)
    camera.reset()
    XCTAssertEqual(camera.mode, .twoD)
    XCTAssertEqual(camera.yaw, 0)
    XCTAssertEqual(camera.translationX, 0)
    camera.setMode(.threeD)
    XCTAssertEqual(camera.yaw, 0.6)
  }
}
