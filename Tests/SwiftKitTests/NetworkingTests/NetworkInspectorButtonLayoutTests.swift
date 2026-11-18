import CoreGraphics
import XCTest
@testable import SwiftKit

/// Tests for the floating inspector trigger's positioning math.
final class NetworkInspectorButtonLayoutTests: XCTestCase {
    private let layout = NetworkInspectorButtonLayout(diameter: 50, edgeInset: 10)
    private let size = CGSize(width: 400, height: 800)

    // MARK: - Coordinate conversion

    func testUnitPositionMapsToViewCoordinates() {
        let center = layout.center(unitX: 0.5, unitY: 0.25, in: size)

        XCTAssertEqual(center.x, 200, accuracy: 0.001)
        XCTAssertEqual(center.y, 200, accuracy: 0.001)
    }

    func testTranslationMovesFromStoredPosition() {
        let center = layout.center(
            unitX: 0.5,
            unitY: 0.5,
            translation: CGSize(width: 20, height: -30),
            in: size
        )

        XCTAssertEqual(center.x, 220, accuracy: 0.001)
        XCTAssertEqual(center.y, 370, accuracy: 0.001)
    }

    func testUnitPositionRoundTripsACenterPoint() {
        let center = CGPoint(x: 123, y: 456)

        let unit = layout.unitPosition(for: center, in: size)

        XCTAssertEqual(unit?.x ?? 0, 0.3075, accuracy: 0.0001)
        XCTAssertEqual(unit?.y ?? 0, 0.57, accuracy: 0.0001)
    }

    func testUnitPositionRequiresANonZeroSize() {
        XCTAssertNil(layout.unitPosition(for: CGPoint(x: 10, y: 10), in: .zero))
        XCTAssertNil(
            layout.unitPosition(for: CGPoint(x: 10, y: 10), in: CGSize(width: 0, height: 800))
        )
    }

    // MARK: - Clamping

    func testPositionClampsToTopLeadingEdge() {
        let center = layout.center(unitX: 0, unitY: 0, in: size)

        XCTAssertEqual(center.x, 35, accuracy: 0.001)
        XCTAssertEqual(center.y, 35, accuracy: 0.001)
    }

    func testPositionClampsToBottomTrailingEdge() {
        let center = layout.center(unitX: 1, unitY: 1, in: size)

        XCTAssertEqual(center.x, 365, accuracy: 0.001)
        XCTAssertEqual(center.y, 765, accuracy: 0.001)
    }

    func testDraggedPositionIsClampedToTheEdges() {
        let center = layout.center(
            unitX: 0.5,
            unitY: 0.5,
            translation: CGSize(width: 5_000, height: 5_000),
            in: size
        )

        XCTAssertEqual(center.x, 365, accuracy: 0.001)
        XCTAssertEqual(center.y, 765, accuracy: 0.001)
    }

    // MARK: - Safe area

    func testSafeAreaInsetsShrinkTheDraggableArea() {
        let insets = NetworkInspectorButtonLayout.Insets(
            top: 50,
            leading: 20,
            bottom: 34,
            trailing: 10
        )

        let topLeading = layout.center(unitX: 0, unitY: 0, in: size, insets: insets)
        let bottomTrailing = layout.center(unitX: 1, unitY: 1, in: size, insets: insets)

        XCTAssertEqual(topLeading.x, 55, accuracy: 0.001)
        XCTAssertEqual(topLeading.y, 85, accuracy: 0.001)
        XCTAssertEqual(bottomTrailing.x, 355, accuracy: 0.001)
        XCTAssertEqual(bottomTrailing.y, 731, accuracy: 0.001)
    }

    // MARK: - Degenerate geometry

    func testTinyGeometryDoesNotInvertBounds() {
        let bounds = layout.bounds(in: CGSize(width: 40, height: 40))

        XCTAssertEqual(bounds.minX, 35, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 35, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 35, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 35, accuracy: 0.001)
    }

    func testZeroGeometryKeepsTheTriggerAtTheMinimum() {
        let center = layout.center(unitX: 0.5, unitY: 0.5, in: .zero)

        XCTAssertEqual(center.x, 35, accuracy: 0.001)
        XCTAssertEqual(center.y, 35, accuracy: 0.001)
    }
}
