//
//  InteractionLedgerTests.swift
//  ChapterScriptTests
//
//  THE SEQUENCE-VISIT SEMANTICS, TESTED OFF-DEVICE.
//
//  These assert the half of the interaction runtime that is arithmetic: whether
//  an activation may produce a response, given the authored lifetime, the
//  runtime enabled state, and what has already happened during THIS visit. The
//  other half — whether the viewer's forward direction actually found the
//  object, whether a grab registered — needs a Vision Pro and is never claimed
//  here.
//
//  Both the device (`ChapterPlayer.InteractionController`) and the Mac's preview
//  run through this exact type, which is what stops the two from disagreeing
//  about whether a one-shot has been spent.
//
//  These are the tests Phase 7 and Phase 8 inherit: if `.once` is ever
//  reinterpreted, they fail.
//

import XCTest
@testable import ChapterScript

final class InteractionLedgerTests: XCTestCase {

    private func spec(_ id: String,
                      lifetime: InteractionLifetime = .everyTime,
                      initiallyEnabled: Bool = true,
                      trigger: InteractionTrigger = .tap) -> InteractionSpec {
        InteractionSpec(id: id, trigger: trigger, lifetime: lifetime,
                        initiallyEnabled: initiallyEnabled,
                        actions: [.showEntity(name: "Label")])
    }

    // MARK: - Lifetime

    func testEveryTimeFiresOnEveryActivation() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .everyTime)])

        XCTAssertEqual(ledger.fire("a"), .fire)
        XCTAssertEqual(ledger.fire("a"), .fire)
        XCTAssertEqual(ledger.fire("a"), .fire)
        XCTAssertTrue(ledger.isArmed("a"))
    }

    func testOnceFiresAtMostOncePerVisit() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once)])

        XCTAssertEqual(ledger.fire("a"), .fire)
        XCTAssertEqual(ledger.fire("a"), .refuse(.alreadyFired))
        XCTAssertEqual(ledger.fire("a"), .refuse(.alreadyFired))
        XCTAssertFalse(ledger.isArmed("a"))
    }

    func testANewVisitRearmsAOneShot() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once)])
        XCTAssertEqual(ledger.fire("a"), .fire)

        // End of visit → new visit. This is what `SequenceEngine.stop` followed
        // by `play` does, and it is what an author means by "once".
        ledger.reset()
        ledger.register([spec("a", lifetime: .once)])
        XCTAssertEqual(ledger.fire("a"), .fire)
    }

    func testBeginFreshVisitRestoresAuthoredDefaultsWithoutUnloading() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once), spec("b", initiallyEnabled: false)])
        XCTAssertEqual(ledger.fire("a"), .fire)
        ledger.setEnabled(true, id: "b")

        ledger.beginFreshVisit()

        XCTAssertNotNil(ledger.spec("a"), "A fresh visit is not an unload.")
        XCTAssertEqual(ledger.fire("a"), .fire, "The one-shot re-arms.")
        XCTAssertFalse(ledger.isEffectivelyEnabled("b"),
                       "Runtime enablement returns to the AUTHORED default, not to what playback left behind.")
    }

    // MARK: - Authored vs runtime state

    func testRuntimeEnablementNeverTouchesTheAuthoredSpec() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", initiallyEnabled: true)])

        ledger.setEnabled(false, id: "a")

        XCTAssertFalse(ledger.isEffectivelyEnabled("a"))
        XCTAssertTrue(ledger.spec("a")?.initiallyEnabled ?? false,
                      "`initiallyEnabled` describes how a visit STARTS. Playback must never rewrite it.")
    }

    func testEffectiveEnablementStartsFromTheAuthoredValue() {
        var ledger = InteractionLedger()
        ledger.register([spec("on", initiallyEnabled: true), spec("off", initiallyEnabled: false)])
        XCTAssertTrue(ledger.isEffectivelyEnabled("on"))
        XCTAssertFalse(ledger.isEffectivelyEnabled("off"))
        XCTAssertEqual(ledger.fire("off"), .refuse(.disabled))
    }

    func testDisablingAndReEnablingRestoresFiring() {
        var ledger = InteractionLedger()
        ledger.register([spec("a")])

        ledger.setEnabled(false, id: "a")
        XCTAssertEqual(ledger.fire("a"), .refuse(.disabled))

        ledger.setEnabled(true, id: "a")
        XCTAssertEqual(ledger.fire("a"), .fire)
    }

    /// The rule Phase 8 must not reinterpret.
    func testEnableDoesNotSecretlyMeanReset() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once)])
        XCTAssertEqual(ledger.fire("a"), .fire)

        ledger.setEnabled(false, id: "a")
        ledger.setEnabled(true, id: "a")

        XCTAssertEqual(ledger.fire("a"), .refuse(.alreadyFired),
                       "Otherwise ‘once’ would quietly mean ‘once per switch-on’.")
        XCTAssertTrue(ledger.hasFired("a"))
    }

    func testEnablingAnUnknownIdIsANoOpRatherThanACrash() {
        var ledger = InteractionLedger()
        ledger.setEnabled(true, id: "ghost")
        XCTAssertEqual(ledger.fire("ghost"), .refuse(.notRegistered))
    }

    // MARK: - Several interactions

    func testOneObjectCanHoldSeveralInteractionsThatDoNotInterfere() {
        var ledger = InteractionLedger()
        ledger.register([
            spec("tap", lifetime: .everyTime, trigger: .tap),
            spec("facing", lifetime: .once, trigger: .viewerFacing(dwell: 1)),
            spec("grab", lifetime: .everyTime, trigger: .grab)
        ])

        XCTAssertEqual(ledger.fire("facing"), .fire)
        XCTAssertEqual(ledger.fire("facing"), .refuse(.alreadyFired))
        // Spending the one-shot must not touch its siblings.
        XCTAssertEqual(ledger.fire("tap"), .fire)
        XCTAssertEqual(ledger.fire("tap"), .fire)
        XCTAssertEqual(ledger.fire("grab"), .fire)
        XCTAssertEqual(ledger.armedCount, 2)
    }

    func testRegisteringReSeedsFromTheAuthoredValue() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once)])
        _ = ledger.fire("a")
        XCTAssertTrue(ledger.hasFired("a"))

        // An install IS the start of a visit.
        ledger.register([spec("a", lifetime: .once)])
        XCTAssertFalse(ledger.hasFired("a"))
        XCTAssertEqual(ledger.registeredIDs.count, 1)
    }

    // MARK: - Response dispatch

    func testFiringReturnsTheAuthoredResponses() {
        var ledger = InteractionLedger()
        var authored = spec("a")
        authored.actions = [.showEntity(name: "Label"),
                            .playAudio(AudioActionDTO(file: "vo.wav", channel: "vo"))]
        ledger.register([authored])

        let (outcome, actions) = ledger.firing("a")
        XCTAssertEqual(outcome, .fire)
        XCTAssertEqual(actions.count, 2)
        // The response vocabulary IS the step vocabulary — no interaction-only
        // action set, and nothing here rewrites what an action means.
        XCTAssertEqual(actions[0], .showEntity(name: "Label"))
    }

    func testARefusedActivationDispatchesNothing() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once)])
        _ = ledger.firing("a")

        let (outcome, actions) = ledger.firing("a")
        XCTAssertEqual(outcome, .refuse(.alreadyFired))
        XCTAssertTrue(actions.isEmpty,
                      "A caller must not be able to dispatch a response for a refused activation.")
    }

    /// One lifetime truth, whatever the input route. An accessibility
    /// activation and a physical one are the same activation as far as this
    /// type is concerned — which is the whole reason there is only one of it.
    func testEveryInputRouteSharesOneLifetime() {
        var ledger = InteractionLedger()
        ledger.register([spec("a", lifetime: .once)])

        XCTAssertEqual(ledger.fire("a"), .fire, "say: the accessibility route")
        XCTAssertEqual(ledger.fire("a"), .refuse(.alreadyFired), "say: the physical route, later")
    }

    // MARK: - Teardown

    func testResetLeavesNothingBehind() {
        var ledger = InteractionLedger()
        ledger.register([spec("a"), spec("b", lifetime: .once)])
        _ = ledger.fire("b")

        ledger.reset()
        XCTAssertTrue(ledger.registeredIDs.isEmpty)
        XCTAssertEqual(ledger.armedCount, 0)
        XCTAssertEqual(ledger.fire("a"), .refuse(.notRegistered),
                       "A watch that outlives its Sequence is Act One's narration firing in Act Three.")
    }

    // MARK: - Suspending and resuming a visit (Phase 8D)

    /// **RESUME CONTINUES A VISIT; IT DOES NOT BEGIN ONE.**
    ///
    /// A ledger is a value, so putting a suspended visit aside and handing it
    /// back is a copy. That is the whole mechanism behind the documented
    /// difference between the two Return policies — and for three phases the
    /// navigator preserved the visit id while every entry re-armed anyway, so
    /// the difference existed only on paper.
    func testASuspendedVisitCanBePutAsideAndHandedBack() {
        var gallery = InteractionLedger()
        gallery.register([spec("radio", lifetime: .once), spec("door")])
        XCTAssertEqual(gallery.fire("radio"), .fire)

        // The audience leaves. The visit is put aside as it stands.
        let suspended = gallery

        // Another Sequence plays: a fresh visit, its own ledger, nothing spent.
        var artifactRoom = InteractionLedger()
        artifactRoom.register([spec("plinth", lifetime: .once)])
        XCTAssertEqual(artifactRoom.fire("plinth"), .fire)

        // They come back. Resume restores what they had already done.
        var resumed = suspended
        XCTAssertEqual(resumed.fire("radio"), .refuse(.alreadyFired),
                       "Resume must not undo what the audience already did.")
        XCTAssertTrue(resumed.registeredIDs.contains("door"))
    }

    /// The other half: a FRESH visit of the same Sequence starts clean, which
    /// is what Restart and Return · Restart mean.
    func testAFreshVisitOfTheSameSequenceStartsClean() {
        var first = InteractionLedger()
        first.register([spec("radio", lifetime: .once)])
        XCTAssertEqual(first.fire("radio"), .fire)

        var second = InteractionLedger()
        second.register([spec("radio", lifetime: .once)])
        XCTAssertEqual(second.fire("radio"), .fire,
                       "A fresh visit re-arms every one-shot in it.")
    }

    /// Runtime state, and it stays that way.
    func testALedgerIsNotCodable() {
        XCTAssertFalse((InteractionLedger.self as Any) is any Encodable.Type,
                       "A viewer's progress is not a property of the document.")
    }
}
