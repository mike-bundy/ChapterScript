//
//  PlaceholderOriginTests.swift
//  ChapterScriptTests
//
//  `PlaceholderSpec.origin` — the fact separating a deliberately authored
//  placeholder from an internal Timeline track surface. Additive and
//  tolerant: absent stays absent (old documents re-save byte-identically),
//  unknown raw values degrade to nil rather than failing the load.
//

import XCTest
@testable import ChapterScript

final class PlaceholderOriginTests: XCTestCase {

    func testOriginRoundTrips() throws {
        var spec = PlaceholderSpec.videoPanel(label: "Main Screen")
        spec.origin = .trackSurface
        let data = try JSONEncoder().encode(spec)
        let back = try JSONDecoder().decode(PlaceholderSpec.self, from: data)
        XCTAssertEqual(back.origin, .trackSurface)

        spec.origin = .authored
        let authored = try JSONDecoder().decode(
            PlaceholderSpec.self, from: JSONEncoder().encode(spec))
        XCTAssertEqual(authored.origin, .authored)
    }

    func testAbsentOriginStaysAbsentAndEncodesNoKey() throws {
        let spec = PlaceholderSpec.videoPanel(label: "Legacy Panel")
        XCTAssertNil(spec.origin, "constructors do not invent an origin")

        let data = try JSONEncoder().encode(spec)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["origin"],
                     "nil encodes to NO key — existing documents re-save unchanged")

        let back = try JSONDecoder().decode(PlaceholderSpec.self, from: data)
        XCTAssertNil(back.origin)
    }

    func testUnknownOriginDegradesToNil() throws {
        let json = #"{"role":"videoPanel","label":"X","origin":"fromTheFuture"}"#
        let spec = try JSONDecoder().decode(PlaceholderSpec.self,
                                            from: Data(json.utf8))
        XCTAssertNil(spec.origin, "a newer tool's origin kind must not fail the load")
        XCTAssertEqual(spec.role, .videoPanel)
    }
}
