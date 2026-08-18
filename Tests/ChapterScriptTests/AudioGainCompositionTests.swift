//
//  AudioGainCompositionTests.swift
//  ChapterScriptTests
//
//  THE COMPOSITION RULE, pinned.
//
//  Before this rule existed the two hosts disagreed: the Mac preview ignored
//  `fadeAudio` completely, and the runtime ran a fade ramp on one task while
//  the automation sampler wrote the same property from another and cancelled
//  it. "Whichever ran last wins" is exactly what these tests forbid.
//

import XCTest
@testable import ChapterScript

final class AudioGainCompositionTests: XCTestCase {

    private func track(_ channel: String, volume keys: [(Double, Float)]) -> AudioAutomationTrack {
        var track = AudioAutomationTrack(channel: channel)
        var curve = AnimationCurve()
        for (time, value) in keys { curve.setKey(AnimationKey(time: time, value: value)) }
        track[.volume] = curve
        return track
    }

    // MARK: - Level (fades alone)

    func testNoFadesHoldsTheBaseLevel() {
        XCTAssertEqual(AudioGainComposition.level(base: 0.8, fades: [], at: 5), 0.8)
    }

    /// A fade-in starts at SILENCE regardless of the base, because that is
    /// what a fade-in means — the explicit `from` is what says so.
    func testFadeInRampsFromSilence() {
        let fade = AudioFade(startTime: 0, duration: 2, to: 1.0, from: 0)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: [fade], at: 0), 1.0,
                       "at the very start the fade has not begun")
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: [fade], at: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: [fade], at: 2), 1.0, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: [fade], at: 9), 1.0, accuracy: 0.001)
    }

    /// A `fadeAudio` with no explicit start begins from whatever level is in
    /// force — which is the base when nothing has faded yet.
    func testFadeOutRampsFromTheRunningLevel() {
        let fade = AudioFade(startTime: 10, duration: 4, to: 0)
        XCTAssertEqual(AudioGainComposition.level(base: 0.8, fades: [fade], at: 9), 0.8)
        XCTAssertEqual(AudioGainComposition.level(base: 0.8, fades: [fade], at: 12), 0.4, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 0.8, fades: [fade], at: 14), 0.0, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 0.8, fades: [fade], at: 30), 0.0)
    }

    /// Fades apply IN ORDER, each starting where the last left off — so a duck
    /// and a recovery read as one gesture rather than two absolutes.
    func testSuccessiveFadesChain() {
        let down = AudioFade(startTime: 2, duration: 1, to: 0.2)
        let up = AudioFade(startTime: 6, duration: 1, to: 1.0)
        let fades = [down, up]
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: fades, at: 1), 1.0)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: fades, at: 2.5), 0.6, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: fades, at: 4), 0.2, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: fades, at: 6.5), 0.6, accuracy: 0.001)
        XCTAssertEqual(AudioGainComposition.level(base: 1.0, fades: fades, at: 8), 1.0, accuracy: 0.001)
    }

    /// Order of the ARRAY must not matter; order of TIME must.
    func testFadesAreOrderedByTimeNotByArrayPosition() {
        let down = AudioFade(startTime: 2, duration: 1, to: 0.2)
        let up = AudioFade(startTime: 6, duration: 1, to: 1.0)
        XCTAssertEqual(
            AudioGainComposition.level(base: 1, fades: [up, down], at: 4),
            AudioGainComposition.level(base: 1, fades: [down, up], at: 4)
        )
    }

    func testZeroDurationFadeIsAnInstantChange() {
        let cut = AudioFade(startTime: 5, duration: 0, to: 0.25)
        XCTAssertEqual(AudioGainComposition.level(base: 1, fades: [cut], at: 4.99), 1.0)
        XCTAssertEqual(AudioGainComposition.level(base: 1, fades: [cut], at: 5.01), 0.25)
    }

    // MARK: - Composition (the whole rule)

    /// THE HEADLINE: a fade and a volume key COMPOSE. Neither overwrites the
    /// other, and the answer does not depend on which was authored last.
    func testFadeAndAutomationCompose() {
        // Base 1.0, fading in over 2s, with the channel curve riding at 0.5.
        let fade = AudioFade(startTime: 0, duration: 2, to: 1.0, from: 0)
        let tracks = [track("audio-music", volume: [(0, 0.5)])]

        // Halfway through the fade: level 0.5, ride 0.5 ⇒ 0.25.
        let mid = AudioGainComposition.authoredGain(
            base: 1.0, fades: [fade], channel: "audio-music", at: 1, in: tracks
        )
        XCTAssertEqual(mid, 0.25, accuracy: 0.001)

        // After the fade: level 1.0, ride 0.5 ⇒ 0.5.
        let after = AudioGainComposition.authoredGain(
            base: 1.0, fades: [fade], channel: "audio-music", at: 5, in: tracks
        )
        XCTAssertEqual(after, 0.5, accuracy: 0.001)
    }

    /// The brief's worked example: base 0 dB, fade in 0→1 over 2s, a −6 dB
    /// volume key at 1s. The result must be deterministic and must be the
    /// PRODUCT, not one or the other.
    func testWorkedExampleFromTheBrief() {
        let fade = AudioFade(startTime: 0, duration: 2, to: 1.0, from: 0)
        // −6 dB ≈ 0.501 linear.
        let minusSix: Float = 0.501
        let tracks = [track("audio-vo", volume: [(0, 1.0), (1, minusSix)])]

        let atOne = AudioGainComposition.authoredGain(
            base: 1.0, fades: [fade], channel: "audio-vo", at: 1, in: tracks
        )
        // level(1s) = 0.5 (half through the fade), ride(1s) = 0.501.
        XCTAssertEqual(atOne, 0.5 * minusSix, accuracy: 0.002)
        // Neither factor alone.
        XCTAssertNotEqual(atOne, 0.5, accuracy: 0.05)
        XCTAssertNotEqual(atOne, minusSix, accuracy: 0.05)
    }

    func testMasterCurveRidesOnTop() {
        var master = AudioAutomationTrack(channel: AudioAutomationTrack.masterChannel)
        var curve = AnimationCurve()
        curve.setKey(AnimationKey(time: 0, value: 0.5))
        master[.volume] = curve
        let tracks = [track("audio-music", volume: [(0, 0.5)]), master]

        let gain = AudioGainComposition.authoredGain(
            base: 1.0, channel: "audio-music", at: 0, in: tracks
        )
        XCTAssertEqual(gain, 0.25, accuracy: 0.001, "channel × master")
    }

    /// An un-automated, un-faded clip must be EXACTLY its base — the rule has
    /// to be free for the overwhelmingly common document.
    func testUnautomatedClipIsItsBase() {
        XCTAssertEqual(
            AudioGainComposition.authoredGain(base: 0.8, channel: "audio-a", at: 3, in: []),
            0.8
        )
    }

    /// Bezier handles overshoot past a key on purpose; gain does not.
    func testGainIsClamped() {
        let tracks = [track("audio-a", volume: [(0, 1.0), (1, 1.0)])]
        let gain = AudioGainComposition.authoredGain(
            base: 1.0,
            fades: [AudioFade(startTime: 0, duration: 1, to: 5)],
            channel: "audio-a", at: 1, in: tracks
        )
        XCTAssertLessThanOrEqual(gain, 1.0)
        XCTAssertGreaterThanOrEqual(gain, 0.0)
    }

    // MARK: - Gathering from a document

    func testFadesAreGatheredFromTheSequenceInAbsoluteTime() {
        var first = StepDefinitionDTO(id: "s1", name: "S1", duration: 10,
                                      actions: [], scheduledActions: [], gate: nil)
        first.authoredActions = [
            AuthoredAction(id: "a1", at: 0, action: .playAudio(
                AudioActionDTO(file: "m.wav", channel: "audio-m", volume: 1, loop: false,
                               fadeIn: 2)
            ))
        ]
        var second = StepDefinitionDTO(id: "s2", name: "S2", duration: 10,
                                       actions: [], scheduledActions: [], gate: nil)
        second.authoredActions = [
            AuthoredAction(id: "a2", at: 3,
                           action: .fadeAudio(channel: "audio-m", to: 0, duration: 4))
        ]
        let sequence = SequenceDefinitionDTO(
            id: "seq", name: "S", phase: "immersive", steps: [first, second],
            visibility: VisibilityStateDTO(), onComplete: .holdOnLastStep
        )

        let fades = AudioGainComposition.fades(forChannel: "audio-m", in: sequence)
        XCTAssertEqual(fades.count, 2)
        // The fade-in is at the clip's start…
        XCTAssertEqual(fades[0].startTime, 0)
        XCTAssertEqual(fades[0].from, 0, "a fade-in starts from silence")
        // …and the fadeAudio is at step-2-start (10) + its offset (3) = 13.
        XCTAssertEqual(fades[1].startTime, 13, accuracy: 0.001)
        XCTAssertEqual(fades[1].to, 0)
    }

    func testFadesForAnotherChannelAreNotGathered() {
        var step = StepDefinitionDTO(id: "s1", name: "S1", duration: 10,
                                     actions: [], scheduledActions: [], gate: nil)
        step.authoredActions = [
            AuthoredAction(id: "a1", at: 0,
                           action: .fadeAudio(channel: "audio-other", to: 0, duration: 1))
        ]
        let sequence = SequenceDefinitionDTO(
            id: "seq", name: "S", phase: "immersive", steps: [step],
            visibility: VisibilityStateDTO(), onComplete: .holdOnLastStep
        )
        XCTAssertTrue(AudioGainComposition.fades(forChannel: "audio-m", in: sequence).isEmpty)
    }

    /// EVERYTHING IS ON THE AUTHORED CLOCK. A gate holding the sequence at 12s
    /// holds the fade at 12s — there is no wall-clock term anywhere in the
    /// rule, which is what makes that true by construction.
    func testGainIsAPureFunctionOfAuthoredTime() {
        let fade = AudioFade(startTime: 10, duration: 4, to: 0)
        let a = AudioGainComposition.authoredGain(
            base: 1, fades: [fade], channel: "c", at: 12, in: [])
        let b = AudioGainComposition.authoredGain(
            base: 1, fades: [fade], channel: "c", at: 12, in: [])
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, 0.5, accuracy: 0.001, "held at 12s, halfway through the fade")
    }
}
