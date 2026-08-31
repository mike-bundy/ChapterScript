//
//  MaterialOverrideFormatTests.swift
//  FL-14: per-slot overrides — absence is the file's materials, nil is a
//  field's file value, unknown blending round-trips, excess slots survive.
//

import XCTest
@testable import ChapterScript

final class MaterialOverrideFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(value)
    }

    func testAbsentOverridesWriteNothing() throws {
        let entity = EntityDefinition(id: "obj", kind: .usdz)
        let json = String(data: try encode(entity), encoding: .utf8)!
        XCTAssertFalse(json.contains("materialOverrides"),
                       "absent means the file's own materials, byte-identically")
    }

    func testPerSlotOverrideRoundTrips() throws {
        var entity = EntityDefinition(id: "obj", kind: .usdz)
        entity.materialOverrides = [
            MaterialOverrideSpec(slot: 2, slotName: "Trim",
                                 baseColor: ColorRGBA(r: 1, g: 0, b: 0, a: 1),
                                 roughness: 0.3),
        ]
        let back = try JSONDecoder().decode(EntityDefinition.self, from: encode(entity))
        XCTAssertEqual(back.materialOverrides, entity.materialOverrides)
        XCTAssertEqual(back.materialOverrides?.first?.slot, 2)
        XCTAssertNil(back.materialOverrides?.first?.metallic,
                     "nil means the file's value - never written, never lost")
    }

    func testUnknownBlendingIsWeakestClaimAndRoundTripsVerbatim() throws {
        let data = Data(#"{"slot": 0, "blending": "screenDodge"}"#.utf8)
        let spec = try JSONDecoder().decode(MaterialOverrideSpec.self, from: data)
        XCTAssertNil(spec.blending, "an unknown mode claims nothing")
        XCTAssertEqual(spec.unknownBlending, "screenDodge")
        let json = String(data: try encode(spec), encoding: .utf8)!
        XCTAssertTrue(json.contains("screenDodge"), "the raw value survives a re-save")
        XCTAssertFalse(json.contains("unknownBlending"),
                       "the raw value re-encodes under the blending key itself")
    }

    func testKnownBlendingEncodesItsPlainRawValue() throws {
        let spec = MaterialOverrideSpec(slot: 0, blending: .additive)
        let json = String(data: try encode(spec), encoding: .utf8)!
        XCTAssertTrue(json.contains(#""blending":"additive""#))
    }

    func testExcessSlotSurvivesAReSave() throws {
        // The file may be relinked back: an override whose slot exceeds
        // today's count is KEPT (dropping is an authoring decision the
        // format never takes on its own).
        var entity = EntityDefinition(id: "obj", kind: .usdz)
        entity.materialOverrides = [MaterialOverrideSpec(slot: 7, roughness: 1)]
        let back = try JSONDecoder().decode(EntityDefinition.self, from: encode(entity))
        XCTAssertEqual(back.materialOverrides?.first?.slot, 7)
    }

    func testShaderInputsPreserveUnrecognisedValuesVerbatim() throws {
        let data = Data("""
        {"slot": 0, "shaderInputs": {"glowAmount": 0.5, "mystery": {"deep": [1, 2]}}}
        """.utf8)
        let spec = try JSONDecoder().decode(MaterialOverrideSpec.self, from: data)
        let json = String(data: try encode(spec), encoding: .utf8)!
        XCTAssertTrue(json.contains("mystery"), "G7's discipline, one level down")
        XCTAssertTrue(json.contains("glowAmount"))
    }

    func testEmptyOverrideIsDetectable() {
        XCTAssertTrue(MaterialOverrideSpec(slot: 0).isEmpty)
        XCTAssertFalse(MaterialOverrideSpec(slot: 0, unlit: true).isEmpty)
    }
}
