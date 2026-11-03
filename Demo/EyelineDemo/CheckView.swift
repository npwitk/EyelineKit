import EyelineKit
import EyelineKitVision
import SwiftUI

struct CheckView: View {
    var onClose: () -> Void

    @State private var session: EyelineSession
    @State private var runner: ChallengeRunner
    @State private var camera = CameraController()
    @State private var autoplay: Task<Void, Never>?
    @State private var anchor: CameraAnchor?

    @AppStorage("debug") private var showsDebug = false
    @AppStorage("speech") private var speech = true
    @AppStorage("innerDisplay") private var innerDisplay = "supported"
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let session = EyelineSession()
        _session = State(initialValue: session)
        // The demo shows off every move, in a random order.
        var configuration = ChallengeRunner.Configuration()
        configuration.pool = LivenessChallenge.actions
        configuration.actionCount = LivenessChallenge.actions.count...LivenessChallenge.actions.count
        _runner = State(initialValue: ChallengeRunner(session: session, configuration: configuration))
    }

    private var display: FacingDisplay { FacingDisplay(horizontal: horizontal, vertical: vertical) }

    var body: some View {
        EyelineLayout(session: session, supports: innerDisplay == "outerOnly" ? .outerDisplayOnly : .allDisplays) {
            preview
        } footer: {
            controls
        } onAnchorChange: { anchor = $0 }
        .overlay {
            if session.phase == .passed {
                VerifiedView(onContinue: onClose)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: session.phase)
        .task { await start() }
        // Folding moves the app between displays without a scenePhase change: follow the size classes.
        .onChange(of: display) { _, display in
            if session.isDisplaySupported { camera.use(display: display) }
        }
        // No point running the under-display camera while the check asks you to close the phone.
        .onChange(of: session.isDisplaySupported) { _, supported in
            guard !isSimulator else { return }
            if supported { camera.use(display: display) } else { camera.stop() }
        }
        .onChange(of: speech, initial: true) { _, on in
            session.cues.options = on ? .all : [.haptics, .voiceOver]
        }
        .onDisappear {
            autoplay?.cancel()
            runner.cancel()
            camera.stop()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var preview: some View {
        if isSimulator {
            ZStack {
                Color.gray.opacity(0.25)
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .foregroundStyle(.gray)
            }
        } else {
            CameraPreview(controller: camera)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if showsDebug {
                DebugReadout(sample: runner.lastSample, anchor: anchor)
            }
            GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button("Close", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                if case .failed = session.phase {
                    Button("Try again", systemImage: "arrow.clockwise") { runner.start() }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                }
                if isSimulator, session.phase == .running {
                    Button("Simulate", systemImage: "wand.and.stars") { simulateCurrentStep() }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
                Menu {
                    Picker("Inner display", selection: $innerDisplay) {
                        Text("Supported").tag("supported")
                        Text("Ask to close iPhone").tag("outerOnly")
                    }
                    Toggle("Spoken prompts", isOn: $speech)
                    Toggle("Face readout", isOn: $showsDebug)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            }
        }
        .controlSize(.large)
    }

    // MARK: - Flow

    private func start() async {
        if !isSimulator, await CameraController.requestAccess() {
            camera.onSample = { [runner] sample in runner.process(sample) }
            if session.isDisplaySupported { camera.use(display: display) }
        }
        runner.start()
        if UserDefaults.standard.bool(forKey: "autoplay") { startAutoplay() }
    }

    private func simulateCurrentStep() {
        guard let challenge = session.challenge else { return }
        let samples = SimulatedFace.samples(for: challenge)
        Task {
            for sample in samples {
                runner.process(sample)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// Simulator only: performs each step after a pause, so screenshots can catch every state.
    private func startAutoplay() {
        autoplay = Task {
            while !Task.isCancelled, session.phase == .running {
                try? await Task.sleep(for: .seconds(2.5))
                simulateCurrentStep()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

/// Live values for checking thresholds and sign conventions on a real device.
private struct DebugReadout: View {
    var sample: FaceSample?
    var anchor: CameraAnchor?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let anchor {
                Text(verbatim: "anchor \(anchor.source) \(anchor.placement.rawValue) lens \(rect(anchor.cameraRect))")
                ForEach(anchor.regions, id: \.id) { region in
                    Text(verbatim: "region \(region.isActive ? "on " : "off") \(rect(region.frame))")
                }
            }
            if let sample { faceText(sample) }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }

    private func rect(_ r: CGRect) -> String {
        String(format: "(%.0f, %.0f, %.0f×%.0f)", r.minX, r.minY, r.width, r.height)
    }

    private func faceText(_ sample: FaceSample) -> some View {
        Text("faces \(sample.faceCount)  yaw \(sample.yaw, format: .number.precision(.fractionLength(0)))°  pitch \(sample.pitch, format: .number.precision(.fractionLength(0)))°\neyes \(sample.eyeOpenness, format: .number.precision(.fractionLength(2)))  mouth \(sample.mouthOpenness, format: .number.precision(.fractionLength(2)))  area \(sample.faceArea, format: .number.precision(.fractionLength(2)))")
    }
}

/// Shown when every step passed.
private struct VerifiedView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Duoland.green)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text("It's really you")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .safeAreaBar(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: 520)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
}
