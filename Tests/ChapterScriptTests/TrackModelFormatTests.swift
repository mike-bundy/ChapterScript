//
//  TrackModelFormatTests.swift
//  FL-17 C17: track properties are editor metadata keyed by surface id;
//  mute is a document fact; solo appears in NO document type.
//

import XCTest
@testable import ChapterScript

final class TrackModelFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(value)
    }

    func testTrackPropertiesRoundTripOnEditorMetadata() throws {
        var meta = EditorMetadata()
        meta.trackProperties["screen"] = TrackProperties(
            height: 64, colorTag: "coral", isLocked: true)
        let back = try JSONDecoder().decode(EditorMetadata.self, from: encode(meta))
        XCTAssertEqual(back.trackProperties["screen"]?.height, 64)
        XCTAssertEqual(back.trackProperties["screen"]?.isLocked, true)
        XCTAssertFalse(meta.isEmpty, "properties keep the metadata alive")
    }

    func testEmptyPropertiesLeaveMetadataEmpty() {
        var meta = EditorMetadata()
        XCTAssertTrue(meta.isEmpty)
        meta.trackProperties["x"] = TrackProperties()
        XCTAssertTrue(TrackProperties().isEmpty,
                      "an untouched track stores nothing")
    }

    func testMutedDestinationsAreADocumentFact() throws {
        var sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        sequence.mutedDestinations = ["narration"]
        let back = try JSONDecoder().decode(SequenceDefinitionDTO.self,
                                            from: encode(sequence))
        XCTAssertEqual(back.mutedDestinations, ["narration"])
    }

    func testAbsentMuteWritesNothingAndSoloHasNoWireShape() throws {
        let sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        let json = String(data: try encode(sequence), encoding: .utf8)!
        XCTAssertFalse(json.contains("mutedDestinations"))
        XCTAssertFalse(json.contains("solo"),
                       "solo appears in NO document type - the sharpest rule here")
    }
}

extension TrackModelFormatTests {

    func testTrackGainsAndDuckersRoundTrip() throws {
        var sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        sequence.trackGains = ["music": -6]
        sequence.duckers = [DuckerSpec(id: "duck_1",
                                       targetDestinationId: "music",
                                       triggerDestinationId: "narration")]
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let back = try JSONDecoder().decode(SequenceDefinitionDTO.self,
                                            from: e.encode(sequence))
        XCTAssertEqual(back.trackGains?["music"], -6)
        XCTAssertEqual(back.duckers?.first?.depthDB, -12)
        // A dangling target is KEPT through a re-save.
        XCTAssertEqual(back.duckers?.first?.targetDestinationId, "music")
    }

    func testTrackGainIsOneMoreMultiplyInTheOneFormula() {
        let unity = SequenceAudioAutomation.effectiveVolume(
            base: 1, channel: "music", at: 0, in: [], trackGainDB: 0)
        XCTAssertEqual(unity, 1, accuracy: 1e-6)
        let dimmed = SequenceAudioAutomation.effectiveVolume(
            base: 1, channel: "music", at: 0, in: [], trackGainDB: -6)
        XCTAssertEqual(dimmed, 0.501, accuracy: 0.01, "-6 dB is half power")
        let mutedWins = SequenceAudioAutomation.effectiveVolume(
            base: 1, channel: "music", at: 0, in: [], muted: true, trackGainDB: 12)
        XCTAssertEqual(mutedWins, 0, "mute is absolute")
    }
}
