//
//  ExperienceNavigatorTests.swift
//  ChapterScriptTests
//
//  PHASE 8A — ONE NAVIGATOR.
//
//  Two things are pinned here above all others:
//
//    1. Legacy `autoAdvance` produces the SAME A → B → C behaviour it always
//       did, while going through the new navigator (§10).
//    2. Return is VISIT-based, so `A1 → B1 → A2 → B2` returns to A2 and not to
//       A1 (§13). Those are the same authored Sequence.
//
//  Plus the scale rules an hour-long chapter needs: bounded history, and
//  thousands of navigations without unbounded growth.
//

import XCTest
@testable import ChapterScript

final class ExperienceNavigatorTests: XCTestCase {

    private let chapter: Set<String> = ["a", "b", "c", "gallery", "hub"]
    private func exists(_ id: String) -> Bool { chapter.contains(id) }
    private func start() -> String? { "a" }

    private func nav() -> ExperienceNavigator { ExperienceNavigator() }

    private func enter(_ outcome: NavigationOutcome) -> (String, SequenceVisit)? {
        guard case .enter(let id, let visit, _) = outcome else { return nil }
        return (id, visit)
    }

    // MARK: - Start

    func testStartEntersTheChaptersStartAsAFreshVisit() {
        var n = nav()
        let out = n.handle(.init(intent: .start, source: .host),
                           exists: exists, start: start)
        XCTAssertEqual(enter(out)?.0, "a")
        XCTAssertEqual(n.current?.sequenceId, "a")
        XCTAssertFalse(n.canReturn, "Starting clears history — it is the beginning.")
    }

    func testAChapterWithNoStartRefuses() {
        var n = nav()
        let out = n.handle(.init(intent: .start, source: .host),
                           exists: exists, start: { nil })
        XCTAssertEqual(out, .refused(.noStart))
    }

    // MARK: - Legacy autoAdvance convergence

    /// THE COMPATIBILITY TEST. An old linear Chapter still plays A → B → C, and
    /// does it through the same navigator a Go To uses.
    func testLegacyAutoAdvanceStillPlaysAThenBThenC() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        XCTAssertEqual(n.current?.sequenceId, "a")

        let toB = n.handleCompletion(.autoAdvance(nextSequenceId: "b"), from: "a",
                                     exists: exists, start: start)
        XCTAssertEqual(enter(toB)?.0, "b")

        let toC = n.handleCompletion(.autoAdvance(nextSequenceId: "c"), from: "b",
                                     exists: exists, start: start)
        XCTAssertEqual(enter(toC)?.0, "c")
        XCTAssertEqual(n.current?.sequenceId, "c")
    }

    func testEachLinkOfAChainIsItsOwnVisit() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let first = n.current!.id
        _ = n.handleCompletion(.autoAdvance(nextSequenceId: "b"), from: "a",
                               exists: exists, start: start)
        XCTAssertNotEqual(n.current!.id, first)
    }

    func testHoldIsNotNavigationAndIsNotEnd() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let out = n.handleCompletion(.holdOnLastStep, from: "a", exists: exists, start: start)
        XCTAssertEqual(out, .stay)
        XCTAssertEqual(n.current?.sequenceId, "a",
                       "Hold keeps the experience alive on its last frame. It is not End.")
    }

    func testDismissToHomeEnds() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        XCTAssertEqual(n.handleCompletion(.dismissToHome, from: "a",
                                          exists: exists, start: start), .finish)
        XCTAssertNil(n.current)
    }

    func testAMissingChainTargetRefusesRatherThanGuessing() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let out = n.handleCompletion(.autoAdvance(nextSequenceId: "ghost"), from: "a",
                                     exists: exists, start: start)
        XCTAssertEqual(out, .refused(.unknownTarget("ghost")))
        XCTAssertEqual(n.current?.sequenceId, "a",
                       "It does not silently continue to some other Sequence.")
    }

    // MARK: - Go To

    func testGoToEntersAFreshVisitAndRemembersTheOrigin() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let out = n.handle(.init(intent: .goTo(sequenceId: "gallery"),
                                 source: .interaction(entity: "Door", interactionId: "i1")),
                           exists: exists, start: start, currentPosition: 12)
        XCTAssertEqual(enter(out)?.0, "gallery")
        XCTAssertTrue(n.canReturn)
        XCTAssertEqual(n.suspendedCount, 1)
    }

    func testGoToAnUnknownSequenceRefuses() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        XCTAssertEqual(n.handle(.init(intent: .goTo(sequenceId: "ghost"), source: .host),
                                exists: exists, start: start),
                       .refused(.unknownTarget("ghost")))
        XCTAssertEqual(n.suspendedCount, 0, "A refused navigation suspends nothing.")
    }

    // MARK: - Return is visit-based

    /// THE HEADLINE. A1 → B1 → A2 → B2, returning from B2 must reach A2.
    func testReturnFollowsVisitsNotSequenceIds() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)  // A1
        let a1 = n.current!.id
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: exists, start: start)                                        // B1
        _ = n.handle(.init(intent: .goTo(sequenceId: "a"), source: .host),
                     exists: exists, start: start)                                        // A2
        let a2 = n.current!.id
        XCTAssertNotEqual(a1, a2, "Same authored Sequence, different visits.")
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: exists, start: start)                                        // B2

        let back = n.handle(.init(intent: .back(policy: .resume), source: .host),
                            exists: exists, start: start)
        XCTAssertEqual(enter(back)?.1.id, a2,
                       "Return goes to the visit that led here — A2, not A1.")
    }

    func testReturnResumesTheSameVisitAtItsPosition() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let origin = n.current!
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: exists, start: start, currentPosition: 42)

        let back = n.handle(.init(intent: .back(policy: .resume), source: .host),
                            exists: exists, start: start)
        guard case .enter(_, let visit, let resumeAt) = back else { return XCTFail() }
        XCTAssertEqual(visit.id, origin.id,
                       "RESUME keeps the visit id — which is why `.once` stays spent.")
        XCTAssertEqual(resumeAt, 42)
    }

    func testReturnWithRestartPolicyMintsAFreshVisit() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let origin = n.current!
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: exists, start: start, currentPosition: 42)

        let back = n.handle(.init(intent: .back(policy: .restart), source: .host),
                            exists: exists, start: start)
        guard case .enter(let id, let visit, let resumeAt) = back else { return XCTFail() }
        XCTAssertEqual(id, origin.sequenceId)
        XCTAssertNotEqual(visit.id, origin.id, "Restart and Resume must never coincide.")
        XCTAssertNil(resumeAt, "A restarted Sequence begins at the beginning.")
    }

    func testReturnWithNoOriginFailsSafely() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        XCTAssertEqual(n.handle(.init(intent: .back(policy: .resume), source: .host),
                                exists: exists, start: start),
                       .refused(.noOrigin))
        XCTAssertEqual(n.current?.sequenceId, "a", "It stays where it is.")
    }

    func testReturningToADeletedSequenceRefusesRatherThanRedirecting() {
        var n = nav()
        var live: Set<String> = ["a", "b"]
        _ = n.handle(.init(intent: .start, source: .host),
                     exists: { live.contains($0) }, start: start)
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: { live.contains($0) }, start: start)
        live.remove("a")                                    // deleted mid-run

        let back = n.handle(.init(intent: .back(policy: .resume), source: .host),
                            exists: { live.contains($0) }, start: start)
        XCTAssertEqual(back, .refused(.unknownTarget("a")))
    }

    // MARK: - Restart

    func testRestartMintsAFreshVisitOfTheSameSequence() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let before = n.current!
        let out = n.handle(.init(intent: .restart, source: .host), exists: exists, start: start)
        guard case .enter(let id, let visit, let resumeAt) = out else { return XCTFail() }
        XCTAssertEqual(id, before.sequenceId)
        XCTAssertNotEqual(visit.id, before.id)
        XCTAssertNil(resumeAt)
    }

    func testRestartDoesNotDisturbTheHistoryThatLedHere() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: exists, start: start)
        XCTAssertEqual(n.suspendedCount, 1)
        _ = n.handle(.init(intent: .restart, source: .host), exists: exists, start: start)
        XCTAssertEqual(n.suspendedCount, 1, "Restarting B still leaves A returnable.")
    }

    // MARK: - End

    func testEndFinishesAndDiscardsHistory() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                     exists: exists, start: start)
        XCTAssertEqual(n.handle(.init(intent: .end, source: .host),
                                exists: exists, start: start), .finish)
        XCTAssertNil(n.current)
        XCTAssertFalse(n.canReturn, "End is not a Sequence and leaves nowhere to go back to.")
    }

    // MARK: - Scale (§14, §28)

    func testHistoryIsBoundedAndReportsWhatItDropped() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        for _ in 0..<(ExperienceNavigator.historyLimit * 3) {
            _ = n.handle(.init(intent: .goTo(sequenceId: "b"), source: .host),
                         exists: exists, start: start)
        }
        XCTAssertEqual(n.suspendedCount, ExperienceNavigator.historyLimit,
                       "An hour-long chapter must not grow an unbounded stack.")
        XCTAssertGreaterThan(n.droppedHistoryCount, 0,
                             "Dropping is REPORTED, not silent.")
    }

    /// Thousands of navigations, no wall clock, asserting the structures return
    /// to their expected size.
    func testThousandsOfNavigationsStayBounded() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        var ids: Set<SequenceVisitID> = []

        for i in 0..<5_000 {
            let target = i.isMultiple(of: 2) ? "b" : "gallery"
            _ = n.handle(.init(intent: .goTo(sequenceId: target), source: .host),
                         exists: exists, start: start)
            ids.insert(n.current!.id)
            if i.isMultiple(of: 3) {
                _ = n.handle(.init(intent: .back(policy: .resume), source: .host),
                             exists: exists, start: start)
            }
            XCTAssertLessThanOrEqual(n.suspendedCount, ExperienceNavigator.historyLimit)
        }
        XCTAssertGreaterThan(ids.count, 1_000, "Every entry minted a distinct visit.")

        // …and everything returns to nothing at the end.
        _ = n.handle(.init(intent: .end, source: .host), exists: exists, start: start)
        XCTAssertEqual(n.suspendedCount, 0)
        XCTAssertNil(n.current)
    }

    func testDeepNestingUnwindsInOrder() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let chain = ["b", "c", "gallery", "hub"]
        var visits: [SequenceVisitID] = [n.current!.id]
        for id in chain {
            _ = n.handle(.init(intent: .goTo(sequenceId: id), source: .host),
                         exists: exists, start: start)
            visits.append(n.current!.id)
        }
        // Unwind: each Return lands on the visit immediately before.
        for expected in visits.dropLast().reversed() {
            let out = n.handle(.init(intent: .back(policy: .resume), source: .host),
                               exists: exists, start: start)
            XCTAssertEqual(enter(out)?.1.id, expected)
        }
        XCTAssertFalse(n.canReturn)
    }
}

// MARK: - Forward compatibility (Phase 8A.2)

extension ExperienceNavigatorTests {

    /// THE DEFECT THIS FIXES. The first decoder mapped an unrecognised intent
    /// to `.end`, so a newer tool's navigation would have SILENTLY ENDED THE
    /// CHAPTER on an older build. Forward compatibility must never invent
    /// narrative meaning.
    func testAnUnknownIntentDoesNotDecodeAsEnd() throws {
        let json = #"{"kind":"goToChapter","sequenceId":"other"}"#
        let intent = try JSONDecoder().decode(NavigationIntent.self, from: Data(json.utf8))

        XCTAssertNotEqual(intent, .end, "An unknown navigation must never end the Chapter.")
        XCTAssertTrue(intent.isUnsupported)
        XCTAssertNil(intent.explicitTarget, "It must not be guessed into a real destination either.")
    }

    func testAnUnknownIntentNeverBecomesAnyRealNavigation() throws {
        for name in ["goToChapter", "choose", "ifCondition", "", "restartChapter"] {
            let json = "{\"kind\":\"\(name)\"}"
            let intent = try JSONDecoder().decode(NavigationIntent.self, from: Data(json.utf8))
            for real: NavigationIntent in [.start, .end, .restart,
                                           .back(policy: .resume), .back(policy: .restart)] {
                XCTAssertNotEqual(intent, real, "‘\(name)’ was mapped onto \(real).")
            }
        }
    }

    func testAnUnknownIntentFailsInertlyAtRuntime() {
        var n = nav()
        _ = n.handle(.init(intent: .start, source: .host), exists: exists, start: start)
        let before = n.current

        let out = n.handle(.init(intent: .unsupported(kind: "choose", raw: nil), source: .host),
                           exists: exists, start: start)

        guard case .refused(.unsupportedNavigation(let kind)) = out else {
            return XCTFail("expected an inert refusal, got \(out)")
        }
        XCTAssertEqual(kind, "choose")
        XCTAssertEqual(n.current?.id, before?.id, "The story stays exactly where it was.")
        XCTAssertNotNil(n.current, "It must not end the Chapter.")
    }

    /// An older build must not silently downgrade a newer build's chapter.
    func testAnUnknownIntentIsReEmittedVerbatim() throws {
        let json = #"{"kind":"choose","raw":{"options":["a","b"]}}"#
        let intent = try JSONDecoder().decode(NavigationIntent.self, from: Data(json.utf8))
        let round = String(data: try JSONEncoder().encode(intent), encoding: .utf8) ?? ""
        XCTAssertTrue(round.contains("choose"), "The original kind survives a save.")
        XCTAssertTrue(round.contains("options"), "So does its payload.")
    }

    func testKnownIntentsStillRoundTrip() throws {
        for intent: NavigationIntent in [.start, .end, .restart,
                                         .goTo(sequenceId: "gallery"),
                                         .back(policy: .resume), .back(policy: .restart)] {
            let back = try JSONDecoder().decode(
                NavigationIntent.self, from: try JSONEncoder().encode(intent))
            XCTAssertEqual(back, intent)
            XCTAssertFalse(back.isUnsupported)
        }
    }
}
