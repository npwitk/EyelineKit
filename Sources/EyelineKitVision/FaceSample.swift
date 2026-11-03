import CoreGraphics

/// One frame's worth of face measurements. Pure data, so detectors can be tested without a camera.
///
/// Angles are in degrees and in the person's frame of reference:
/// positive `yaw` = head turned to *their* left, positive `pitch` = head tilted up.
public struct FaceSample: Sendable, Equatable {
    /// Number of faces in the frame. All other fields describe the largest face.
    public var faceCount: Int
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    /// Face bounding box in normalised image coordinates (0...1, origin top-left).
    public var faceBox: CGRect
    /// Eye openness, height ÷ width of each eye outline. Roughly 0.3 open, under 0.15 closed.
    public var leftEyeOpenness: Double
    public var rightEyeOpenness: Double
    /// Inner-lip gap ÷ mouth width. Near 0 closed, over 0.3 clearly open.
    public var mouthOpenness: Double
    /// Mouth width ÷ face width. Grows when smiling.
    public var mouthWidth: Double
    /// Vision's capture quality score (0...1), if available.
    public var quality: Double?

    public init(
        faceCount: Int = 1,
        yaw: Double = 0,
        pitch: Double = 0,
        roll: Double = 0,
        faceBox: CGRect = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4),
        leftEyeOpenness: Double = 0.3,
        rightEyeOpenness: Double = 0.3,
        mouthOpenness: Double = 0.02,
        mouthWidth: Double = 0.4,
        quality: Double? = nil
    ) {
        self.faceCount = faceCount
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.faceBox = faceBox
        self.leftEyeOpenness = leftEyeOpenness
        self.rightEyeOpenness = rightEyeOpenness
        self.mouthOpenness = mouthOpenness
        self.mouthWidth = mouthWidth
        self.quality = quality
    }

    public static let noFace = FaceSample(faceCount: 0)

    public var eyeOpenness: Double { (leftEyeOpenness + rightEyeOpenness) / 2 }
    public var faceArea: Double { faceBox.width * faceBox.height }
    public var faceCenter: CGPoint { CGPoint(x: faceBox.midX, y: faceBox.midY) }
}

/// The person's neutral pose, captured while they look straight at the lens.
public struct FaceBaseline: Sendable, Equatable {
    public var yaw: Double
    public var pitch: Double
    public var eyeOpenness: Double
    public var mouthOpenness: Double
    public var mouthWidth: Double
    public var faceArea: Double

    public init(averaging samples: [FaceSample]) {
        let n = Double(max(samples.count, 1))
        yaw = samples.map(\.yaw).reduce(0, +) / n
        pitch = samples.map(\.pitch).reduce(0, +) / n
        eyeOpenness = samples.map(\.eyeOpenness).reduce(0, +) / n
        mouthOpenness = samples.map(\.mouthOpenness).reduce(0, +) / n
        mouthWidth = samples.map(\.mouthWidth).reduce(0, +) / n
        faceArea = samples.map(\.faceArea).reduce(0, +) / n
    }

    public static let neutral = FaceBaseline(averaging: [FaceSample()])
}
