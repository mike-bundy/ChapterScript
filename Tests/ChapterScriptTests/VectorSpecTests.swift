//
//  VectorSpecTests.swift
//  ChapterScriptTests
//
//  FL-22: the vector Object's format guarantees — additive, tolerant,
//  byte-stable, and degrading to `.custom` on an older build exactly as
//  every other late kind does.
//

import XCTest
@testable import ChapterScript

final class VectorSpecTests: XCTestCase {

    func testVectorEntityRoundTrips() throws {
        let entity = EntityDefinition(
            id: "logo", kind: .vector,
            vector: VectorSpec(sourceId: "logo.svg",
                               extrusionDepth: 0.05,
                               capFill: .both,
                               bevelRadius: 0.002,
                               physicalWidth: 0.4))
        let data = try JSONEncoder().encode(entity)
        let back = try JSONDecoder().decode(EntityDefinition.self, from: data)
        XCTAssertEqual(back.kind, .vector)
        XCTAssertEqual(back.vector, entity.vector)
    }

    func testAbsentVectorStaysAbsent() throws {
        let entity = EntityDefinition(id: "box", kind: .primitive)
        let json = String(data: try JSONEncoder().encode(entity), encoding: .utf8)!
        XCTAssertFalse(json.contains("\"vector\""),
                       "a non-vector entity must not gain the key")
    }

    func testUnknownCapFillDecodesAsAbsent() throws {
        let json = """
        {"sourceId":"logo.svg","capFill":"holographic"}
        """
        let spec = try JSONDecoder().decode(VectorSpec.self, from: Data(json.utf8))
        XCTAssertNil(spec.capFill,
                     "an unrecognised cap reads as absent (build resolves .both), never a failed document")
        XCTAssertEqual(spec.sourceId, "logo.svg")
    }

    func testUnknownKindStillDegradesToCustom() throws {
        // The forward direction FL-22 leans on: `.vector` written by this
        // build opens on an older build as inert `.custom` — this pins the
        // decoder rule that makes that safe.
        let json = """
        {"id":"future","kind":"holodeck"}
        """
        let entity = try JSONDecoder().decode(EntityDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(entity.kind, .custom)
    }

    func testVectorKindRawValueIsStable() {
        XCTAssertEqual(EntityKind.vector.rawValue, "vector")
    }
}
