import XCTest
@testable import ChapterScript

/// Format 5 renamed what older Chapters spelled with the retired word. Every
/// older spelling `LegacyFormat` lists must still read as its current value —
/// never fall back to a default (a hold that decoded as Bézier would move).
final class LegacyFormatTests: XCTestCase {

    func testEveryOlderInterpolationReadsAsItsCurrentValue() throws {
        let decoder = ChapterScriptFormat.makeDecoder()
        for (old, current) in LegacyFormat.interpolations {
            let json = Data("\"\(old)\"".utf8)
            if let mode = InterpolationMode(rawValue: current) {
                XCTAssertEqual(try decoder.decode(InterpolationMode.self, from: json), mode, old)
            }
            if let value = AnimationInterpolation(rawValue: current) {
                XCTAssertEqual(try decoder.decode(AnimationInterpolation.self, from: json), value, old)
                let key = try decoder.decode(AnimationKey.self,
                                             from: Data(#"{"time":0,"value":1,"interpolation":"\#(old)"}"#.utf8))
                XCTAssertEqual(key.interpolation, value, old)
                XCTAssertNil(key.unknownInterpolation, "\(old) is known, not carried as unknown")
            }
            XCTAssertTrue(InterpolationMode(rawValue: current) != nil || AnimationInterpolation(rawValue: current) != nil,
                          "\(current) names no interpolation")
        }
    }

    func testEveryOlderCompletionKindReadsAsItsCurrentValue() throws {
        for (old, current) in LegacyFormat.completionKinds {
            let decoded = try ChapterScriptFormat.makeDecoder().decode(
                CompletionActionDTO.self, from: Data(#"{"kind":"\#(old)"}"#.utf8))
            let encoded = try JSONSerialization.jsonObject(
                with: ChapterScriptFormat.makeEncoder().encode(decoded)) as? [String: Any]
            XCTAssertEqual(encoded?["kind"] as? String, current)
        }
    }

    func testTheMigrationRewritesInterpolationValuesWherever_TheyAppear() throws {
        let (old, current) = try XCTUnwrap(LegacyFormat.interpolations.first { $0.value == "held" })
        let document: [String: Any] = [
            "formatVersion": 4, "id": "d", "displayName": "D",
            "sequences": [["id": "s", "name": "S", "phase": "immersive",
                           LegacyFormat.segmentListKey: [],
                           "animationTracks": [["entity": "e", "curves": ["tx": ["keys": [
                               ["time": 0, "value": 0, "interpolation": old]]]]]]]]
        ]
        let migrated = try JSONSerialization.jsonObject(
            with: Migrator.migrate(JSONSerialization.data(withJSONObject: document))) as! [String: Any]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: migrated, options: .sortedKeys), as: UTF8.self)
        XCTAssertTrue(text.contains("\"interpolation\":\"\(current)\""), text)
        XCTAssertFalse(text.contains("\"\(old)\""), text)
    }

    func testIdentifiersOnlyChangeAtTheWholeToken() {
        XCTAssertNil(LegacyFormat.currentIdentifier("footstep_1"))
        XCTAssertNil(LegacyFormat.currentIdentifier("seg_1"))
        XCTAssertEqual(LegacyFormat.currentIdentifier("\(LegacyFormat.segmentListKey.dropLast())_after_sr_1"),
                       "seg_after_sr_1")
    }
}
