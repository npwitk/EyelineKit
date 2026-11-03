import Testing
@testable import EyelineKit
@testable import EyelineKitVision

struct DetectorTests {
    @Test(arguments: LivenessChallenge.allCases)
    func simulatedSequencePasses(challenge: LivenessChallenge) {
        var detector = ChallengeDetector(challenge: challenge)
        let passed = SimulatedFace.samples(for: challenge).contains { detector.update($0).passed }
        #expect(passed)
    }

    @Test(arguments: LivenessChallenge.actions)
    func neutralFaceDoesNotPass(challenge: LivenessChallenge) {
        var detector = ChallengeDetector(challenge: challenge)
        let passed = (0..<30).contains { _ in detector.update(SimulatedFace.neutral).passed }
        #expect(!passed)
    }

    @Test func wrongDirectionDoesNotPass() {
        var left = ChallengeDetector(challenge: .turnLeft)
        #expect(!SimulatedFace.samples(for: .turnRight).contains { left.update($0).passed })
        var up = ChallengeDetector(challenge: .lookUp)
        #expect(!SimulatedFace.samples(for: .lookDown).contains { up.update($0).passed })
    }

    @Test func turnMustBeHeld() {
        var detector = ChallengeDetector(challenge: .turnLeft)
        var turned = SimulatedFace.neutral
        turned.yaw = 30
        #expect(!detector.update(turned).passed)
        #expect(!detector.update(SimulatedFace.neutral).passed) // flicker resets the hold
        #expect(!detector.update(turned).passed)
        #expect(!detector.update(turned).passed)
        #expect(detector.update(turned).passed)
    }

    @Test func noFaceAndCrowdsGiveFeedback() {
        var detector = ChallengeDetector(challenge: .blink)
        #expect(detector.update(.noFace).feedback == .noFace)
        #expect(detector.update(FaceSample(faceCount: 2)).feedback == .multipleFaces)
    }

    @Test func centerFaceCalibratesBaseline() {
        var detector = ChallengeDetector(challenge: .centerFace)
        var sample = SimulatedFace.neutral
        sample.yaw = 5
        for _ in 0..<12 { _ = detector.update(sample) }
        #expect(detector.calibratedBaseline?.yaw == 5)
    }

    @Test func centerFaceAsksToLookAtCamera() {
        var detector = ChallengeDetector(challenge: .centerFace)
        var sample = SimulatedFace.neutral
        sample.yaw = 30
        #expect(detector.update(sample).feedback == .lookAtCamera)
    }
}

@MainActor
struct RunnerTests {
    @Test func fullRunPasses() {
        let session = EyelineSession(cues: EyelineCues(options: []))
        let runner = ChallengeRunner(session: session)
        runner.start(steps: [.blink, .turnRight])
        #expect(runner.steps == [.centerFace, .blink, .turnRight])
        for step in runner.steps {
            #expect(session.challenge == step)
            for sample in SimulatedFace.samples(for: step) {
                runner.process(sample)
                if session.challenge != step { break }
            }
        }
        #expect(session.phase == .passed)
        #expect(session.overallProgress == 1)
    }

    @Test func randomStepsAreDistinct() {
        let steps = ChallengeRunner.randomSteps(from: LivenessChallenge.actions, count: 3...3)
        #expect(Set(steps).count == 3)
    }
}

@MainActor
struct DisplaySupportTests {
    @Test func runnerPausesOnUnsupportedDisplayAndRestartsStep() {
        let session = EyelineSession(cues: EyelineCues(options: []))
        let runner = ChallengeRunner(session: session)
        runner.start(steps: [.blink])

        session.setDisplaySupported(false)
        // Samples are ignored while paused.
        for sample in SimulatedFace.samples(for: .centerFace) { runner.process(sample) }
        #expect(session.challenge == .centerFace)
        #expect(session.stepIndex == 0)

        session.setDisplaySupported(true)
        for sample in SimulatedFace.samples(for: .centerFace) { runner.process(sample) }
        #expect(session.challenge == .blink)
    }
}
