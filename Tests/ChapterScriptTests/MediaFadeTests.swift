//
//  MediaFadeTests.swift
//  ChapterScriptTests
//
//  FL-18 N12: the cross-media fade. One authored intent, two media, and
//  the same shape — so the tests that matter most are the ones proving
//  picture and sound agree about WHEN a clip is gone.
//

import XCTest
@testable import ChapterScript

final class MediaFadeTests: XCTestCase {

    // MARK: - The curve

    func testAClipWithNoFadesIsFullyPresentThroughout() {
        for t in stride(from: 0.0, through: 10.0, by: 1.0) {
            XCTAssertEqual(MediaFadeCurve.multiplier(at: t, start: 0, end: 10,
                                                     fadeIn: nil, fadeOut: nil), 1)
        }
    }

    func testAFadeInRampsFromNothingToWhole() {
        let f = { MediaFadeCurve.multiplier(at: $0, start: 0, end: 10, fadeIn: 2, fadeOut: nil) }
        XCTAssertEqual(f(0), 0, accuracy: 1e-9)
        XCTAssertEqual(f(1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(f(2), 1, accuracy: 1e-9)
        XCTAssertEqual(f(9), 1, accuracy: 1e-9, "no fade-out was authored")
    }

    func testAFadeOutEndsAtNothingExactlyAtTheClipEnd() {
        let f = { MediaFadeCurve.multiplier(at: $0, start: 4, end: 10, fadeIn: nil, fadeOut: 2) }
        XCTAssertEqual(f(4), 1, accuracy: 1e-9)
        XCTAssertEqual(f(8), 1, accuracy: 1e-9)
        XCTAssertEqual(f(9), 0.5, accuracy: 1e-9)
        XCTAssertEqual(f(10), 0, accuracy: 1e-9)
    }

    /// Two handles dragged past each other MEET, scaled proportionally —
    /// the result cannot depend on which one moved last.
    func testOverlongRampsMeetInsteadOfOneWinning() {
        let fitted = MediaFadeCurve.fitted(fadeIn: 6, fadeOut: 6, span: 4)
        XCTAssertEqual(fitted.in, 2, accuracy: 1e-9)
        XCTAssertEqual(fitted.out, 2, accuracy: 1e-9)

        // …and asymmetric wants keep their ratio.
        let lopsided = MediaFadeCurve.fitted(fadeIn: 3, fadeOut: 1, span: 2)
        XCTAssertEqual(lopsided.in, 1.5, accuracy: 1e-9)
        XCTAssertEqual(lopsided.out, 0.5, accuracy: 1e-9)

        // The peak of a fully-crossed clip is at its middle, and it is
        // continuous there rather than jumping.
        let f = { MediaFadeCurve.multiplier(at: $0, start: 0, end: 4, fadeIn: 6, fadeOut: 6) }
        XCTAssertEqual(f(2), 1, accuracy: 1e-9)
        XCTAssertEqual(f(1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(f(3), 0.5, accuracy: 1e-9)
    }

    /// Outside the clip the shape is CLAMPED at its endpoints, never
    /// snapped back to whole — a consumer that lands a hair past the end
    /// through rounding must not see the picture flash back.
    func testOutsideTheClipTheShapeIsClampedNotReset() {
        XCTAssertEqual(MediaFadeCurve.multiplier(at: -5, start: 0, end: 10,
                                                 fadeIn: 2, fadeOut: 2), 0)
        XCTAssertEqual(MediaFadeCurve.multiplier(at: 50, start: 0, end: 10,
                                                 fadeIn: 2, fadeOut: 2), 0)
        XCTAssertEqual(MediaFadeCurve.multiplier(at: 50, start: 0, end: 10,
                                                 fadeIn: nil, fadeOut: nil), 1,
                       "a clip with no fades is whole wherever it is asked about")
    }

    func testAZeroLengthClipIsNotDividedBy() {
        XCTAssertEqual(MediaFadeCurve.multiplier(at: 3, start: 3, end: 3,
                                                 fadeIn: 1, fadeOut: 1), 1)
    }

    // MARK: - The wire

    func testTheFadeFieldsRoundTripAndAbsentStaysAbsent() throws {
        var video = VideoActionDTO(file: "a.mov", channel: "main")
        video.fadeIn = 1.5
        video.fadeOut = 0.75
        let data = try ChapterScriptFormat.makeEncoder().encode(video)
        let back = try ChapterScriptFormat.makeDecoder().decode(VideoActionDTO.self, from: data)
        XCTAssertEqual(back.fadeIn, 1.5)
        XCTAssertEqual(back.fadeOut, 0.75)

        let plain = VideoActionDTO(file: "a.mov", channel: "main")
        let text = String(data: try ChapterScriptFormat.makeEncoder().encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("fadeIn"), "absent stays absent: \(text)")
        XCTAssertFalse(text.contains("fadeOut"))
    }

    func testAudioKeepsItsExistingFadeInAndGainsItsMirror() throws {
        var audio = AudioActionDTO(file: "a.wav", channel: "music", fadeIn: 2)
        audio.fadeOut = 3
        let data = try ChapterScriptFormat.makeEncoder().encode(audio)
        let back = try ChapterScriptFormat.makeDecoder().decode(AudioActionDTO.self, from: data)
        XCTAssertEqual(back.fadeIn, 2)
        XCTAssertEqual(back.fadeOut, 3)
    }

    // MARK: - The sound half, through the ONE gain rule

    private func sequence(fadeIn: Double?, fadeOut: Double?, stop: Double?) -> SequenceDefinitionDTO {
        var audio = AudioActionDTO(file: "score.wav", channel: "music", volume: 1, fadeIn: fadeIn)
        audio.fadeOut = fadeOut
        var actions: [ScheduledActionDTO] = [ScheduledActionDTO(at: 0, action: .playAudio(audio))]
        if let stop {
            actions.append(ScheduledActionDTO(at: stop, action: .stopAudio(channel: "music")))
        }
        let step = StepDefinitionDTO(id: "s1", name: "One", duration: 10,
                                     actions: [], scheduledActions: actions)
        return SequenceDefinitionDTO(id: "seq", name: "Seq", phase: "immersive",
                                     steps: [step], onComplete: .holdOnLastStep)
    }

    func testAnAudioFadeOutReachesSilenceAtTheClipEnd() {
        let fades = AudioGainComposition.fades(forChannel: "music",
                                               in: sequence(fadeIn: nil, fadeOut: 2, stop: nil))
        XCTAssertEqual(fades.count, 1)
        XCTAssertEqual(fades[0].startTime, 8, accuracy: 1e-9, "the step's own end is the clip's end")
        XCTAssertEqual(fades[0].to, 0)
        XCTAssertEqual(AudioGainComposition.level(base: 1, fades: fades, at: 10), 0, accuracy: 1e-6)
        XCTAssertEqual(AudioGainComposition.level(base: 1, fades: fades, at: 9), 0.5, accuracy: 1e-6)
    }

    /// The clip's end is the channel's NEXT STOP, not the step's end —
    /// the same span rule the runtime and the Timeline projection apply.
    func testTheFadeOutFollowsTheStopThatEndsTheClip() {
        let fades = AudioGainComposition.fades(forChannel: "music",
                                               in: sequence(fadeIn: nil, fadeOut: 2, stop: 6))
        XCTAssertEqual(fades.count, 1)
        XCTAssertEqual(fades[0].startTime, 4, accuracy: 1e-9)
        XCTAssertEqual(AudioGainComposition.level(base: 1, fades: fades, at: 6), 0, accuracy: 1e-6)
    }

    func testAudioRampsAreFittedTogetherToo() {
        let fades = AudioGainComposition.fades(forChannel: "music",
                                               in: sequence(fadeIn: 8, fadeOut: 8, stop: nil))
        XCTAssertEqual(fades.count, 2)
        XCTAssertEqual(fades[0].duration, 5, accuracy: 1e-9, "half the clip each")
        XCTAssertEqual(fades[1].duration, 5, accuracy: 1e-9)
    }

    /// PICTURE AND SOUND AGREE. One authored pair of numbers on two media
    /// puts the clip at the same level at the same instant — which is the
    /// whole point of calling this one gesture.
    func testPictureAndSoundAreGoneAtTheSameInstant() {
        let fades = AudioGainComposition.fades(forChannel: "music",
                                               in: sequence(fadeIn: 2, fadeOut: 2, stop: nil))
        for t in stride(from: 0.0, through: 10.0, by: 0.25) {
            let sound = AudioGainComposition.level(base: 1, fades: fades, at: t)
            let picture = MediaFadeCurve.multiplier(at: t, start: 0, end: 10,
                                                    fadeIn: 2, fadeOut: 2)
            XCTAssertEqual(Double(sound), picture, accuracy: 1e-6,
                           "picture and sound disagree at \(t)")
        }
    }
}
