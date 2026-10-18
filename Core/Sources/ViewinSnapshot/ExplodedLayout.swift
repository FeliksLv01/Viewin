import Foundation
import ViewinProtocol

public struct ProjectedPlane: Sendable {
  public let nodeId: String
  public let corners: [LayoutPoint]
  /// Larger depth is closer to the viewer.
  public let depth: Double
}

/// Perspective geometry preview. Layer separation represents tree depth, not physical GPU depth.
public enum ExplodedLayout {
  public static func project(
    document: SnapshotDocument, window: SnapshotWindow,
    viewport: LayoutSize, yaw: Double, pitch: Double,
    spacing: Double, zoom: Double
  ) -> [ProjectedPlane] {
    let visible = document.snapshot.nodes.filter { node in
      node.windowId == window.id && node.geometry != nil
        && (document.ancestors(of: node) + [node]).allSatisfy {
          !$0.visibility.hidden && $0.visibility.alpha > 0
        }
    }
    let maxDepth = visible.map { document.ancestors(of: $0).count }.max() ?? 0
    let separation = max(0, spacing)
    let span = max(window.size.width, window.size.height) + Double(maxDepth) * separation
    // Keep the camera beyond every rotated corner, including at maximum separation.
    let cameraDistance = span * 3
    let scale = max(0.01, min(viewport.width, viewport.height) / (span * 1.2)) * zoom
    return visible.compactMap { node -> ProjectedPlane? in
      guard let geometry = node.geometry, geometry.frameInWindow.width > 0,
        geometry.frameInWindow.height > 0
      else { return nil }
      let z = (Double(document.ancestors(of: node).count) - Double(maxDepth) / 2) * separation
      let points = geometry.cornersInWindow.map { corner -> LayoutPoint in
        let x = corner.x - window.size.width / 2
        let y = corner.y - window.size.height / 2
        let rx = cos(yaw) * x + sin(yaw) * z
        let rz = -sin(yaw) * x + cos(yaw) * z
        let ry = cos(pitch) * y - sin(pitch) * rz
        let depth = sin(pitch) * y + cos(pitch) * rz
        let perspective = cameraDistance / (cameraDistance - depth)
        return LayoutPoint(
          x: viewport.width / 2 + rx * scale * perspective,
          y: viewport.height / 2 + ry * scale * perspective)
      }
      // All layout surfaces are parallel. Sort by plane level rather than a
      // rectangle's center (a small element can be far from the window center).
      return ProjectedPlane(nodeId: node.id, corners: points, depth: z * cos(yaw) * cos(pitch))
    }.sorted { $0.depth < $1.depth }
  }

  public static func hitTest(_ point: LayoutPoint, planes: [ProjectedPlane]) -> String? {
    planes.reversed().first { plane in
      var inside = false
      var previous = plane.corners.count - 1
      for index in plane.corners.indices {
        let a = plane.corners[index]
        let b = plane.corners[previous]
        if (a.y > point.y) != (b.y > point.y),
          point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
        {
          inside.toggle()
        }
        previous = index
      }
      return inside
    }?.nodeId
  }
}
