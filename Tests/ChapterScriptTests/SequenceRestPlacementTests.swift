//
//  SequenceRestPlacementTests.swift
//  ChapterScriptTests
//
//  Sequence-local rest placement (EDITOR_CONTRACTS §18 closure): the
//  additive map that lets one reusable object sit differently in two
//  Sequences without animation. The contract under test:
//
//  - absent and empty are the SAME fact, and neither emits a key, so a
//    Chapter never told about local placement re-saves byte-identically;
//  - an entry overrides the Chapter-global rest for ITS Sequence only;
//  - resolution goes through ONE helper (`restTransform(for:chapterRest:)`).
//

import XCTest
@testable import ChapterScript

final class SequenceRestPlacementTests: XCTestCase {

    private func makeSequence(placements: [String: TransformData]? = nil) -> SequenceDefinitionDTO {
        SequenceDefinitionDTO(
            id: "seq_1",
            name: "One",
            phase: "immersive",
            steps: [StepDefinitionDTO(id: "step_1", name: "Step 1", duration: 10,
                                      authoredActions: [], gate: nil)],
            restPlacements: placements
        )
    }

    // MARK: - Tolerance

    func testDocumentsWithoutTheFieldDecodeToNil() throws {
        let sequence = makeSequence()
        let data = try ChapterScriptFormat.makeEncoder().encode(sequence)
        let reopened = try ChapterScriptFormat.makeDecoder()
            .decode(SequenceDefinitionDTO.self, from: data)
        XCTAssertNil(reopened.restPlacements)
    }

    func testNilEmitsNoKey() throws {
        let data = try ChapterScriptFormat.makeEncoder().encode(makeSequence())
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("restPlacements"),
                       "a Chapter never told about local placement must not grow the key")
    }

    func testEmptyNormalizesToNilEverywhere() throws {
        // Through the init.
        XCTAssertNil(makeSequence(placements: [:]).restPlacements)
        // Through a mutation.
        var sequence = makeSequence(placements: ["box": TransformData()])
        sequence.restPlacements = [:]
        XCTAssertNil(sequence.restPlacements)
        // Through decode of a hand-written empty map.
        var withEmpty = makeSequence()
        withEmpty.restPlacements = nil
        let base = try ChapterScriptFormat.makeEncoder().encode(withEmpty)
        var jsonObject = try JSONSerialization.jsonObject(with: base) as! [String: Any]
        jsonObject["restPlacements"] = [String: Any]()
        let doctored = try JSONSerialization.data(withJSONObject: jsonObject)
        let reopened = try ChapterScriptFormat.makeDecoder()
            .decode(SequenceDefinitionDTO.self, from: doctored)
        XCTAssertNil(reopened.restPlacements)
    }

    // MARK: - Round trip

    func testPlacementsRoundTrip() throws {
        let placed = TransformData(
            position: Vec3(1.5, 0.25, -2),
            rotation: Quat(x: 0, y: 0.7071, z: 0, w: 0.7071),
            scale: Vec3(2, 2, 2)
        )
        let sequence = makeSequence(placements: ["radio": placed])
        let data = try ChapterScriptFormat.makeEncoder().encode(sequence)
        let reopened = try ChapterScriptFormat.makeDecoder()
            .decode(SequenceDefinitionDTO.self, from: data)
        XCTAssertEqual(reopened.restPlacements?["radio"], placed)
    }

    // MARK: - Resolution

    func testResolutionPrefersTheLocalPlacementInItsSequenceOnly() {
        let chapterRest = TransformData(position: Vec3(0, 1, 0))
        let localRest = TransformData(position: Vec3(3, 1, -4))

        let placed = makeSequence(placements: ["radio": localRest])
        let unplaced = makeSequence()

        // The placing Sequence sees ITS placement...
        XCTAssertEqual(
            placed.restTransform(for: "radio", chapterRest: chapterRest),
            localRest
        )
        // ...every other Sequence still sees the Chapter rest — the
        // recorded defect was exactly this leaking across Sequences.
        XCTAssertEqual(
            unplaced.restTransform(for: "radio", chapterRest: chapterRest),
            chapterRest
        )
        // An unplaced entity in the placing Sequence also falls back.
        XCTAssertEqual(
            placed.restTransform(for: "door", chapterRest: chapterRest),
            chapterRest
        )
    }
}
