//
//  EffectFormatTests.swift
//  ChapterScriptTests
//
//  G7 — the sharpest tolerant-decode requirement in the roadmap: an
//  unrecognised Effect keeps its id, EVERY parameter (unrecognised keys
//  and unrecognised value shapes included), its position and its enabled
//  flag, and re-saves byte-identically. An older build must never destroy
//  a newer build's work.
//

import XCTest
@testable import ChapterScript

final class EffectFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    /// A stack written by an imaginary NEWER build: an unknown effect id,
    /// an unknown parameter key, an unknown value SHAPE (an array and a
    /// nested object), plus known shapes — including a colour whose float
    /// values do not survive a Float round trip.
    private var newerBuildJSON: String {
        """
        [
          {
            "effectId" : "maestro.effect.hologram",
            "enabled" : false,
            "id" : "fx_future1",
            "parameters" : {
              "matrix" : [1, 0, 0.62, {"nested" : true}],
              "mysteryShape" : {"kind" : "torus", "windings" : 3},
              "strength" : 0.62,
              "tint" : {"a" : 1, "b" : 0.30000001192092896, "g" : 0.62, "r" : 0.25}
            }
          }
        ]
        """
    }

    func testG7UnrecognisedEffectRoundTripsByteIdentically() throws {
        let data = Data(newerBuildJSON.utf8)
        let decoded = try ChapterScriptFormat.makeDecoder()
            .decode([EffectInstance].self, from: data)

        XCTAssertEqual(decoded[0].effectId, "maestro.effect.hologram",
                       "the id survives even though nothing can render it")
        XCTAssertEqual(decoded[0].enabled, false, "the author's flag survives")
        XCTAssertEqual(decoded[0].parameters.count, 4, "EVERY parameter survives")

        // Canonicalize once (whitespace differs from the format encoder),
        // then the invariant: decode → encode is a fixed point.
        let first = try encode(decoded)
        let again = try ChapterScriptFormat.makeDecoder()
            .decode([EffectInstance].self, from: first)
        XCTAssertEqual(try encode(again), first,
                       "an older build's save must not destroy a newer build's work")
        // And nothing was dropped on the way through.
        XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("mysteryShape"))
        XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("0.30000001192092896"),
                      "float-hostile values re-encode verbatim")
    }

    func testKnownShapesReadThroughAccessors() throws {
        var instance = EffectInstance(effectId: "maestro.effect.reference")
        instance.parameters = [
            "strength": .number(0.5),
            "invert": .bool(true),
            "mode": .string("soft"),
            "tint": .color(ColorRGBA(r: 1, g: 0.5, b: 0.25, a: 1)),
            "centre": .point(EffectPoint(x: 0.5, y: 0.5)),
        ]
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(EffectInstance.self, from: encode(instance))
        XCTAssertEqual(back.parameters["strength"]?.numberValue, 0.5)
        XCTAssertEqual(back.parameters["invert"]?.boolValue, true)
        XCTAssertEqual(back.parameters["mode"]?.stringValue, "soft")
        XCTAssertEqual(back.parameters["tint"]?.colorValue,
                       ColorRGBA(r: 1, g: 0.5, b: 0.25, a: 1))
        XCTAssertEqual(back.parameters["centre"]?.pointValue,
                       EffectPoint(x: 0.5, y: 0.5))
        // What this build writes is also a fixed point.
        XCTAssertEqual(try encode(back), try encode(instance))
    }

    func testStackOrderSurvives() throws {
        let stack = [
            EffectInstance(id: "a", effectId: "one"),
            EffectInstance(id: "b", effectId: "two"),
            EffectInstance(id: "c", effectId: "three"),
        ]
        let back = try ChapterScriptFormat.makeDecoder()
            .decode([EffectInstance].self, from: encode(stack))
        XCTAssertEqual(back.map(\.id), ["a", "b", "c"],
                       "order IS evaluation order; the array carries it")
    }

    func testEmptyParametersEncodeToNothing() throws {
        let bytes = try encode(EffectInstance(id: "x", effectId: "e"))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("parameters"))
    }

    func testAbsentEnabledDecodesTrue() throws {
        let json = #"{"id":"x","effectId":"e"}"#
        let back = try JSONDecoder().decode(EffectInstance.self,
                                            from: Data(json.utf8))
        XCTAssertTrue(back.enabled)
    }
}

// MARK: - The carriers

final class EffectCarrierFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    func testAbsentEffectsWriteNothingAnywhere() throws {
        let video = VideoActionDTO(file: "a.mov", channel: "v")
        XCTAssertFalse(String(decoding: try encode(video), as: UTF8.self)
            .contains("effects"))
        let cue = BackdropCue(id: "b", startTime: 0, spec: nil)
        XCTAssertFalse(String(decoding: try encode(cue), as: UTF8.self)
            .contains("effects"))
        let sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        XCTAssertFalse(String(decoding: try encode(sequence), as: UTF8.self)
            .contains("effectKeyTracks"))
        let doc = ChapterDocument(id: "c", displayName: "C")
        XCTAssertFalse(String(decoding: try encode(doc), as: UTF8.self)
            .contains("sourceSeedEffects"))
    }

    func testStackRidesTheVideoOccurrence() throws {
        var video = VideoActionDTO(file: "a.mov", channel: "v")
        video.effects = [EffectInstance(id: "fx1", effectId: "maestro.effect.reference",
                                        parameters: ["amount": .number(0.5)])]
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(VideoActionDTO.self, from: encode(video))
        XCTAssertEqual(back.effects, video.effects)
        XCTAssertEqual(try encode(back), try encode(video))
    }

    func testEffectKeyTracksRoundTripOnTheSequence() throws {
        var curve = AnimationCurve()
        curve.setKey(AnimationKey(time: 1, value: 0.25))
        curve.setKey(AnimationKey(time: 3, value: 0.75))
        var sequence = SequenceDefinitionDTO(
            id: "s", name: "S", phase: "immersive",
            steps: [StepDefinitionDTO(id: "st", name: "St", duration: 5, actions: [])])
        sequence.effectKeyTracks = [EffectKeyTrack(instanceId: "fx1",
                                                   channels: ["amount": curve])]
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(SequenceDefinitionDTO.self, from: encode(sequence))
        XCTAssertEqual(back.effectKeyTracks?.first?["amount"].keys.count, 2)
        XCTAssertEqual(try encode(back), try encode(sequence))
    }

    func testEmptiedKeyCurveDisappears() {
        var track = EffectKeyTrack(instanceId: "fx1")
        var curve = AnimationCurve()
        curve.setKey(AnimationKey(time: 1, value: 0.5))
        track["amount"] = curve
        XCTAssertTrue(track.hasAnyKeys)
        track["amount"] = AnimationCurve()
        XCTAssertFalse(track.hasAnyKeys)
        XCTAssertNil(track.channels["amount"], "no ghost channels")
    }

    func testSeedStacksRideEditorMetadata() throws {
        var metadata = EditorMetadata()
        metadata.sourceSeedEffects["shot.mov"] = [
            EffectInstance(id: "seed1", effectId: "maestro.effect.reference"),
        ]
        var doc = ChapterDocument(id: "c", displayName: "C")
        doc.editorMetadata = metadata
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(ChapterDocument.self, from: encode(doc))
        XCTAssertEqual(back.editorMetadata?.sourceSeedEffects["shot.mov"]?.count, 1)
        XCTAssertEqual(try encode(back), try encode(doc))
        XCTAssertFalse(EditorMetadata().isEmpty == false, "empty stays empty")
    }
}

// MARK: - The display blend (FL-11)

final class BlendModeFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    func testAbsentBlendWritesNothing() throws {
        let video = VideoActionDTO(file: "a.mov", channel: "v")
        XCTAssertFalse(String(decoding: try encode(video), as: UTF8.self)
            .contains("blendMode"))
    }

    func testUnknownModeRendersNormalAndRoundTripsVerbatim() throws {
        let json = #"{"file":"a.mov","channel":"v","blendMode":"hologramBlend"}"#
        let back = try JSONDecoder().decode(VideoActionDTO.self,
                                            from: Data(json.utf8))
        XCTAssertEqual(back.blendMode?.renderedMode, BlendMode.normal,
                       "the weakest visual claim")
        let bytes = try encode(back)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self)
            .contains("hologramBlend"),
                      "an older build never rewrites a newer build's blend")
        let again = try JSONDecoder().decode(VideoActionDTO.self, from: bytes)
        XCTAssertEqual(try encode(again), bytes)
    }

    func testTheElevenModesRoundTrip() throws {
        let modes: [BlendMode] = [.normal, .replace, .darken, .multiply,
                                  .lighten, .screen, .overlay, .softLight,
                                  .hardLight, .add, .subtract, .difference]
        for mode in modes {
            let back = try JSONDecoder().decode(
                BlendMode.self, from: encode(mode))
            XCTAssertEqual(back, mode)
        }
    }
}

// MARK: - The two-source transition (FL-12)

final class VideoTransitionFormatTests: XCTestCase {

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try ChapterScriptFormat.makeEncoder().encode(value)
    }

    func testAbsentTransitionWritesNothing() throws {
        let video = VideoActionDTO(file: "a.mov", channel: "v")
        XCTAssertFalse(String(decoding: try encode(video), as: UTF8.self)
            .contains("videoTransition"))
    }

    func testTransitionRidesTheIncomingOccurrence() throws {
        var video = VideoActionDTO(file: "b.mov", channel: "v")
        video.videoTransition = VideoTransitionSpec(duration: 1.5)
        let back = try ChapterScriptFormat.makeDecoder()
            .decode(VideoActionDTO.self, from: encode(video))
        XCTAssertEqual(back.videoTransition?.duration, 1.5)
        XCTAssertTrue(back.videoTransition?.isRenderable == true)
        XCTAssertEqual(try encode(back), try encode(video))
    }

    /// An unrecognised kind decodes to NO renderable transition — never
    /// a dip and never a dissolve the author did not author — and the
    /// raw value survives a re-save verbatim.
    func testUnknownKindIsNoTransitionAndRoundTrips() throws {
        let json = #"{"file":"a.mov","channel":"v","videoTransition":{"duration":2,"kind":"pageCurl"}}"#
        let back = try JSONDecoder().decode(VideoActionDTO.self,
                                            from: Data(json.utf8))
        XCTAssertEqual(back.videoTransition?.isRenderable, false,
                       "an unknown kind renders NOTHING")
        XCTAssertEqual(back.videoTransition?.kindRaw, "pageCurl")
        let bytes = try encode(back)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("pageCurl"))
        let again = try JSONDecoder().decode(VideoActionDTO.self, from: bytes)
        XCTAssertEqual(try encode(again), bytes)
    }
}
