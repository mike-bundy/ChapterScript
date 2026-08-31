//
//  ChapterTimebaseTests.swift
//  ChapterScriptTests
//
//  FL-03: the Chapter's one rational timebase, and PD-1's promises —
//  absent means 24/1 and STAYS absent (byte-identical re-save), the decoder
//  is tolerant, and validation belongs to the authoring boundary.
//

import XCTest
@testable import ChapterScript

final class ChapterTimebaseTests: XCTestCase {

    private func encode(_ document: ChapterDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    private func makeDocument(timebase: ChapterTimebase? = nil) -> ChapterDocument {
        ChapterDocument(
            id: "chapter_tb", displayName: "Timebase",
            sequences: [SequenceDefinitionDTO(
                id: "seq", name: "S", phase: "immersive",
                steps: [StepDefinitionDTO(
                    id: "s1", name: "A", duration: 5, actions: [])])],
            timebase: timebase)
    }

    // MARK: - PD-1: absent means 24/1, and absent stays absent

    func testAbsentTimebaseReSavesByteIdentically() throws {
        let document = makeDocument()
        XCTAssertNil(document.timebase)
        let bytes = try encode(document)
        XCTAssertFalse(String(data: bytes, encoding: .utf8)!.contains("timebase"),
                       "an untold Chapter carries NO timebase key")

        let reopened = try JSONDecoder().decode(ChapterDocument.self, from: bytes)
        XCTAssertNil(reopened.timebase, "open writes nothing")
        XCTAssertEqual(try encode(reopened), bytes,
                       "open then save is byte-identical — the standing guarantee")
    }

    func testAPresentTimebaseRoundTripsExactly() throws {
        let ntsc = ChapterTimebase(numerator: 30000, denominator: 1001)
        let document = makeDocument(timebase: ntsc)
        let bytes = try encode(document)
        let reopened = try JSONDecoder().decode(ChapterDocument.self, from: bytes)
        XCTAssertEqual(reopened.timebase, ntsc,
                       "the NTSC family are exact fractions, never rounded decimals")
        XCTAssertEqual(try encode(reopened), bytes)
    }

    /// An OLD build reading a NEW chapter: the unknown key is ignored, the
    /// document opens. Simulated by decoding a document with the key through
    /// the same tolerant path (keyed decoding ignores unknown keys by
    /// construction; this pins that the rest of the document is unharmed).
    func testDocumentWithTimebaseStillDecodesEverythingElse() throws {
        let document = makeDocument(timebase: ChapterTimebase(numerator: 30, denominator: 1))
        let bytes = try encode(document)
        let reopened = try JSONDecoder().decode(ChapterDocument.self, from: bytes)
        XCTAssertEqual(reopened.sequences.count, 1)
        XCTAssertEqual(reopened.sequences[0].steps[0].duration, 5)
    }

    // MARK: - Tolerance vs validation

    func testAnInvalidPairDecodesButIsNotValid() throws {
        // The decoder is TOLERANT — it keeps what the file says. The
        // authoring boundary is what refuses it (consumers resolve to 24/1
        // and report).
        let json = """
        {"formatVersion": \(ChapterScriptFormat.currentFormatVersion),
         "id": "x", "displayName": "X",
         "entities": [], "sequences": [],
         "particlePresets": [], "manifest": {"entries": []},
         "timebase": {"numerator": 0, "denominator": -5}}
        """
        let document = try JSONDecoder().decode(
            ChapterDocument.self, from: Data(json.utf8))
        XCTAssertNotNil(document.timebase, "tolerance keeps the file's claim")
        XCTAssertFalse(document.timebase!.isValid,
                       "and validity is a separate question the authoring boundary asks")
    }

    func testValidityRange() {
        XCTAssertTrue(ChapterTimebase(numerator: 24, denominator: 1).isValid)
        XCTAssertTrue(ChapterTimebase(numerator: 30000, denominator: 1001).isValid)
        XCTAssertTrue(ChapterTimebase(numerator: 90, denominator: 1).isValid)
        XCTAssertFalse(ChapterTimebase(numerator: 0, denominator: 1).isValid)
        XCTAssertFalse(ChapterTimebase(numerator: 24, denominator: 0).isValid)
        XCTAssertFalse(ChapterTimebase(numerator: -24, denominator: 1).isValid)
        XCTAssertFalse(ChapterTimebase(numerator: 1, denominator: 2).isValid,
                       "half a frame per second is below the sane authoring floor")
    }

    func testDefaultIsTwentyFourOverOne() {
        XCTAssertEqual(ChapterTimebase.default.numerator, 24)
        XCTAssertEqual(ChapterTimebase.default.denominator, 1)
        XCTAssertEqual(ChapterTimebase.default.fps, 24)
    }
}
