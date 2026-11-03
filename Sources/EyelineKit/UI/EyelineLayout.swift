import SwiftUI

/// Configuration for `EyelineLayout`.
public struct EyelineStyle: Sendable {
    public var tint: Color = .green
    public var promptFont: Font = .system(.title, design: .rounded, weight: .bold)
    /// Diameter of the face preview. Keep it small: a big preview is what pulls the eyes off the lens.
    public var previewDiameter: CGFloat = 150
    public var showsGazeTarget = true
    public var showsStepDots = true
    public var maxColumnWidth: CGFloat = 300
    /// When the lens sits in a side bar (iPhone Duo), grow a capsule out of it that shows the
    /// move and the prompt right under the camera.
    public var showsLensCapsule = true
    /// Hide the status bar while the capsule shows, so the clock and signal don't share the bar.
    public var hidesStatusBarForLensCapsule = true
    public var capsule = LensCapsuleStyle()

    public init() {}
}

/// A liveness screen whose instructions sit right beside the active camera.
///
/// ```swift
/// EyelineLayout(session: session) {
///     CameraPreview(controller: camera)   // any view; it's clipped to a circle
/// } footer: {
///     Button("Cancel", action: cancel)
/// }
/// ```
public struct EyelineLayout<Preview: View, Footer: View>: View {
    @Bindable var session: EyelineSession
    var mode: CameraAnchorMode
    var style: EyelineStyle
    var support: EyelineDisplaySupport
    var preview: Preview
    var footer: Footer
    var onAnchorChange: ((CameraAnchor) -> Void)?

    public init(
        session: EyelineSession,
        anchor mode: CameraAnchorMode = .automatic,
        style: EyelineStyle = EyelineStyle(),
        supports support: EyelineDisplaySupport = .allDisplays,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        onAnchorChange: ((CameraAnchor) -> Void)? = nil
    ) {
        self.onAnchorChange = onAnchorChange
        self.session = session
        self.mode = mode
        self.style = style
        self.support = support
        self.preview = preview()
        self.footer = footer()
    }

    public var body: some View {
        CameraAnchorReader(mode: mode) { anchor in
            let unsupported = support == .outerDisplayOnly && anchor.isOnFoldingDisplay
            Group {
                if unsupported {
                    ZStack(alignment: .bottom) {
                        FoldPrompt(tint: style.capsule.fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        footer.padding()
                    }
                    .transition(.opacity)
                } else {
                    check(anchor)
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: unsupported)
            .onChange(of: unsupported, initial: true) { _, unsupported in
                session.setDisplaySupported(!unsupported)
            }
            .onChange(of: anchor, initial: true) { _, anchor in onAnchorChange?(anchor) }
        }
        .sensoryFeedback(.success, trigger: session.completedSteps)
    }

    @ViewBuilder
    private func check(_ anchor: CameraAnchor) -> some View {
            let capsule = style.showsLensCapsule ? anchor.lensCapsule : nil
            let clearance = capsule?.kind == .vertical ? Self.clearance(for: capsule?.frame, in: anchor.safeRect) : EdgeInsets()
            let layoutAnchor = Self.layoutAnchor(anchor, capsule: capsule, leadingClearance: clearance.leading)
            ZStack(alignment: footerAlignment(for: anchor)) {
                CameraHuggingLayout(anchor: layoutAnchor, maxWidth: style.maxColumnWidth) {
                    // The capsule carries the instruction; otherwise it goes beside the lens.
                    if capsule == nil {
                        InstructionColumn(session: session, anchor: anchor, style: style)
                    }
                    PreviewRing(session: session, style: style) { preview }
                }
                .padding(clearance)
                footer
                    .padding()
                    .padding(clearance)
            }
            // Behind the content: the capsule hangs where nothing else is laid out, and keeping it
            // with the rings lets the lens pulse bend both. The pulse can't touch the camera
            // preview or the glass buttons (UIKit-backed views can't be redrawn by a layer
            // effect), so it is applied to this pure-SwiftUI layer only.
            .background(alignment: .topLeading) { lensDecoration(anchor, capsule: capsule) }
            // Only the side-bar capsule shares space with the status bar.
            .statusBarHidden(capsule?.kind == .vertical && style.hidesStatusBarForLensCapsule)
            .animation(.smooth, value: session.phase)
            .animation(.smooth, value: anchor)
    }

    /// The rings and the capsule on one full-screen layer, bent together by the lens pulse.
    @ViewBuilder
    private func lensDecoration(_ anchor: CameraAnchor, capsule: LensCapsuleGeometry?) -> some View {
        if let screen = anchor.screenRect {
            let lens = CGPoint(x: anchor.cameraCenter.x - screen.minX, y: anchor.cameraCenter.y - screen.minY)
            let step = AnyHashable([session.challenge?.rawValue ?? "", "\(session.stepIndex)"])
            ZStack(alignment: .topLeading) {
                if style.capsule.showsRipple, session.phase == .running {
                    LensRippleField(lensCenter: lens, tint: style.capsule.fill, trigger: step)
                        .transition(.opacity)
                }
                if let capsule {
                    LensCapsule(session: session, geometry: capsule, style: style.capsule)
                        .offset(x: capsule.frame.minX - screen.minX, y: capsule.frame.minY - screen.minY)
                        .transition(.opacity)
                }
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            .modifier(LensPulse(
                origin: lens,
                trigger: AnyHashable([step, AnyHashable(session.attentionRequests)]),
                // iOS already plays this pulse when the under-display camera turns on.
                skipsFirst: anchor.isOnFoldingDisplay,
                strength: style.capsule.pulseStrength,
                isEnabled: style.capsule.pulsesFromLens && session.phase == .running
            ))
            .offset(x: screen.minX, y: screen.minY)
        }
    }

    /// The anchor the preview is laid out against. Under a drop capsule the preview goes below
    /// the capsule, centred, rather than below the bare lens.
    static func layoutAnchor(_ anchor: CameraAnchor, capsule: LensCapsuleGeometry?, leadingClearance: CGFloat) -> CameraAnchor {
        var result = anchor.shifted(byLeading: leadingClearance)
        if let capsule, capsule.kind == .drop {
            result.cameraRect = CGRect(x: capsule.frame.minX, y: capsule.frame.minY,
                                       width: capsule.frame.width, height: capsule.estimatedHeight)
            result.placement = .top
        }
        return result
    }

    /// Room to leave so the main content doesn't run under the capsule (hiding the status bar
    /// can grow the safe area into the bar).
    static func clearance(for column: CGRect?, in safeRect: CGRect, gap: CGFloat = 8) -> EdgeInsets {
        guard let column else { return EdgeInsets() }
        var insets = EdgeInsets()
        if column.midX > safeRect.midX {
            insets.trailing = max(0, safeRect.maxX - (column.minX - gap))
        } else {
            insets.leading = max(0, (column.maxX + gap) - safeRect.minX)
        }
        return insets
    }

    /// The footer goes to the edge away from the lens.
    private func footerAlignment(for anchor: CameraAnchor) -> Alignment {
        anchor.placement.vertical == .bottom ? .top : .bottom
    }
}

struct InstructionColumn: View {
    var session: EyelineSession
    var anchor: CameraAnchor
    var style: EyelineStyle

    var body: some View {
        let alignment = anchor.placement.horizontalAlignment
        VStack(alignment: alignment, spacing: 10) {
            promptRow
            if let feedback = session.feedback {
                Label(feedback.message, systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            if style.showsStepDots, session.stepCount > 1 {
                StepDots(count: session.stepCount, current: session.stepIndex, progress: session.stepProgress, tint: style.tint)
            }
        }
        .multilineTextAlignment(textAlignment)
        .animation(.smooth, value: session.challenge)
        .animation(.smooth, value: session.feedback)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var promptRow: some View {
        let target = GazeTarget(pointerAngle: anchor.pointerAngle, tint: style.tint)
        let showsTarget = style.showsGazeTarget
        switch anchor.placement.horizontal {
        case .trailing:
            HStack(alignment: .top, spacing: 12) {
                prompt
                if showsTarget { target }
            }
        case .leading:
            HStack(alignment: .top, spacing: 12) {
                if showsTarget { target }
                prompt
            }
        case .center:
            VStack(spacing: 10) {
                if showsTarget { target }
                prompt
            }
        }
    }

    @ViewBuilder
    private var prompt: some View {
        switch session.phase {
        case .passed:
            Label(String(localized: "result.passed", defaultValue: "Done", bundle: .module), systemImage: "checkmark.circle.fill")
                .font(style.promptFont)
                .foregroundStyle(style.tint)
        case .failed(let reason):
            VStack(alignment: anchor.placement.horizontalAlignment) {
                Text(String(localized: "result.failed", defaultValue: "Let's try again", bundle: .module))
                    .font(style.promptFont)
                if !reason.isEmpty {
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        case .idle, .running:
            if let challenge = session.challenge {
                VStack(alignment: anchor.placement.horizontalAlignment, spacing: 6) {
                    FaceGlyph(challenge, color: style.tint)
                        .frame(width: 52, height: 52)
                    Text(challenge.prompt)
                        .font(style.promptFont)
                        .fixedSize() // prompts are a few words; never break a word across lines
                        .id(challenge)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                }
            } else {
                Text(String(localized: "lookHere", defaultValue: "Look here", bundle: .module))
                    .font(style.promptFont)
            }
        }
    }

    private var textAlignment: TextAlignment {
        switch anchor.placement.horizontal {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

struct StepDots: View {
    var count: Int
    var current: Int
    var progress: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(tint)
                                .frame(width: proxy.size.width * fill(for: index))
                        }
                    }
                    .clipShape(.capsule)
                    .frame(width: index == current ? 28 : 12, height: 6)
            }
        }
        .animation(.smooth, value: current)
        .animation(.linear(duration: 0.15), value: progress)
        .accessibilityLabel(Text(String(localized: "step \(current + 1) of \(count)", bundle: .module)))
    }

    private func fill(for index: Int) -> CGFloat {
        if index < current { return 1 }
        if index == current { return progress }
        return 0
    }
}

struct PreviewRing<Content: View>: View {
    var session: EyelineSession
    var style: EyelineStyle
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: style.previewDiameter, height: style.previewDiameter)
            .clipShape(.circle)
            .padding(5)
            .overlay {
                Circle().stroke(.quaternary, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: session.overallProgress)
                    .stroke(style.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: session.overallProgress)
            }
            .accessibilityHidden(true)
    }
}
