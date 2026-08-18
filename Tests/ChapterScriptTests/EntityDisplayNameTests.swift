import XCTest
@testable import ChapterScript

/// `displayName` separates the visible label from stable identity.
///
/// The rule these tests defend: adding a label to the format must not change a
/// single byte of any document that does not use one. A real project on disk
/// contains `"id": "IMG_0071.MOV"`; it must keep saying exactly that, and it
/// must not grow a `displayName: null`.
final class EntityDisplayNameTests: XCTestCase {

    private func encoded(_ entity: EntityDefinition) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(entity)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Decode tolerance

    func testDocumentWithoutDisplayNameDecodes() throws {
        let json = #"""
        {"id":"IMG_0071.MOV","kind":"videoPanel","initiallyEnabled":true,
         "gestureEnabled":false,
         "transform":{"position":{"x":0,"y":0,"z":-1.5},
                      "rotation":{"w":1,"x":0,"y":0,"z":0},
                      "scale":{"x":1,"y":1,"z":1}}}
        """#
        let entity = try JSONDecoder().decode(EntityDefinition.self,
                                              from: Data(json.utf8))
        XCTAssertEqual(entity.id, "IMG_0071.MOV")
        XCTAssertNil(entity.displayName)
        XCTAssertEqual(entity.resolvedDisplayName, "IMG_0071.MOV",
                       "an unlabelled entity reads as its id, which is what it always did")
    }

    func testDisplayNameRoundTrips() throws {
        let entity = EntityDefinition(id: "dest_8F2A", displayName: "Main Screen",
                                      kind: .videoPanel)
        let data = try JSONEncoder().encode(entity)
        let back = try JSONDecoder().decode(EntityDefinition.self, from: data)
        XCTAssertEqual(back.displayName, "Main Screen")
        XCTAssertEqual(back.id, "dest_8F2A")
    }

    // MARK: - No byte churn for documents that do not use it

    /// The important one. If this fails, every existing project's `chapter.json`
    /// grows a null on the next save — a diff nobody asked for, in a file
    /// format that syncs over the wire.
    func testAbsentDisplayNameEmitsNoKey() throws {
        let entity = EntityDefinition(id: "IMG_0071.MOV", kind: .videoPanel)
        let object = try encoded(entity)
        XCTAssertFalse(object.keys.contains("displayName"),
                       "a nil label must not be written as null")
    }

    func testPresentDisplayNameEmitsTheKey() throws {
        let entity = EntityDefinition(id: "dest_8F2A", displayName: "Main Screen",
                                      kind: .videoPanel)
        let object = try encoded(entity)
        XCTAssertEqual(object["displayName"] as? String, "Main Screen")
    }

    // MARK: - Identity is not the label

    func testRenamingDoesNotChangeId() {
        var entity = EntityDefinition(id: "dest_8F2A", displayName: "Main Screen",
                                      kind: .videoPanel)
        entity.displayName = "Archive Projection"
        XCTAssertEqual(entity.id, "dest_8F2A")
    }

    /// Labels are not unique and must never be used as keys.
    func testTwoEntitiesMayShareALabelAndStayDistinct() {
        let a = EntityDefinition(id: "dest_1", displayName: "Screen", kind: .videoPanel)
        let b = EntityDefinition(id: "dest_2", displayName: "Screen", kind: .videoPanel)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a, b)
    }

    func testBlankLabelFallsBackToId() {
        XCTAssertEqual(
            EntityDefinition(id: "dest_1", displayName: "", kind: .videoPanel)
                .resolvedDisplayName, "dest_1")
        XCTAssertEqual(
            EntityDefinition(id: "dest_1", displayName: "  \n ", kind: .videoPanel)
                .resolvedDisplayName, "dest_1")
    }
}
