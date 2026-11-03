import SwiftUI

/// Places a column of views as close to the camera as the safe area allows.
///
/// Subviews are ordered nearest-first: the first one sits right beside the lens and each
/// following one is stacked farther away. The layout fills its proposal, which must be the
/// same rect the anchor was resolved against (the safe area).
public struct CameraHuggingLayout: Layout {
    public var anchor: CameraAnchor
    public var padding: CGFloat
    public var spacing: CGFloat
    /// Widest the column may get. Narrow keeps every word near the lens.
    public var maxWidth: CGFloat
    /// Distance from the column's camera-side edge to the gaze target's centre, so the target
    /// lines up under a lens that is inside the safe area.
    public var leadOffset: CGFloat

    public init(anchor: CameraAnchor, padding: CGFloat = 16, spacing: CGFloat = 14, maxWidth: CGFloat = 320, leadOffset: CGFloat = 22) {
        self.anchor = anchor
        self.padding = padding
        self.spacing = spacing
        self.maxWidth = maxWidth
        self.leadOffset = leadOffset
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = Self.frames(
            anchor: anchor,
            bounds: bounds,
            sizes: subviews.map { $0.sizeThatFits(ProposedViewSize(width: min(bounds.width - padding * 2, maxWidth), height: nil)) },
            padding: padding,
            spacing: spacing,
            leadOffset: leadOffset
        )
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    /// The pure geometry, exposed for tests and for UIKit hosts.
    public static func frames(
        anchor: CameraAnchor,
        bounds: CGRect,
        sizes: [CGSize],
        padding: CGFloat = 16,
        spacing: CGFloat = 14,
        leadOffset: CGFloat = 22
    ) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let camera = anchor.cameraRect.offsetBy(dx: bounds.minX, dy: bounds.minY)
        let inner = bounds.insetBy(dx: padding, dy: padding / 2)
        let placement = anchor.placement

        let columnWidth = sizes.map(\.width).max() ?? 0
        let columnHeight = sizes.map(\.height).reduce(0, +) + spacing * CGFloat(sizes.count - 1)

        // Horizontal: put the column's camera-side edge at the lens.
        let lensOutsideTrailing = camera.midX >= inner.maxX
        let lensOutsideLeading = camera.midX <= inner.minX
        var columnMinX: CGFloat
        switch placement.horizontal {
        case .trailing:
            let edge = lensOutsideTrailing ? inner.maxX : camera.midX + leadOffset
            columnMinX = edge - columnWidth
        case .leading:
            let edge = lensOutsideLeading ? inner.minX : camera.midX - leadOffset
            columnMinX = edge
        case .center:
            columnMinX = camera.midX - columnWidth / 2
        }
        columnMinX = clamp(columnMinX, inner.minX, inner.maxX - columnWidth)

        // Vertical: start just past the lens. A lens beside the safe area (in a vertical bar)
        // doesn't push the column down, so the first line sits level with it.
        let overlapsHorizontally = camera.maxX > bounds.minX && camera.minX < bounds.maxX
        var columnMinY: CGFloat
        switch placement.vertical {
        case .top:
            columnMinY = overlapsHorizontally ? camera.maxY + spacing : max(camera.minY, inner.minY)
        case .bottom:
            columnMinY = (overlapsHorizontally ? camera.minY - spacing : min(camera.maxY, inner.maxY)) - columnHeight
        case .center:
            columnMinY = camera.midY - columnHeight / 2
        }
        columnMinY = clamp(columnMinY, inner.minY, inner.maxY - columnHeight)

        // Lay the items out nearest-first, reversing for a lens below the column.
        let ordered = placement.vertical == .bottom ? Array(sizes.indices.reversed()) : Array(sizes.indices)
        var frames = Array(repeating: CGRect.zero, count: sizes.count)
        var y = columnMinY
        for index in ordered {
            let size = sizes[index]
            let x: CGFloat = switch placement.horizontal {
                case .leading: columnMinX
                case .center: columnMinX + (columnWidth - size.width) / 2
                case .trailing: columnMinX + columnWidth - size.width
            }
            frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: size)
            y += size.height + spacing
        }
        return frames
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        guard high >= low else { return low }
        return min(max(value, low), high)
    }
}
