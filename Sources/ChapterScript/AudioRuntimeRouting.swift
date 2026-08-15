//
//  AudioRuntimeRouting.swift
//  ChapterScript
//
//  HOW AN AUTHORED PLAYBACK MODEL BECOMES A PLAYBACK PATH — the one decision.
//
//  THE GAP THIS CLOSES. `SpatialAudioManager.play(action:)` routed on a single
//  test:
//
//      if action.spatial != nil { playSpatial(...) } else { playAmbient(...) }
//
//  and the authored `playbackModel` never reached the runtime at all — the
//  DTO→runtime bridge copied eleven fields and not that one. So an ambisonic
//  bed, an Apple Spatial Audio master and an ordinary stereo cue all took the
//  same path. `spatial != nil` answers "is there attachment metadata", which is
//  not the same question as "what are the playback semantics".
//
//  WHY THE DECISION LIVES IN THE FORMAT PACKAGE. It is a pure function of
//  authored state, both the editor and the player need the same answer (the
//  editor to tell an author what will happen, the player to do it), and here it
//  is testable on macOS — ChapterPlayer is visionOS-only and has no test
//  target. Execution stays in ChapterPlayer; only the decision is shared.
//
//  WHAT THE PLATFORM ACTUALLY DOES, measured rather than assumed. Opening the
//  owner's real files with `AVAudioFile` — the same API the runtime's ambient
//  path uses — gives:
//
//      Ambisonic.WAV      8 ch, 96 kHz, layout DiscreteInOrder(8)
//      ASAF.mp4          18 ch, 48 kHz, layout DiscreteInOrder(18)
//      Dolby Spatial.mp4  6 ch, 48 kHz, layout MPEG_5_1_C
//      Intro 2.mp3        2 ch, no layout
//
//  So AVAudioEngine hands back RAW CHANNELS, not a spatial render: no ambisonic
//  decode (the file is not even reported as ambisonic — our BWF inference is
//  the only evidence), APAC flattened to eighteen discrete channels, and the
//  Atmos JOC objects already gone, leaving a 5.1 bed. Feeding any of those into
//  a stereo mixer is a downmix, not a reproduction.
//
//  That is a PLATFORM BOUNDARY for this architecture, not a Maestro bug and not
//  merely unwritten code: scene-based and object-based masters need system
//  media playback, which is a different pipeline from the sample-accurate
//  `AVAudioEngine` graph the Sequence clock drives. Recording it here means the
//  next person does not rediscover it by ear.
//

import Foundation

public enum AudioRuntimeRouting {

    /// The playback paths the runtime actually has.
    public enum Route: String, Sendable, Equatable, CaseIterable {
        /// Straight to the mixer, unspatialised. The runtime calls this
        /// "ambient", which is a misleading name for a correct behaviour:
        /// `AVAudioPlayerNode` → bus mixer → main mixer, with no environment
        /// node anywhere, so nothing tracks the head and nothing is placed.
        /// That IS head-locked.
        case headLocked
        /// A RealityKit audio source parented to the emitter entity, so the
        /// authored (and animated) transform is the location. One XYZ
        /// representation, not a second one.
        case positional
        /// A decoded sound field, orientation-tracked, not placed.
        case sceneBased
        /// THE ENCODED ASSET, HANDED TO THE SYSTEM PLAYER INTACT.
        ///
        /// Never opened as sample buffers first — that is what flattens APAC to
        /// discrete channels and strips Atmos objects down to a 5.1 bed. The
        /// master keeps its own spatial scene and the system renders it; Maestro
        /// contributes the listening frame (`AudioSpatialPresentation`) and the
        /// narrative gain, and nothing else.
        case systemSpatialMedia
    }

    /// Whether the runtime can honour the authored intent on that path.
    ///
    /// `fallback` is deliberately distinct from `supported`. Silently taking an
    /// unrelated path is the defect this file exists to remove; taking a
    /// declared, reasoned, logged one is a product decision.
    public enum Support: Sendable, Equatable {
        case supported(Route)
        /// The authored model cannot be reproduced; this is the path taken
        /// instead, and why. The author's intent is preserved in the document
        /// — only the playback is degraded.
        case fallback(Route, from: AudioPlaybackModel, reason: String)

        public var route: Route {
            switch self {
            case .supported(let r):      return r
            case .fallback(let r, _, _): return r
            }
        }

        public var isFallback: Bool {
            if case .fallback = self { return true }
            return false
        }
    }

    // MARK: - The decision

    /// Route one authored cue.
    ///
    /// `playbackModel` is the authority when present. When it is absent — every
    /// document written before the field existed — the LEGACY inference applies:
    /// an attachment means positional, anything else is what the old code did
    /// with it, which was the unspatialised path. That is the historic
    /// behaviour exactly, so no existing chapter changes how it sounds. An old
    /// stereo cue is never promoted to ambisonic or spatial-mix by guesswork.
    public static func route(
        playbackModel: AudioPlaybackModel?,
        hasSpatialAttachment: Bool
    ) -> Support {
        let model = playbackModel ?? (hasSpatialAttachment ? .positional : .headLocked)

        switch model {
        case .headLocked:
            return .supported(.headLocked)

        case .positional:
            // A cue authored positional with nothing to attach to has no
            // location to be at. Rather than invent an origin, say so and play
            // it head-locked — audible, and honest about what happened.
            guard hasSpatialAttachment else {
                return .fallback(.headLocked, from: .positional,
                                 reason: "positional cue has no emitter or position to play from")
            }
            return .supported(.positional)

        case .spatialMix:
            // SUPPORTED, on the other pipeline. An encoded master goes to the
            // system player whole; Maestro never decodes it and never gives it
            // a location.
            return .supported(.systemSpatialMedia)

        case .sceneBased:
            // A recorder's ambisonic WAV is raw PCM channels, not an encoded
            // master — the system player has nothing to decode and the audio
            // graph has no ambisonic decoder. Neither pipeline can carry it
            // faithfully as it stands, so it is declared, not disguised.
            return .fallback(.headLocked, from: .sceneBased, reason: sceneBasedReason)
        }
    }

    /// Convenience for a whole authored action.
    public static func route(for audio: AudioActionDTO) -> Support {
        route(playbackModel: audio.playbackModel,
              hasSpatialAttachment: audio.spatial?.attachToEntity != nil
                                 || audio.spatial?.position != nil)
    }

    // MARK: - Why the two are not supported

    public static let sceneBasedReason = """
        Scene-based (ambisonic) playback needs a decoder. A recorder's ambisonic \
        WAV arrives as discrete PCM channels — the file is not even reported as \
        ambisonic, so the audio graph downmixes rather than decodes, and the \
        system player has no encoded scene to render. The source needs \
        preparation into a form one of the two pipelines can carry.
        """

    public static let sceneBasedPreparationNote = """
        Requires preparation for faithful Vision Pro scene-based playback.
        """

    // MARK: - Capability matrix

    /// What is true today for each authored model, kept in one place so the
    /// editor, the runtime and `docs/VISIONOS_AUDIO_QA.md` cannot drift.
    ///
    /// DEVICE VERIFICATION IS DELIBERATELY ABSENT. Nothing here can be
    /// perceptually verified without a headset, so nothing here claims to be.
    public struct Capability: Sendable, Equatable {
        public let model: AudioPlaybackModel
        /// The editor can author it.
        public let authoring: Bool
        /// The runtime dispatches it to a path chosen for it.
        public let routing: Bool
        /// The runtime reproduces the authored intent.
        public let faithfulPlayback: Bool
        /// One line an author could be shown.
        public let note: String
    }

    public static func capability(of model: AudioPlaybackModel) -> Capability {
        switch model {
        case .headLocked:
            return Capability(model: model, authoring: true, routing: true,
                              faithfulPlayback: true,
                              note: "Plays unspatialised, as authored.")
        case .positional:
            return Capability(model: model, authoring: true, routing: true,
                              faithfulPlayback: true,
                              note: "Plays from its emitter, following the authored transform.")
        case .sceneBased:
            return Capability(model: model, authoring: true, routing: true,
                              faithfulPlayback: false,
                              note: "Requires preparation for faithful Vision Pro scene-based playback — plays downmixed for now.")
        case .spatialMix:
            return Capability(model: model, authoring: true, routing: true,
                              faithfulPlayback: true,
                              note: "Played by the system spatial renderer, which keeps the mix intact.")
        }
    }

    /// Models the runtime cannot yet reproduce faithfully. The editor can use
    /// this for a quiet advisory without becoming a compatibility dashboard.
    /// True when the model's presentation is a LISTENING FRAME rather than a
    /// location — i.e. the Inspector should offer Spatial Presentation and not
    /// X/Y/Z. The one place that answers it, so UI and runtime agree.
    public static func usesSpatialPresentation(_ model: AudioPlaybackModel) -> Bool {
        model == .spatialMix
    }

    public static var modelsAwaitingFaithfulPlayback: [AudioPlaybackModel] {
        AudioPlaybackModel.allCases.filter { !capability(of: $0).faithfulPlayback }
    }
}
