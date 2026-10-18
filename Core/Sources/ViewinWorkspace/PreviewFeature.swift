import Foundation
import Observation
import ViewinSnapshot

@MainActor @Observable public final class PreviewFeature {

  public var camera = PreviewCamera()
  public var controls = Controls()
  public var showBounds: Bool {
    didSet { defaults.set(showBounds, forKey: "viewin_preview_showBounds") }
  }
  @ObservationIgnored private let defaults: UserDefaults
  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    showBounds = defaults.object(forKey: "viewin_preview_showBounds") as? Bool ?? true
  }
  public func synchronizeControls() { controls.update(camera) }

  /// A derived read model: rotating/panning never invalidates unrelated toolbar controls.
  @Observable public final class Controls {
    public var mode = PreviewCamera.Mode.threeD
    public var freeRotation = true
    public var zoom = 0.27
    public var layerSpacing = 0.22
    public init() {}
    func update(_ camera: PreviewCamera) {
      if mode != camera.mode { mode = camera.mode }
      if freeRotation != camera.freeRotation { freeRotation = camera.freeRotation }
      if zoom != camera.scale { zoom = camera.scale }
      if layerSpacing != camera.interspace { layerSpacing = camera.interspace }
    }
  }
  public enum Action: Sendable {
    case modeChanged(PreviewCamera.Mode)
    case freeRotationChanged(Bool)
    case zoomChanged(Double)
    case spacingChanged(Double)
    case boundsChanged(Bool)
    case reset
    case drag(PreviewCamera.Drag, x: Double, y: Double)
    case scroll(x: Double, y: Double, command: Bool)
    case magnify(Double)
  }
  public func send(_ action: Action) {
    switch action {
    case .modeChanged(let mode):
      self.camera.setMode(mode)
    case .freeRotationChanged(let value): self.camera.setFreeRotation(value)
    case .zoomChanged(let value): self.camera.scale = min(1, max(0, value))
    case .spacingChanged(let value): self.camera.interspace = min(1, max(0, value))
    case .boundsChanged(let value): showBounds = value
    case .reset: self.camera.reset()
    case .drag(let start, let x, let y): self.camera.drag(start, x: x, y: y)
    case .scroll(let x, let y, let command): self.camera.scroll(x: x, y: y, command: command)
    case .magnify(let amount): self.camera.magnify(amount)
    }
    synchronizeControls()
  }
}
