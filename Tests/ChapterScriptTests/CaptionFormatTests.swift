//
//  CaptionFormatTests.swift
//  ChapterScriptTests
//
//  FL-08's format guarantees: absent means no captions and writes nothing;
//  a pre-Caption document re-saves byte-identically; an unrecognised kind
//  decodes to the WEAKER claim; an unresolved styleId is kept; and the
//  whole model round-trips.
//

import XCTest
@testable import ChapterScript

final class CaptionFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    private func makeSequence() -> SequenceDefinitionDTO {
        SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
    }

    func testAbsentCaptionsEncodeToNothing() throws {
        let sequence = makeSequence()
        XCTAssertFalse(String(decoding: try encode(sequence), as: UTF8.self)
            .contains("captionTracks"))

        let doc = ChapterDocument(id: "c", displayName: "C")
        XCTAssertFalse(String(decoding: try encode(doc), as: UTF8.self)
            .contains("captionStyles"))
    }

    /// A pre-Caption document decodes and re-encodes without gaining a key —
    /// the standing guarantee.
    func testPreCaptionDocumentStaysByteIdentical() throws {
        let doc = ChapterDocument(id: "c", displayName: "C",
                                  sequences: [makeSequence()])
        let first = try encode(doc)
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(ChapterDocument.self, from: first)
        XCTAssertEqual(try encode(back), first)
    }

    func testFullModelRoundTrips() throws {
        var sequence = makeSequence()
        sequence.captionTracks = [CaptionTrack(
            id: "t1", language: "fr-CA", kind: .subtitles,
            label: "Français", styleId: "style-1",
            cues: [
                CaptionCue(id: "c1", start: 1, end: 2.5, text: "Bonjour",
                           runs: [CaptionStyleRun(start: 0, length: 7, italic: true,
                                                  voice: "Narrator")]),
                CaptionCue(id: "c2", start: 2.5, end: 4, text: "le monde",
                           regionId: "r1"),
            ])]
        var doc = ChapterDocument(id: "c", displayName: "C", sequences: [sequence])
        doc.captionStyles = [CaptionStyle(
            id: "style-1", name: "House", fontFamily: "Helvetica",
            fontSize: 0.05, maxLineCount: 2,
            mode: .viewerFacing, distance: 1.8)]

        let bytes = try encode(doc)
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(ChapterDocument.self, from: bytes)
        XCTAssertEqual(back.sequences[0].captionTracks,
                       sequence.captionTracks)
        XCTAssertEqual(back.captionStyles, doc.captionStyles)
        // And the second save is byte-stable.
        XCTAssertEqual(try encode(back), bytes)
    }

    /// An unrecognised kind is the WEAKER claim: calling a translation an
    /// accessibility artefact would over-claim, so the fallback is subtitles.
    func testUnknownKindDecodesAsSubtitles() throws {
        let json = #"{"id":"t","language":"en","kind":"karaoke","cues":[]}"#
        let track = try JSONDecoder().decode(CaptionTrack.self,
                                             from: Data(json.utf8))
        XCTAssertEqual(track.kind, .subtitles)
    }

    func testAbsentKindDecodesAsSubtitles() throws {
        let json = #"{"id":"t","language":"en"}"#
        let track = try JSONDecoder().decode(CaptionTrack.self,
                                             from: Data(json.utf8))
        XCTAssertEqual(track.kind, .subtitles)
        XCTAssertTrue(track.cues.isEmpty, "absent cues decode to none")
    }

    func testUnknownPresentationModeDecodesAsViewerFacing() throws {
        let json = #"{"id":"s","mode":"holographic"}"#
        let style = try JSONDecoder().decode(CaptionStyle.self,
                                             from: Data(json.utf8))
        XCTAssertEqual(style.mode, .viewerFacing)
    }

    /// An id that names no style resolves to the default AND IS KEPT — a
    /// round trip through an older build must not destroy the reference.
    func testUnresolvedStyleIdSurvivesReSave() throws {
        var sequence = makeSequence()
        sequence.captionTracks = [CaptionTrack(id: "t", language: "en",
                                               styleId: "gone")]
        let bytes = try encode(sequence)
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(SequenceDefinitionDTO.self, from: bytes)
        XCTAssertEqual(back.captionTracks?.first?.styleId, "gone")
        XCTAssertEqual(try encode(back), bytes)
    }
}
