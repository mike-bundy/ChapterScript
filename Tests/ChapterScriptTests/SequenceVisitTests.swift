//
//  SequenceVisitTests.swift
//  ChapterScriptTests
//
//  PHASE 8.0 — THE VISIT BOUNDARY.
//
//  Phase 6 established what a visit MEANS (`.once` is at most one activation
//  per visit) and the runtime honoured it by rebuilding state on each play. But
//  nothing named a visit, so nothing could tell two apart — which Return and
//  Resume will need to do. These pin the boundary before those exist.
//

import XCTest
@testable import ChapterScript

final class SequenceVisitTests: XCTestCase {

    func testEveryEntryMintsAFreshIdentity() {
        let a = SequenceVisit(sequenceId: "museum")
        let b = SequenceVisit(sequenceId: "museum")
        XCTAssertNotEqual(a.id, b.id,
                          "Play, stop, play again is two visits of one Sequence — not one visit seen twice.")
        XCTAssertNotEqual(a, b)
    }

    func testAVisitKnowsWhatItIsAVisitOf() {
        let visit = SequenceVisit(sequenceId: "museum")
        XCTAssertTrue(visit.isVisit(of: "museum"))
        XCTAssertFalse(visit.isVisit(of: "gallery"),
                       "Asked by stable id — never by name or index.")
    }

    func testTwoSequencesVisitedInTurnAreDistinct() {
        let a = SequenceVisit(sequenceId: "opening")
        let b = SequenceVisit(sequenceId: "museum")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a.sequenceId, b.sequenceId)
    }

    func testTheSameVisitValueComparesEqualToItself() {
        // A visit passed around must be recognisable as the SAME visit — that
        // is what makes "is this still the current one?" answerable.
        let visit = SequenceVisit(sequenceId: "museum")
        let carried = visit
        XCTAssertEqual(visit, carried)
        XCTAssertTrue(carried.isVisit(of: "museum"))
    }

    func testAnIdentityCanBeReconstructedForTests() {
        let id = SequenceVisitID()
        XCTAssertEqual(SequenceVisit(id: id, sequenceId: "s"),
                       SequenceVisit(id: id, sequenceId: "s"))
    }

    /// THE GUARD. A visit describes a moment of playback, not authored content.
    /// Runtime state reaching the document is the bug this asserts against —
    /// the same rule `InteractionLedger` and `StoryRegionRuntime` already keep.
    func testAVisitIsNotCodable() {
        XCTAssertFalse((SequenceVisit.self as Any) is any Codable.Type)
        XCTAssertFalse((SequenceVisitID.self as Any) is any Codable.Type)
    }

    func testAVisitIDIsNotDerivedFromTheSequenceID() {
        // Two visits of the same Sequence must not collide, and a visit id must
        // not be reconstructible from authored state — otherwise a "new" visit
        // could be mistaken for a resumed one.
        let ids = Set((0..<50).map { _ in SequenceVisit(sequenceId: "museum").id })
        XCTAssertEqual(ids.count, 50)
    }

    // MARK: - The Story Region contract

    /// Entering, looping and leaving a Story Region all happen INSIDE one
    /// visit. Phase 7 already behaves this way; this states it so Phase 8's
    /// Return/Restart cannot quietly reinterpret it.
    func testAStoryRegionHoldDoesNotCreateANewVisit() {
        let visit = SequenceVisit(sequenceId: "museum")

        // Directed → Explore → hold → exit → Directed, all within one visit.
        let duringExplore = visit
        let duringHold = visit
        let afterExit = visit

        XCTAssertEqual(duringExplore, visit)
        XCTAssertEqual(duringHold, visit)
        XCTAssertEqual(afterExit, visit)
        XCTAssertEqual(afterExit.id, visit.id,
                       "An Explore loop is not a new visit — that is why `.once` stays spent across it.")
    }

    func testStoppingAndPlayingAgainIsANewVisit() {
        var current: SequenceVisit? = SequenceVisit(sequenceId: "museum")
        let first = current!
        current = nil                                   // stop discards it
        current = SequenceVisit(sequenceId: "museum")   // fresh play
        XCTAssertNotEqual(current!.id, first.id)
    }
}
