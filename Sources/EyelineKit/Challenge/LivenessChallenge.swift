import Foundation

/// An action the person performs for an active liveness check.
///
/// Directions are from the person's point of view: `.turnLeft` means toward *their* left,
/// which is the left of the screen they are looking at.
public enum LivenessChallenge: String, Sendable, CaseIterable, Identifiable, Codable {
    case centerFace
    case holdStill
    case blink
    case turnLeft
    case turnRight
    case lookUp
    case lookDown
    case shake
    case smile
    case openMouth
    case moveCloser
    case moveAway

    public var id: String { rawValue }

    /// Short on-screen prompt, at most a few words so it can be read in a glance beside the lens.
    public var prompt: String {
        switch self {
        case .centerFace: String(localized: "challenge.centerFace", defaultValue: "Center your face", bundle: .module)
        case .holdStill: String(localized: "challenge.holdStill", defaultValue: "Hold still", bundle: .module)
        case .blink: String(localized: "challenge.blink", defaultValue: "Blink", bundle: .module)
        case .turnLeft: String(localized: "challenge.turnLeft", defaultValue: "Turn left", bundle: .module)
        case .turnRight: String(localized: "challenge.turnRight", defaultValue: "Turn right", bundle: .module)
        case .lookUp: String(localized: "challenge.lookUp", defaultValue: "Look up", bundle: .module)
        case .lookDown: String(localized: "challenge.lookDown", defaultValue: "Look down", bundle: .module)
        case .shake: String(localized: "challenge.shake", defaultValue: "Shake your head", bundle: .module)
        case .smile: String(localized: "challenge.smile", defaultValue: "Smile", bundle: .module)
        case .openMouth: String(localized: "challenge.openMouth", defaultValue: "Open your mouth", bundle: .module)
        case .moveCloser: String(localized: "challenge.moveCloser", defaultValue: "Move closer", bundle: .module)
        case .moveAway: String(localized: "challenge.moveAway", defaultValue: "Move back", bundle: .module)
        }
    }

    /// A full sentence for speech, so the person can keep their eyes on the lens.
    public var spokenPrompt: String {
        switch self {
        case .centerFace: String(localized: "spoken.centerFace", defaultValue: "Look at the camera and center your face.", bundle: .module)
        case .holdStill: String(localized: "spoken.holdStill", defaultValue: "Hold still.", bundle: .module)
        case .blink: String(localized: "spoken.blink", defaultValue: "Please blink.", bundle: .module)
        case .turnLeft: String(localized: "spoken.turnLeft", defaultValue: "Slowly turn your head to the left.", bundle: .module)
        case .turnRight: String(localized: "spoken.turnRight", defaultValue: "Slowly turn your head to the right.", bundle: .module)
        case .lookUp: String(localized: "spoken.lookUp", defaultValue: "Tilt your head up.", bundle: .module)
        case .lookDown: String(localized: "spoken.lookDown", defaultValue: "Tilt your head down.", bundle: .module)
        case .shake: String(localized: "spoken.shake", defaultValue: "Shake your head from side to side.", bundle: .module)
        case .smile: String(localized: "spoken.smile", defaultValue: "Please smile.", bundle: .module)
        case .openMouth: String(localized: "spoken.openMouth", defaultValue: "Open your mouth.", bundle: .module)
        case .moveCloser: String(localized: "spoken.moveCloser", defaultValue: "Move your face closer.", bundle: .module)
        case .moveAway: String(localized: "spoken.moveAway", defaultValue: "Move your face back a little.", bundle: .module)
        }
    }

    /// The challenges a randomised check usually draws from (the calibration steps are excluded).
    public static let actions: [LivenessChallenge] = [
        .blink, .turnLeft, .turnRight, .lookUp, .lookDown, .shake, .smile, .openMouth, .moveCloser, .moveAway,
    ]
}

/// Live guidance while a challenge runs.
public enum EyelineFeedback: Sendable, Equatable {
    case noFace
    case multipleFaces
    case tooDark
    case tooFar
    case tooClose
    case lookAtCamera
    case holdStill
    case custom(String)

    public var message: String {
        switch self {
        case .noFace: String(localized: "feedback.noFace", defaultValue: "No face found", bundle: .module)
        case .multipleFaces: String(localized: "feedback.multipleFaces", defaultValue: "Only one face, please", bundle: .module)
        case .tooDark: String(localized: "feedback.tooDark", defaultValue: "Find more light", bundle: .module)
        case .tooFar: String(localized: "feedback.tooFar", defaultValue: "Move closer", bundle: .module)
        case .tooClose: String(localized: "feedback.tooClose", defaultValue: "Move back", bundle: .module)
        case .lookAtCamera: String(localized: "feedback.lookAtCamera", defaultValue: "Look at the camera", bundle: .module)
        case .holdStill: String(localized: "feedback.holdStill", defaultValue: "Hold still", bundle: .module)
        case .custom(let text): text
        }
    }
}
