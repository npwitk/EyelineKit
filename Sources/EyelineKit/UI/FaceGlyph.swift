import SwiftUI

/// A line-drawn face in the style of the Face ID symbol (corner brackets, eyes, nose, smile)
/// whose features act out a challenge: they shake, turn, tilt, blink, smile, open the mouth, or
/// grow and shrink inside the brackets for closer/away.
///
/// The brackets stay put as a frame of reference while the features move. Turns are mirrored:
/// a turn toward the screen's left is the person's left.
public struct FaceGlyph: View {
    var challenge: LivenessChallenge?
    var color: Color
    var period: Double
    var animates: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ challenge: LivenessChallenge?, color: Color = .primary, period: Double = 1.6, animates: Bool = true) {
        self.challenge = challenge
        self.color = color
        self.period = period
        self.animates = animates
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !animates)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            // With Reduce Motion, show the key pose of the move instead of looping it.
            let pose = FaceGlyphPose(challenge: challenge, t: reduceMotion || !animates ? 0.5 : t)
            Canvas { canvas, size in
                Self.draw(pose, in: &canvas, size: min(size.width, size.height), color: color)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func draw(_ pose: FaceGlyphPose, in canvas: inout GraphicsContext, size s: CGFloat, color: Color) {
        let lineWidth = s * 0.075
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(color)

        // Corner brackets.
        let inset = lineWidth / 2 + s * 0.03 * pose.bracketsIn
        let length = s * 0.24
        let radius = s * 0.13
        var brackets = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: inset, y: inset), 1, 1),
            (CGPoint(x: s - inset, y: inset), -1, 1),
            (CGPoint(x: inset, y: s - inset), 1, -1),
            (CGPoint(x: s - inset, y: s - inset), -1, -1),
        ]
        for (corner, sx, sy) in corners {
            brackets.move(to: CGPoint(x: corner.x, y: corner.y + sy * length))
            brackets.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + sx * length, y: corner.y), radius: radius)
            brackets.addLine(to: CGPoint(x: corner.x + sx * length, y: corner.y))
        }
        canvas.stroke(brackets, with: ink, style: style)

        // Features, moved as one face. The nose moves a little more than the eyes for depth.
        let k = pose.scale
        let center = CGPoint(x: s / 2 + pose.yaw * s * 0.10, y: s / 2 + pose.pitch * s * 0.09)
        var features = Path()

        // Eyes: short vertical strokes that close to dashes on a blink.
        for side in [-1.0, 1.0] {
            let foreshorten = 1 - max(0, side * pose.yaw) * 0.35
            let x = center.x + side * s * 0.13 * k * (1 - abs(pose.yaw) * 0.12)
            let y = center.y - s * 0.09 * k
            if pose.eyeOpen < 0.25 {
                features.move(to: CGPoint(x: x - s * 0.035, y: y))
                features.addLine(to: CGPoint(x: x + s * 0.035, y: y))
            } else {
                let half = s * 0.05 * k * pose.eyeOpen * foreshorten
                features.move(to: CGPoint(x: x, y: y - half))
                features.addLine(to: CGPoint(x: x, y: y + half))
            }
        }

        // Nose: the Face ID "J".
        let nose = CGPoint(x: center.x + pose.yaw * s * 0.03, y: center.y)
        features.move(to: CGPoint(x: nose.x + s * 0.015, y: nose.y - s * 0.10 * k))
        features.addLine(to: CGPoint(x: nose.x + s * 0.015, y: nose.y + s * 0.03 * k))
        features.addQuadCurve(
            to: CGPoint(x: nose.x - s * 0.04 * k, y: nose.y + s * 0.05 * k),
            control: CGPoint(x: nose.x + s * 0.015, y: nose.y + s * 0.06 * k)
        )

        // Mouth: a smile that deepens, or an open "O".
        let mouthY = center.y + s * 0.17 * k
        let mouthHalf = s * 0.12 * k * (1 + pose.smile * 0.25)
        if pose.mouthOpen > 0.08 {
            let h = s * 0.16 * k * pose.mouthOpen
            let w = mouthHalf * 1.3
            features.addEllipse(in: CGRect(x: center.x - w / 2, y: mouthY - h / 2 + s * 0.01, width: w, height: max(h, lineWidth)))
        } else {
            features.move(to: CGPoint(x: center.x - mouthHalf, y: mouthY))
            features.addQuadCurve(
                to: CGPoint(x: center.x + mouthHalf, y: mouthY),
                control: CGPoint(x: center.x, y: mouthY + s * (0.07 + pose.smile * 0.08) * k)
            )
        }
        canvas.stroke(features, with: ink, style: style)
    }
}

/// The glyph's pose at a point in the loop. Pure, so it can be tested.
struct FaceGlyphPose: Equatable {
    /// -1 (screen left, the person's left) … 1
    var yaw: Double = 0
    /// -1 (up) … 1 (down)
    var pitch: Double = 0
    var eyeOpen: Double = 1
    var mouthOpen: Double = 0
    var smile: Double = 0
    var scale: Double = 1
    /// 0…1: brackets draw in, "focusing" on the face.
    var bracketsIn: Double = 0

    init(challenge: LivenessChallenge?, t: Double) {
        let pulse = Self.pulse(t)
        let wave = sin(t * 2 * .pi)
        switch challenge {
        case .blink: eyeOpen = (0.40...0.56).contains(t) ? 0 : 1
        case .turnLeft: yaw = -pulse
        case .turnRight: yaw = pulse
        case .lookUp: pitch = -pulse
        case .shake: yaw = wave
        case .smile: smile = pulse
        case .openMouth: mouthOpen = pulse
        case .moveCloser: scale = 1 + 0.22 * pulse
        case .moveAway: scale = 1 - 0.25 * pulse
        case .centerFace: bracketsIn = pulse
        case .holdStill, nil: break
        }
    }

    /// 0 → 1, hold, → 0 across the loop.
    static func pulse(_ t: Double) -> Double {
        func smooth(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        if t < 0.3 { return smooth(t / 0.3) }
        if t < 0.65 { return 1 }
        return 1 - smooth((t - 0.65) / 0.3)
    }
}
