import AppKit
import SceneKit
import SwiftUI
import ViewinProtocol
import ViewinSnapshot

/// SwiftUI owns the workspace; a retained SceneKit scene renders textures and
/// animates folding, as in Lookin, without rasterizing every plane on the CPU.
struct ExplodedPreview: NSViewRepresentable {
  let contentID: ObjectIdentifier?
  let workspace: WorkspaceStore
  let document: SnapshotDocument
  let window: SnapshotWindow
  let expanded: Set<String>
  let search: String
  let selectedId: String?
  let hoveredId: String?
  let focusRootId: String?
  let includedIds: Set<String>?
  let hiddenPreviewIds: Set<String>
  let showHidden: Bool
  let bounds: Bool
  let cameraState: PreviewCamera
  let images: [String: NSImage]

  func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
  func makeNSView(context: Context) -> LayoutSceneView {
    let view = LayoutSceneView()
    view.scene = context.coordinator.scene
    view.pointOfView = context.coordinator.camera
    view.antialiasingMode = .multisampling4X
    view.rendersContinuously = false
    view.autoenablesDefaultLighting = false
    view.allowsCameraControl = false
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
    view.onSelect = { [weak coordinator = context.coordinator] id in
      guard let coordinator, let node = coordinator.document?.node(id) else { return }
      coordinator.workspace.select(node)
    }
    view.onDoubleClick = { [weak workspace] id in workspace?.doubleClick(id) }
    view.onHover = { [weak workspace] id in workspace?.hover(id) }
    view.makeDrag = { [weak workspace] translating in
      workspace?.camera.beginDrag(translating: translating)
    }
    view.onDrag = { [weak workspace] start, x, y in
      workspace?.drag(start, x: x, y: y)
    }
    view.onScroll = { [weak workspace] x, y, command in
      workspace?.scroll(x: x, y: y, command: command)
    }
    view.onMagnify = { [weak workspace] amount in workspace?.magnify(amount) }
    view.onAppearanceChange = { [weak coordinator = context.coordinator] in
      coordinator?.updateHighlights()
    }
    view.onNavigate = { [weak workspace] key in workspace?.navigateSelection(key) }
    context.coordinator.view = view
    return view
  }
  func updateNSView(_ view: LayoutSceneView, context: Context) {
    context.coordinator.update(self)
  }

  @MainActor final class Coordinator: NSObject {
    struct Layer {
      let node: SCNNode
      let border: SCNNode
      let mask: SCNNode
      var imageId: String?
    }
    let workspace: WorkspaceStore
    let scene = SCNScene()
    let root = SCNNode()
    let camera = SCNNode()
    weak var view: LayoutSceneView?
    var document: SnapshotDocument?
    var layers: [String: Layer] = [:]
    var contentID: ObjectIdentifier?
    var snapshotId = ""
    var windowId = ""
    var expanded = Set<String>()
    var search = ""
    var surfaces: [HierarchyPresentation.Surface] = []
    var selectedId: String?
    var hoveredId: String?
    var focusRootId: String?
    var includedIds: Set<String>?
    var hiddenPreviewIds = Set<String>()
    var showHidden = false
    var showBounds = true
    var screenSize = CGSize(width: 390, height: 844)
    var maximumLevel = 0
    var spacing = 0.254
    var previousCamera: PreviewCamera?
    var cameraRevision = -1
    var is3D = false
    var imageCount = -1

    init(workspace: WorkspaceStore) {
      self.workspace = workspace
      super.init()
      camera.camera = SCNCamera()
      camera.camera?.automaticallyAdjustsZRange = true
      camera.camera?.focalLength = 20 + 0.27 * 0.27 * 730
      camera.position = SCNVector3(0, 0, 34)
      scene.rootNode.addChildNode(camera)
      scene.rootNode.addChildNode(root)
    }
    func update(_ input: ExplodedPreview) {
      let rebuilt =
        contentID != input.contentID || snapshotId != input.document.snapshot.snapshotId
        || windowId != input.window.id
      if rebuilt {
        contentID = input.contentID
        document = input.document
        snapshotId = input.document.snapshot.snapshotId
        windowId = input.window.id
        screenSize = CGSize(width: input.window.size.width, height: input.window.size.height)
        layers.values.forEach { $0.node.removeFromParentNode() }
        layers.removeAll(keepingCapacity: true)
        for entry in workspace.previewHierarchy?.entries ?? [] {
          guard let geometry = entry.node.geometry else { continue }
          let frame = geometry.frameInWindow
          guard frame.width > 0, frame.height > 0 else { continue }
          let plane = SCNPlane(width: frame.width * 0.01, height: frame.height * 0.01)
          let material = SCNMaterial()
          material.lightingModel = .constant
          material.isDoubleSided = true
          material.diffuse.contents = NSColor.clear
          material.diffuse.magnificationFilter = .linear
          material.diffuse.minificationFilter = .linear
          plane.materials = [material]
          let node = SCNNode(geometry: plane)
          node.name = entry.node.id
          node.position = SCNVector3(
            Float((frame.x + frame.width / 2 - screenSize.width / 2) * 0.01),
            Float((screenSize.height / 2 - frame.y - frame.height / 2) * 0.01), 0)
          let w = Float(frame.width * 0.005)
          let h = Float(frame.height * 0.005)
          let border = outlineNode(width: w, height: h)
          border.position.z = 0.003
          node.addChildNode(border)
          let mask = SCNNode(
            geometry: SCNPlane(width: frame.width * 0.01, height: frame.height * 0.01))
          let maskMaterial = SCNMaterial()
          maskMaterial.lightingModel = .constant
          maskMaterial.isDoubleSided = true
          maskMaterial.diffuse.contents = NSColor(
            red: 110 / 255, green: 183 / 255, blue: 1, alpha: 1)
          maskMaterial.readsFromDepthBuffer = false
          maskMaterial.writesToDepthBuffer = false
          mask.geometry?.materials = [maskMaterial]
          mask.categoryBitMask = 2
          mask.position.z = 0.002
          node.addChildNode(mask)
          root.addChildNode(node)
          layers[entry.node.id] = Layer(node: node, border: border, mask: mask)
        }
        hoveredId = nil
      }
      let foldChanged =
        rebuilt || expanded != input.expanded || search != input.search
        || focusRootId != input.focusRootId || includedIds != input.includedIds
        || hiddenPreviewIds != input.hiddenPreviewIds || showHidden != input.showHidden
      let texturesChanged = rebuilt || imageCount != input.images.count
      expanded = input.expanded
      search = input.search
      focusRootId = input.focusRootId
      includedIds = input.includedIds
      hiddenPreviewIds = input.hiddenPreviewIds
      showHidden = input.showHidden
      imageCount = input.images.count
      if foldChanged {
        surfaces =
          workspace.previewHierarchy?.surfaces(
            expanded: expanded, rootId: focusRootId, includedIds: includedIds,
            hiddenPreviewIds: hiddenPreviewIds, showHidden: showHidden) ?? []
        maximumLevel = surfaces.map(\.level).max() ?? 0
      }
      let modeChanged = is3D != (input.cameraState.mode == .threeD)
      let placementChanged =
        foldChanged || modeChanged || spacing != input.cameraState.layerDistance
      let previousSelection = selectedId
      let previousHover = hoveredId
      let boundsChanged = showBounds != input.bounds
      is3D = input.cameraState.mode == .threeD
      spacing = input.cameraState.layerDistance
      let cameraTransition =
        cameraRevision != input.cameraState.revision && input.cameraState.animated
      cameraRevision = input.cameraState.revision
      selectedId = input.selectedId
      hoveredId = input.hoveredId
      showBounds = input.bounds
      SCNTransaction.begin()
      SCNTransaction.animationDuration =
        !rebuilt && (foldChanged || modeChanged || cameraTransition) ? 0.25 : 0
      SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      if rebuilt || previousCamera != input.cameraState {
        root.eulerAngles = SCNVector3(
          Float(input.cameraState.pitch), Float(input.cameraState.yaw), 0)
        root.position = SCNVector3(
          Float(input.cameraState.translationX), Float(input.cameraState.translationY), 0)
        camera.camera?.focalLength = input.cameraState.focalLength
        previousCamera = input.cameraState
      }
      if foldChanged {
        let visible = Set(surfaces.map { $0.node.id })
        for (id, var layer) in layers {
          let shown = visible.contains(id)
          layer.node.opacity = shown ? 1 : 0
          layer.node.categoryBitMask = shown ? 1 : 0
          if !shown, layer.imageId != nil {
            layer.node.geometry?.firstMaterial?.diffuse.contents = NSColor.clear
            layer.imageId = nil
            layers[id] = layer
          }
        }
      }
      if placementChanged || texturesChanged {
        for (order, surface) in surfaces.enumerated() {
          guard var layer = layers[surface.node.id] else { continue }
          let z = (Double(surface.level) - (Double(maximumLevel) * 0.5).rounded()) * spacing
          if placementChanged {
            layer.node.position.z = CGFloat(z + Double(order) * 0.00001)
            layer.node.renderingOrder = order * 10
          }
          if texturesChanged || layer.imageId != surface.imageId {
            layer.imageId = surface.imageId
            let image = surface.imageId.flatMap { input.images[$0] }
            layer.node.geometry?.firstMaterial?.diffuse.contents =
              image
              ?? (input.document.snapshot.source == "fixture"
                ? fixtureImage(surface.node) : NSImage(size: NSSize(width: 1, height: 1)))
            layers[surface.node.id] = layer
          }
        }
      }
      if foldChanged || boundsChanged {
        updateHighlights()
      } else if previousSelection != selectedId || previousHover != hoveredId {
        for id in Set([previousSelection, selectedId, previousHover, hoveredId].compactMap({ $0 }))
        { updateHighlight(id) }
      }
      SCNTransaction.commit()
      view?.setAccessibilityLabel(is3D ? L10n.text("3D 拆层预览") : L10n.text("2D 布局预览"))
      view?.setAccessibilityValue(
        L10n.format("可见图层 %@，选中 %@，悬停 %@，旋转角度 %@，倾斜 %@，平移 %@ / %@，大小 %@", String(describing: surfaces.count), String(describing: selectedId ?? L10n.text("无")), String(describing: hoveredId ?? L10n.text("无")), String(describing: Int(input.cameraState.yaw * 180 / .pi)), String(describing: Int(input.cameraState.pitch * 180 / .pi)), String(describing: input.cameraState.translationX.formatted(.number.precision(.fractionLength(2)))), String(describing: input.cameraState.translationY.formatted(.number.precision(.fractionLength(2)))), String(describing: input.cameraState.clampedScale.formatted(.number.precision(.fractionLength(2)))))
      )
    }
    func updateHighlights() { for id in layers.keys { updateHighlight(id) } }
    func updateHighlight(_ id: String) {
      guard let layer = layers[id] else { return }
      let selected = id == selectedId
      let hover = id == hoveredId
      let color =
        selected || hover
        ? NSColor(red: 100 / 255, green: 146 / 255, blue: 199 / 255, alpha: 1)
        : (view?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          ? NSColor(red: 160 / 255, green: 168 / 255, blue: 189 / 255, alpha: 0.6)
          : NSColor(red: 120 / 255, green: 122 / 255, blue: 124 / 255, alpha: 0.6))
      layer.border.geometry?.firstMaterial?.diffuse.contents = color
      layer.border.geometry?.firstMaterial?.readsFromDepthBuffer = !(selected || hover)
      layer.border.geometry?.firstMaterial?.writesToDepthBuffer = false
      layer.border.renderingOrder = selected || hover ? 1_000_002 : layer.node.renderingOrder + 2
      layer.border.isHidden = !(showBounds || selected || hover)
      layer.mask.isHidden = !(selected || hover)
      layer.mask.opacity = selected ? 0.35 : (hover ? 0.18 : 0)
      layer.mask.renderingOrder = selected ? 1_000_001 : 1_000_000
    }
    func outlineNode(width: Float, height: Float) -> SCNNode {
      let points = [
        SCNVector3(-width, -height, 0), SCNVector3(width, -height, 0),
        SCNVector3(width, height, 0), SCNVector3(-width, height, 0),
      ]
      let geometry = SCNGeometry(
        sources: [SCNGeometrySource(vertices: points)],
        elements: [
          SCNGeometryElement(indices: [Int32(0), 1, 1, 2, 2, 3, 3, 0], primitiveType: .line)
        ])
      let material = SCNMaterial()
      material.lightingModel = .constant
      material.isDoubleSided = true
      geometry.materials = [material]
      let node = SCNNode(geometry: geometry)
      node.categoryBitMask = 2
      return node
    }

    func fixtureImage(_ node: SnapshotNode) -> NSImage {
      let frame = node.geometry!.frameInWindow
      let size = NSSize(width: frame.width, height: frame.height)
      return NSImage(size: size, flipped: true) { rect in
        if node.kind == "window" {
          NSColor.white.setFill()
          rect.fill()
        }
        if node.kind == "button" {
          NSColor.systemBlue.setFill()
          NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        }
        if let text = node.textPreview {
          (text as NSString).draw(
            in: rect.insetBy(dx: 4, dy: 4),
            withAttributes: [
              .font: NSFont.systemFont(ofSize: node.kind == "button" ? 16 : 14),
              .foregroundColor: node.kind == "button" ? NSColor.white : NSColor.black,
            ])
        }
        return true
      }
    }
  }
}
