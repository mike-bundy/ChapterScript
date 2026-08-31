//
//  SourceAlphaInterpretationTests.swift
//  ChapterScriptTests
//
//  FL-04 — the alpha field is additive, tolerant, and absent means
//  Automatic. A Chapter never told anything about alpha re-saves
//  byte-identically.
//

import XCTest
@testable import ChapterScript

final class SourceAlphaInterpretationTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    // MARK: - Absent means absent

    func testAbsentAlphaEncodesToNothing() throws {
        let video = VideoInterpretation(layout: .sideBySide)
        let json = String(decoding: try encode(video), as: UTF8.self)
        XCTAssertFalse(json.contains("alpha"))

        let image = ImageInterpretation(placement: .environment)
        let imageJSON = String(decoding: try encode(image), as: UTF8.self)
        XCTAssertFalse(imageJSON.contains("alpha"))
    }

    /// The byte-identity rule, at the field level: a record written before
    /// FL-04 decodes and re-encodes to the same bytes.
    func testPreAlphaRecordRoundTripsByteIdentical() throws {
        let legacy = Data(#"{"layout":"sideBySide","projection":"equirectangular"}"#.utf8)
        let decoded = try ChapterScriptFormat.makeDecoder()
            .decode(VideoInterpretation.self, from: legacy)
        XCTAssertNil(decoded.alpha)
        let re = try encode(decoded)
        let reDecoded = try ChapterScriptFormat.makeDecoder()
            .decode(VideoInterpretation.self, from: re)
        XCTAssertEqual(reDecoded, decoded)
        XCTAssertFalse(String(decoding: re, as: UTF8.self).contains("alpha"))
    }

    // MARK: - Round trip

    func testAllThreeStatesRoundTrip() throws {
        for state in SourceAlpha.allCases {
            let video = VideoInterpretation(alpha: state)
            let back = try ChapterScriptFormat.makeDecoder()
                .decode(VideoInterpretation.self, from: encode(video))
            XCTAssertEqual(back.alpha, state)

            let image = ImageInterpretation(alpha: state)
            let imageBack = try ChapterScriptFormat.makeDecoder()
                .decode(ImageInterpretation.self, from: encode(image))
            XCTAssertEqual(imageBack.alpha, state)
        }
    }

    // MARK: - Tolerance: an unknown future case is Automatic, not a failure

    func testUnknownAlphaDecodesAsAbsent() throws {
        let future = Data(#"{"alpha":"linearCoverage","layout":"mono"}"#.utf8)
        let decoded = try ChapterScriptFormat.makeDecoder()
            .decode(VideoInterpretation.self, from: future)
        XCTAssertNil(decoded.alpha, "an unrecognised alpha must read as Automatic")
        XCTAssertEqual(decoded.layout, .mono, "the rest of the record still decodes")

        let futureImage = Data(#"{"alpha":"somethingNew"}"#.utf8)
        let image = try ChapterScriptFormat.makeDecoder()
            .decode(ImageInterpretation.self, from: futureImage)
        XCTAssertNil(image.alpha)
        XCTAssertTrue(image.isEmpty, "nothing decided means the record can be dropped")
    }

    // MARK: - isEmpty gates the never-write-an-empty-record rule

    func testAlphaAloneMakesTheRecordNonEmpty() {
        XCTAssertTrue(VideoInterpretation().isEmpty)
        XCTAssertFalse(VideoInterpretation(alpha: .straight).isEmpty)
        XCTAssertTrue(ImageInterpretation().isEmpty)
        XCTAssertFalse(ImageInterpretation(alpha: .premultiplied).isEmpty)
    }
}
