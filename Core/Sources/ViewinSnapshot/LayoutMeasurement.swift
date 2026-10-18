import ViewinProtocol

/// Axis-aligned bounding-frame gaps in the same window's logical units.
public struct LayoutMeasurement: Sendable {
  public let horizontalGap: Double
  public let verticalGap: Double

  public init(from a: LayoutRect, to b: LayoutRect) {
    horizontalGap = max(0, max(a.x - b.x - b.width, b.x - a.x - a.width))
    verticalGap = max(0, max(a.y - b.y - b.height, b.y - a.y - a.height))
  }
}
