//
//  MediaSourceRangeTests.swift
//  ChapterScriptTests
//
//  The range's own rules, and the wire compatibility that lets old documents
//  keep working. The composed document behaviour (placement, trimming,
//  backdrop overwrite) is tested in MaestroKit against real documents — these
//  cover the value type the whole feature stands on.
//

import XCTest
@testable import ChapterScript

final class MediaSourceRangeTests: XCTestCase {

    private let frame = 1.0 / 24.0

    // MARK: - Defaults

    func testUnmarkedRangeIsWholeSource() {
        let r = MediaSourceRange.full
        XCTAssertTrue(r.isFullSource)
        XCTAssertEqual(r.resolvedIn, 0)
        XCTAssertEqual(r.resolvedOut(masterDuration: 60), 60)
        XCTAssertEqual(r.duration(masterDuration: 60), 60)
    }

    func testUnmarkedRangeOnUnprobedMasterHasUnknownDuration() {
        // Not zero. A zero duration would make a placed clip collapse the
        // instant it was dropped, before the probe ever landed.
        XCTAssertNil(MediaSourceRange.full.duration(masterDuration: nil))
        XCTAssertNil(MediaSourceRange.full.resolvedOut(masterDuration: nil))
    }

    func testExplicitRangeDurationIsTheWindowNotTheMaster() {
        let r = MediaSourceRange(sourceIn: 20, sourceOut: 27)
        XCTAssertEqual(r.duration(masterDuration: 60)!, 7, accuracy: 1e-9)
    }

    func testOutPastMasterIsClampedWhenResolving() {
        let r = MediaSourceRange(sourceIn: 50, sourceOut: 90)
        XCTAssertEqual(r.resolvedOut(masterDuration: 60), 60)
        XCTAssertEqual(r.duration(masterDuration: 60)!, 10, accuracy: 1e-9)
    }

    func testReversedRangeReportsZeroDurationNotNegative() {
        let r = MediaSourceRange(sourceIn: 30, sourceOut: 10)
        XCTAssertEqual(r.duration(masterDuration: 60), 0)
    }

    // MARK: - Validation

    func testOutAtOrBeforeInIsInvalid() {
        XCTAssertThrowsError(try MediaSourceRange(sourceIn: 30, sourceOut: 10).validate()) {
            XCTAssertEqual($0 as? MediaSourceRange.Problem,
                           .outNotAfterIn(sourceIn: 30, sourceOut: 10))
        }
        XCTAssertThrowsError(try MediaSourceRange(sourceIn: 30, sourceOut: 30).validate())
    }

    func testSubFrameRangeIsInvalid() {
        let r = MediaSourceRange(sourceIn: 5, sourceOut: 5 + frame / 2)
        XCTAssertThrowsError(try r.validate(masterDuration: 60, minimumDuration: frame))
        XCTAssertTrue(MediaSourceRange(sourceIn: 5, sourceOut: 5 + frame)
            .isValid(masterDuration: 60, minimumDuration: frame))
    }

    func testInPastEndOfMasterIsInvalid() {
        XCTAssertThrowsError(try MediaSourceRange(sourceIn: 90).validate(masterDuration: 60)) {
            XCTAssertEqual($0 as? MediaSourceRange.Problem,
                           .inPastEndOfMedia(sourceIn: 90, masterDuration: 60))
        }
    }

    func testValidationSkipsMasterChecksWhenDurationUnknown() {
        // An author can mark a range before the probe lands; only the checks
        // that genuinely need the master are deferred.
        XCTAssertTrue(MediaSourceRange(sourceIn: 90, sourceOut: 120).isValid())
    }

    // MARK: - Clamping

    func testClampPullsBothMarksInsideMaster() {
        let r = MediaSourceRange(sourceIn: 80, sourceOut: 120)
            .clamped(toMasterDuration: 60, minimumDuration: frame)
        XCTAssertEqual(r.resolvedIn, 60 - frame, accuracy: 1e-9)
        XCTAssertEqual(r.resolvedOut(masterDuration: 60)!, 60, accuracy: 1e-9)
        XCTAssertTrue(r.isValid(masterDuration: 60, minimumDuration: frame))
    }

    func testClampLeavesLegalRangeAloneAndKeepsFullSourceUnmarked() {
        let legal = MediaSourceRange(sourceIn: 10, sourceOut: 20)
        XCTAssertEqual(legal.clamped(toMasterDuration: 60), legal)
        XCTAssertTrue(MediaSourceRange.full.clamped(toMasterDuration: 60).isFullSource)
    }

    // MARK: - Sequence time → source time

    func testElapsedMapsThroughTheInPoint() {
        // The headline case from the spec: a clip at sequence t=10 using
        // source 30 → 40 shows source 35 at sequence 15, not source 5.
        let r = MediaSourceRange(sourceIn: 30, sourceOut: 40)
        XCTAssertEqual(r.sourceTime(forElapsed: 0, masterDuration: 60), 30)
        XCTAssertEqual(r.sourceTime(forElapsed: 5, masterDuration: 60), 35)
    }

    func testPastTheWindowHoldsTheLastInstantWhenNotLooping() {
        let r = MediaSourceRange(sourceIn: 30, sourceOut: 40)
        XCTAssertEqual(r.sourceTime(forElapsed: 25, masterDuration: 60), 40)
    }

    func testLoopingWrapsTheSelectedWindowNotTheWholeFile() {
        let r = MediaSourceRange(sourceIn: 30, sourceOut: 32)
        // Four cycles of a 2s selection: 8s in is back at the in-point.
        XCTAssertEqual(r.sourceTime(forElapsed: 8, masterDuration: 60, looping: true), 30, accuracy: 1e-9)
        XCTAssertEqual(r.sourceTime(forElapsed: 5, masterDuration: 60, looping: true), 31, accuracy: 1e-9)
    }

    func testUnprobedMasterDegradesToPreSourceRangeBehaviour() {
        XCTAssertEqual(MediaSourceRange.full.sourceTime(forElapsed: 4, masterDuration: nil), 4)
    }

    // MARK: - Constrained edits

    func testSlipKeepsWindowLengthAndClampsToMaster() {
        let r = MediaSourceRange(sourceIn: 20, sourceOut: 27)
        let slipped = r.slipped(by: 5, masterDuration: 60)
        XCTAssertEqual(slipped.resolvedIn, 25, accuracy: 1e-9)
        XCTAssertEqual(slipped.duration(masterDuration: 60)!, 7, accuracy: 1e-9)

        // Slipping off the end pins to the last window that fits — the
        // duration is what must not change during a slip.
        let pinned = r.slipped(by: 1000, masterDuration: 60)
        XCTAssertEqual(pinned.duration(masterDuration: 60)!, 7, accuracy: 1e-9)
        XCTAssertEqual(pinned.resolvedOut(masterDuration: 60)!, 60, accuracy: 1e-9)

        let floored = r.slipped(by: -1000, masterDuration: 60)
        XCTAssertEqual(floored.resolvedIn, 0)
        XCTAssertEqual(floored.duration(masterDuration: 60)!, 7, accuracy: 1e-9)
    }

    func testTrimStartMovesInPointOnly() {
        let r = MediaSourceRange(sourceIn: 20, sourceOut: 27)
        let trimmed = r.trimmingStart(to: 24, masterDuration: 60)
        XCTAssertEqual(trimmed.resolvedIn, 24)
        XCTAssertEqual(trimmed.sourceOut, 27)
    }

    func testTrimStartCannotCrossTheOutPointOrGoNegative() {
        let r = MediaSourceRange(sourceIn: 20, sourceOut: 27)
        let crossed = r.trimmingStart(to: 99, masterDuration: 60, minimumDuration: frame)
        XCTAssertEqual(crossed.resolvedIn, 27 - frame, accuracy: 1e-9)
        XCTAssertEqual(r.trimmingStart(to: -50, masterDuration: 60).resolvedIn, 0)
    }

    func testTrimEndCannotRunPastAvailableSource() {
        // The NLE default: a normal trim stops at the end of the media.
        // Going beyond is Loop or Hold, authored deliberately.
        let r = MediaSourceRange(sourceIn: 20, sourceOut: 27)
        XCTAssertEqual(r.trimmingEnd(to: 500, masterDuration: 60).sourceOut, 60)
        XCTAssertEqual(r.trimmingEnd(to: 5, masterDuration: 60, minimumDuration: frame).sourceOut!,
                       20 + frame, accuracy: 1e-9)
    }

    // MARK: - Wire compatibility

    func testVideoWithoutMarksStillDecodesAndMeansWholeSource() throws {
        let json = #"{"file":"a.mov","channel":"main","volume":1,"loop":false}"#
        let dto = try JSONDecoder().decode(VideoActionDTO.self, from: Data(json.utf8))
        XCTAssertTrue(dto.sourceRange.isFullSource)
    }

    func testExistingVideoMarksAreReadThroughTheLens() throws {
        let json = #"{"file":"a.mov","channel":"main","sourceIn":12,"sourceOut":19}"#
        let dto = try JSONDecoder().decode(VideoActionDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.sourceRange, MediaSourceRange(sourceIn: 12, sourceOut: 19))
        XCTAssertEqual(dto.sourceRange.duration(masterDuration: 60)!, 7, accuracy: 1e-9)
    }

    func testAudioWithoutMarksDecodesAsWholeSource() throws {
        let json = #"{"file":"a.wav","channel":"amb","scope":"sequence","volume":1,"loop":true}"#
        let dto = try JSONDecoder().decode(AudioActionDTO.self, from: Data(json.utf8))
        XCTAssertTrue(dto.sourceRange.isFullSource)
    }

    func testAudioRangeRoundTrips() throws {
        var dto = AudioActionDTO(file: "a.wav", channel: "amb")
        dto.sourceRange = MediaSourceRange(sourceIn: 3, sourceOut: 9)
        let back = try JSONDecoder().decode(
            AudioActionDTO.self, from: try JSONEncoder().encode(dto))
        XCTAssertEqual(back.sourceRange, MediaSourceRange(sourceIn: 3, sourceOut: 9))
    }

    func testUnmarkedRangeEmitsNoKeys() throws {
        // Clean documents stay clean: "whole source" is the absence of marks,
        // not a pair of zeros that later reads as an authored decision.
        let data = try JSONEncoder().encode(AudioActionDTO(file: "a.wav", channel: "amb"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("sourceIn"))
        XCTAssertFalse(json.contains("sourceOut"))
    }

    // MARK: - Backdrop cues

    func testBackdropCueCarriesRangePerInstance() throws {
        let spec = ImmersiveBackdropSpec.video(
            file: "b.mov", layout: .mono, field: .equirect360,
            radius: 1000, loop: true, audioEnabled: false)
        var cue = BackdropCue(startTime: 12, spec: spec)
        cue.sourceRange = MediaSourceRange(sourceIn: 4, sourceOut: 10)
        let back = try JSONDecoder().decode(
            BackdropCue.self, from: try JSONEncoder().encode(cue))
        XCTAssertEqual(back.sourceRange, MediaSourceRange(sourceIn: 4, sourceOut: 10))
        XCTAssertEqual(back.sourceRange.duration(masterDuration: 30)!, 6, accuracy: 1e-9)
    }

    func testStaticBackdropsRefuseARangeRatherThanStoringAMeaninglessOne() {
        var usdz = BackdropCue(startTime: 0, spec: .usdz(assetId: "set"))
        XCTAssertFalse(usdz.supportsSourceRange)
        usdz.sourceRange = MediaSourceRange(sourceIn: 4, sourceOut: 10)
        XCTAssertTrue(usdz.sourceRange.isFullSource)
        XCTAssertNil(usdz.sourceIn)

        var image = BackdropCue(startTime: 0, spec: .image(file: "p.heic", field: .equirect360, radius: 1000))
        XCTAssertFalse(image.supportsSourceRange)
        image.sourceRange = MediaSourceRange(sourceIn: 1, sourceOut: 2)
        XCTAssertTrue(image.sourceRange.isFullSource)
    }

    func testOldBackdropCueDecodesAsWholeSource() throws {
        let json = #"{"id":"c1","startTime":5,"spec":{"kind":"video","file":"b.mov"}}"#
        let cue = try JSONDecoder().decode(BackdropCue.self, from: Data(json.utf8))
        XCTAssertTrue(cue.sourceRange.isFullSource)
        XCTAssertTrue(cue.supportsSourceRange)
    }

    // MARK: - Independence

    func testTwoInstancesOfOneMasterDoNotShareARange() {
        var a = VideoActionDTO(file: "interview.mov", channel: "v1")
        var b = VideoActionDTO(file: "interview.mov", channel: "v2")
        a.sourceRange = MediaSourceRange(sourceIn: 10, sourceOut: 16)
        b.sourceRange = MediaSourceRange(sourceIn: 62, sourceOut: 85)
        XCTAssertEqual(a.sourceRange, MediaSourceRange(sourceIn: 10, sourceOut: 16))
        XCTAssertEqual(b.sourceRange, MediaSourceRange(sourceIn: 62, sourceOut: 85))
    }
}
