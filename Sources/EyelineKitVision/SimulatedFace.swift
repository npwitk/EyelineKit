import CoreGraphics
import EyelineKit

/// Synthetic sample sequences that perform each challenge. Used by the tests, and by the demo
/// on the Simulator, which has no camera.
public enum SimulatedFace {
    public static let neutral = FaceSample()

    /// Frames that perform `challenge`, starting and ending in the neutral pose.
    public static func samples(for challenge: LivenessChallenge) -> [FaceSample] {
        let n = neutral
        func with(_ change: (inout FaceSample) -> Void) -> FaceSample {
            var sample = n
            change(&sample)
            return sample
        }
        func hold(_ sample: FaceSample, _ frames: Int = 5) -> [FaceSample] { Array(repeating: sample, count: frames) }

        switch challenge {
        case .centerFace, .holdStill:
            return hold(n, 15)
        case .blink:
            return hold(n, 2) + hold(with { $0.leftEyeOpenness = 0.05; $0.rightEyeOpenness = 0.05 }, 2) + hold(n, 2)
        case .turnLeft:
            return hold(n, 1) + hold(with { $0.yaw = 30 })
        case .turnRight:
            return hold(n, 1) + hold(with { $0.yaw = -30 })
        case .lookUp:
            return hold(n, 1) + hold(with { $0.pitch = 20 })
        case .lookDown:
            return hold(n, 1) + hold(with { $0.pitch = -20 })
        case .shake:
            return hold(with { $0.yaw = 20 }, 2) + hold(with { $0.yaw = -20 }, 2) + hold(n, 2)
        case .smile:
            return hold(with { $0.mouthWidth = n.mouthWidth * 1.25 })
        case .openMouth:
            return hold(with { $0.mouthOpenness = 0.4 })
        case .moveCloser:
            return hold(with { $0.faceBox = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6) })
        case .moveAway:
            return hold(with { $0.faceBox = CGRect(x: 0.38, y: 0.38, width: 0.24, height: 0.24) })
        }
    }
}
