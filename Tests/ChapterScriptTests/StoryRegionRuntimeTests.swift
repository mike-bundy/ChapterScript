//
//  StoryRegionRuntimeTests.swift
//  ChapterScriptTests
//
//  THE TWO CLOCKS, PINNED BEFORE ANY UI EXISTS.
//
//  Every assertion here is about a rule an author would notice being broken:
//  content skipped, an action fired twice, a story that jumped ahead, a timer
//  that ran while the app was in the background. The device half — a tap
//  landing, a video looping — is not claimed here.
//
//  Two clocks appear throughout and are never mixed up:
//
//      authoredTime   the Sequence clock. Parks at the region end during a
//                     hold, because the engine clamps it there.
//      runtimeTime    the runtime's pause-aware playback clock. Keeps going.
//

import XCTest
@testable import ChapterScript

final class StoryRegionRuntimeTests: XCTestCase {

    /// 10 → 20s, the span used by most of these.
    private func radioRoom(fallback: Double? = nil) -> StoryRegion {
        StoryRegion(id: "sr_radio", name: "Radio Room",
                    startTime: 10, previewDuration: 10,
                    exit: StepGateDTO(type: .tap), fallbackTimeout: fallback)
    }

    // MARK: - The first pass always plays

    func testEnteringARegionDoesNotFreezeAnything() {
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 10)

        // Authored time is inside the span: the first pass is running, and the
        // clock is free to keep advancing through it.
        XCTAssertEqual(runtime.phase(authoredTime: 10), .firstPass)
        XCTAssertEqual(runtime.phase(authoredTime: 14), .firstPass)
        XCTAssertEqual(runtime.phase(authoredTime: 19.99), .firstPass)
        XCTAssertTrue(runtime.mayAdvance(authoredTime: 14),
                      "A region must never freeze the story on entry — the authored pass plays.")
    }

    // MARK: - Resolving early does not skip content

    func testResolvingEarlyDoesNotSkipTheRestOfTheFirstPass() {
        var runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 10)

        // The viewer satisfies the exit at 14s of a 10→20 region.
        runtime.resolve(atRuntimeTime: 14)

        XCTAssertEqual(runtime.resolution, .exitCondition)
        // Authored time continues NORMALLY from 14 to 20. Nothing between them
        // may be skipped — jumping ahead would make the Timeline
        // non-deterministic, and every action in that window is authored.
        for t in stride(from: 14.0, to: 20.0, by: 1.0) {
            XCTAssertTrue(runtime.mayAdvance(authoredTime: t))
        }
        // And at the boundary it simply continues, with no hold.
        XCTAssertTrue(runtime.mayAdvance(authoredTime: 20))
        XCTAssertEqual(runtime.phase(authoredTime: 20), .resolved)
    }

    // MARK: - Unresolved at the boundary holds

    func testUnresolvedAtTheBoundaryHolds() {
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 10)

        XCTAssertEqual(runtime.phase(authoredTime: 20), .held)
        XCTAssertFalse(runtime.mayAdvance(authoredTime: 20),
                       "The story parks AT the boundary until its exit resolves.")
    }

    func testTheAuthoredClockNeverRunsBackward() {
        // Looping is a SAMPLING overlay. The authored clock the engine reports
        // stays at the boundary; only `loopSampleTime` moves, and only for
        // targets explicitly authored to loop.
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 0)

        let samples = (0...40).map { runtime.loopSampleTime(authoredTime: 20, atRuntimeTime: Double($0)) }
        XCTAssertTrue(samples.allSatisfy { $0 != nil })
        // The overlay cycles inside the region…
        for sample in samples.compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(sample, 10)
            XCTAssertLessThan(sample, 20)
        }
        // …while the phase — and therefore the authored clock — never leaves
        // the hold.
        XCTAssertEqual(runtime.phase(authoredTime: 20), .held)
    }

    func testLoopSampleTimeIsAbsentDuringTheFirstPass() {
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 0)
        XCTAssertNil(runtime.loopSampleTime(authoredTime: 15, atRuntimeTime: 5),
                     "There is nothing to overlay while authored time is still doing the job.")
    }

    func testLoopWrapsAtThePreviewSpan() {
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 0)
        // dwell = elapsed − previewDuration. At runtime 10 the hold has just begun.
        XCTAssertEqual(runtime.loopSampleTime(authoredTime: 20, atRuntimeTime: 10) ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(runtime.loopSampleTime(authoredTime: 20, atRuntimeTime: 13) ?? -1, 13, accuracy: 0.001)
        // One full lap: back to the region start, not to zero and not past the end.
        XCTAssertEqual(runtime.loopSampleTime(authoredTime: 20, atRuntimeTime: 20) ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(runtime.loopSampleTime(authoredTime: 20, atRuntimeTime: 25) ?? -1, 15, accuracy: 0.001)
    }

    // MARK: - Resolving while held

    func testResolvingWhileHeldReleasesTheStoryExactlyOnce() {
        var runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 0)
        XCTAssertFalse(runtime.mayAdvance(authoredTime: 20))

        runtime.resolve(atRuntimeTime: 33)
        XCTAssertTrue(runtime.mayAdvance(authoredTime: 20))

        // A detector that fires twice at the boundary must not resolve twice.
        runtime.resolve(atRuntimeTime: 34)
        XCTAssertEqual(runtime.resolvedAtRuntimeTime, 33,
                       "Resolution is idempotent — a second satisfaction changes nothing.")
    }

    // MARK: - The fallback timer

    func testTheTimerRunsFromRegionEntryNotFromTheHold() {
        var runtime = StoryRegionRuntime(region: radioRoom(fallback: 30), enteredAtRuntimeTime: 100)

        // 10s of authored first pass + 19s of dwell = 29s in the room.
        XCTAssertFalse(runtime.fallbackExpired(atRuntimeTime: 129))
        // 30s in the room, wherever they were spent.
        XCTAssertTrue(runtime.fallbackExpired(atRuntimeTime: 130))

        XCTAssertTrue(runtime.applyFallbackIfDue(atRuntimeTime: 130))
        XCTAssertEqual(runtime.resolution, .fallbackTimer)
    }

    func testATimerExpiringDuringTheFirstPassDoesNotSkipIt() {
        // Preview 10s, fallback 4s: the timer is up while authored time is
        // still at 14 of a 10→20 region.
        var runtime = StoryRegionRuntime(region: radioRoom(fallback: 4), enteredAtRuntimeTime: 0)

        XCTAssertTrue(runtime.applyFallbackIfDue(atRuntimeTime: 4))
        XCTAssertEqual(runtime.resolution, .fallbackTimer)

        // The exit is satisfied — and the authored first pass still plays out.
        for t in stride(from: 14.0, through: 20.0, by: 1.0) {
            XCTAssertTrue(runtime.mayAdvance(authoredTime: t),
                          "A timer marks the exit satisfied. It never fast-forwards authored content.")
        }
    }

    func testAnAlreadyResolvedRegionIgnoresItsTimer() {
        var runtime = StoryRegionRuntime(region: radioRoom(fallback: 5), enteredAtRuntimeTime: 0)
        runtime.resolve(.exitCondition, atRuntimeTime: 2)
        XCTAssertFalse(runtime.applyFallbackIfDue(atRuntimeTime: 99))
        XCTAssertEqual(runtime.resolution, .exitCondition,
                       "The viewer resolved it; the timer must not overwrite why.")
    }

    func testNoTimerMeansNoExpiry() {
        let runtime = StoryRegionRuntime(region: radioRoom(fallback: nil), enteredAtRuntimeTime: 0)
        XCTAssertFalse(runtime.fallbackExpired(atRuntimeTime: 10_000))
    }

    // MARK: - Pause

    func testThePauseAwareClockIsTheCallersToSupply() {
        // The runtime measures on whatever clock it is handed. The engine hands
        // it a PAUSE-AWARE playback clock, so a pause simply stops advancing
        // the value — there is no second timer here to leak or race, and a
        // suspended app cannot come back to an expired region.
        var runtime = StoryRegionRuntime(region: radioRoom(fallback: 30), enteredAtRuntimeTime: 0)

        // 20s of playback, then a long pause during which the clock does not move.
        XCTAssertFalse(runtime.applyFallbackIfDue(atRuntimeTime: 20))
        XCTAssertFalse(runtime.applyFallbackIfDue(atRuntimeTime: 20))
        XCTAssertFalse(runtime.applyFallbackIfDue(atRuntimeTime: 20),
                       "Wall time passing while paused must not expire a region.")
        // Playback resumes and reaches 30s of real playback.
        XCTAssertTrue(runtime.applyFallbackIfDue(atRuntimeTime: 30))
    }

    // MARK: - Dwell reporting

    func testDwellIsZeroUntilTheBoundary() {
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 0)
        XCTAssertEqual(runtime.dwell(authoredTime: 15, atRuntimeTime: 5), 0)
        XCTAssertEqual(runtime.dwell(authoredTime: 20, atRuntimeTime: 14), 4, accuracy: 0.001)
    }

    // MARK: - Not serialized

    func testRuntimeStateHasNoRouteIntoADocument() {
        // Same guard as `InteractionLedger`. If someone makes this Codable the
        // assertion fails — a region's dwell must never reach a document, an
        // undo stack or the sync protocol.
        let runtime = StoryRegionRuntime(region: radioRoom(), enteredAtRuntimeTime: 0)
        XCTAssertFalse((runtime as Any) is any Encodable)
    }
}

// MARK: - The authored model

final class StoryRegionModelTests: XCTestCase {

    private func region(_ id: String, _ start: Double, _ duration: Double) -> StoryRegion {
        StoryRegion(id: id, startTime: start, previewDuration: duration)
    }

    func testASequenceWithNoRegionsIsEntirelyDirected() {
        let sequence = SequenceDefinitionDTO(id: "s", name: "S", phase: "immersive", steps: [])
        XCTAssertTrue(sequence.storyRegions.isEmpty,
                      "Directed is the ABSENCE of a region. Nothing is drawn to get ordinary playback.")
        XCTAssertNil(StoryRegionTimeline.region(at: 5, in: sequence.storyRegions))
    }

    func testRegionsMayTouchButNotOverlap() {
        let existing = [region("a", 10, 5)]          // 10 → 15
        XCTAssertFalse(StoryRegionTimeline.overlaps(region("b", 15, 5), in: existing),
                       "Adjacent is legal: at any instant exactly one region is in control.")
        XCTAssertFalse(StoryRegionTimeline.overlaps(region("b", 0, 10), in: existing))
        XCTAssertTrue(StoryRegionTimeline.overlaps(region("b", 14, 5), in: existing))
        XCTAssertTrue(StoryRegionTimeline.overlaps(region("b", 11, 1), in: existing))
        XCTAssertTrue(StoryRegionTimeline.overlaps(region("b", 5, 20), in: existing),
                      "A region that swallows another is an overlap, not a merge.")
    }

    func testARegionDoesNotOverlapItself() {
        let existing = [region("a", 10, 5)]
        var moved = existing[0]
        moved.previewDuration = 8
        XCTAssertFalse(StoryRegionTimeline.overlaps(moved, in: existing))
    }

    func testAvailableDurationStopsAtTheNextRegion() {
        let existing = [region("a", 10, 5), region("b", 30, 5)]
        XCTAssertEqual(StoryRegionTimeline.availableDuration(from: 15, in: existing), 15)
        XCTAssertEqual(StoryRegionTimeline.availableDuration(from: 0, in: existing), 10)
        XCTAssertNil(StoryRegionTimeline.availableDuration(from: 12, in: existing),
                     "Starting inside another region has no room — refuse rather than trim someone else's.")
    }

    func testOnlyARegionEndIsAStallPoint() {
        // A boundary is "a place the story can stall" (TIMELINE_3_0 D2). A
        // region's END is one — its exit gate lives there. Its START is not:
        // the first pass has to run straight through it.
        XCTAssertEqual(StoryRegionTimeline.requiredBoundaries([region("a", 10, 5)]), [15])
        XCTAssertEqual(StoryRegionTimeline.requiredBoundaries([region("a", 0, 20)]), [20])
        XCTAssertEqual(
            StoryRegionTimeline.requiredBoundaries([region("b", 30, 5), region("a", 10, 5)]),
            [15, 35], "Sorted, whatever order they are stored in.")
    }

    func testContainsIsHalfOpen() {
        let r = region("a", 10, 5)
        XCTAssertTrue(r.contains(10))
        XCTAssertTrue(r.contains(14.999))
        XCTAssertFalse(r.contains(15), "The end belongs to what comes next — the rule that stops double-firing.")
    }

    func testEverythingHoldsUnlessExplicitlyAuthored() {
        var r = region("a", 10, 5)
        r.continuations = [.init(target: .entityAnimation(entity: "Radio"), behavior: .loop)]
        XCTAssertEqual(r.behavior(for: .entityAnimation(entity: "Radio")), .loop)
        XCTAssertEqual(r.behavior(for: .entityAnimation(entity: "Door")), .hold,
                       "Inferring behaviour would make a chapter nobody can read off the document.")
        XCTAssertEqual(r.behavior(for: .occurrence(actionId: "act_1")), .hold)
    }

    func testRoundTripAndTolerance() throws {
        var r = region("sr_1", 10, 5)
        r.name = "Radio Room"
        r.fallbackTimeout = 30
        r.exit = StepGateDTO(type: .viewerFacing, targetEntity: "Radio")
        r.continuations = [
            .init(target: .occurrence(actionId: "act_9"), behavior: .loop),
            .init(target: .backdropCue(id: "cue_2"), behavior: .stop)
        ]
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(StoryRegion.self, from: data), r)

        // A region from a newer tool, with only a span.
        let sparse = try JSONDecoder().decode(
            StoryRegion.self, from: Data(#"{"id":"sr_2","startTime":4,"previewDuration":2}"#.utf8))
        XCTAssertEqual(sparse.exit.type, .tap)
        XCTAssertNil(sparse.fallbackTimeout)
        XCTAssertTrue(sparse.continuations.isEmpty)

        // An unknown continuation target degrades rather than failing the load.
        let odd = try JSONDecoder().decode(
            StoryContinuationTarget.self, from: Data(#"{"kind":"hologram","id":"x"}"#.utf8))
        XCTAssertEqual(odd, .occurrence(actionId: "x"))
    }

    func testAnEmptyContinuationListAddsNothingToTheDocument() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(region("a", 1, 1)), as: UTF8.self)
        XCTAssertFalse(text.contains("continuations"))
    }

    func testASpanShorterThanAFrameIsClampedRatherThanRefused() {
        // A drag must never be able to produce a region the author cannot see.
        XCTAssertEqual(region("a", 0, 0).previewDuration, StoryRegion.minimumDuration, accuracy: 1e-9)
        XCTAssertEqual(StoryRegion(startTime: -5, previewDuration: 3).startTime, 0)
    }

    func testAWholeSequenceRegionIsJustARegion() {
        // Not a second Sequence type. Nothing here distinguishes it.
        let whole = region("a", 0, 120)
        XCTAssertTrue(whole.contains(0))
        XCTAssertTrue(whole.contains(119.9))
        XCTAssertEqual(StoryRegionTimeline.requiredBoundaries([whole]), [120])
    }
}
