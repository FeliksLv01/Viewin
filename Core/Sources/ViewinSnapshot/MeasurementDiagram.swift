import ViewinProtocol

/// Lookin-style edge guides in window coordinates; independent of preview projection/zoom.
public struct MeasurementDiagram: Equatable, Sendable {
  public enum Axis: Equatable, Sendable { case horizontal, vertical }
  public struct Guide: Equatable, Sendable {
    public let axis: Axis
    public let start: LayoutPoint
    public let end: LayoutPoint
    public let value: Double
  }
  public let selected: LayoutRect
  public let hovered: LayoutRect
  public let union: LayoutRect
  public let guides: [Guide]
  public let selectedOpacity: Double
  public let hoveredOpacity: Double

  public init?(selected a: LayoutRect, hovered b: LayoutRect) {
    guard Self.valid(a), Self.valid(b) else { return nil }
    selected = a
    hovered = b
    let minX = min(a.x, b.x)
    let minY = min(a.y, b.y)
    union = LayoutRect(
      x: minX, y: minY,
      width: max(a.x + a.width, b.x + b.width) - minX,
      height: max(a.y + a.height, b.y + b.height) - minY)
    func contains(_ outer: LayoutRect, _ inner: LayoutRect) -> Bool {
      outer.x <= inner.x && outer.y <= inner.y
        && outer.x + outer.width >= inner.x + inner.width
        && outer.y + outer.height >= inner.y + inner.height
    }
    let intersects =
      a.x < b.x + b.width && a.x + a.width > b.x
      && a.y < b.y + b.height && a.y + a.height > b.y
    if contains(a, b) {
      selectedOpacity = 0.2
      hoveredOpacity = 1
    } else if contains(b, a) {
      selectedOpacity = 1
      hoveredOpacity = 0.2
    } else {
      selectedOpacity = intersects ? 0.2 : 1
      hoveredOpacity = intersects ? 0.2 : 1
    }
    guides =
      Self.axisGuides(
        .horizontal, a.x, a.x + a.width, b.x, b.x + b.width,
        a.y + a.height / 2, b.y + b.height / 2)
      + Self.axisGuides(
        .vertical, a.y, a.y + a.height, b.y, b.y + b.height,
        a.x + a.width / 2, b.x + b.width / 2)
  }

  private static func valid(_ rect: LayoutRect) -> Bool {
    let coordinates: [Double] = [
      rect.x, rect.y, rect.width, rect.height,
      rect.x + rect.width, rect.y + rect.height,
    ]
    return coordinates.allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
  }

  /// Same directional cases and tolerance as LKMeasureResultView, shared by both axes.
  private static func axisGuides(
    _ axis: Axis, _ a0: Double, _ a1: Double,
    _ b0: Double, _ b1: Double, _ crossA: Double, _ crossB: Double
  ) -> [Guide] {
    func compare(_ x: Double, _ y: Double) -> Int {
      abs(x - y) < 0.00001 ? 0 : (x < y ? -1 : 1)
    }
    var lines: [Guide] = []
    func add(_ first: Double, _ second: Double, _ cross: Double) {
      let start = min(first, second)
      let end = max(first, second)
      lines.append(
        Guide(
          axis: axis,
          start: LayoutPoint(
            x: axis == .horizontal ? start : cross, y: axis == .horizontal ? cross : start),
          end: LayoutPoint(
            x: axis == .horizontal ? end : cross, y: axis == .horizontal ? cross : end),
          value: abs(second - first)))
    }
    switch compare(a0, b0) {
    case -1:
      if compare(a1, b0) == -1 {
        add(a1, b0, crossA)
      } else if compare(a1, b1) == -1 {
        add(a1, b1, crossA)
      } else if compare(a1, b1) == 1 {
        add(b1, a1, crossB)
        add(a0, b0, crossB)
      }
    case 0:
      if compare(a1, b1) == -1 {
        add(a1, b1, crossA)
      } else if compare(a1, b1) == 1 {
        add(b1, a1, crossB)
      }
    default:
      if compare(a0, b1) == 1 {
        add(a0, b1, crossA)
      } else {
        add(b0, a0, crossA)
        if compare(a1, b1) == -1 { add(a1, b1, crossA) }
      }
    }
    return lines
  }
}
