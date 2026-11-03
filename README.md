# EyelineKit

Face-check instructions that sit **right under the camera**, so people can read them while looking at the lens.

Banking and eKYC apps ask you to blink, turn left or move closer during a face check. Their screens assume a camera at the top centre: a big preview in the middle, the instruction below it. On iPhone Duo the outer display's camera sits in the top-right corner, inside the vertical bar. You either look at the lens and can't read the instruction, or read the instruction and look away from the lens, and the check fails.

EyelineKit finds where the camera actually is and puts the instruction there.

## What it does

- **Finds the lens.** It reads the camera's position from `ReservedRegion` (iOS 27.1). On iPhones without reserved regions, it falls back to the top centre (Dynamic Island).
- **Grows a capsule out of the camera.**
  - Outer display: a tall capsule hangs from the lens in the vertical bar.
  - Inner display: a wide "drop" hangs under the under-display camera, like the Dynamic Island expanding.
  - Inside the capsule, a Face ID-style glyph acts out the move above a word or two. The outline fills with progress, step dots (or a "2/11" counter) show where you are, and it turns amber when something's wrong ("No face found").
- **Pulls the eyes back to the lens.** A Metal shader sends soft rings out from the camera, with a stronger wave each time the instruction changes. With Reduce Motion it's a still glow.
- **Works without reading.** Each instruction is spoken (English and Thai), steps play haptics, and VoiceOver announces changes.
- **Can require the outer display.** The inner camera is a 4 MP under-display camera. With `supports: .outerDisplayOnly`, the inner display shows "Close your iPhone to continue" with a to-scale folding animation, and the check pauses until the phone is closed. Displays that don't fold (other iPhones, iPad) are unaffected.

## Requirements

- iOS 18 or later. The camera position, the capsule and the outer-display option need iOS 27.1; earlier versions use the top-centre fallback.
- Xcode 27.1 or later, Swift 6.2.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/npwitk/EyelineKit.git", from: "0.1.0")
```

| Product | What it is |
|---|---|
| `EyelineKit` | The layout, camera anchoring, the challenge model and the cues. No camera code, so it works with any liveness engine. |
| `EyelineKitVision` | A reference engine: picks the front camera that faces the person, reads Vision face landmarks, and runs a randomised sequence of challenges. |

> **`EyelineKitVision` is a UX reference, not anti-spoofing.** It can't tell a live face from a replayed video or a mask. A bank or eKYC flow should keep its certified liveness engine (ISO 30107-3 / iBeta) and use `EyelineKit` for the screen only.

## Usage

### With your own liveness engine

```swift
import EyelineKit

let session = EyelineSession()

EyelineLayout(session: session, supports: .outerDisplayOnly) {
    MyVendorPreview()              // any view; shown as a small circle near the lens
} footer: {
    Button("Cancel", action: cancel)
}

// Push your engine's state in:
session.start(stepCount: 3)
session.setChallenge(.blink, step: 0)
session.setProgress(0.5)
session.setFeedback(.lookAtCamera)
session.completeStep()
session.finish(passed: true)
```

If you use `.outerDisplayOnly`, pause your engine while `session.isDisplaySupported` is `false` (or handle `session.onDisplaySupportChange`).

UIKit, for SDKs that own their preview view:

```swift
let controller = EyelineViewController(
    session: session,
    previewView: sdk.previewView,
    supports: .outerDisplayOnly,
    onCancel: { … }
)
```

### With the reference engine

```swift
import EyelineKit
import EyelineKitVision

let session = EyelineSession()
let runner = ChallengeRunner(session: session)
let camera = CameraController()

camera.onSample = { runner.process($0) }
camera.use(display: FacingDisplay(horizontal: horizontalSizeClass, vertical: verticalSizeClass))
runner.start()   // "Center your face", then 2–3 random moves
```

Call `camera.use(display:)` again whenever the size classes change. Opening or closing the phone moves the app between displays without changing `scenePhase`. `ChallengeRunner` pauses by itself on an unsupported display.

Challenges: `blink`, `turnLeft`, `turnRight`, `lookUp`, `lookDown`, `shake`, `smile`, `openMouth`, `moveCloser`, `moveAway`, plus the calibration steps `centerFace` and `holdStill`. Change the pool, count and timeout through `ChallengeRunner.Configuration`, and the detection thresholds through `DetectorThresholds`.

### Styling

```swift
var style = EyelineStyle()
style.capsule.fill = .mint              // capsule colour
style.capsule.ink = .black              // glyph and text
style.capsule.warningFill = .orange
style.capsule.showsRipple = false
style.hidesStatusBarForLensCapsule = false
style.previewDiameter = 120

EyelineLayout(session: session, style: style) { … }
```

Speech, haptics and VoiceOver are set on the session's cues: `EyelineSession(cues: EyelineCues(options: [.haptics, .voiceOver]))`.

`FaceGlyph(.blink)` and `FoldPrompt()` can be used on their own. `CameraAnchorReader { anchor in … }` gives you the camera position for a fully custom layout.

## How the camera is found

1. Reserved regions are only returned for views they overlap, and the outer camera sits in the vertical bar, outside the safe area. So EyelineKit reads `.occlusion` regions twice, once inside the safe area and once full screen.
2. Active regions win. A region that just switched on (the under-display camera when capture starts) is preferred, then the smallest. An inactive region still beats guessing.
3. A display that reports a hinge (`.division`, even inactive) is the inner display. That's how `.outerDisplayOnly` tells it apart from other screens.

## Demo app

`Demo/EyelineDemo.xcodeproj` is a check for **Bank of Duoland**, a pretend bank. Set your signing team and run it on iPhone Duo. To regenerate the project from `Demo/project.yml`, run `xcodegen generate`.

- The check runs every move in a random order.
- The settings menu has **Inner display** (*Supported* or *Ask to close iPhone*), **Spoken prompts**, and **Face readout**, which shows the camera position and live face values for tuning on a device.
- The Simulator has no camera. The **Simulate** button performs the current step, and the launch arguments `-startCheck YES -autoplay YES` run the whole flow.

## Tests

```sh
xcodebuild test -scheme EyelineKit-Package -destination 'platform=iOS Simulator,name=iPhone Duo'
```

## Known limitations

- The detection thresholds and the head-turn direction (`FaceAnalyzer.yawSign`, `pitchSign`) still need checking on more devices.
- Rear-camera mode isn't built yet: with the phone open, show the screen on the outer display through `CameraCaptureAccessory` while the 48 MP rear camera films the person.

## License

MIT. See [LICENSE](LICENSE).
