import SwiftUI
import UIKit

/// UIKit entry point for SDKs that own their preview view (for example an
/// `AVCaptureVideoPreviewLayer` inside a `UIView`). The preview is embedded in the camera-anchored
/// layout; the SDK keeps driving it as before and pushes its state into `session`.
///
/// ```swift
/// let session = EyelineSession()
/// let eyeline = EyelineViewController(session: session, previewView: vendorSDK.previewView)
/// present(eyeline, animated: true)
/// vendorSDK.onInstruction = { session.setChallenge(.blink, step: 0) }
/// ```
public final class EyelineViewController: UIViewController {
    public let session: EyelineSession
    private let previewView: UIView
    private let mode: CameraAnchorMode
    private let style: EyelineStyle
    private let support: EyelineDisplaySupport
    private let onCancel: (() -> Void)?

    public init(
        session: EyelineSession,
        previewView: UIView,
        anchor mode: CameraAnchorMode = .automatic,
        style: EyelineStyle = EyelineStyle(),
        supports support: EyelineDisplaySupport = .allDisplays,
        onCancel: (() -> Void)? = nil
    ) {
        self.support = support
        self.session = session
        self.previewView = previewView
        self.mode = mode
        self.style = style
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let root = EyelineLayout(session: session, anchor: mode, style: style, supports: support) {
            HostedView(view: previewView)
        } footer: {
            if let onCancel {
                Button(String(localized: "cancel", defaultValue: "Cancel", bundle: .module), action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }
}

private struct HostedView: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
