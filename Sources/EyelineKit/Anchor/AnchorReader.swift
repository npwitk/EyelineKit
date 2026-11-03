import SwiftUI

/// Reads where the camera is and hands the anchor to its content.
///
/// The anchor is in the reader's own coordinate space: its origin is the top-leading corner of
/// the safe area, and the camera rect may lie outside it (in a bar or bezel). It updates when the
/// device folds, rotates or moves between displays, and when the under-display camera turns on.
public struct CameraAnchorReader<Content: View>: View {
    private let mode: CameraAnchorMode
    private let content: (CameraAnchor) -> Content
    @State private var preferredID: String?
    @State private var lastActiveIDs: Set<String> = []
    /// Regions read by a full-screen reader, in global coordinates. The lens usually sits in a
    /// bar or bezel outside the safe area, so a reader confined to the safe area may not see it.
    @State private var fullScreenRegions: [RegionSnapshot] = []
    @State private var fullScreenFrame: CGRect?

    public init(mode: CameraAnchorMode = .automatic, @ViewBuilder content: @escaping (CameraAnchor) -> Content) {
        self.mode = mode
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let regions = CameraAnchorResolver.merge(
                Self.occlusionRegions(in: proxy),
                fullScreenRegions.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
            )
            let safeRect = CGRect(origin: .zero, size: proxy.size)
            let anchor = CameraAnchorResolver.resolve(
                regions: regions,
                safeRect: safeRect,
                screenRect: fullScreenFrame?.offsetBy(dx: -origin.x, dy: -origin.y),
                isOnFoldingDisplay: Self.hasFold(proxy),
                preferredID: preferredID,
                mode: mode
            )
            content(anchor)
                .onChange(of: regions, initial: true) { _, newValue in
                    trackActivation(newValue)
                }
        }
        .background {
            GeometryReader { full in
                let origin = full.frame(in: .global).origin
                let regions = Self.occlusionRegions(in: full).map { $0.offsetBy(dx: origin.x, dy: origin.y) }
                let frame = full.frame(in: .global)
                Color.clear
                    .onChange(of: regions, initial: true) { _, newValue in
                        fullScreenRegions = newValue
                    }
                    .onChange(of: frame, initial: true) { _, newValue in
                        fullScreenFrame = newValue
                    }
            }
            .ignoresSafeArea()
        }
    }


    private func trackActivation(_ regions: [RegionSnapshot]) {
        let active = Set(regions.filter(\.isActive).map(\.id))
        // A region that just switched on is most likely the lens the capture session opened.
        if let fresh = active.subtracting(lastActiveIDs).first, !lastActiveIDs.isEmpty {
            preferredID = fresh
        }
        if let preferredID, !active.contains(preferredID) {
            self.preferredID = nil
        }
        lastActiveIDs = active
    }

    /// A hinge region exists (even inactive, while the display is flat) only on a folding display.
    static func hasFold(_ proxy: GeometryProxy) -> Bool {
        guard #available(iOS 27.1, *) else { return false }
        return !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }

    static func occlusionRegions(in proxy: GeometryProxy) -> [RegionSnapshot] {
        guard #available(iOS 27.1, *) else { return [] }
        return proxy.reservedRegions(kind: .occlusion, options: .includeInactive).map { region in
            RegionSnapshot(
                id: String(describing: region.id),
                frame: region.frame,
                marginTop: region.margins.top,
                marginLeading: region.margins.leading,
                marginBottom: region.margins.bottom,
                marginTrailing: region.margins.trailing,
                isActive: region.isActive
            )
        }
    }
}
