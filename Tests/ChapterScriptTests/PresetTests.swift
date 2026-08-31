//
//  PresetTests.swift
//  ChapterScriptTests
//
//  FL-21: the preset library's format guarantees. Tolerant decode, the
//  unknown-kind and unknown-payload round-trips, the K12 field flag, and
//  the document-level byte-identity promise for Chapters that never
//  saved a preset.
//

import XCTest
@testable import ChapterScript

final class PresetTests: XCTestCase {

    private func doc(presets: [PresetEntry]? = nil) -> ChapterDocument {
        ChapterDocument(id: "c1", displayName: "C", presets: presets)
    }

    private func roundTrip(_ document: ChapterDocument) throws -> ChapterDocument {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try JSONDecoder().decode(
            ChapterDocument.self, from: enc.encode(document))
    }

    // MARK: Absence

    func testAbsentPresetsStaysAbsent() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(doc())
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("\"presets\""),
                       "A Chapter that never saved a preset must not gain the key")
        let back = try roundTrip(doc())
        XCTAssertNil(back.presets)
    }

    // MARK: Typed payload round-trips

    func testTitlePresetRoundTrips() throws {
        let entry = PresetEntry(
            id: "p1", kind: .title, name: "Hero",
            categoryPath: ["Titles", "Openers"],
            isFavorite: true,
            payload: .title(TextSpec(text: "", fontSize: 0.2, color: .white)))
        let back = try roundTrip(doc(presets: [entry]))
        XCTAssertEqual(back.presets, [entry])
        guard case .title(let spec)? = back.presets?.first?.payload else {
            return XCTFail("payload lost its type")
        }
        XCTAssertEqual(spec.fontSize, 0.2)
    }

    func testCurvePresetRoundTrips() throws {
        let entry = PresetEntry(
            id: "p2", kind: .curve, name: "Snappy",
            payload: .curve(CurvePresetPayload(interpolation: "easeOut")))
        let back = try roundTrip(doc(presets: [entry]))
        XCTAssertEqual(back.presets, [entry])
    }

    // MARK: Tolerance (G7 one level up)

    func testUnknownKindIsKeptAndNotKnown() throws {
        let entry = PresetEntry(
            id: "p3", kind: PresetKind(rawValue: "hologram"), name: "Future",
            payload: .raw(.object(["type": .string("hologram"),
                                   "value": .number(9)])))
        XCTAssertFalse(entry.kind.isKnown)
        let back = try roundTrip(doc(presets: [entry]))
        XCTAssertEqual(back.presets, [entry],
                       "an unrecognised kind keeps its entry and round-trips")
    }

    func testUnknownPayloadRoundTripsVerbatim() throws {
        let json = """
        {"id":"p4","kind":"title","name":"Newer",
         "payload":{"type":"volumetricTitle","value":{"depth":3},"extra":true}}
        """
        let entry = try JSONDecoder().decode(PresetEntry.self, from: Data(json.utf8))
        guard case .raw = entry.payload else {
            return XCTFail("an unknown payload type must fall back to .raw")
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let out = String(data: try enc.encode(entry), encoding: .utf8)!
        XCTAssertTrue(out.contains("\"volumetricTitle\""))
        XCTAssertTrue(out.contains("\"extra\":true"),
                      "unrecognised sibling keys inside the payload survive")
    }

    func testMissingCategoryPathDecodesEmptyAndEmptyEmitsNoKey() throws {
        let json = """
        {"id":"p5","kind":"curve","name":"Bare",
         "payload":{"type":"curve","value":{"interpolation":"linear"}}}
        """
        let entry = try JSONDecoder().decode(PresetEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.categoryPath, [])
        let out = String(data: try JSONEncoder().encode(entry), encoding: .utf8)!
        XCTAssertFalse(out.contains("categoryPath"))
    }

    // MARK: Dependencies (R6)

    func testDependencyRoundTrips() throws {
        let entry = PresetEntry(
            id: "p6", kind: .title, name: "Branded",
            payload: .title(TextSpec(text: "")),
            requires: [PresetDependency(kind: .font, descriptor: "Avenir Next",
                                        isCarried: false)])
        let back = try roundTrip(doc(presets: [entry]))
        XCTAssertEqual(back.presets?.first?.requires?.first?.descriptor, "Avenir Next")
    }

    // MARK: K12 — the field flag

    func testConsumerEditableFlagRoundTripsAndAbsentMeansAbsent() throws {
        var spec = TextSpec(text: "Subtitle")
        let bare = String(data: try JSONEncoder().encode(spec), encoding: .utf8)!
        XCTAssertFalse(bare.contains("isConsumerEditable"),
                       "unset stays unwritten — old Chapters re-save byte-identically")
        spec.isConsumerEditable = true
        let flagged = try JSONDecoder().decode(
            TextSpec.self, from: try JSONEncoder().encode(spec))
        XCTAssertEqual(flagged.isConsumerEditable, true)
    }
}
