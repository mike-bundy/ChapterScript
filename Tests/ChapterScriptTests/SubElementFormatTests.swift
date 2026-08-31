//
//  SubElementFormatTests.swift
//  FL-16: prim-path identity, unconditional keeping, byte-identity when
//  absent, clipName's checked fallback.
//

import XCTest
@testable import ChapterScript

final class SubElementFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(value)
    }

    func testAbsentSubElementsWriteNothing() throws {
        let entity = EntityDefinition(id: "car", kind: .usdz)
        let json = String(data: try encode(entity), encoding: .utf8)!
        XCTAssertFalse(json.contains("subElements"))
        XCTAssertFalse(json.contains("clipName"))
    }

    func testAReferenceRoundTripsOnABuildThatCannotResolveIt() throws {
        // Option C's whole obligation: kept whether or not this system can
        // resolve it - this test runs on a machine with no USDKit at all.
        var entity = EntityDefinition(id: "car", kind: .usdz)
        entity.subElements = [SubElementOverride(
            primPath: "/Car/Door_Left",
            isVisible: false,
            transformOffset: TransformData(
                position: Vec3(0, 0.1, 0),
                rotation: Quat(x: 0, y: 0, z: 0, w: 1),
                scale: Vec3(1, 1, 1)),
            materialOverrides: [MaterialOverrideSpec(slot: 0, roughness: 0.2)])]
        let back = try JSONDecoder().decode(EntityDefinition.self, from: encode(entity))
        XCTAssertEqual(back.subElements, entity.subElements)
        XCTAssertEqual(try encode(back), try encode(entity),
                       "re-saves unchanged - kept, never dropped")
    }

    func testTwoObjectsUsingOneFileAddressIndependently() throws {
        // The reference is (objectId, primPath) - the path alone is not it.
        var a = EntityDefinition(id: "car1", kind: .usdz, usdzAssetId: "car.usdz")
        var b = EntityDefinition(id: "car2", kind: .usdz, usdzAssetId: "car.usdz")
        a.subElements = [SubElementOverride(primPath: "/Car/Door_Left", isVisible: false)]
        b.subElements = [SubElementOverride(primPath: "/Car/Door_Left", isVisible: true)]
        XCTAssertNotEqual(a.subElements, b.subElements)
    }

    func testClipNameRoundTripsAndAbsentMeansEveryClip() throws {
        let spec = UsdzAnimationSpec(clipName: "DoorOpen")
        let back = try JSONDecoder().decode(UsdzAnimationSpec.self, from: encode(spec))
        XCTAssertEqual(back.clipName, "DoorOpen")
        let legacy = try JSONDecoder().decode(
            UsdzAnimationSpec.self,
            from: Data(#"{"enabled": true, "loop": true, "speed": 1}"#.utf8))
        XCTAssertNil(legacy.clipName, "absent = every clip, today's behaviour")
    }

    func testEmptyOverrideIsDetectable() {
        XCTAssertTrue(SubElementOverride(primPath: "/X").isEmpty)
        XCTAssertFalse(SubElementOverride(primPath: "/X", isVisible: true).isEmpty)
    }
}
