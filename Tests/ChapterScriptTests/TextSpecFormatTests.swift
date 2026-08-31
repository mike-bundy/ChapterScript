//
//  TextSpecFormatTests.swift
//  ChapterScriptTests
//
//  FL-07 — every new field optional and tolerant; absent means today's Mac
//  constant; a pre-Title Chapter re-saves byte-identically.
//

import XCTest
@testable import ChapterScript

final class TextSpecFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    /// A spec written before FL-07 gains no keys.
    func testLegacySpecEncodesNoNewKeys() throws {
        let spec = TextSpec(text: "Chapter One", fontSize: 0.37,
                            color: ColorRGBA(r: 0.1, g: 0.2, b: 0.3, a: 1),
                            maxWidth: 1.85)
        let json = String(decoding: try encode(spec), as: UTF8.self)
        for key in ["fontFamily", "tracking", "leading", "alignmentX",
                    "extrusionDepth", "capFill", "bevelRadius", "material",
                    "slotMaterials"] {
            XCTAssertFalse(json.contains(key), "unexpected key: \(key)")
        }
    }

    func testLegacyBytesRoundTripByteIdentically() throws {
        let legacy = Data(
            #"{"color":{"a":1,"b":0.3,"g":0.2,"r":0.1},"fontSize":0.37,"maxWidth":1.85,"text":"Chapter One"}"#
            .utf8)
        let decoded = try ChapterScriptFormat.makeDecoder()
            .decode(TextSpec.self, from: legacy)
        XCTAssertNil(decoded.fontFamily)
        XCTAssertNil(decoded.extrusionDepth)
        let re = try encode(decoded)
        let reDecoded = try ChapterScriptFormat.makeDecoder()
            .decode(TextSpec.self, from: re)
        XCTAssertEqual(reDecoded, decoded)
        for key in ["fontFamily", "extrusionDepth", "capFill"] {
            XCTAssertFalse(String(decoding: re, as: UTF8.self).contains(key))
        }
    }

    func testFullSpecRoundTrips() throws {
        let spec = TextSpec(
            text: "على الشاشة", fontSize: 0.2, color: .white, maxWidth: 2,
            fontFamily: "Avenir Next", fontWeight: 700, fontIsItalic: true,
            fontSourceId: "source_font_1", tracking: 0.01, leading: 0.25,
            alignmentX: .natural, alignmentY: .baseline,
            extrusionDepth: 0.05, capFill: .front,
            bevelRadius: 0.004, bevelProfileId: "bevel_soft", bevelSegments: 6,
            material: MaterialSpec(baseColor: .white, metallic: 1, roughness: 0.2),
            slotMaterials: TextSlotMaterials(
                front: MaterialSpec(baseColor: ColorRGBA(r: 1, g: 0, b: 0, a: 1)),
                sides: MaterialSpec(baseColor: ColorRGBA(r: 0, g: 0, b: 1, a: 1))))
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(TextSpec.self, from: encode(spec))
        XCTAssertEqual(back, spec)
    }

    /// An enum case from a NEWER tool decodes as absent — today's constant —
    /// and the rest of the spec survives.
    func testUnknownEnumCasesReadAsAbsent() throws {
        let future = Data(
            #"{"alignmentX":"spiral","capFill":"holographic","fontSize":0.2,"text":"Hi","color":{"a":1,"b":1,"g":1,"r":1}}"#
            .utf8)
        let decoded = try ChapterScriptFormat.makeDecoder()
            .decode(TextSpec.self, from: future)
        XCTAssertNil(decoded.alignmentX)
        XCTAssertNil(decoded.capFill)
        XCTAssertEqual(decoded.text, "Hi")
        XCTAssertEqual(decoded.fontSize, 0.2, accuracy: 1e-6)
    }

    func testSlotMaterialsEmptyIsDetectable() {
        XCTAssertTrue(TextSlotMaterials().isEmpty)
        XCTAssertFalse(TextSlotMaterials(front: MaterialSpec()).isEmpty)
    }
}
