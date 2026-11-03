import CoreGraphics
import Testing
@testable import EyelineKit

/// Region numbers measured on the iPhone Duo simulator (see the iphone-duo-adaptation skill's
/// device-and-metrics reference). Coordinates are relative to the safe area.
struct CameraAnchorTests {
    // Inner display, landscape: 867 x 611 content, bar-corner occlusion active, UDC inactive.
    let innerLandscape = CGRect(x: 0, y: 0, width: 867, height: 611)
    let barCorner = RegionSnapshot(id: "bar", frame: CGRect(x: 867, y: -24, width: 84, height: 120), isActive: true)
    let udcOff = RegionSnapshot(id: "udc", frame: CGRect(x: 677.3, y: -3, width: 58, height: 37), isActive: false)
    var udcOn: RegionSnapshot { var r = udcOff; r.isActive = true; return r }

    @Test func outerDisplayCameraInTrailingBarHugsTopTrailing() {
        // Outer display, portrait: ~382 wide content, camera in the trailing vertical bar at the top.
        let safe = CGRect(x: 0, y: 0, width: 382, height: 640)
        let camera = RegionSnapshot(id: "outer", frame: CGRect(x: 392, y: 8, width: 60, height: 60),
                                    marginTop: 6, marginLeading: 6, marginBottom: 6, marginTrailing: 6, isActive: true)
        let anchor = CameraAnchorResolver.resolve(regions: [camera], safeRect: safe)
        #expect(anchor.source == .reservedRegion)
        #expect(anchor.placement == .topTrailing)
        #expect(anchor.cameraRect == CGRect(x: 398, y: 14, width: 48, height: 48))
        #expect(abs(anchor.pointerAngle.degrees - 45) < 0.001)
    }

    @Test func inactiveRegionsAreIgnored() {
        let anchor = CameraAnchorResolver.resolve(regions: [barCorner, udcOff], safeRect: innerLandscape)
        #expect(anchor.cameraRect == barCorner.frame)
    }

    @Test func underDisplayCameraWinsOnceItTurnsOn() {
        // Both active: the smaller (the lens itself) is picked even without activation history.
        let anchor = CameraAnchorResolver.resolve(regions: [barCorner, udcOn], safeRect: innerLandscape)
        #expect(anchor.cameraRect == udcOn.frame)
        #expect(anchor.placement == .topTrailing)
    }

    @Test func preferredIDBeatsSize() {
        let anchor = CameraAnchorResolver.resolve(regions: [barCorner, udcOn], safeRect: innerLandscape, preferredID: "bar")
        #expect(anchor.cameraRect == barCorner.frame)
    }

    @Test func noRegionsFallsBackToTopCenter() {
        let anchor = CameraAnchorResolver.resolve(regions: [], safeRect: CGRect(x: 0, y: 0, width: 402, height: 800))
        #expect(anchor.source == .fallback)
        #expect(anchor.placement == .top)
        #expect(anchor.pointerAngle.degrees == 0)
    }

    @Test func overridesWin() {
        let safe = CGRect(x: 0, y: 0, width: 400, height: 800)
        let placed = CameraAnchorResolver.resolve(regions: [barCorner], safeRect: safe, mode: .placement(.bottomLeading))
        #expect(placed.placement == .bottomLeading)
        #expect(placed.source == .override)
        let rect = CameraAnchorResolver.resolve(regions: [], safeRect: safe, mode: .rect(CGRect(x: 380, y: 390, width: 20, height: 20)))
        #expect(rect.placement == .trailing)
    }

    @Test(arguments: [
        (CGPoint(x: 10, y: 10), AnchorPlacement.topLeading),
        (CGPoint(x: 200, y: -20), .top),
        (CGPoint(x: 410, y: 10), .topTrailing),
        (CGPoint(x: -10, y: 400), .leading),
        (CGPoint(x: 200, y: 820), .bottom),
        (CGPoint(x: 390, y: 790), .bottomTrailing),
    ])
    func placementThirds(center: CGPoint, expected: AnchorPlacement) {
        let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        #expect(CameraAnchorResolver.placement(of: rect, in: CGRect(x: 0, y: 0, width: 400, height: 800)) == expected)
    }
}

struct CameraHuggingLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 382, height: 640)

    @Test func columnHugsCameraInTrailingBar() {
        let anchor = CameraAnchor(cameraRect: CGRect(x: 398, y: 14, width: 48, height: 48), safeRect: bounds,
                                  placement: .topTrailing, source: .reservedRegion)
        let frames = CameraHuggingLayout.frames(anchor: anchor, bounds: bounds, sizes: [CGSize(width: 200, height: 80), CGSize(width: 160, height: 160)])
        // Instruction: against the trailing edge, level with the lens (not pushed below it).
        #expect(frames[0].maxX == CGFloat(366))
        #expect(frames[0].minY == CGFloat(14))
        // Preview: right under the instruction, also trailing-aligned.
        #expect(frames[1].maxX == CGFloat(366))
        #expect(frames[1].minY == frames[0].maxY + 14)
    }

    @Test func columnGoesBelowALensInsideTheSafeArea() {
        let safe = CGRect(x: 0, y: 0, width: 867, height: 611)
        let anchor = CameraAnchor(cameraRect: CGRect(x: 677, y: -3, width: 58, height: 37), safeRect: safe,
                                  placement: .topTrailing, source: .reservedRegion)
        let frames = CameraHuggingLayout.frames(anchor: anchor, bounds: safe, sizes: [CGSize(width: 220, height: 80)])
        #expect(frames[0].minY == CGFloat(48))
        // Gaze target (22 pt in from the trailing edge) sits under the lens centre.
        #expect(frames[0].maxX == CGFloat(728))
    }

    @Test func topCenterIsCentredUnderTheIsland() {
        let safe = CGRect(x: 0, y: 0, width: 402, height: 800)
        let anchor = CameraAnchorResolver.resolve(regions: [], safeRect: safe)
        let frames = CameraHuggingLayout.frames(anchor: anchor, bounds: safe, sizes: [CGSize(width: 200, height: 60)])
        #expect(frames[0].midX == CGFloat(201))
        #expect(frames[0].minY == CGFloat(14)) // island bottom (0) + spacing
    }

    @Test func bottomCameraReversesOrder() {
        let safe = CGRect(x: 0, y: 0, width: 400, height: 800)
        let anchor = CameraAnchor(cameraRect: CGRect(x: 195, y: 805, width: 10, height: 10), safeRect: safe,
                                  placement: .bottom, source: .override)
        let frames = CameraHuggingLayout.frames(anchor: anchor, bounds: safe, sizes: [CGSize(width: 100, height: 50), CGSize(width: 100, height: 100)])
        #expect(frames[0].minY > frames[1].minY) // nearest item is lowest
        #expect(frames[0].maxY <= CGFloat(792))
    }
}

struct InactiveRegionTests {
    @Test func inactiveCameraBeatsTopCentreGuess() {
        let safe = CGRect(x: 0, y: 0, width: 382, height: 640)
        let lens = RegionSnapshot(id: "outer", frame: CGRect(x: 392, y: 8, width: 60, height: 60), isActive: false)
        let anchor = CameraAnchorResolver.resolve(regions: [lens], safeRect: safe)
        #expect(anchor.source == .inactiveReservedRegion)
        #expect(anchor.placement == .topTrailing)
        #expect(anchor.regions == [lens])
    }

    @Test func mergeKeepsPrimaryCopy() {
        let a = RegionSnapshot(id: "x", frame: .zero, isActive: true)
        let b = RegionSnapshot(id: "x", frame: CGRect(x: 1, y: 1, width: 1, height: 1), isActive: false)
        let c = RegionSnapshot(id: "y", frame: CGRect(x: 50, y: 50, width: 10, height: 10), isActive: false)
        let d = RegionSnapshot(id: "z", frame: CGRect(x: 1, y: 1, width: 1, height: 1), isActive: true)
        #expect(CameraAnchorResolver.merge([a], [b, c]) == [a, c])
        #expect(CameraAnchorResolver.merge([d], [b]) == [d]) // same frame, different id

    }
}
