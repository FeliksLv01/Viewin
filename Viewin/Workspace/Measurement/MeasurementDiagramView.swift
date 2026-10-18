import AppKit
import SwiftUI
import ViewinConnection
import ViewinProtocol
import ViewinSnapshot
import ViewinWorkspace

struct MeasurementDiagramView: NSViewRepresentable {
  let diagram: MeasurementDiagram
  let selectedImage: NSImage?
  let hoveredImage: NSImage?
  let selectedName: String
  let hoveredName: String
  let unit: String

  func makeNSView(context: Context) -> DiagramCanvas { DiagramCanvas() }
  func updateNSView(_ view: DiagramCanvas, context: Context) {
    view.diagram = diagram
    view.selectedImage = selectedImage
    view.hoveredImage = hoveredImage
    view.names = (selectedName, hoveredName)
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.image)
    view.setAccessibilityLabel(L10n.text("测距结果"))
    let distances = diagram.guides.map {
      L10n.format("%@ %@ %@", String(describing: $0.axis == .horizontal ? L10n.text("水平") : L10n.text("垂直")), String(describing: measurementNumber($0.value)), String(describing: unit))
    }.joined(separator: "，")
    view.setAccessibilityValue(
      L10n.format("选中 %@，悬停 %@，%@", String(describing: selectedName), String(describing: hoveredName), String(describing: distances.isEmpty ? L10n.text("边缘重合") : distances)))
    view.needsDisplay = true
  }

  final class DiagramCanvas: NSView {
    var diagram: MeasurementDiagram?
    var selectedImage: NSImage?
    var hoveredImage: NSImage?
    var names = ("", "")
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
      guard let diagram, bounds.width > 40, bounds.height > 40 else { return }
      let scale = min(
        (bounds.width - 40) / diagram.union.width, (bounds.height - 40) / diagram.union.height)
      let origin = CGPoint(
        x: (bounds.width - diagram.union.width * scale) / 2,
        y: (bounds.height - diagram.union.height * scale) / 2)
      func point(_ p: LayoutPoint) -> CGPoint {
        CGPoint(
          x: origin.x + (p.x - diagram.union.x) * scale,
          y: origin.y + (p.y - diagram.union.y) * scale)
      }
      func rect(_ r: LayoutRect) -> CGRect {
        CGRect(
          origin: point(LayoutPoint(x: r.x, y: r.y)),
          size: CGSize(width: r.width * scale, height: r.height * scale))
      }
      let a = rect(diagram.selected)
      let b = rect(diagram.hovered)
      drawImage(selectedImage, name: names.0, in: a, opacity: diagram.selectedOpacity)
      drawImage(hoveredImage, name: names.1, in: b, opacity: diagram.hoveredOpacity)
      let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      NSColor(white: dark ? 123 / 255 : 190 / 255, alpha: 1).setStroke()
      for frame in [a, b] {
        let path = NSBezierPath(rect: frame)
        path.lineWidth = 1
        path.stroke()
      }
      var labels: [CGRect] = []
      // Horizontal guides first, as in Lookin; vertical pills can move right on collision.
      for guide in diagram.guides {
        let start = point(guide.start)
        let end = point(guide.end)
        let horizontal = guide.axis == .horizontal
        let color =
          horizontal
          ? NSColor(red: 10 / 255, green: 127 / 255, blue: 251 / 255, alpha: 1)
          : NSColor(red: 209 / 255, green: 120 / 255, blue: 0, alpha: 1)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: start)
        path.line(to: end)
        for endPoint in [start, end] {
          path.move(
            to: CGPoint(x: endPoint.x - (horizontal ? 0 : 3), y: endPoint.y - (horizontal ? 3 : 0)))
          path.line(
            to: CGPoint(x: endPoint.x + (horizontal ? 0 : 3), y: endPoint.y + (horizontal ? 3 : 0)))
        }
        path.stroke()
        let text = measurementNumber(guide.value) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let width = min(bounds.width - 8, size.width + 6)
        var frame = CGRect(
          x: horizontal ? (start.x + end.x - width) / 2 : start.x - width - 5,
          y: horizontal ? start.y - 23 : (start.y + end.y) / 2 - 9, width: width, height: 18)
        var alpha = 1.0
        if !horizontal
          && labels.contains(where: {
            $0.intersection(frame).width * $0.intersection(frame).height > 100
          })
        {
          frame.origin.x = start.x + 5
          alpha = 0.5
        }
        frame.origin.x = min(max(4, frame.minX), bounds.width - width - 4)
        frame.origin.y = min(max(2, frame.minY), bounds.height - 20)
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9).fill()
        text.draw(in: frame.insetBy(dx: 3, dy: 0), withAttributes: attributes)
        labels.append(frame)
      }
    }
    private func drawImage(_ image: NSImage?, name: String, in frame: CGRect, opacity: Double) {
      if let image {
        image.draw(
          in: frame, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true,
          hints: nil)
      } else {
        NSColor.controlAccentColor.withAlphaComponent(0.08 * opacity).setFill()
        frame.fill()
        (L10n.format("%@\n无截图", String(describing: name)) as NSString).draw(
          in: frame.insetBy(dx: 3, dy: 3),
          withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
          ])
      }
    }
  }
}

private func measurementNumber(_ value: Double) -> String {
  value.formatted(.number.precision(.fractionLength(0...2)))
}
