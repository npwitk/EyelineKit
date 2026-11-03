import CoreGraphics
import SwiftUI

/// Where the camera sits relative to the safe area, in thirds.
///
/// The instruction stack is aligned to this edge so it hugs the lens.
public enum AnchorPlacement: String, Sendable, CaseIterable {
    case topLeading, top, topTrailing
    case leading, trailing
    case bottomLeading, bottom, bottomTrailing

    public enum Horizontal: Sendable { case leading, center, trailing }
    public enum Vertical: Sendable { case top, center, bottom }

    public init(horizontal: Horizontal, vertical: Vertical) {
        switch (vertical, horizontal) {
        case (.top, .leading): self = .topLeading
        case (.top, .center): self = .top
        case (.top, .trailing): self = .topTrailing
        case (.center, .leading): self = .leading
        case (.center, .trailing): self = .trailing
        case (.center, .center): self = .top // A camera in the middle of the screen does not exist; treat it as top.
        case (.bottom, .leading): self = .bottomLeading
        case (.bottom, .center): self = .bottom
        case (.bottom, .trailing): self = .bottomTrailing
        }
    }

    public var horizontal: Horizontal {
        switch self {
        case .topLeading, .leading, .bottomLeading: .leading
        case .top, .bottom: .center
        case .topTrailing, .trailing, .bottomTrailing: .trailing
        }
    }

    public var vertical: Vertical {
        switch self {
        case .topLeading, .top, .topTrailing: .top
        case .leading, .trailing: .center
        case .bottomLeading, .bottom, .bottomTrailing: .bottom
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch horizontal {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// The resolved position of the camera the person should look at, in the coordinate space
/// of the view that resolved it (origin at the top-leading corner of its safe area).
public struct CameraAnchor: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Read from an active `.occlusion` reserved region (iOS 27.1+, e.g. iPhone Duo).
        case reservedRegion
        /// Read from an inactive `.occlusion` region, because no region was active.
        case inactiveReservedRegion
        /// No reserved region was available, so the top centre of the screen is assumed (Dynamic Island / notch).
        case fallback
        /// Supplied by the host app.
        case override
    }

    /// The physical camera rect, without the interactive margins.
    public var cameraRect: CGRect
    /// The safe area the anchor was resolved against.
    public var safeRect: CGRect
    public var placement: AnchorPlacement
    public var source: Source
    /// The occlusion regions the anchor was resolved from, for diagnostics.
    public var regions: [RegionSnapshot] = []
    /// The whole window, including bars, in the same coordinates. `nil` until measured.
    public var screenRect: CGRect?
    /// Whether this display folds (it reports a hinge `.division` region, active or not). On
    /// iPhone Duo that means the inner display; the outer display and other iPhones don't fold.
    public var isOnFoldingDisplay = false

    public init(cameraRect: CGRect, safeRect: CGRect, placement: AnchorPlacement, source: Source) {
        self.cameraRect = cameraRect
        self.safeRect = safeRect
        self.placement = placement
        self.source = source
    }

    public var cameraCenter: CGPoint { CGPoint(x: cameraRect.midX, y: cameraRect.midY) }

    /// The capsule that grows out of the lens and carries the instruction.
    ///
    /// - A lens in a side bar (iPhone Duo's outer display) gets a tall `.vertical` capsule.
    /// - A lens at the top of the screen (the inner under-display camera, a Dynamic Island the
    ///   system reports) gets a wide `.drop`, like the island expanding.
    /// - `nil` when the lens position is only guessed (`.fallback`) or isn't at the top.
    ///
    /// Decided from the screen edges, not the safe area, so hiding the status bar (which can
    /// change the safe area) doesn't flip it.
    public var lensCapsule: LensCapsuleGeometry? {
        guard let screenRect, placement.vertical == .top, source != .fallback else { return nil }
        let edgeDistance = min(screenRect.maxX - cameraRect.midX, cameraRect.midX - screenRect.minX)
        guard screenRect.height > cameraRect.maxY + 240 else { return nil }
        guard edgeDistance < 70 else { return dropCapsule(in: screenRect) }

        // Wide enough for a word, narrow enough to stay inside the bar.
        let width = min(max(cameraRect.width * 1.9, 64), edgeDistance * 2 - 4)
        // Concentric with the lens, so the camera sits in the capsule's rounded top.
        let top = max(cameraRect.midY - width / 2, screenRect.minY + 4)
        // The system pill around the lens grows taller while the camera is in use (the green
        // privacy dot), beyond the reported lens rect. Leave room for it at its tallest.
        let pillBottom = cameraRect.minY + max(cameraRect.height, cameraRect.width * 1.75)
        return LensCapsuleGeometry(
            kind: .vertical,
            frame: CGRect(x: cameraRect.midX - width / 2, y: top, width: width, height: screenRect.maxY - top),
            contentTop: pillBottom + 10 - top,
            cornerRadius: width / 2
        )
    }

    private func dropCapsule(in screenRect: CGRect) -> LensCapsuleGeometry {
        // A rim around the pill, so its rounded top is concentric with the pill's ends.
        let rim: CGFloat = 7
        let radius = cameraRect.height / 2 + rim
        let width = min(max(240, cameraRect.width + rim * 2), screenRect.width - 32)
        let x = min(max(cameraRect.midX - width / 2, screenRect.minX + 16), screenRect.maxX - 16 - width)
        let top = max(cameraRect.minY - rim, screenRect.minY + 4)
        return LensCapsuleGeometry(
            kind: .drop,
            frame: CGRect(x: x, y: top, width: width, height: screenRect.maxY - top),
            contentTop: cameraRect.maxY + 8 - top,
            cornerRadius: min(radius, 30)
        )
    }


    /// The same anchor seen from a view whose leading edge is `inset` points further in.
    func shifted(byLeading inset: CGFloat) -> CameraAnchor {
        guard inset != 0 else { return self }
        var copy = self
        copy.cameraRect = cameraRect.offsetBy(dx: -inset, dy: 0)
        copy.safeRect = CGRect(x: safeRect.minX, y: safeRect.minY, width: safeRect.width - inset, height: safeRect.height)
        copy.screenRect = screenRect?.offsetBy(dx: -inset, dy: 0)
        return copy
    }

    /// The direction from the instruction stack toward the lens, as a rotation of an upward arrow.
    public var pointerAngle: Angle {
        let dx: CGFloat = if cameraRect.minX >= safeRect.maxX - 1 { 1 }
            else if cameraRect.maxX <= safeRect.minX + 1 { -1 }
            else { 0 }
        let dy: CGFloat = switch placement.vertical {
            case .top: -1
            case .center: 0
            case .bottom: 1
        }
        // (0, 0) can only happen for a centred camera; point up.
        let up = dx == 0 && dy == 0 ? -1 : dy
        return .radians(atan2(dx, -up))
    }
}

/// How the host app wants the camera located.
public enum CameraAnchorMode: Sendable, Equatable {
    /// Read reserved regions; fall back to the top centre.
    case automatic
    /// Ignore reserved regions and hug this edge of the safe area.
    case placement(AnchorPlacement)
    /// A camera rect the host measured itself, in the safe-area coordinate space.
    case rect(CGRect)
}

/// Where the under-lens capsule goes, in the anchor's coordinates.
public struct LensCapsuleGeometry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Tall and narrow, hanging from a lens in a side bar.
        case vertical
        /// Wide, dropping from a lens at the top of the screen.
        case drop
    }

    public var kind: Kind
    /// The capsule's horizontal extent and top. `height` is the room available; the capsule
    /// itself is only as tall as its content.
    public var frame: CGRect
    /// Distance from the capsule's top to where content may start, below the camera pill.
    public var contentTop: CGFloat
    public var cornerRadius: CGFloat

    /// About how tall the capsule's content makes it, for keeping other content clear.
    public var estimatedHeight: CGFloat {
        switch kind {
        case .vertical: contentTop + frame.width * 0.6 + 70 + frame.width * 0.32
        case .drop: contentTop + 46 + 22 + 16
        }
    }
}
