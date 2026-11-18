import CoreGraphics

/// Pure positioning math for the floating network inspector trigger.
///
/// The trigger stores its position as a fraction of the available view size. This type converts
/// that fraction into a point, clamps it inside the safe area for the current screen, and converts
/// a dragged point back into a fraction for persistence. Keeping the math separate makes it
/// testable on macOS hosts where the SwiftUI overlay is not compiled.
internal struct NetworkInspectorButtonLayout: Equatable {
    /// Safe-area distances that shrink the draggable region.
    internal struct Insets: Equatable {
        internal let top: CGFloat
        internal let leading: CGFloat
        internal let bottom: CGFloat
        internal let trailing: CGFloat

        internal init(
            top: CGFloat = 0,
            leading: CGFloat = 0,
            bottom: CGFloat = 0,
            trailing: CGFloat = 0
        ) {
            self.top = top
            self.leading = leading
            self.bottom = bottom
            self.trailing = trailing
        }
    }

    /// The clamped area in which the trigger center may move.
    internal struct Bounds: Equatable {
        internal let minX: CGFloat
        internal let maxX: CGFloat
        internal let minY: CGFloat
        internal let maxY: CGFloat
    }

    /// A persisted position expressed as fractions of the view size.
    internal struct UnitPosition: Equatable {
        internal let x: Double
        internal let y: Double
    }

    internal let diameter: CGFloat
    internal let edgeInset: CGFloat

    /// Creates a layout for a circular trigger.
    /// - Parameters:
    ///   - diameter: The trigger diameter in points.
    ///   - edgeInset: The minimum distance from the safe-area edge in points.
    internal init(diameter: CGFloat = 54, edgeInset: CGFloat = 8) {
        self.diameter = diameter
        self.edgeInset = edgeInset
    }

    /// Returns the area in which the trigger center may move.
    /// - Parameters:
    ///   - size: The available view size.
    ///   - insets: Safe-area distances to respect.
    /// - Returns: Clamped center bounds.
    internal func bounds(in size: CGSize, insets: Insets = Insets()) -> Bounds {
        let radius = diameter / 2

        let minX = radius + edgeInset + insets.leading
        let minY = radius + edgeInset + insets.top
        let maxX = max(minX, size.width - radius - edgeInset - insets.trailing)
        let maxY = max(minY, size.height - radius - edgeInset - insets.bottom)

        return Bounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    /// Resolves a persisted position plus a live drag translation into a clamped center point.
    /// - Parameters:
    ///   - unitX: The stored horizontal fraction.
    ///   - unitY: The stored vertical fraction.
    ///   - translation: The current drag translation. Defaults to zero.
    ///   - size: The available view size.
    ///   - insets: Safe-area distances to respect.
    /// - Returns: A center point inside the draggable bounds.
    internal func center(
        unitX: Double,
        unitY: Double,
        translation: CGSize = .zero,
        in size: CGSize,
        insets: Insets = Insets()
    ) -> CGPoint {
        let bounds = bounds(in: size, insets: insets)
        let base = CGPoint(
            x: CGFloat(unitX) * size.width,
            y: CGFloat(unitY) * size.height
        )

        return CGPoint(
            x: min(max(base.x + translation.width, bounds.minX), bounds.maxX),
            y: min(max(base.y + translation.height, bounds.minY), bounds.maxY)
        )
    }

    /// Converts a center point back into a persisted fraction.
    /// - Parameters:
    ///   - center: The resolved center point.
    ///   - size: The available view size.
    /// - Returns: The fraction to persist, or `nil` when the view has no area.
    internal func unitPosition(for center: CGPoint, in size: CGSize) -> UnitPosition? {
        guard size.width > 0, size.height > 0 else { return nil }

        return UnitPosition(
            x: Double(center.x / size.width),
            y: Double(center.y / size.height)
        )
    }
}
