@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Which display the app is on, which decides which front camera faces the person.
public enum FacingDisplay: Sendable, Equatable {
    /// iPhone Duo outer display (compact width), or a regular iPhone.
    case outer
    /// iPhone Duo inner display (regular width and height): the under-display camera.
    case inner

    public init(horizontal: UserInterfaceSizeClass?, vertical: UserInterfaceSizeClass?) {
        self = horizontal == .regular && vertical == .regular ? .inner : .outer
    }
}

/// A front-camera capture session that follows the display.
///
/// Folding or unfolding does **not** change `scenePhase`, so call `use(display:)` whenever the size
/// classes change; the controller switches lenses if needed. Frames are analysed off the main
/// thread and delivered as `FaceSample`s.
public final class CameraController: NSObject, @unchecked Sendable {
    public let captureSession = AVCaptureSession()
    public let previewLayer: AVCaptureVideoPreviewLayer

    /// Called on the main actor with each analysed frame.
    public var onSample: (@MainActor (FaceSample) -> Void)?
    public var analyzer = FaceAnalyzer()

    private let sessionQueue = DispatchQueue(label: "EyelineKit.camera.session")
    private let videoQueue = DispatchQueue(label: "EyelineKit.camera.video")
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var display: FacingDisplay?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []

    public override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    /// The device type now in use, for diagnostics.
    public var activeDeviceName: String? { input?.device.localizedName }

    public static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Picks the front camera that faces the person on `display`.
    public static func frontCamera(for display: FacingDisplay) -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        if #available(iOS 27.1, *) {
            let preferred: [AVCaptureDevice.DeviceType] = display == .inner
                ? [.builtInInnerUltraWideCamera, .builtInOuterUltraWideCamera]
                : [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera]
            types = preferred + types
        }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .front).devices
        // DiscoverySession keeps the device-type order, so the first match is the best fit.
        for type in types {
            if let device = devices.first(where: { $0.deviceType == type }) { return device }
        }
        return devices.first
    }

    /// Starts the session (if needed) on the camera for `display`.
    public func use(display: FacingDisplay) {
        sessionQueue.async { [self] in
            if self.display != display || input == nil {
                self.display = display
                reconfigure(for: display)
            }
            if !captureSession.isRunning { captureSession.startRunning() }
        }
    }

    public func stop() {
        sessionQueue.async { [self] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    private func reconfigure(for display: FacingDisplay) {
        guard let device = Self.frontCamera(for: display) else { return }
        if input?.device == device { return }

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .high

        if let input { captureSession.removeInput(input) }
        guard let newInput = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(newInput) else { return }
        captureSession.addInput(newInput)
        input = newInput

        if !captureSession.outputs.contains(output), captureSession.canAddOutput(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: videoQueue)
            captureSession.addOutput(output)
        }
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        DispatchQueue.main.async { [self] in observeRotation(of: device) }
    }

    /// Keeps frames upright for Vision and the preview upright on screen, including when the app
    /// moves between displays.
    @MainActor
    private func observeRotation(of device: AVCaptureDevice) {
        rotationObservations.removeAll()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator

        let applyCapture: @Sendable (CGFloat) -> Void = { [weak self] angle in
            guard let self else { return }
            sessionQueue.async {
                if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
        }
        let applyPreview: @MainActor (CGFloat) -> Void = { [weak self] angle in
            if let connection = self?.previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        applyCapture(coordinator.videoRotationAngleForHorizonLevelCapture)
        applyPreview(coordinator.videoRotationAngleForHorizonLevelPreview)

        rotationObservations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { coordinator, _ in
                applyCapture(coordinator.videoRotationAngleForHorizonLevelCapture)
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                Task { @MainActor in applyPreview(angle) }
            },
        ]
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let sample = analyzer.analyze(sampleBuffer) else { return }
        let handler = onSample
        Task { @MainActor in handler?(sample) }
    }
}

/// Shows a `CameraController`'s preview.
public struct CameraPreview: UIViewRepresentable {
    let controller: CameraController

    public init(controller: CameraController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer = controller.previewLayer
        return view
    }

    public func updateUIView(_ uiView: PreviewView, context: Context) {}

    public final class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let previewLayer { layer.addSublayer(previewLayer) }
            }
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
