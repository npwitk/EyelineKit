import SwiftUI

/// Colours for the under-lens capsule.
public struct LensCapsuleStyle: Sendable {
    public var fill = Color(red: 0.75, green: 0.94, blue: 0.62)
    /// Used while the engine reports a problem ("No face found").
    public var warningFill = Color(red: 1.0, green: 0.84, blue: 0.56)
    public var ink = Color(red: 0.10, green: 0.14, blue: 0.08)
    public var showsRipple = true
    /// A refraction wave from the lens at the start and at every new instruction, like the
    /// pulse iOS plays around the under-display camera.
    public var pulsesFromLens = true
    /// How far the pulse bends the content at its peak, in points.
    public var pulseStrength: CGFloat = 14

    public init() {}
}

/// A capsule that grows down out of the lens: the camera sits in its rounded top, and below it
/// a Face ID-style glyph acts out the move above a word or two.
struct LensCapsule: View {
    var session: EyelineSession
    var geometry: LensCapsuleGeometry
    var style: LensCapsuleStyle

    var body: some View {
        let fill = session.feedback == nil ? style.fill : style.warningFill
        let shape = TopStartRoundedRect(cornerRadius: geometry.cornerRadius)
        content
            .padding(.top, geometry.contentTop)
            .frame(width: geometry.frame.width)
            .background {
                shape
                    .fill(fill)
                    .shadow(color: fill.opacity(0.9), radius: 14)
                shape
                    .trim(from: 0, to: session.phase == .passed ? 1 : session.overallProgress)
                    .stroke(style.ink.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(1.5)
            }
            .animation(.smooth, value: session.challenge)
            .animation(.smooth, value: session.feedback)
            .animation(.smooth, value: session.overallProgress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
    }

    @ViewBuilder
    private var content: some View {
        let width = geometry.frame.width
        switch geometry.kind {
        case .vertical:
            VStack(spacing: 6) {
                glyph
                    .frame(width: width * 0.6, height: width * 0.6)
                label(size: 15, lines: 3)
                    .padding(.horizontal, 5)
                pips.padding(.top, 2)
            }
            .padding(.bottom, width * 0.32)
        case .drop:
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    glyph
                        .frame(width: 46, height: 46)
                    label(size: 22, lines: 2)
                }
                pips
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func label(size: CGFloat, lines: Int) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(style.ink)
            .multilineTextAlignment(geometry.kind == .vertical ? .center : .leading)
            .lineLimit(lines)
            .minimumScaleFactor(0.65)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
    }

    @ViewBuilder
    private var pips: some View {
        if session.stepCount > 1 {
            StepPips(count: session.stepCount, current: session.stepIndex, passed: session.phase == .passed, ink: style.ink,
                     availableWidth: geometry.frame.width - (geometry.kind == .vertical ? 16 : 36))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch session.phase {
        case .passed:
            Image(systemName: "checkmark")
                .resizable().scaledToFit().fontWeight(.bold).padding(6)
                .foregroundStyle(style.ink)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "arrow.clockwise")
                .resizable().scaledToFit().fontWeight(.bold).padding(6)
                .foregroundStyle(style.ink)
        case .idle, .running:
            FaceGlyph(session.challenge, color: style.ink)
                .id(session.challenge)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var text: String {
        switch session.phase {
        case .passed: String(localized: "result.passed", defaultValue: "Done", bundle: .module)
        case .failed: String(localized: "result.failed", defaultValue: "Let's try again", bundle: .module)
        case .idle, .running: session.feedback?.message ?? session.challenge?.prompt ?? ""
        }
    }
}

/// A rounded rectangle whose outline starts at the top centre, so a progress trim begins at the
/// camera and runs clockwise around. With a radius of half the width it's a vertical capsule.
struct TopStartRoundedRect: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct StepPips: View {
    var count: Int
    var current: Int
    var passed: Bool
    var ink: Color
    var availableWidth: CGFloat

    /// Dots are 5 pt (7 pt for the current one) with 4 pt gaps.
    static func dotsWidth(count: Int) -> CGFloat {
        CGFloat(count) * 5 + 2 + CGFloat(max(count - 1, 0)) * 4
    }

    var body: some View {
        Group {
            if Self.dotsWidth(count: count) <= availableWidth {
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(ink.opacity(passed || index <= current ? 0.85 : 0.22))
                            .frame(width: index == current && !passed ? 7 : 5, height: index == current && !passed ? 7 : 5)
                    }
                }
            } else {
                // Too many steps for dots in this width: a compact counter instead.
                Text(verbatim: "\(passed ? count : current + 1)/\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.7))
                    .contentTransition(.numericText())
            }
        }
        .animation(.smooth, value: current)
    }
}

/// The ripple field: rings from the lens across the whole screen, drawn with a Metal shader.
struct LensRippleField: View {
    /// The lens centre in this view's coordinates; the view fills the frame it's given.
    var lensCenter: CGPoint
    var tint: Color
    /// Changes whenever the instruction changes, to send a brighter wave.
    var trigger: AnyHashable

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstStart = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
        TimelineView(.animation(paused: reduceMotion)) { context in
            let now = context.date
            let time = Float(now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            let burst = Float(exp(-max(0, now.timeIntervalSince(burstStart)) * 1.8))
            Rectangle()
                .fill(.black)
                .colorEffect(
                    ShaderLibrary.bundle(.module).eyelineLensRipple(
                        .float2(lensCenter),
                        .float(time),
                        .color(tint),
                        .float(Float(max(proxy.size.width, proxy.size.height) * 0.75)),
                        .float(reduceMotion ? 0 : burst),
                        .float(reduceMotion ? 0 : 1)
                    )
                )
        }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger, initial: true) { burstStart = .now }
    }
}
