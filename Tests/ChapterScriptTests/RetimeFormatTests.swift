//
//  RetimeFormatTests.swift
//  FL-13: the retime curve — format tolerance, identity cost, and the one
//  mapping's new parameters.
//

import XCTest
@testable import ChapterScript

final class RetimeFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(value)
    }

    // MARK: - Absence is identity, byte-identically

    func testAbsentRetimeWritesNothing() throws {
        let video = VideoActionDTO(file: "a.mov", channel: "main")
        let json = String(data: try encode(video), encoding: .utf8)!
        XCTAssertFalse(json.contains("retime"))
        XCTAssertFalse(json.contains("pitch"))
        let audio = AudioActionDTO(file: "a.wav", channel: "voice")
        let audioJSON = String(data: try encode(audio), encoding: .utf8)!
        XCTAssertFalse(audioJSON.contains("retime"))
    }

    func testRetimeRoundTripsOnBothCarriers() throws {
        var video = VideoActionDTO(file: "a.mov", channel: "main")
        video.retime = RetimeCurve.constant(sourceIn: 2, sourceOut: 8)
        video.pitch = .locked
        let back = try JSONDecoder().decode(VideoActionDTO.self, from: encode(video))
        XCTAssertEqual(back.retime, video.retime)
        XCTAssertEqual(back.pitch, .locked)

        var audio = AudioActionDTO(file: "a.wav", channel: "voice")
        audio.retime = RetimeCurve.constant(sourceIn: 0, sourceOut: 4)
        let audioBack = try JSONDecoder().decode(AudioActionDTO.self, from: encode(audio))
        XCTAssertEqual(audioBack.retime, audio.retime)
    }

    // MARK: - Sampling tolerance

    func testUnrecognisedSamplingIsNearestAndRoundTrips() throws {
        let data = Data(#"{"keys": [], "sampling": "opticalFlow"}"#.utf8)
        let curve = try JSONDecoder().decode(RetimeCurve.self, from: data)
        XCTAssertEqual(curve.sampling, .unknown("opticalFlow"))
        XCTAssertEqual(curve.sampling.effective, .nearest)
        let json = String(data: try encode(curve), encoding: .utf8)!
        XCTAssertTrue(json.contains("opticalFlow"))
    }

    func testUnrecognisedPitchIsFollowsSpeed() throws {
        let pitch = try JSONDecoder().decode(PitchHandling.self,
                                             from: Data(#""formantMagic""#.utf8))
        XCTAssertEqual(pitch, .followsSpeed)
    }

    // MARK: - The identity fast path is today's exact behaviour

    func testIdentityPathMatchesOldMappingExactly() {
        let range = MediaSourceRange(sourceIn: 3, sourceOut: 9)
        for elapsed in stride(from: -1.0, through: 12.0, by: 0.7) {
            let old = range.sourceTime(forElapsed: elapsed, masterDuration: 20, looping: true)
            let new = range.sourceTime(forElapsed: elapsed, masterDuration: 20, looping: true,
                                       retime: .identity, clipSpan: 6, nativeRateCorrection: 1)
            XCTAssertEqual(old, new, accuracy: 1e-12)
        }
    }

    func testNativeRateCorrectionScalesElapsedOnIdentityPath() {
        // A 25 fps master in a 24 fps Chapter: factor 24/25.
        let range = MediaSourceRange(sourceIn: 10, sourceOut: nil)
        let mapped = range.sourceTime(forElapsed: 5, masterDuration: 100,
                                      nativeRateCorrection: 24.0 / 25.0)
        XCTAssertEqual(mapped, 10 + 5 * 24.0 / 25.0, accuracy: 1e-12)
    }

    // MARK: - Spans of one curve: constant, reverse, freeze

    func testConstantCurveMapsLinearly() {
        // 2×: a 3-second span reads source 4 → 10.
        let range = MediaSourceRange(sourceIn: 4, sourceOut: 10)
        let curve = RetimeCurve.constant(sourceIn: 4, sourceOut: 10)
        let mid = range.sourceTime(forElapsed: 1.5, masterDuration: 20,
                                   retime: curve, clipSpan: 3)
        XCTAssertEqual(mid, 7, accuracy: 1e-9)
    }

    func testReverseIsANegativeSlopeSpanNotAFlag() {
        let range = MediaSourceRange(sourceIn: 0, sourceOut: 10)
        let curve = RetimeCurve.constant(sourceIn: 10, sourceOut: 0)
        XCTAssertTrue(curve.containsReverseSpan)
        let early = range.sourceTime(forElapsed: 1, masterDuration: 10,
                                     retime: curve, clipSpan: 4)
        let late = range.sourceTime(forElapsed: 3, masterDuration: 10,
                                    retime: curve, clipSpan: 4)
        XCTAssertGreaterThan(early, late)
        // The absence proof: RetimeCurve stores keys and sampling — there is
        // no reverse flag to set. (Mirror of the guide's "no other field".)
        let json = String(data: try! encode(curve), encoding: .utf8)!
        XCTAssertFalse(json.contains("reverse"))
    }

    func testFreezeIsAZeroSlopeSpan() {
        let curve = RetimeCurve(keys: [
            RetimeKey(timelinePosition: 0, sourcePosition: 2),
            RetimeKey(timelinePosition: 0.5, sourcePosition: 5),
            RetimeKey(timelinePosition: 1, sourcePosition: 5),
        ])
        let range = MediaSourceRange(sourceIn: 0, sourceOut: 10)
        let frozenA = range.sourceTime(forElapsed: 6, masterDuration: 10,
                                       retime: curve, clipSpan: 10)
        let frozenB = range.sourceTime(forElapsed: 9, masterDuration: 10,
                                       retime: curve, clipSpan: 10)
        XCTAssertEqual(frozenA, 5, accuracy: 1e-9)
        XCTAssertEqual(frozenB, 5, accuracy: 1e-9)
        XCTAssertFalse(curve.containsReverseSpan)
    }

    func testCurveResultClampsToTheAuthoredWindow() {
        // A curve stating positions outside the window cannot escape it.
        let range = MediaSourceRange(sourceIn: 5, sourceOut: 8)
        let curve = RetimeCurve.constant(sourceIn: 0, sourceOut: 20)
        let atStart = range.sourceTime(forElapsed: 0, masterDuration: 30,
                                       retime: curve, clipSpan: 2)
        let atEnd = range.sourceTime(forElapsed: 2, masterDuration: 30,
                                     retime: curve, clipSpan: 2)
        XCTAssertEqual(atStart, 5, accuracy: 1e-9)
        XCTAssertEqual(atEnd, 8, accuracy: 1e-9)
    }

    func testSteppedHoldsTheLeftKey() {
        let curve = RetimeCurve(keys: [
            RetimeKey(timelinePosition: 0, sourcePosition: 1, interpolation: .stepped),
            RetimeKey(timelinePosition: 1, sourcePosition: 9),
        ])
        XCTAssertEqual(curve.sourcePosition(atFraction: 0.99)!, 1, accuracy: 1e-9)
        XCTAssertEqual(curve.sourcePosition(atFraction: 1.0)!, 9, accuracy: 1e-9)
    }

    func testUnshapedBezierEqualsLinear() {
        let curve = RetimeCurve(keys: [
            RetimeKey(timelinePosition: 0, sourcePosition: 0, interpolation: .bezier),
            RetimeKey(timelinePosition: 1, sourcePosition: 10),
        ])
        for f in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(curve.sourcePosition(atFraction: f)!, f * 10, accuracy: 1e-6)
        }
    }

    func testSingleKeyCurveIsIdentity() {
        let curve = RetimeCurve(keys: [RetimeKey(timelinePosition: 0, sourcePosition: 3)])
        XCTAssertTrue(curve.isIdentity)
        // And the mapping treats it as identity: falls to the plain path.
        let range = MediaSourceRange(sourceIn: 0, sourceOut: 10)
        let mapped = range.sourceTime(forElapsed: 2, masterDuration: 10,
                                      retime: curve, clipSpan: 4)
        XCTAssertEqual(mapped, 2, accuracy: 1e-12)
    }
}

// MARK: - FL-19: named easing

final class NamedEasingTests: XCTestCase {

    private func curve(_ kind: AnimationInterpolation) -> AnimationCurve {
        AnimationCurve(keys: [
            AnimationKey(time: 0, value: 0, interpolation: kind),
            AnimationKey(time: 1, value: 1)])
    }

    func testTheFiveDefinedShapesAtSampledPoints() {
        let e = { (k: AnimationInterpolation, t: Double) -> Float in
            SequenceAnimationEvaluator.evaluate(self.curve(k), at: t, rest: 0) }
        XCTAssertEqual(e(.easeIn, 0.5), 0.25, accuracy: 1e-5)
        XCTAssertEqual(e(.easeOut, 0.5), 0.75, accuracy: 1e-5)
        XCTAssertEqual(e(.easeInOut, 0.25), 0.125, accuracy: 1e-5)
        XCTAssertEqual(e(.easeInOut, 0.75), 0.875, accuracy: 1e-5)
        XCTAssertLessThan(e(.easeInOutBack, 0.15), 0,
                          "back overshoots below zero on the way in")
        XCTAssertEqual(e(.easeInOutElastic, 1.0), 1, accuracy: 1e-5)
        XCTAssertEqual(e(.easeInOutElastic, 0), 0, accuracy: 1e-5)
    }

    func testUnknownInterpolationRendersBezierAndRoundTripsVerbatim() throws {
        let data = Data(#"{"time": 1, "value": 2, "interpolation": "easeQuantum"}"#.utf8)
        let key = try JSONDecoder().decode(AnimationKey.self, from: data)
        XCTAssertEqual(key.interpolation, .bezier, "the most general shape")
        XCTAssertEqual(key.unknownInterpolation, "easeQuantum")
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let json = String(data: try e.encode(key), encoding: .utf8)!
        XCTAssertTrue(json.contains("easeQuantum"), "a newer build restores it")
    }

    func testExistingThreeReSaveByteIdentically() throws {
        let key = AnimationKey(time: 2, value: 5, interpolation: .linear)
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let first = try e.encode(key)
        let back = try JSONDecoder().decode(AnimationKey.self, from: first)
        XCTAssertEqual(try e.encode(back), first)
    }
}
