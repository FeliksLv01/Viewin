import Foundation

/// Input/state semantics independently implemented from Lookin's preview behavior.
/// Scale and interspace use Lookin's normalized 0...1 control range.
public struct PreviewCamera: Sendable, Equatable {
  public enum Mode: String, Sendable {
    case twoD = "2D"
    case threeD = "3D"
  }
  public struct Drag: Sendable {
    let translating: Bool
    let yaw: Double
    let pitch: Double
    let x: Double
    let y: Double
  }

  public private(set) var mode: Mode = .threeD
  public private(set) var freeRotation = true
  public private(set) var yaw = 0.6
  public private(set) var pitch = 0.0
  public private(set) var translationX = 0.0
  public private(set) var translationY = 0.0
  public private(set) var savedYaw = 0.0
  public private(set) var savedPitch = 0.0
  public var scale = 0.27
  public var interspace = 0.22
  /// Discrete changes animate; pointer updates do not. Revision distinguishes the
  /// next gesture update from a preceding animated transition.
  public private(set) var revision = 0
  public private(set) var animated = false

  public init() {}
  public var focalLength: Double { 20 + clampedScale * clampedScale * 730 }
  public var layerDistance: Double { mode == .twoD ? 0.01 : 0.1 + min(1, max(0, interspace)) * 0.7 }
  public var clampedScale: Double { min(1, max(0, scale)) }

  public mutating func setMode(_ value: Mode) {
    guard value != mode else { return }
    if value == .twoD {
      savedYaw = yaw
      savedPitch = pitch
      yaw = 0
      pitch = 0
    } else {
      yaw = savedYaw >= 0 ? max(0.18, savedYaw) : min(-0.18, savedYaw)
      pitch = freeRotation ? savedPitch : 0
    }
    mode = value
    changed(animated: true)
  }

  public mutating func setFreeRotation(_ value: Bool) {
    guard freeRotation != value else { return }
    freeRotation = value
    if !value { pitch = 0 } else if mode == .threeD { pitch = -0.05 }
    changed(animated: true)
  }

  public func beginDrag(translating: Bool) -> Drag {
    Drag(translating: translating, yaw: yaw, pitch: pitch, x: translationX, y: translationY)
  }
  /// Translation is in view points, with positive y downwards (Lookin's flipped stage).
  public mutating func drag(_ start: Drag, x: Double, y: Double) {
    if start.translating {
      let factor = (1 - clampedScale) * 0.92 + 0.08
      translationX = start.x + x * 0.01 * factor
      translationY = start.y - y * 0.01 * factor
    } else {
      guard mode == .threeD else { return }
      yaw = Self.normalized(start.yaw + x * 0.01)
      pitch = freeRotation ? Self.normalized(start.pitch + y * 0.004) : 0
    }
    changed(animated: false)
  }

  public mutating func scroll(x: Double, y: Double, command: Bool) {
    if command {
      scale = min(1, max(0, clampedScale - y * 0.005))
    } else {
      let factor = (1 - clampedScale) * 0.7 + 0.3
      translationX += x * 0.04 * factor
      translationY -= y * 0.04 * factor
    }
    changed(animated: false)
  }
  public mutating func magnify(_ amount: Double) {
    scale = min(1, max(0, clampedScale + amount * 0.3))
    changed(animated: false)
  }
  public mutating func reset() {
    yaw = mode == .threeD ? 0.6 : 0
    pitch = 0
    savedYaw = 0.6
    savedPitch = 0
    translationX = 0
    translationY = 0
    scale = 0.27
    changed(animated: true)
  }
  public mutating func resetForNewContentSize() {
    scale = 0.27
    changed(animated: false)
  }
  private mutating func changed(animated: Bool) {
    self.animated = animated
    revision &+= 1
  }
  private static func normalized(_ angle: Double) -> Double {
    let value = angle.truncatingRemainder(dividingBy: .pi * 2)
    if value <= -.pi { return value + .pi * 2 }
    if value >= .pi { return value - .pi * 2 }
    return value
  }
}
