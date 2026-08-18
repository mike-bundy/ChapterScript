//
//  AudioRuntimeRoutingTests.swift
//  ChapterScriptTests
//
//  EVERY AUTHORED PLAYBACK MODEL REACHES A PATH CHOSEN FOR IT.
//
//  The defect these pin: the runtime routed on `action.spatial != nil`, and the
//  authored `playbackModel` never reached it — the DTO bridge copied eleven
//  fields and dropped the twelfth. Head-locked stereo, an ambisonic bed and an
//  Apple Spatial Audio master were indistinguishable at playback.
//
//  These are ROUTING tests. They prove where a cue is sent, never how it
//  sounds; nothing here can be verified without a headset and nothing here
//  claims to be.
//

import XCTest
@testable import ChapterScript

final class AudioRuntimeRoutingTests: XCTestCase {

    private func cue(
        _ model: AudioPlaybackModel?, emitter: String? = nil, position: Vec3? = nil
    ) -> AudioActionDTO {
        var audio = AudioActionDTO(file: "x.wav", channel: "audio-x")
        audio.playbackModel = model
        if emitter != nil || position != nil {
            audio.spatial = SpatialAudioConfigDTO(position: position, attachToEntity: emitter)
        }
        return audio
    }

    // MARK: - The four models reach four decisions

    func testHeadLockedRoutesHeadLocked() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(.headLocked)),
                       .supported(.headLocked))
    }

    func testPositionalRoutesPositional() {
        XCTAssertEqual(
            AudioRuntimeRouting.route(for: cue(.positional, emitter: "Emitter")),
            .supported(.positional))
    }

    /// A bare position, with no emitter, is still somewhere to play from.
    func testPositionalWithAPositionButNoEmitterIsStillPositional() {
        XCTAssertEqual(
            AudioRuntimeRouting.route(for: cue(.positional, position: Vec3(x: 1, y: 0, z: -2))),
            .supported(.positional))
    }

    /// SCENE-BASED IS NOT SILENTLY AMBIENT. It degrades, and the degradation
    /// says which model it came from and why.
    func testSceneBasedDegradesExplicitly() {
        let routed = AudioRuntimeRouting.route(for: cue(.sceneBased))
        guard case .fallback(let route, let from, let reason) = routed else {
            return XCTFail("scene-based must not report as supported")
        }
        XCTAssertEqual(route, .headLocked)
        XCTAssertEqual(from, .sceneBased)
        XCTAssertFalse(reason.isEmpty, "a fallback without a reason is a silent detour")
    }

    /// SUPERSEDED: spatial-mix used to degrade, because the only pipeline was
    /// the audio graph and that flattens an encoded master. It now has its own
    /// path — the system player, asset intact — so it is genuinely supported.
    func testSpatialMixUsesTheSystemMediaPipeline() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(.spatialMix)),
                       .supported(.systemSpatialMedia))
    }

    /// NEITHER IS EVER ROUTED POSITIONAL. Point-spatialising a sound field or a
    /// mastered immersive mix is the specific wrong answer — worse than a
    /// downmix, because it invents a location the mix never had.
    func testFieldsAndMixesAreNeverPointSpatialised() {
        for model in [AudioPlaybackModel.sceneBased, .spatialMix] {
            // Even carrying an emitter, which an author could have left behind
            // when switching models.
            let routed = AudioRuntimeRouting.route(for: cue(model, emitter: "Leftover Emitter"))
            XCTAssertNotEqual(routed.route, .positional,
                              "\(model.rawValue) must never be point-spatialised")
        }
    }

    /// Every model reaches a decision — no model falls off the end.
    func testEveryModelIsRouted() {
        for model in AudioPlaybackModel.allCases {
            let routed = AudioRuntimeRouting.route(
                playbackModel: model, hasSpatialAttachment: model == .positional)
            XCTAssertTrue(AudioRuntimeRouting.Route.allCases.contains(routed.route),
                          "\(model.rawValue) reached no path")
        }
    }

    // MARK: - Backward compatibility

    /// A DOCUMENT WRITTEN BEFORE THE FIELD EXISTED MUST SOUND THE SAME.
    /// The historic rule was exactly `spatial != nil`, so that is the inference.
    func testLegacyCueWithAnAttachmentIsPositional() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(nil, emitter: "Emitter")),
                       .supported(.positional))
    }

    func testLegacyCueWithoutAnAttachmentIsHeadLocked() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(nil)),
                       .supported(.headLocked))
    }

    /// AN OLD STEREO CUE IS NEVER PROMOTED. Nothing about a legacy document
    /// may make it ambisonic or spatial-mix by guesswork — that would change
    /// how existing chapters sound.
    func testLegacyCuesAreNeverPromotedToASpatialModel() {
        for legacy in [cue(nil), cue(nil, emitter: "E")] {
            let routed = AudioRuntimeRouting.route(for: legacy)
            XCTAssertFalse(routed.isFallback, "a legacy cue must route cleanly")
            XCTAssertTrue([.headLocked, .positional].contains(routed.route))
        }
    }

    // MARK: - Incoherent authoring

    /// Positional with nothing to attach to has no location. Say so and stay
    /// audible, rather than inventing an origin.
    func testPositionalWithoutAnywhereToPlayFromDegrades() {
        let routed = AudioRuntimeRouting.route(
            playbackModel: .positional, hasSpatialAttachment: false)
        guard case .fallback(let route, let from, _) = routed else {
            return XCTFail("expected a declared fallback")
        }
        XCTAssertEqual(route, .headLocked)
        XCTAssertEqual(from, .positional)
    }

    // MARK: - Capability matrix

    func testCapabilitiesSeparateAuthoringFromFaithfulPlayback() {
        for model in AudioPlaybackModel.allCases {
            XCTAssertTrue(AudioRuntimeRouting.capability(of: model).authoring,
                          "every model is authorable")
            XCTAssertTrue(AudioRuntimeRouting.capability(of: model).routing,
                          "every model is routed")
        }
        XCTAssertTrue(AudioRuntimeRouting.capability(of: .headLocked).faithfulPlayback)
        XCTAssertTrue(AudioRuntimeRouting.capability(of: .positional).faithfulPlayback)
        XCTAssertFalse(AudioRuntimeRouting.capability(of: .sceneBased).faithfulPlayback,
                       "a recorder ambisonic WAV still needs preparation")
        XCTAssertTrue(AudioRuntimeRouting.capability(of: .spatialMix).faithfulPlayback,
                      "an encoded master is played intact by the system pipeline")
    }

    /// The matrix and the router agree. Two sources of truth about the same
    /// fact is how an editor ends up promising what a runtime does not do.
    func testTheMatrixAgreesWithTheRouter() {
        for model in AudioPlaybackModel.allCases {
            let routed = AudioRuntimeRouting.route(
                playbackModel: model, hasSpatialAttachment: model == .positional)
            XCTAssertEqual(AudioRuntimeRouting.capability(of: model).faithfulPlayback,
                           !routed.isFallback,
                           "\(model.rawValue): matrix and router disagree")
        }
    }

    /// Only scene-based is still waiting; spatial-mix has its pipeline.
    func testOnlySceneBasedAwaitsFaithfulPlayback() {
        XCTAssertEqual(Set(AudioRuntimeRouting.modelsAwaitingFaithfulPlayback), [.sceneBased])
    }

    // MARK: - The owner's real media, by interpretation

    /// These assert the ROUTE each real file's interpretation produces. The
    /// interpretations themselves are proved against the actual files by
    /// `MaestroStudioTests/AudioFormatProbeTests`; this is the half that says
    /// what the runtime then does with them.
    func testRealMediaInterpretationsRouteAsIntended() {
        // Ambisonic.WAV — FOA, inferred from BWF. Scene-based, never positional.
        let ambisonic = AudioRuntimeRouting.route(
            playbackModel: .sceneBased, hasSpatialAttachment: false)
        XCTAssertNotEqual(ambisonic.route, .positional, "a sound field is not a point")
        XCTAssertTrue(ambisonic.isFallback, "scene-based decoding is not implemented")

        // ASAF.mp4 — APAC, HOA bed + objects. Handed to the system player
        // whole: never positional, and no longer degraded.
        let asaf = AudioRuntimeRouting.route(
            playbackModel: .spatialMix, hasSpatialAttachment: false)
        XCTAssertEqual(asaf, .supported(.systemSpatialMedia))

        // Dolby Spatial.mp4 — E-AC-3 + JOC. Same treatment as any encoded mix.
        let dolby = AudioRuntimeRouting.route(
            playbackModel: .spatialMix, hasSpatialAttachment: false)
        XCTAssertEqual(dolby, asaf, "encoded spatial masters share one decision")

        // Ordinary stereo — head-locked by default.
        XCTAssertEqual(AudioRuntimeRouting.route(playbackModel: .headLocked,
                                                 hasSpatialAttachment: false),
                       .supported(.headLocked))

        // An ordinary file attached to an emitter — positional.
        XCTAssertEqual(AudioRuntimeRouting.route(playbackModel: .positional,
                                                 hasSpatialAttachment: true),
                       .supported(.positional))
    }

    // MARK: - Occurrence identity is not routing

    /// ROUTING IS PER CUE, NOT PER FILE. Two occurrences of one source with
    /// different models are two decisions — the router reads the action, never
    /// the filename, so it cannot collapse them.
    func testTwoOccurrencesOfOneFileRouteIndependently() {
        var headLocked = AudioActionDTO(file: "DoorKnock.wav", channel: "audio-door-1")
        headLocked.playbackModel = .headLocked

        var positional = AudioActionDTO(file: "DoorKnock.wav", channel: "audio-door-2")
        positional.playbackModel = .positional
        positional.spatial = SpatialAudioConfigDTO(attachToEntity: "Door Emitter")

        XCTAssertEqual(AudioRuntimeRouting.route(for: headLocked), .supported(.headLocked))
        XCTAssertEqual(AudioRuntimeRouting.route(for: positional), .supported(.positional))
    }
}

// MARK: - Two pipelines, two meanings of "spatial"

/// The final routing model: a POSITIONAL SOURCE is an object in the scene with
/// X/Y/Z; an ENCODED SPATIAL MASTER already contains its own spatial scene and
/// is handed to the system player whole. Both are "spatial"; they are not the
/// same idea, and collapsing them is what double-spatialization is.
final class AudioPipelineRoutingTests: XCTestCase {

    private func cue(
        _ model: AudioPlaybackModel?, emitter: String? = nil,
        loop: Bool = false, loopConfig: LoopConfigDTO? = nil
    ) -> AudioActionDTO {
        var audio = AudioActionDTO(file: "x.mp4", channel: "audio-x")
        audio.playbackModel = model
        audio.loop = loop
        audio.loopConfig = loopConfig
        if let emitter { audio.spatial = SpatialAudioConfigDTO(attachToEntity: emitter) }
        return audio
    }

    /// 1. Positional stays on the RealityKit source path.
    func testPositionalUsesTheSceneSourcePipeline() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(.positional, emitter: "E")),
                       .supported(.positional))
    }

    /// 2. Head-locked stays on the interactive non-positional path.
    func testHeadLockedUsesTheNonPositionalPipeline() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(.headLocked)),
                       .supported(.headLocked))
    }

    /// 3 & 4. ASAF and Dolby — encoded masters — go to the system player, and
    /// are SUPPORTED there rather than degraded.
    func testEncodedSpatialMastersUseTheSystemMediaPipeline() {
        let routed = AudioRuntimeRouting.route(for: cue(.spatialMix))
        XCTAssertEqual(routed, .supported(.systemSpatialMedia))
        XCTAssertFalse(routed.isFallback, "an encoded master is played, not degraded")
        XCTAssertTrue(AudioRuntimeRouting.capability(of: .spatialMix).faithfulPlayback)
    }

    /// 5. A recorder's ambisonic WAV is neither an encoded master nor a point
    /// source. Declared as needing preparation, not disguised.
    func testSceneBasedIsDeclaredAsNeedingPreparation() {
        let routed = AudioRuntimeRouting.route(for: cue(.sceneBased))
        guard case .fallback(_, let from, let reason) = routed else {
            return XCTFail("scene-based must not claim to be supported")
        }
        XCTAssertEqual(from, .sceneBased)
        XCTAssertFalse(reason.isEmpty)
        XCTAssertFalse(AudioRuntimeRouting.capability(of: .sceneBased).faithfulPlayback)
        XCTAssertTrue(
            AudioRuntimeRouting.capability(of: .sceneBased).note.contains("preparation"),
            "the author should be told what the source needs")
    }

    /// 6. LOOPING DOES NOT CHANGE THE ROUTE. It used to: `loopConfig` returned
    /// before any routing decision, so a looped positional cue played from
    /// nowhere and a looped master was flattened.
    func testLoopingDoesNotChangeTheRoute() {
        let config = LoopConfigDTO(loop: "body.wav")
        XCTAssertEqual(
            AudioRuntimeRouting.route(for: cue(.positional, emitter: "E", loopConfig: config)).route,
            .positional, "a looped positional cue is still positional")
        XCTAssertEqual(
            AudioRuntimeRouting.route(for: cue(.spatialMix, loop: true)).route,
            .systemSpatialMedia, "a looped master is still an encoded master")
        XCTAssertEqual(
            AudioRuntimeRouting.route(for: cue(.headLocked, loop: true)).route,
            .headLocked)
    }

    /// 7. The capability model the Inspector reads and the route the runtime
    /// takes are the same fact.
    func testInspectorCapabilityMatchesTheRuntimeRoute() {
        for model in AudioPlaybackModel.allCases {
            let routed = AudioRuntimeRouting.route(
                playbackModel: model, hasSpatialAttachment: model == .positional)
            XCTAssertEqual(AudioRuntimeRouting.capability(of: model).faithfulPlayback,
                           !routed.isFallback, "\(model.rawValue)")
        }
    }

    /// 8. NO ENCODED MASTER EVER RECEIVES AN XYZ EMITTER — even one left behind
    /// when the author switched models.
    func testAnEncodedMasterIsNeverGivenAnEmitter() {
        let routed = AudioRuntimeRouting.route(for: cue(.spatialMix, emitter: "Leftover"))
        XCTAssertEqual(routed.route, .systemSpatialMedia)
        XCTAssertNotEqual(routed.route, .positional)
    }

    /// 9. …and no positional cue is treated as an encoded master.
    func testAPositionalCueNeverBecomesAnEncodedMaster() {
        XCTAssertNotEqual(
            AudioRuntimeRouting.route(for: cue(.positional, emitter: "E")).route,
            .systemSpatialMedia)
    }

    /// SPATIAL PRESENTATION IS A LISTENING FRAME, NOT A LOCATION — offered for
    /// an encoded master and for nothing else.
    func testOnlyEncodedMastersOfferASpatialPresentation() {
        XCTAssertTrue(AudioRuntimeRouting.usesSpatialPresentation(.spatialMix))
        for model in [AudioPlaybackModel.headLocked, .positional, .sceneBased] {
            XCTAssertFalse(AudioRuntimeRouting.usesSpatialPresentation(model),
                           "\(model.rawValue) has no listening frame to choose")
        }
    }

    /// The presentation round-trips, and an unknown value degrades to
    /// head-tracked rather than throwing.
    func testSpatialPresentationRoundTripsAndDegrades() throws {
        var audio = AudioActionDTO(file: "m.mp4", channel: "c")
        audio.playbackModel = .spatialMix
        audio.spatialPresentation = .fixed
        let back = try JSONDecoder().decode(
            AudioActionDTO.self, from: JSONEncoder().encode(audio))
        XCTAssertEqual(back.spatialPresentation, .fixed)

        let unknown = try JSONDecoder().decode(
            AudioSpatialPresentation.self, from: Data("\"holographic\"".utf8))
        XCTAssertEqual(unknown, .headTracked)
    }

    /// An absent presentation stays absent, so existing bundles re-save
    /// byte-identically.
    func testAbsentPresentationEmitsNoKey() throws {
        let audio = AudioActionDTO(file: "m.mp4", channel: "c")
        let json = String(decoding: try JSONEncoder().encode(audio), as: UTF8.self)
        XCTAssertFalse(json.contains("spatialPresentation"))
    }
}

// MARK: - Spatial presentation actually reaches the player

/// THE CONTROL IS NOT DECORATIVE.
///
/// The first implementation switched on the presentation and did nothing with
/// it — `.headTracked` fell through to `break`, `.fixed` only logged — so the
/// Inspector configured metadata while the player kept the system default.
/// These pin the mapping that `SystemSpatialMediaPlayer` now applies to
/// `AVPlayer.intendedSpatialAudioExperience`.
final class SpatialPresentationWiringTests: XCTestCase {

    private func cue(
        _ model: AudioPlaybackModel?, presentation: AudioSpatialPresentation? = nil,
        emitter: String? = nil
    ) -> AudioActionDTO {
        var audio = AudioActionDTO(file: "master.mp4", channel: "audio-m")
        audio.playbackModel = model
        audio.spatialPresentation = presentation
        if let emitter { audio.spatial = SpatialAudioConfigDTO(attachToEntity: emitter) }
        return audio
    }

    /// 1. Head Tracked maps to the head-tracked intent.
    func testHeadTrackedMapsToTheHeadTrackedIntent() {
        XCTAssertEqual(AudioRuntimeRouting.spatialExperience(for: .headTracked), .headTracked)
        XCTAssertEqual(
            AudioRuntimeRouting.spatialExperience(for: cue(.spatialMix, presentation: .headTracked)),
            .headTracked)
    }

    /// 2. Fixed maps to the fixed intent — never to automatic, and never to a
    /// bypass, which would strip the spatial processing entirely.
    func testFixedMapsToTheFixedIntent() {
        XCTAssertEqual(AudioRuntimeRouting.spatialExperience(for: .fixed), .fixed)
        XCTAssertEqual(
            AudioRuntimeRouting.spatialExperience(for: cue(.spatialMix, presentation: .fixed)),
            .fixed)
    }

    /// Every authored presentation maps to a definite intent — none falls
    /// through to the system's choice.
    func testEveryPresentationHasAnExplicitIntent() {
        for presentation in AudioSpatialPresentation.allCases {
            XCTAssertTrue(
                AudioRuntimeRouting.SpatialExperienceIntent.allCases.contains(
                    AudioRuntimeRouting.spatialExperience(for: presentation)))
        }
    }

    /// 3. Spatial Mix uses pipeline B, and an unset presentation means
    /// head-tracked — what an encoded master is for.
    func testSpatialMixDefaultsToHeadTracked() {
        XCTAssertEqual(AudioRuntimeRouting.route(for: cue(.spatialMix)).route,
                       .systemSpatialMedia)
        XCTAssertEqual(AudioRuntimeRouting.spatialExperience(for: cue(.spatialMix)), .headTracked)
    }

    /// 4. PIPELINE A NEVER TOUCHES THIS. A positional cue's location comes from
    /// its emitter's transform, and an ordinary cue is not spatialised at all —
    /// neither may be handed a spatial-experience setting.
    func testPipelineACuesHaveNoSpatialExperience() {
        XCTAssertNil(AudioRuntimeRouting.spatialExperience(
            for: cue(.positional, presentation: .fixed, emitter: "E")),
            "a positional cue is placed by its emitter, not by a listening frame")
        XCTAssertNil(AudioRuntimeRouting.spatialExperience(
            for: cue(.headLocked, presentation: .fixed)))
        XCTAssertNil(AudioRuntimeRouting.spatialExperience(for: cue(.sceneBased)))
    }

    /// 5. Looping does not change the route or the intent — a looped master is
    /// still an encoded master with the author's listening frame.
    func testLoopingPreservesRouteAndPresentation() {
        var looped = cue(.spatialMix, presentation: .fixed)
        looped.loop = true
        XCTAssertEqual(AudioRuntimeRouting.route(for: looped).route, .systemSpatialMedia)
        XCTAssertEqual(AudioRuntimeRouting.spatialExperience(for: looped), .fixed)
    }

    /// 6. Persistence: the choice survives a document round trip, and still
    /// maps to the same intent afterwards.
    func testPresentationSurvivesSaveAndReopen() throws {
        for presentation in AudioSpatialPresentation.allCases {
            let saved = cue(.spatialMix, presentation: presentation)
            let reopened = try JSONDecoder().decode(
                AudioActionDTO.self, from: JSONEncoder().encode(saved))
            XCTAssertEqual(reopened.spatialPresentation, presentation)
            XCTAssertEqual(AudioRuntimeRouting.spatialExperience(for: reopened),
                           AudioRuntimeRouting.spatialExperience(for: presentation))
        }
    }
}
