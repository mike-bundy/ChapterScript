//
//  RigFormatTests.swift
//  FL-15: members by id in a flat array, byte-identity when absent, the
//  bare-[String] proposal shape still loads, nil bind means identity.
//

import XCTest
@testable import ChapterScript

final class RigFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(value)
    }

    func testAbsentMembersWriteNothing() throws {
        let entity = EntityDefinition(id: "car", kind: .rig)
        let json = String(data: try encode(entity), encoding: .utf8)!
        XCTAssertFalse(json.contains("members"))
    }

    func testMembersRoundTripWithTheirBinds() throws {
        var rig = EntityDefinition(id: "car", kind: .rig)
        rig.members = [
            RigMember(id: "wheel_fl",
                      bindParentRest: TransformData(
                        position: Vec3(1, 0, 2),
                        rotation: Quat(x: 0, y: 0, z: 0, w: 1),
                        scale: Vec3(1, 1, 1))),
            RigMember(id: "wheel_fr"),
        ]
        let back = try JSONDecoder().decode(EntityDefinition.self, from: encode(rig))
        XCTAssertEqual(back.members, rig.members)
        XCTAssertNil(back.members?[1].bindParentRest, "nil bind means identity")
    }

    func testBareStringArrayDecodesWithIdentityBinds() throws {
        let data = Data("""
        {"id": "car", "kind": "rig", "members": ["wheel_fl", "door_l"]}
        """.utf8)
        let entity = try JSONDecoder().decode(EntityDefinition.self, from: data)
        XCTAssertEqual(entity.members?.map(\.id), ["wheel_fl", "door_l"],
                       "the GROUP_RIGS proposal shape remains loadable")
        XCTAssertTrue(entity.members!.allSatisfy { $0.bindParentRest == nil })
    }

    func testUnknownRigKindDegradesToCustomOnOldReaders() throws {
        // The forward story: this build KNOWS .rig.
        let entity = try JSONDecoder().decode(
            EntityDefinition.self,
            from: Data(#"{"id": "r", "kind": "rig"}"#.utf8))
        XCTAssertEqual(entity.kind, .rig)
        // And an unknown FUTURE kind still degrades as always.
        let future = try JSONDecoder().decode(
            EntityDefinition.self,
            from: Data(#"{"id": "x", "kind": "hologram"}"#.utf8))
        XCTAssertEqual(future.kind, .custom)
    }

    func testADocumentWithNoRigsReSavesByteIdentically() throws {
        let entity = EntityDefinition(id: "statue", kind: .usdz)
        let first = try encode(entity)
        let back = try JSONDecoder().decode(EntityDefinition.self, from: first)
        XCTAssertEqual(try encode(back), first)
    }
}
