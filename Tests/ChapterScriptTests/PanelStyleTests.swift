//
//  PanelStyleTests.swift
//  ChapterScriptTests
//
//  SEQUENCE-LOCAL PANEL STYLE (`SequenceDefinitionDTO.panelStyles`) — the
//  style twin of `restPlacements`. One reusable screen may present
//  differently in every Sequence: rounding "Main Screen" while editing one
//  Sequence must not round it in another (the recorded defect this layer
//  closes). Per-field override semantics: nil inherits, a present value
//  wins — explicit square (0) included.
//

import XCTest
@testable import ChapterScript

final class PanelStyleTests: XCTestCase {

    private func makeSequence(styles: [String: PanelStyleOverride]? = nil) -> SequenceDefinitionDTO {
        SequenceDefinitionDTO(
            id: "seq", name: "Seq", phase: "immersive",
            steps: [StepDefinitionDTO(id: "s1", name: "Step 1", duration: 10,
                                      authoredActions: [], gate: nil)],
            panelStyles: styles)
    }

    // MARK: Resolution — the one rule

    func testAbsentOverrideInheritsTheChapterStyle() {
        let base = PanelStyleOverride(cornerRadius: 0.2,
                                      spatialPresentation: .spatial,
                                      passthroughTinting: true)
        let resolved = makeSequence().panelStyle(for: "screen", base: base)
        XCTAssertEqual(resolved, base)
    }

    func testPerFieldOverrideWinsAndTheRestInherits() {
        let base = PanelStyleOverride(cornerRadius: 0.2,
                                      spatialPresentation: .spatial,
                                      passthroughTinting: true)
        let sequence = makeSequence(styles: [
            "screen": PanelStyleOverride(cornerRadius: 0.05)
        ])
        let resolved = sequence.panelStyle(for: "screen", base: base)
        XCTAssertEqual(resolved.cornerRadius, 0.05, "the present field wins")
        XCTAssertEqual(resolved.spatialPresentation, .spatial, "nil fields inherit")
        XCTAssertEqual(resolved.passthroughTinting, true)
    }

    func testExplicitSquareIsDifferentFromNoOpinion() {
        let base = PanelStyleOverride(cornerRadius: 0.2)
        let sequence = makeSequence(styles: [
            "screen": PanelStyleOverride(cornerRadius: 0)
        ])
        XCTAssertEqual(sequence.panelStyle(for: "screen", base: base).cornerRadius, 0,
                       "explicit 0 means SQUARE IN THIS SEQUENCE, not inherit")
    }

    func testAnotherEntityIsUntouched() {
        let base = PanelStyleOverride(cornerRadius: 0.2)
        let sequence = makeSequence(styles: [
            "screen": PanelStyleOverride(cornerRadius: 0.05)
        ])
        XCTAssertEqual(sequence.panelStyle(for: "other", base: base).cornerRadius, 0.2)
    }

    // MARK: Coding — additive and tolerant

    func testDocumentsWithoutTheKeyDecodeAndReencodeWithoutIt() throws {
        let sequence = makeSequence()
        let data = try JSONEncoder().encode(sequence)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("panelStyles"),
                       "nil emits NO key — untouched Chapters re-save byte-identically")
        let decoded = try JSONDecoder().decode(SequenceDefinitionDTO.self, from: data)
        XCTAssertNil(decoded.panelStyles)
    }

    func testRoundTripPreservesTheOverrides() throws {
        let sequence = makeSequence(styles: [
            "screen": PanelStyleOverride(cornerRadius: 0.08,
                                         spatialPresentation: .flat,
                                         passthroughTinting: false)
        ])
        let decoded = try JSONDecoder().decode(
            SequenceDefinitionDTO.self, from: JSONEncoder().encode(sequence))
        XCTAssertEqual(decoded.panelStyles?["screen"]?.cornerRadius, 0.08)
        XCTAssertEqual(decoded.panelStyles?["screen"]?.spatialPresentation, .flat)
        XCTAssertEqual(decoded.panelStyles?["screen"]?.passthroughTinting, false)
    }

    func testEmptiedMapNormalizesToAbsent() {
        var sequence = makeSequence(styles: ["screen": PanelStyleOverride(cornerRadius: 0.1)])
        sequence.panelStyles = [:]
        XCTAssertNil(sequence.panelStyles, "empty and absent are the same fact")
    }
}
