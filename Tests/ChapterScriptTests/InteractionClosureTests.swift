//
//  InteractionClosureTests.swift
//  ChapterScriptTests
//
//  PHASE 6 CLOSURE — the semantics Phase 7 and Phase 8 inherit.
//
//  Two things are pinned here that no later phase may quietly reinterpret:
//
//  1. THE PRIVACY CONTRACT. Maestro measures the viewer's forward DIRECTION.
//     visionOS does not give an app the eye ray, and no product surface may
//     claim otherwise. The trigger is named for what is actually measured.
//  2. THE VISIT BOUNDARY. `.once` means once per Sequence Visit — not per
//     chapter, not per enable/disable cycle, and not per Story Region loop.
//
//  Compatibility is asserted against real Phase 6 wire shapes, because a
//  chapter authored yesterday must still open.
//

import XCTest
@testable import ChapterScript

final class InteractionClosureTests: XCTestCase {

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: - The privacy contract

    func testTheFacingTriggerIsNotNamedAfterTheEyes() throws {
        let wire = try json(InteractionTrigger.viewerFacing(dwell: 1.5))
        XCTAssertTrue(wire.contains("viewerFacing"))
        XCTAssertFalse(wire.lowercased().contains("gaze"),   // LEGACY-INTERACTION-VOCAB: the assertion IS the rule
                       "Maestro measures the viewer's forward direction. Naming it after the eyes claims a capability visionOS does not give an app.")
        XCTAssertFalse(wire.lowercased().contains("\"look\""))
    }

    func testTheSpokenAndWrittenPhraseIsFaceToward() {
        XCTAssertEqual(InteractionSemantics.triggerPhrase(.viewerFacing(dwell: nil)), "Face Toward")
        for trigger: InteractionTrigger in [.tap, .viewerFacing(dwell: 1), .approach(radius: 1), .grab] {
            let phrase = InteractionSemantics.triggerPhrase(trigger).lowercased()
            XCTAssertFalse(phrase.contains("gaze"))   // LEGACY-INTERACTION-VOCAB: the assertion IS the rule
            XCTAssertFalse(phrase.contains("look"))
        }
    }

    // MARK: - Wire compatibility with the first Phase 6 build

    func testAPhase6DocumentWrittenAsLookStillOpens() throws {
        // The exact shape the first build wrote.
        let legacy = Data("""
        {"id":"ix_1","trigger":{"kind":"look","dwell":2.5},"lifetime":"once","isEnabled":false,
         "actions":[{"kind":"showEntity","name":"Label"}]}
        """.utf8)
        let spec = try JSONDecoder().decode(InteractionSpec.self, from: legacy)

        XCTAssertEqual(spec.trigger, .viewerFacing(dwell: 2.5),
                       "‘look’ is compatibility vocabulary and must decode to the accurate trigger.")
        XCTAssertFalse(spec.initiallyEnabled,
                       "‘isEnabled’ was the authored starting state all along; it decodes into the name that says so.")
        XCTAssertEqual(spec.lifetime, .once)
        XCTAssertEqual(spec.actions.count, 1)
    }

    func testAGazeSpellingAlsoDecodes() throws {   // LEGACY-INTERACTION-VOCAB: the assertion IS the rule
        let data = Data(#"{"kind":"gaze","dwell":1}"#.utf8)   // LEGACY-INTERACTION-VOCAB: the assertion IS the rule
        XCTAssertEqual(try JSONDecoder().decode(InteractionTrigger.self, from: data),
                       .viewerFacing(dwell: 1))
    }

    func testReSavingAPhase6DocumentWritesTheAccurateSpelling() throws {
        let legacy = Data(#"{"id":"ix_1","trigger":{"kind":"look"},"isEnabled":true}"#.utf8)
        let spec = try JSONDecoder().decode(InteractionSpec.self, from: legacy)
        let rewritten = try json(spec)

        XCTAssertTrue(rewritten.contains("viewerFacing"))
        XCTAssertTrue(rewritten.contains("initiallyEnabled"))
        XCTAssertFalse(rewritten.contains("\"isEnabled\""),
                       "The old key is decoded, never written back.")
    }

    func testTheGateWireValueIsPreservedForOlderPlayers() throws {
        // A gate type an older build does not recognise decodes as `.tap`,
        // which would silently turn a facing gate into a tap gate on somebody's
        // device. So the WIRE stays as it was and only the Swift name changed.
        let gate = StepGateDTO(type: .viewerFacing, targetEntity: "Radio")
        XCTAssertTrue(try json(gate).contains("\"gaze\""),   // LEGACY-INTERACTION-VOCAB: the assertion IS the rule
                      "Compatibility vocabulary on the wire, accurate vocabulary everywhere a human reads it.")

        // …and the accurate spelling is accepted if a document carries it.
        let hand = Data(#""viewerFacing""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(GateType.self, from: hand), .viewerFacing)
    }

    // MARK: - Authored state is not runtime state

    func testTheAuthoredFieldIsNamedForWhatItMeans() throws {
        let spec = InteractionSpec(id: "ix", initiallyEnabled: false)
        let wire = try json(spec)
        XCTAssertTrue(wire.contains("initiallyEnabled"))
        // The document describes how a VISIT STARTS. Nothing in it describes
        // what playback has since done.
        XCTAssertFalse(wire.contains("hasFired"))
        XCTAssertFalse(wire.contains("effectivelyEnabled"))
    }

    func testRuntimeStateIsNotEncodableAtAll() {
        // `InteractionLedger` is deliberately NOT Codable. If someone makes it
        // so, this stops compiling — which is the point: a visit's state must
        // have no route into a document, an undo stack or the sync protocol.
        XCTAssertFalse((InteractionLedger() as Any) is any Encodable,
                       "Runtime visit state must have no path into the document.")
    }

    // MARK: - The visit boundary

    func testAStoryRegionLoopWouldNotRearmAOneShot() {
        // Phase 7 will loop Explore content WITHIN a visit. Looping is not a new
        // visit, so a one-shot stays spent — pinned now so Phase 7 cannot
        // reinterpret `.once` by accident.
        var ledger = InteractionLedger()
        ledger.register([InteractionSpec(id: "a", lifetime: .once)])
        XCTAssertEqual(ledger.fire("a"), .fire)

        // A loop iteration changes nothing about the ledger.
        XCTAssertEqual(ledger.fire("a"), .refuse(.alreadyFired))
        XCTAssertTrue(ledger.hasFired("a"))

        // Only a NEW visit re-arms.
        ledger.beginFreshVisit()
        XCTAssertEqual(ledger.fire("a"), .fire)
    }

    func testASuspendedVisitKeepsItsStateWhileAFreshOneDoesNot() {
        // Phase 8's Return+Resume preserves a suspended visit's state;
        // Return+Restart creates a fresh one. Both are expressible today with
        // no new concept: keep the ledger, or begin a fresh visit.
        var suspended = InteractionLedger()
        suspended.register([InteractionSpec(id: "a", lifetime: .once)])
        _ = suspended.fire("a")
        suspended.setEnabled(false, id: "a")

        let resumed = suspended                     // Resume: the same visit.
        XCTAssertTrue(resumed.hasFired("a"))
        XCTAssertFalse(resumed.isEffectivelyEnabled("a"))

        var restarted = suspended
        restarted.beginFreshVisit()                 // Restart: a new visit.
        XCTAssertFalse(restarted.hasFired("a"))
        XCTAssertTrue(restarted.isEffectivelyEnabled("a"))
    }
}
