import ViewinProtocol
import XCTest

@testable import ViewinSnapshot

final class MeasurementDiagramTests: XCTestCase {
  func testSeparatedRectsUseEdgeGapsAndCorrectAxes() throws {
    let a = rect(0, 0, 40, 20)
    let b = rect(60, 50, 10, 10)
    let diagram = try XCTUnwrap(MeasurementDiagram(selected: a, hovered: b))
    XCTAssertEqual(diagram.guides.map(\.value), [20, 30])
    XCTAssertEqual(diagram.guides[0].start, LayoutPoint(x: 40, y: 10))
    XCTAssertEqual(diagram.guides[0].end, LayoutPoint(x: 60, y: 10))
    XCTAssertEqual(diagram.guides[1].start, LayoutPoint(x: 20, y: 20))
    XCTAssertEqual(diagram.guides[1].end, LayoutPoint(x: 20, y: 50))
    XCTAssertEqual(diagram.selectedOpacity, 1)
    XCTAssertEqual(diagram.hoveredOpacity, 1)
    let reverse = try XCTUnwrap(MeasurementDiagram(selected: b, hovered: a))
    XCTAssertEqual(reverse.guides.map(\.value), [20, 30])
  }

  func testContainmentMeasuresInsetsAndFadesOnlyOuterScreenshot() throws {
    let a = rect(-10, -20, 100, 100)
    let b = rect(0, 0, 30, 40)
    let diagram = try XCTUnwrap(MeasurementDiagram(selected: a, hovered: b))
    XCTAssertEqual(
      diagram.guides.filter { $0.axis == .horizontal }.map(\.value).sorted(), [10, 60])
    XCTAssertEqual(diagram.guides.filter { $0.axis == .vertical }.map(\.value).sorted(), [20, 40])
    XCTAssertEqual(diagram.selectedOpacity, 0.2)
    XCTAssertEqual(diagram.hoveredOpacity, 1)
    XCTAssertEqual(diagram.union, a)
    let reverse = try XCTUnwrap(MeasurementDiagram(selected: b, hovered: a))
    XCTAssertEqual(reverse.selectedOpacity, 1)
    XCTAssertEqual(reverse.hoveredOpacity, 0.2)
    XCTAssertEqual(reverse.guides.map(\.value).sorted(), diagram.guides.map(\.value).sorted())
  }

  func testPartialOverlapShowsEdgeOffsetsInsteadOfMisleadingZeroGaps() throws {
    let a = rect(0, 0, 50, 50)
    let b = rect(20, 30, 60, 40)
    let diagram = try XCTUnwrap(MeasurementDiagram(selected: a, hovered: b))
    XCTAssertEqual(diagram.guides.map(\.value), [30, 20])
    XCTAssertEqual(diagram.selectedOpacity, 0.2)
    XCTAssertEqual(diagram.hoveredOpacity, 0.2)
  }

  func testAlignedRectsHaveNoRedundantZeroLabels() throws {
    let a = rect(0, 0, 50, 50)
    XCTAssertTrue(try XCTUnwrap(MeasurementDiagram(selected: a, hovered: a)).guides.isEmpty)
    let near = rect(0.000001, 0.000001, 50, 50)
    XCTAssertTrue(try XCTUnwrap(MeasurementDiagram(selected: a, hovered: near)).guides.isEmpty)
    let aligned = try XCTUnwrap(MeasurementDiagram(selected: a, hovered: rect(0, 10, 50, 20)))
    XCTAssertTrue(aligned.guides.filter { $0.axis == .horizontal }.isEmpty)
    XCTAssertEqual(aligned.guides.map(\.value).sorted(), [10, 20])
  }

  func testInvalidGeometryIsRejectedWithoutNaNOrDivisionByZero() {
    let good = rect(0, 0, 10, 10)
    for bad in [
      rect(0, 0, 0, 10), rect(0, 0, 10, -1), rect(.nan, 0, 10, 10), rect(0, 0, .infinity, 10),
    ] {
      XCTAssertNil(MeasurementDiagram(selected: good, hovered: bad))
      XCTAssertNil(MeasurementDiagram(selected: bad, hovered: good))
    }
  }

  func testDirectionalCasesAlwaysProduceAxisAlignedGuidesWithRealDistances() throws {
    let a = rect(10, 20, 30, 40)
    for x in [-50.0, 0, 10, 15, 40, 80] {
      for y in [-50.0, 0, 20, 30, 60, 80] {
        for size in [10.0, 30, 100] {
          let diagram = try XCTUnwrap(
            MeasurementDiagram(selected: a, hovered: rect(x, y, size, size)))
          for guide in diagram.guides {
            XCTAssertGreaterThanOrEqual(guide.value, 0)
            if guide.axis == .horizontal {
              XCTAssertEqual(guide.start.y, guide.end.y)
              XCTAssertEqual(guide.value, guide.end.x - guide.start.x, accuracy: 0.00001)
            } else {
              XCTAssertEqual(guide.start.x, guide.end.x)
              XCTAssertEqual(guide.value, guide.end.y - guide.start.y, accuracy: 0.00001)
            }
          }
        }
      }
    }
  }
  private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> LayoutRect {
    LayoutRect(x: x, y: y, width: width, height: height)
  }
}
