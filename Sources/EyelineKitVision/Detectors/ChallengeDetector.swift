import CoreGraphics
import EyelineKit

/// Thresholds, relative to the person's baseline. Tune per product; these are starting points.
public struct DetectorThresholds: Sendable {
    public var turnDegrees: Double = 22
    public var tiltDegrees: Double = 14
    public var shakeDegrees: Double = 14
    /// Eyes count as closed below this fraction of the baseline openness.
    public var blinkClosedRatio: Double = 0.55
    public var blinkOpenRatio: Double = 0.8
    public var smileWidthRatio: Double = 1.12
    public var mouthOpenGain: Double = 0.18
    public var closerAreaRatio: Double = 1.45
    public var awayAreaRatio: Double = 0.65
    /// Frames a pose has to be held before it counts, to reject single-frame noise.
    public var holdFrames: Int = 3

    // Calibration (centerFace / holdStill)
    public var centerMaxAngle: Double = 12
    public var centerMaxOffset: Double = 0.18
    public var minFaceArea: Double = 0.04
    public var maxFaceArea: Double = 0.65
    public var calibrationFrames: Int = 12
    public var stillMaxDelta: Double = 2.5

    public init() {}
}

public struct DetectorUpdate: Sendable, Equatable {
    public var progress: Double
    public var passed: Bool
    public var feedback: EyelineFeedback?

    public init(progress: Double, passed: Bool = false, feedback: EyelineFeedback? = nil) {
        self.progress = progress
        self.passed = passed
        self.feedback = feedback
    }
}

/// Watches samples for one challenge. Create a fresh detector per step.
public struct ChallengeDetector: Sendable {
    public let challenge: LivenessChallenge
    public var thresholds: DetectorThresholds
    public private(set) var baseline: FaceBaseline

    private var held = 0
    private var phase = 0
    private var calibration: [FaceSample] = []
    private var previous: FaceSample?

    public init(challenge: LivenessChallenge, baseline: FaceBaseline = .neutral, thresholds: DetectorThresholds = DetectorThresholds()) {
        self.challenge = challenge
        self.baseline = baseline
        self.thresholds = thresholds
    }

    /// The baseline measured by a passed `.centerFace` step.
    public var calibratedBaseline: FaceBaseline? {
        calibration.count >= thresholds.calibrationFrames ? FaceBaseline(averaging: calibration) : nil
    }

    public mutating func update(_ sample: FaceSample) -> DetectorUpdate {
        defer { previous = sample }
        if sample.faceCount == 0 { held = 0; return DetectorUpdate(progress: 0, feedback: .noFace) }
        if sample.faceCount > 1 { held = 0; return DetectorUpdate(progress: 0, feedback: .multipleFaces) }

        let t = thresholds
        switch challenge {
        case .centerFace:
            if sample.faceArea < t.minFaceArea { calibration.removeAll(); return DetectorUpdate(progress: 0, feedback: .tooFar) }
            if sample.faceArea > t.maxFaceArea { calibration.removeAll(); return DetectorUpdate(progress: 0, feedback: .tooClose) }
            let offset = hypot(sample.faceCenter.x - 0.5, sample.faceCenter.y - 0.5)
            guard abs(sample.yaw) < t.centerMaxAngle, abs(sample.pitch) < t.centerMaxAngle, offset < t.centerMaxOffset else {
                calibration.removeAll()
                return DetectorUpdate(progress: 0, feedback: .lookAtCamera)
            }
            calibration.append(sample)
            return frameProgress(calibration.count, of: t.calibrationFrames)

        case .holdStill:
            if let previous, abs(sample.yaw - previous.yaw) + abs(sample.pitch - previous.pitch) > t.stillMaxDelta {
                held = 0
                return DetectorUpdate(progress: 0, feedback: .holdStill)
            }
            held += 1
            return frameProgress(held, of: t.calibrationFrames)

        case .blink:
            let ratio = sample.eyeOpenness / max(baseline.eyeOpenness, 0.01)
            switch phase {
            case 0 where ratio >= t.blinkOpenRatio: phase = 1
            case 1 where ratio <= t.blinkClosedRatio: phase = 2
            case 2 where ratio >= t.blinkOpenRatio: phase = 3
            default: break
            }
            return DetectorUpdate(progress: Double(phase) / 3, passed: phase == 3)

        case .turnLeft:
            return holdBeyond(sample.yaw - baseline.yaw, t.turnDegrees)
        case .turnRight:
            return holdBeyond(baseline.yaw - sample.yaw, t.turnDegrees)
        case .lookUp:
            return holdBeyond(sample.pitch - baseline.pitch, t.tiltDegrees)
        case .lookDown:
            return holdBeyond(baseline.pitch - sample.pitch, t.tiltDegrees)

        case .shake:
            return oscillation(sample.yaw - baseline.yaw, t.shakeDegrees)

        case .smile:
            let gain = sample.mouthWidth / max(baseline.mouthWidth, 0.01)
            return holdBeyond(gain - 1, t.smileWidthRatio - 1)
        case .openMouth:
            return holdBeyond(sample.mouthOpenness - baseline.mouthOpenness, t.mouthOpenGain)
        case .moveCloser:
            let gain = sample.faceArea / max(baseline.faceArea, 0.001)
            return holdBeyond(gain - 1, t.closerAreaRatio - 1)
        case .moveAway:
            let gain = sample.faceArea / max(baseline.faceArea, 0.001)
            return holdBeyond(1 - gain, 1 - t.awayAreaRatio)
        }
    }

    /// Passes once `value` has stayed past `threshold` for `holdFrames` frames.
    private mutating func holdBeyond(_ value: Double, _ threshold: Double) -> DetectorUpdate {
        if value >= threshold { held += 1 } else { held = 0 }
        let reach = min(max(value / threshold, 0), 1)
        let progress = held > 0 ? 0.8 + 0.2 * Double(held) / Double(thresholds.holdFrames) : reach * 0.8
        return DetectorUpdate(progress: min(progress, 1), passed: held >= thresholds.holdFrames)
    }

    /// Passes after the value swings past +threshold and -threshold (either order) and returns near zero.
    /// Used for shake.
    private mutating func oscillation(_ value: Double, _ threshold: Double) -> DetectorUpdate {
        // phase bits: 1 = went positive, 2 = went negative
        if value >= threshold { phase |= 1 }
        if value <= -threshold { phase |= 2 }
        let swings = (phase & 1) + ((phase >> 1) & 1)
        let returned = phase == 3 && abs(value) < threshold / 2
        return DetectorUpdate(progress: returned ? 1 : Double(swings) / 2 * 0.9, passed: returned)
    }

    private func frameProgress(_ count: Int, of total: Int) -> DetectorUpdate {
        DetectorUpdate(progress: Double(count) / Double(total), passed: count >= total)
    }
}
