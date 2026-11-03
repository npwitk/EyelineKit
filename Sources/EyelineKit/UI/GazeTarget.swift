import SwiftUI

/// A pulsing ring with an arrow toward the lens: "look here".
public struct GazeTarget: View {
    var pointerAngle: Angle
    var tint: Color
    var size: CGFloat

    public init(pointerAngle: Angle, tint: Color = .accentColor, size: CGFloat = 44) {
        self.pointerAngle = pointerAngle
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.35), lineWidth: 2)
                .phaseAnimator([false, true]) { ring, expanded in
                    ring
                        .scaleEffect(expanded ? 1.25 : 0.9)
                        .opacity(expanded ? 0 : 1)
                } animation: { _ in .easeOut(duration: 1.2) }
            Circle()
                .fill(tint.opacity(0.15))
            Image(systemName: "arrow.up")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint)
                .rotationEffect(pointerAngle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
