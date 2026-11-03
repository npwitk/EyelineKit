import CoreGraphics

/// A platform-neutral copy of a reserved region, so resolution is a pure, testable function.
public struct RegionSnapshot: Sendable, Hashable {
    public var id: String
    /// The region's frame *including* its margins, as the system reports it.
    public var frame: CGRect
    public var marginTop: CGFloat
    public var marginLeading: CGFloat
    public var marginBottom: CGFloat
    public var marginTrailing: CGFloat
    public var isActive: Bool

    public init(
        id: String,
        frame: CGRect,
        marginTop: CGFloat = 0,
        marginLeading: CGFloat = 0,
        marginBottom: CGFloat = 0,
        marginTrailing: CGFloat = 0,
        isActive: Bool
    ) {
        self.id = id
        self.frame = frame
        self.marginTop = marginTop
        self.marginLeading = marginLeading
        self.marginBottom = marginBottom
        self.marginTrailing = marginTrailing
        self.isActive = isActive
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> RegionSnapshot {
        var copy = self
        copy.frame = frame.offsetBy(dx: dx, dy: dy)
        return copy
    }

    /// The physical rect: `frame` already includes the margins, so take them back off.
    public var bareRect: CGRect {
        CGRect(
            x: frame.minX + marginLeading,
            y: frame.minY + marginTop,
            width: max(0, frame.width - marginLeading - marginTrailing),
            height: max(0, frame.height - marginTop - marginBottom)
        )
    }
}

public enum CameraAnchorResolver {
    /// Picks the camera to look at and where the instructions should go.
    ///
    /// - Parameters:
    ///   - regions: `.occlusion` regions, queried with `.includeInactive`.
    ///   - safeRect: the safe area in the same coordinate space as `regions`.
    ///   - preferredID: the region that most recently became active. The inner under-display
    ///     camera only becomes active while a capture session runs, so a fresh activation is
    ///     the strongest hint of which lens is in use.
    ///   - mode: the host's override, if any.
    ///   - screenRect: the whole window in the same coordinates, if known.
    public static func resolve(
        regions: [RegionSnapshot],
        safeRect: CGRect,
        screenRect: CGRect? = nil,
        isOnFoldingDisplay: Bool = false,
        preferredID: String? = nil,
        mode: CameraAnchorMode = .automatic
    ) -> CameraAnchor {
        var anchor = resolveIgnoringScreen(regions: regions, safeRect: safeRect, preferredID: preferredID, mode: mode)
        anchor.screenRect = screenRect
        anchor.isOnFoldingDisplay = isOnFoldingDisplay
        return anchor
    }

    private static func resolveIgnoringScreen(
        regions: [RegionSnapshot],
        safeRect: CGRect,
        preferredID: String?,
        mode: CameraAnchorMode
    ) -> CameraAnchor {
        switch mode {
        case .placement(let placement):
            return CameraAnchor(
                cameraRect: rect(for: placement, in: safeRect),
                safeRect: safeRect,
                placement: placement,
                source: .override
            )
        case .rect(let rect):
            return CameraAnchor(
                cameraRect: rect,
                safeRect: safeRect,
                placement: placement(of: rect, in: safeRect),
                source: .override
            )
        case .automatic:
            break
        }

        let usable = regions.filter { $0.bareRect.width > 0 && $0.bareRect.height > 0 }
        let active = usable.filter(\.isActive)
        // An inactive occlusion still marks where a lens physically is; it beats guessing.
        let candidates = active.isEmpty ? usable : active
        let chosen = candidates.first { $0.id == preferredID }
            ?? candidates.min { area($0.bareRect) < area($1.bareRect) }

        guard let chosen else {
            var anchor = CameraAnchor(
                cameraRect: rect(for: .top, in: safeRect),
                safeRect: safeRect,
                placement: .top,
                source: .fallback
            )
            anchor.regions = regions
            return anchor
        }
        let bare = chosen.bareRect
        var anchor = CameraAnchor(
            cameraRect: bare,
            safeRect: safeRect,
            placement: placement(of: bare, in: safeRect),
            source: chosen.isActive ? .reservedRegion : .inactiveReservedRegion
        )
        anchor.regions = regions
        return anchor
    }

    /// Classifies a camera rect into thirds of the safe area.
    public static func placement(of rect: CGRect, in safeRect: CGRect) -> AnchorPlacement {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let third = CGSize(width: safeRect.width / 3, height: safeRect.height / 3)

        let horizontal: AnchorPlacement.Horizontal =
            if center.x < safeRect.minX + third.width { .leading }
            else if center.x > safeRect.maxX - third.width { .trailing }
            else { .center }

        let vertical: AnchorPlacement.Vertical =
            if center.y < safeRect.minY + third.height { .top }
            else if center.y > safeRect.maxY - third.height { .bottom }
            else { .center }

        return AnchorPlacement(horizontal: horizontal, vertical: vertical)
    }

    /// A small stand-in rect just outside the safe area at the given edge.
    static func rect(for placement: AnchorPlacement, in safeRect: CGRect) -> CGRect {
        let size: CGFloat = 12
        let x: CGFloat = switch placement.horizontal {
            case .leading: safeRect.minX - size
            case .center: safeRect.midX - size / 2
            case .trailing: safeRect.maxX
        }
        let y: CGFloat = switch placement.vertical {
            case .top: safeRect.minY - size
            case .center: safeRect.midY - size / 2
            case .bottom: safeRect.maxY
        }
        return CGRect(x: x, y: y, width: size, height: size)
    }

    /// Same region seen by two readers: keep the first list's copy. Readers can report the same
    /// region under different IDs, so a matching frame also counts as a duplicate.
    public static func merge(_ primary: [RegionSnapshot], _ secondary: [RegionSnapshot]) -> [RegionSnapshot] {
        let ids = Set(primary.map(\.id))
        return primary + secondary.filter { candidate in
            !ids.contains(candidate.id) && !primary.contains { sameFrame($0.frame, candidate.frame) }
        }
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}
