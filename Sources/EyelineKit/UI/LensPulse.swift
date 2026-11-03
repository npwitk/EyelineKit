import SwiftUI

/// Bends the view's content with a refraction wave from the lens each time `trigger` changes,
/// replicating the pulse iOS plays when the under-display camera turns on. On the outer display,
/// where iOS has no such cue, it pulls the eyes back to the camera at every new instruction.
struct LensPulse: ViewModifier {
    var origin: CGPoint
    var trigger: AnyHashable
    /// Skip the pulse for the first trigger (iOS already plays one when the inner camera starts).
    var skipsFirst: Bool
    var isEnabled: Bool

    static let duration: TimeInterval = 1.1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var hasSeenFirst = false

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: start == nil)) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) } ?? Self.duration
            content.layerEffect(
                ShaderLibrary.bundle(.module).eyelineLensPulse(
                    .float2(origin),
                    .float(Float(elapsed)),
                    .float(420),   // points per second
                    .float(34),    // wave width
                    .float(14)     // peak displacement
                ),
                maxSampleOffset: CGSize(width: 16, height: 16),
                isEnabled: isEnabled && start != nil && elapsed < Self.duration && !reduceMotion
            )
        }
        .onChange(of: trigger, initial: true) {
            defer { hasSeenFirst = true }
            if skipsFirst && !hasSeenFirst { return }
            let begun = Date.now
            start = begun
            Task {
                try? await Task.sleep(for: .seconds(Self.duration))
                if start == begun { start = nil }
            }
        }
    }
}
