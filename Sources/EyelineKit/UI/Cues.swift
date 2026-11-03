import AVFoundation
import UIKit

/// Cues that don't need reading: speech, haptics and VoiceOver announcements.
///
/// Speech is the most direct fix for an off-centre lens. The person hears "please blink" and
/// never has to look away from the camera at all.
@MainActor
public final class EyelineCues {
    public struct Options: Sendable, OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let speech = Options(rawValue: 1 << 0)
        public static let haptics = Options(rawValue: 1 << 1)
        public static let voiceOver = Options(rawValue: 1 << 2)

        public static let all: Options = [.speech, .haptics, .voiceOver]
    }

    public var options: Options
    /// BCP 47 language for speech. Defaults to the language EyelineKit's strings resolved to.
    public var speechLanguage: String?
    public var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate

    private let synthesizer = AVSpeechSynthesizer()
    private let notification = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    public init(options: Options = .all, speechLanguage: String? = nil) {
        self.options = options
        self.speechLanguage = speechLanguage
    }

    func challengeChanged(to challenge: LivenessChallenge) {
        if options.contains(.haptics) { impact.impactOccurred() }
        speak(challenge.spokenPrompt)
        announce(challenge.prompt)
    }

    func feedbackChanged(to feedback: EyelineFeedback) {
        announce(feedback.message)
    }

    func stepPassed() {
        if options.contains(.haptics) { notification.notificationOccurred(.success) }
    }

    func finished(passed: Bool) {
        if options.contains(.haptics) { notification.notificationOccurred(passed ? .success : .error) }
        let text = passed
            ? String(localized: "result.passed", defaultValue: "Done", bundle: .module)
            : String(localized: "result.failed", defaultValue: "Let's try again", bundle: .module)
        speak(text)
    }

    public func speak(_ text: String) {
        guard options.contains(.speech), !UIAccessibility.isVoiceOverRunning else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = speechRate
        utterance.voice = AVSpeechSynthesisVoice(language: resolvedLanguage)
        synthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func announce(_ text: String) {
        guard options.contains(.voiceOver), UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private var resolvedLanguage: String {
        if let speechLanguage { return speechLanguage }
        switch Bundle.module.preferredLocalizations.first {
        case "th": return "th-TH"
        case let code?: return code
        case nil: return AVSpeechSynthesisVoice.currentLanguageCode()
        }
    }
}
