import CoreGraphics
import CoreMedia
import ImageIO
import Vision

/// Turns camera frames into `FaceSample`s with Vision's face landmarks.
///
/// Frames are expected upright and unmirrored (the camera controller sets the connection's
/// rotation from `AVCaptureDevice.RotationCoordinator`).
public struct FaceAnalyzer: Sendable {
    /// Flip these if a device reports the opposite sign. The demo's debug overlay shows the live
    /// values so the convention can be checked on hardware: turning to *your* left must make yaw go up.
    public var yawSign: Double = 1
    public var pitchSign: Double = 1

    public init() {}

    public func analyze(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation = .up) -> FaceSample? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return sample(from: request.results ?? [], imageSize: orientation.isRotated ? CGSize(width: size.height, height: size.width) : size)
    }

    func sample(from faces: [VNFaceObservation], imageSize: CGSize) -> FaceSample {
        guard let face = faces.max(by: { area($0.boundingBox) < area($1.boundingBox) }) else { return .noFace }

        let box = face.boundingBox
        let topLeftBox = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        var sample = FaceSample(
            faceCount: faces.count,
            yaw: yawSign * degrees(face.yaw),
            pitch: pitchSign * degrees(face.pitch),
            roll: degrees(face.roll),
            faceBox: topLeftBox
        )

        if let landmarks = face.landmarks {
            let faceWidth = box.width * imageSize.width
            if let eye = landmarks.leftEye { sample.leftEyeOpenness = openness(eye, imageSize) }
            if let eye = landmarks.rightEye { sample.rightEyeOpenness = openness(eye, imageSize) }
            if let inner = landmarks.innerLips, let outer = landmarks.outerLips {
                let outerBounds = bounds(outer, imageSize)
                let innerBounds = bounds(inner, imageSize)
                sample.mouthOpenness = Double(innerBounds.height / max(outerBounds.width, 1))
                sample.mouthWidth = Double(outerBounds.width / max(faceWidth, 1))
            }
        }
        if let quality = face.faceCaptureQuality { sample.quality = Double(quality) }
        return sample
    }

    private func openness(_ region: VNFaceLandmarkRegion2D, _ imageSize: CGSize) -> Double {
        let rect = bounds(region, imageSize)
        return Double(rect.height / max(rect.width, 1))
    }

    private func bounds(_ region: VNFaceLandmarkRegion2D, _ imageSize: CGSize) -> CGRect {
        let points = region.pointsInImage(imageSize: imageSize)
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func degrees(_ radians: NSNumber?) -> Double {
        (radians?.doubleValue ?? 0) * 180 / .pi
    }

    private func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}

private extension CGImagePropertyOrientation {
    var isRotated: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored: true
        default: false
        }
    }
}
