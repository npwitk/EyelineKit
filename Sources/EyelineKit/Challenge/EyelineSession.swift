import Foundation
import Observation

/// The state a EyelineKit layout shows. Any liveness engine can drive it: push the current
/// challenge, progress and feedback in, and the layout and cues follow.
@MainActor
@Observable
public final class EyelineSession {
    public enum Phase: Sendable, Equatable {
        case idle
        case running
        case passed
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var challenge: LivenessChallenge?
    /// Zero-based index of the current step.
    public private(set) var stepIndex = 0
    public private(set) var stepCount = 0
    /// Progress of the current step, 0...1.
    public private(set) var stepProgress: Double = 0
    public private(set) var feedback: EyelineFeedback?
    /// Increments each time a step passes, for haptics and animations.
    public private(set) var completedSteps = 0

    /// Increments each time the layout should pulse from the lens to pull the eyes back.
    public private(set) var attentionRequests = 0

    /// `false` while the layout shows "close your iPhone" because the check is set to the outer
    /// display only. Engines should pause; `ChallengeRunner` does this for you.
    public private(set) var isDisplaySupported = true
    /// Called when `isDisplaySupported` changes, for engines that pause and resume.
    @ObservationIgnored public var onDisplaySupportChange: ((Bool) -> Void)?

    public let cues: EyelineCues

    public init(cues: EyelineCues = EyelineCues()) {
        self.cues = cues
    }

    /// Overall progress across all steps, 0...1.
    public var overallProgress: Double {
        guard stepCount > 0 else { return phase == .passed ? 1 : 0 }
        if phase == .passed { return 1 }
        return (Double(stepIndex) + stepProgress) / Double(stepCount)
    }

    public func start(stepCount: Int) {
        self.stepCount = stepCount
        stepIndex = 0
        stepProgress = 0
        completedSteps = 0
        feedback = nil
        challenge = nil
        phase = .running
    }

    public func setChallenge(_ challenge: LivenessChallenge, step: Int) {
        let changed = challenge != self.challenge || step != stepIndex
        self.challenge = challenge
        stepIndex = step
        stepProgress = 0
        feedback = nil
        if phase != .running { phase = .running }
        // While the display is unsupported, the fold prompt owns speech.
        if changed, isDisplaySupported { cues.challengeChanged(to: challenge) }
    }

    public func setProgress(_ progress: Double) {
        stepProgress = min(max(progress, 0), 1)
    }

    public func setFeedback(_ feedback: EyelineFeedback?) {
        guard feedback != self.feedback else { return }
        self.feedback = feedback
        if let feedback { cues.feedbackChanged(to: feedback) }
        // Eyes have drifted from the lens: pulse from it.
        if feedback == .lookAtCamera { drawAttentionToLens() }
    }

    /// Plays the refraction pulse from the lens now. The layout also plays it on every new
    /// instruction and when the feedback becomes `.lookAtCamera`.
    public func drawAttentionToLens() {
        attentionRequests += 1
    }

    /// Marks the current step done. The engine then calls `setChallenge` for the next one, or `finish`.
    public func completeStep() {
        stepProgress = 1
        completedSteps += 1
        cues.stepPassed()
    }

    public func finish(passed: Bool, reason: String = "") {
        challenge = nil
        feedback = nil
        phase = passed ? .passed : .failed(reason)
        cues.finished(passed: passed)
    }

    /// Set by `EyelineLayout`; call it yourself only if you build your own layout.
    public func setDisplaySupported(_ supported: Bool) {
        guard supported != isDisplaySupported else { return }
        isDisplaySupported = supported
        if !supported {
            cues.speak(String(localized: "fold.spoken", defaultValue: "Close your iPhone and use the outer screen to continue.", bundle: .module))
        }
        onDisplaySupportChange?(supported)
    }

    public func reset() {
        phase = .idle
        challenge = nil
        stepIndex = 0
        stepCount = 0
        stepProgress = 0
        feedback = nil
        cues.stopSpeaking()
    }
}
