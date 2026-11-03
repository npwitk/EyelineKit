import Foundation
import EyelineKit
import Observation

/// Runs a randomised active-liveness sequence on `FaceSample`s and drives a `EyelineSession`.
///
/// > Important: This is a **UX reference**, not presentation-attack detection. It cannot tell a
/// > live face from a replayed video or a mask. A bank or eKYC flow must keep its certified
/// > liveness engine (ISO 30107-3 / iBeta tested) and use EyelineKit only for the layout and cues.
@MainActor
@Observable
public final class ChallengeRunner {
    public struct Configuration: Sendable {
        /// Challenges to draw from.
        public var pool: [LivenessChallenge] = [.blink, .turnLeft, .turnRight, .smile, .openMouth, .shake]
        /// How many actions to ask for after calibration.
        public var actionCount: ClosedRange<Int> = 2...3
        public var stepTimeout: Duration = .seconds(10)
        /// Start with `.centerFace`, which also measures the baseline the other detectors compare against.
        public var calibrates = true
        public var thresholds = DetectorThresholds()

        public init() {}
    }

    public let session: EyelineSession
    public var configuration: Configuration
    public private(set) var steps: [LivenessChallenge] = []
    /// The latest sample, for debug overlays.
    public private(set) var lastSample: FaceSample?

    private var detector: ChallengeDetector?
    private var baseline: FaceBaseline = .neutral
    private var stepStartedAt: ContinuousClock.Instant?
    private var timeoutTask: Task<Void, Never>?

    public init(session: EyelineSession, configuration: Configuration = Configuration()) {
        self.session = session
        self.configuration = configuration
        session.onDisplaySupportChange = { [weak self] supported in
            self?.displaySupportChanged(supported)
        }
    }

    /// Pauses on an unsupported display, then restarts the current step from scratch.
    private func displaySupportChanged(_ supported: Bool) {
        guard session.phase == .running, !steps.isEmpty else { return }
        if supported {
            begin(step: session.stepIndex)
        } else {
            timeoutTask?.cancel()
            detector = nil
        }
    }

    /// Starts a new random sequence, or the given steps.
    public func start(steps fixed: [LivenessChallenge]? = nil) {
        var steps = fixed ?? Self.randomSteps(from: configuration.pool, count: configuration.actionCount)
        if configuration.calibrates, steps.first != .centerFace { steps.insert(.centerFace, at: 0) }
        self.steps = steps
        baseline = .neutral
        session.start(stepCount: steps.count)
        begin(step: 0)
    }

    public func cancel() {
        timeoutTask?.cancel()
        detector = nil
        session.reset()
    }

    /// Feed every analysed frame here.
    public func process(_ sample: FaceSample) {
        lastSample = sample
        guard var detector, session.phase == .running else { return }
        let update = detector.update(sample)
        self.detector = detector

        session.setProgress(update.progress)
        session.setFeedback(update.feedback)

        if update.passed {
            if detector.challenge == .centerFace, let calibrated = detector.calibratedBaseline {
                baseline = calibrated
            }
            advance()
        }
    }

    private func begin(step index: Int) {
        let challenge = steps[index]
        guard session.isDisplaySupported else {
            timeoutTask?.cancel()
            detector = nil
            session.setChallenge(challenge, step: index)
            return
        }
        detector = ChallengeDetector(challenge: challenge, baseline: baseline, thresholds: configuration.thresholds)
        session.setChallenge(challenge, step: index)
        scheduleTimeout(for: index)
    }

    private func advance() {
        session.completeStep()
        let next = session.stepIndex + 1
        if next < steps.count {
            begin(step: next)
        } else {
            timeoutTask?.cancel()
            detector = nil
            session.finish(passed: true)
        }
    }

    private func scheduleTimeout(for index: Int) {
        timeoutTask?.cancel()
        let timeout = configuration.stepTimeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.session.phase == .running, self.session.stepIndex == index else { return }
            self.detector = nil
            self.session.finish(passed: false, reason: String(localized: "Time ran out on this step."))
        }
    }

    static func randomSteps(from pool: [LivenessChallenge], count: ClosedRange<Int>) -> [LivenessChallenge] {
        let n = min(Int.random(in: count), pool.count)
        return Array(pool.shuffled().prefix(n))
    }
}
