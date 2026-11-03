import CoreGraphics
import Testing
@testable import EyelineKit

struct FaceGlyphTests {
    @Test func turnLeftFacesScreenLeftLikeAMirror() {
        #expect(FaceGlyphPose(challenge: .turnLeft, t: 0.5).yaw == -1)
        #expect(FaceGlyphPose(challenge: .turnRight, t: 0.5).yaw == 1)
    }

    @Test func movesStartFromNeutral() {
        for challenge in LivenessChallenge.allCases where challenge != .shake {
            let start = FaceGlyphPose(challenge: challenge, t: 0)
            #expect(start.yaw == 0 && start.pitch == 0 && start.mouthOpen == 0 && start.scale == 1, "\(challenge)")
        }
    }

    @Test func blinkClosesMidLoop() {
        #expect(FaceGlyphPose(challenge: .blink, t: 0.48).eyeOpen == 0)
        #expect(FaceGlyphPose(challenge: .blink, t: 0.1).eyeOpen == 1)
    }
}

struct LensCapsuleTests {
    let safe = CGRect(x: 0, y: 0, width: 382, height: 640)
    let screen = CGRect(x: 0, y: -10, width: 466, height: 678)

    @Test func capsuleWrapsASideBarLens() throws {
        let lens = CGRect(x: 400, y: 29, width: 37, height: 37)
        let anchor = CameraAnchorResolver.resolve(
            regions: [RegionSnapshot(id: "o", frame: lens, isActive: true)], safeRect: safe, screenRect: screen)
        let capsule = try #require(anchor.lensCapsule)
        // Concentric with the lens: the camera sits in the rounded top.
        #expect(abs(capsule.frame.midX - lens.midX) < 0.01)
        #expect(abs((capsule.frame.minY + capsule.frame.width / 2) - lens.midY) < 0.01)
        // Stays inside the screen's bar.
        #expect(capsule.frame.maxX <= screen.maxX)
        // Content starts below the in-use pill (about 1.75 × the lens width tall), not the lens rect.
        #expect(capsule.frame.minY + capsule.contentTop >= lens.minY + lens.width * 1.75)
    }

    @Test func noCapsuleForTopCentreIsland() {
        let anchor = CameraAnchorResolver.resolve(regions: [], safeRect: safe, screenRect: screen)
        #expect(anchor.lensCapsule == nil)
    }
}

struct DropCapsuleTests {
    // Inner display, landscape: under-display camera in use near the top, inside the content.
    let safe = CGRect(x: 0, y: 0, width: 867, height: 611)
    let screen = CGRect(x: 0, y: -24, width: 951, height: 669)
    let udc = RegionSnapshot(id: "udc", frame: CGRect(x: 677, y: -3, width: 58, height: 37), isActive: true)

    @Test func underDisplayCameraGetsADrop() throws {
        let anchor = CameraAnchorResolver.resolve(regions: [udc], safeRect: safe, screenRect: screen, isOnFoldingDisplay: true)
        let capsule = try #require(anchor.lensCapsule)
        #expect(capsule.kind == .drop)
        #expect(abs(capsule.frame.midX - udc.frame.midX) < 0.01)      // centred on the lens
        #expect(capsule.frame.minY < udc.frame.minY)                   // the pill sits inside its top
        #expect(capsule.frame.minY + capsule.contentTop > udc.frame.maxY) // content starts below it
        #expect(capsule.frame.maxX <= screen.maxX - 16)
        #expect(anchor.isOnFoldingDisplay)
    }

    @Test func dropIsClampedOnScreen() throws {
        let corner = RegionSnapshot(id: "c", frame: CGRect(x: 760, y: -3, width: 58, height: 37), isActive: true) // 78 pt from the edge: a drop, not a side bar
        let anchor = CameraAnchorResolver.resolve(regions: [corner], safeRect: safe, screenRect: CGRect(x: 0, y: -24, width: 867, height: 669))
        let capsule = try #require(anchor.lensCapsule)
        #expect(capsule.kind == .drop)
        #expect(capsule.frame.maxX <= CGFloat(851))
    }

    @Test func guessedLensGetsNoCapsule() {
        let anchor = CameraAnchorResolver.resolve(regions: [], safeRect: safe, screenRect: screen)
        #expect(anchor.lensCapsule == nil)
    }
}
