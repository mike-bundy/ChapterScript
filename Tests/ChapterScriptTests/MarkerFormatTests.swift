//
//  MarkerFormatTests.swift
//  ChapterScriptTests
//
//  FL-06 — three additive, tolerant fields; a Chapter with no Markers
//  re-saves byte-identically.
//

import XCTest
@testable import ChapterScript

final class MarkerFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    func testAbsentMarkersEncodeToNothing() throws {
        let sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        XCTAssertFalse(String(decoding: try encode(sequence), as: UTF8.self)
            .contains("markers"))

        let video = VideoActionDTO(file: "a.mov", channel: "main")
        XCTAssertFalse(String(decoding: try encode(video), as: UTF8.self)
            .contains("markers"))

        let audio = AudioActionDTO(file: "a.wav", channel: "music")
        XCTAssertFalse(String(decoding: try encode(audio), as: UTF8.self)
            .contains("markers"))

        let doc = ChapterDocument(id: "c", displayName: "C")
        XCTAssertFalse(String(decoding: try encode(doc), as: UTF8.self)
            .contains("markerCategories"))
    }

    func testMarkersRoundTripOnEveryOwner() throws {
        let marker = Marker(id: "marker_1", time: 3.25, duration: 1.5,
                            name: "Beat 3", categoryId: "cat_1")

        var video = VideoActionDTO(file: "a.mov", channel: "main")
        video.markers = [marker]
        let videoBack = try ChapterScriptFormat.makeDecoder()
            .decode(VideoActionDTO.self, from: encode(video))
        XCTAssertEqual(videoBack.markers, [marker])

        var audio = AudioActionDTO(file: "a.wav", channel: "music")
        audio.markers = [marker]
        let audioBack = try ChapterScriptFormat.makeDecoder()
            .decode(AudioActionDTO.self, from: encode(audio))
        XCTAssertEqual(audioBack.markers, [marker])

        var sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        sequence.markers = [marker]
        let seqBack = try ChapterScriptFormat.makeDecoder()
            .decode(SequenceDefinitionDTO.self, from: encode(sequence))
        XCTAssertEqual(seqBack.markers, [marker])

        let doc = ChapterDocument(
            id: "c", displayName: "C",
            markerCategories: [MarkerCategory(
                id: "cat_1", name: "Beats",
                color: ColorRGBA(r: 1, g: 0, b: 0, a: 1))])
        let docBack = try ChapterScriptFormat.makeDecoder()
            .decode(ChapterDocument.self, from: encode(doc))
        XCTAssertEqual(docBack.markerCategories?.first?.name, "Beats")
    }

    /// The UNKNOWN category id is a resolve-layer concern; the FORMAT keeps
    /// the reference verbatim so nothing is destroyed in a round trip.
    func testUnknownCategoryReferenceSurvivesVerbatim() throws {
        let marker = Marker(id: "m", time: 1, categoryId: "cat_gone")
        var video = VideoActionDTO(file: "a.mov", channel: "main")
        video.markers = [marker]
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(VideoActionDTO.self, from: encode(video))
        XCTAssertEqual(back.markers?.first?.categoryId, "cat_gone")
    }

    /// A pre-Marker document decodes and re-encodes without gaining a key.
    func testPreMarkerDocumentStaysByteIdentical() throws {
        let doc = ChapterDocument(
            id: "c", displayName: "C",
            sequences: [SequenceDefinitionDTO(
                id: "s", name: "S", phase: "immersive",
                steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5,
                                          actions: [])])])
        let first = try encode(doc)
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(ChapterDocument.self, from: first)
        XCTAssertEqual(try encode(back), first)
    }
}
