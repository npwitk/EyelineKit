import SwiftUI

/// Which displays a check may run on.
public enum EyelineDisplaySupport: Sendable, Equatable {
    /// Run wherever the app is.
    case allDisplays
    /// On a folding iPhone's inner display, ask the person to close the device and use the outer
    /// display, whose camera is far sharper than the under-display one. Displays that don't fold
    /// (the outer display, other iPhones, iPad) are unaffected.
    case outerDisplayOnly
}

/// "Close your iPhone to continue", with a phone that folds shut to reveal the outer display.
public struct FoldPrompt: View {
    var tint: Color
    var title: String
    var message: String

    public init(
        tint: Color = Color(red: 0.75, green: 0.94, blue: 0.62),
        title: String? = nil,
        message: String? = nil
    ) {
        self.tint = tint
        self.title = title ?? String(localized: "fold.title", defaultValue: "Close your iPhone to continue", bundle: .module)
        self.message = message ?? String(localized: "fold.body", defaultValue: "The face check uses the outer camera. It's much sharper than the camera under this screen.", bundle: .module)
    }

    public var body: some View {
        VStack(spacing: 28) {
            FoldingPhone(tint: tint)
                .frame(width: 172, height: 122)
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
        }
        .padding(32)
        .accessibilityElement(children: .combine)
    }
}

/// iPhone Duo closing like a book, drawn to scale.
///
/// Facing the inner display, the left half carries the outer display on its back. It swings
/// toward you over the right half, the outer display turns into view (hinge on its left, camera
/// top-right), and the camera lights up.
///
/// Measurements, in millimetres: body from Apple's specs (164.6 × 117.8 open, 84.1 × 117.8
/// closed); display corners, bezels and the camera position from the iPhone Duo simulator's
/// display masks and reserved regions (outer display 466 × 678 pt at ≈ 6.04 pt/mm; corners
/// 7 pt on the hinge side and 65 pt on the free side; camera centred at 418.5, 47.5 pt; inner
/// display corners 58.7 pt).
struct FoldingPhone: View {
    var tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Spec {
        static let height = 117.8
        static let halfWidth = 82.3          // 164.6 / 2
        static let bodyCorner = 14.0         // free-edge corners of the body
        static let hingeCorner = 3.0         // the closed phone's hinge edge
        static let bezel = 3.45
        static let outerBezelTopBottom = 2.75
        static let innerDisplayCorner = 9.7
        static let outerDisplayCorner = 10.8 // free side
        static let outerDisplayHingeCorner = 1.2
        static let outerCamera = CGPoint(x: 72.7, y: 10.6) // from the closed phone's top-left
        static let cameraDiameter = 6.1
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = reduceMotion ? Self.Phase(angle: 180, glow: 1) : Self.phase(at: context.date.timeIntervalSinceReferenceDate)
            GeometryReader { proxy in
                let mm = min(proxy.size.height / Spec.height, proxy.size.width / (Spec.halfWidth * 2))
                let half = CGSize(width: Spec.halfWidth * mm, height: Spec.height * mm)
                // Slide so the closed phone ends up centred where the open one was.
                let slide = -half.width / 2 * (phase.angle / 180)
                HStack(spacing: 0) {
                    leftHalf(phase: phase, mm: mm)
                        .frame(width: half.width, height: half.height)
                        .rotation3DEffect(.degrees(phase.angle), axis: (x: 0, y: 1, z: 0),
                                          anchor: .trailing, anchorZ: 0, perspective: 0.35)
                        .zIndex(1)
                    rightHalf(mm: mm)
                        .frame(width: half.width, height: half.height)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(x: slide)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Halves

    /// The half that stays put: inner display's right half, round corners on the right.
    private func rightHalf(mm: CGFloat) -> some View {
        let body = UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: Spec.bodyCorner * mm, topTrailing: Spec.bodyCorner * mm), style: .continuous)
        let screen = UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: Spec.innerDisplayCorner * mm, topTrailing: Spec.innerDisplayCorner * mm), style: .continuous)
        return body.fill(Self.titanium)
            .overlay {
                screen.fill(Self.glass)
                    .padding(.vertical, Spec.bezel * mm)
                    .padding(.trailing, Spec.bezel * mm)
            }
            .overlay(alignment: .leading) { crease(mm: mm) }
    }

    /// The half that swings: inner display's left half in front, outer display on the back.
    @ViewBuilder
    private func leftHalf(phase: Phase, mm: CGFloat) -> some View {
        let edgeOn = abs(sin(phase.angle * .pi / 180))
        ZStack {
            if phase.angle < 90 {
                let body = UnevenRoundedRectangle(cornerRadii: .init(topLeading: Spec.bodyCorner * mm, bottomLeading: Spec.bodyCorner * mm), style: .continuous)
                let screen = UnevenRoundedRectangle(cornerRadii: .init(topLeading: Spec.innerDisplayCorner * mm, bottomLeading: Spec.innerDisplayCorner * mm), style: .continuous)
                body.fill(Self.titanium)
                    .overlay {
                        screen.fill(Self.glass)
                            .padding(.vertical, Spec.bezel * mm)
                            .padding(.leading, Spec.bezel * mm)
                    }
                    .overlay(alignment: .trailing) { crease(mm: mm) }
            } else {
                outerSide(glow: phase.glow, mm: mm)
                    .scaleEffect(x: -1) // drawn as seen when closed; the 180° turn mirrors it back
            }
        }
        // Darken as it turns edge-on, like light falling off. `brightness` touches only the drawn
        // shape, so the rounded corners stay clean.
        .brightness(-0.22 * edgeOn)
    }

    /// The closed phone's face: outer display, hinge on the left, camera top-right.
    private func outerSide(glow: Double, mm: CGFloat) -> some View {
        let body = UnevenRoundedRectangle(cornerRadii: .init(topLeading: Spec.hingeCorner * mm, bottomLeading: Spec.hingeCorner * mm,
                                                             bottomTrailing: Spec.bodyCorner * mm, topTrailing: Spec.bodyCorner * mm),
                                          style: .continuous)
        let screen = UnevenRoundedRectangle(cornerRadii: .init(topLeading: Spec.outerDisplayHingeCorner * mm, bottomLeading: Spec.outerDisplayHingeCorner * mm,
                                                               bottomTrailing: Spec.outerDisplayCorner * mm, topTrailing: Spec.outerDisplayCorner * mm),
                                            style: .continuous)
        let lens = Spec.cameraDiameter * mm
        return body.fill(Self.titanium)
            .overlay {
                screen.fill(Self.glass)
                    .padding(.horizontal, Spec.bezel * mm)
                    .padding(.vertical, Spec.outerBezelTopBottom * mm)
            }
            .overlay(alignment: .topLeading) {
                ZStack {
                    Circle()
                        .stroke(tint, lineWidth: lens * 0.35)
                        .frame(width: lens * (1.4 + glow), height: lens * (1.4 + glow))
                        .opacity(glow * (1 - glow * 0.5))
                    Circle().fill(tint.opacity(0.55 * glow)).frame(width: lens * 1.8).blur(radius: lens * 0.4)
                    Circle().fill(.black).frame(width: lens, height: lens)
                }
                .frame(width: lens * 4, height: lens * 4)
                .position(x: Spec.outerCamera.x * mm, y: Spec.outerCamera.y * mm)
            }
    }

    private func crease(mm: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: max(0.5, 0.4 * mm))
            .padding(.vertical, Spec.bezel * mm)
    }

    private static let titanium = Color(red: 0.86, green: 0.86, blue: 0.84)
    private static let glass = Color(red: 0.07, green: 0.08, blue: 0.09)

    // MARK: Timing

    struct Phase: Equatable {
        /// 0 = open flat, 180 = closed.
        var angle: Double
        /// 0…1 camera glow once closed.
        var glow: Double
    }

    /// Open (0.6 s) → fold (1.1 s) → closed with the camera glowing (1.5 s) → open (0.6 s).
    static func phase(at time: TimeInterval) -> Phase {
        let t = time.truncatingRemainder(dividingBy: 3.8)
        func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2 }
        switch t {
        case ..<0.6: return Phase(angle: 0, glow: 0)
        case ..<1.7: return Phase(angle: 180 * ease((t - 0.6) / 1.1), glow: 0)
        case ..<3.2:
            let pulse = sin(min((t - 1.7) / 1.5, 1) * .pi)
            return Phase(angle: 180, glow: pulse)
        default: return Phase(angle: 180 * (1 - ease((t - 3.2) / 0.6)), glow: 0)
        }
    }
}
