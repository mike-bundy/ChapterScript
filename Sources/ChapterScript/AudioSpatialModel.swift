//
//  AudioSpatialModel.swift
//  ChapterScript
//
//  WHAT AUDIO IS, AND WHAT MAESTRO DOES WITH IT — the persisted half.
//
//  These types live in the FORMAT package because documents contain them: an
//  authored playback model rides on `AudioActionDTO`, and an author's
//  interpretation of an ambiguous source is chapter truth that must survive a
//  save, reach a peer, and open on a runtime. The probe's READ-OUT
//  (`MaestroKit.AudioFormatIdentity`) is not persisted and stays out of here.
//
//  The distinction this file exists to hold open:
//
//      AudioSpatialForm     what the CHANNELS MEAN   — read from the file
//      AudioPlaybackModel   what MAESTRO DOES        — chosen by the author
//
//  They are not the same question and the second is constrained by the first.
//  A Dolby Atmos master and a mono footstep are both "spatial audio" and have
//  almost nothing else in common; collapsing them into one flag is what makes
//  an editor offer Position X/Y/Z on a finished mix. See
//  `docs/AUDIO_ARCHITECTURE.md` §4 for the full matrix and the measured
//  evidence behind it.
//

import Foundation

// MARK: - Provenance

/// How sure are we, and who says so?
///
/// The first three are ordered by authority: a `.userDefined` interpretation
/// overrides an `.inferred` one, which overrides nothing at all. `.detected`
/// is never overridden as a FACT — an author can reinterpret what four
/// channels mean, but not how many channels there are.
public enum AudioFactSource: String, Codable, Sendable, Equatable, CaseIterable {
    /// Read from the format description, channel layout or container. The file
    /// says so.
    case detected
    /// Derived from a weaker signal — vendor metadata, a channel-count
    /// convention, a filename. Plausible, not proven.
    case inferred
    /// The author told us. Beats detection for INTERPRETATION only.
    case userDefined
    /// Not determinable.
    case unknown

    public var label: String {
        switch self {
        case .detected:    return "detected"
        case .inferred:    return "inferred"
        case .userDefined: return "set by you"
        case .unknown:     return "unknown"
        }
    }

    /// True when this fact should be presented as certain.
    public var isCertain: Bool { self == .detected }
}

// MARK: - Ambisonics

/// Channel ordering convention for an ambisonic stream.
public enum AmbisonicOrdering: String, Codable, Sendable, Equatable, CaseIterable {
    /// Ambisonic Channel Number — the modern convention, and what AmbiX uses.
    case acn
    /// Furse-Malham — legacy, first order only, W X Y Z.
    case fuma

    public var label: String {
        switch self {
        case .acn:  return "ACN"
        case .fuma: return "FuMa"
        }
    }
}

/// Normalization convention for an ambisonic stream.
public enum AmbisonicNormalization: String, Codable, Sendable, Equatable, CaseIterable {
    case sn3d
    case n3d
    /// FuMa's own normalization, which travels with FuMa ordering.
    case maxN

    public var label: String {
        switch self {
        case .sn3d: return "SN3D"
        case .n3d:  return "N3D"
        case .maxN: return "MaxN"
        }
    }
}

/// A described ambisonic stream. `order` 1 is FOA, 2 is SOA, 3+ is HOA.
public struct AmbisonicSpec: Codable, Sendable, Equatable {
    public var order: Int
    public var ordering: AmbisonicOrdering
    public var normalization: AmbisonicNormalization
    /// Index of the first ambisonic channel within the file. Non-zero for
    /// field recorders that write a B-format bed FOLLOWED by raw capsules
    /// (the owner's Zoom F8 does exactly this — see the WAV case in
    /// `docs/AUDIO_ARCHITECTURE.md`), where channels 4…7 are A-format and
    /// must NOT be fed to an ambisonic decoder.
    public var channelOffset: Int

    public init(
        order: Int,
        ordering: AmbisonicOrdering = .acn,
        normalization: AmbisonicNormalization = .sn3d,
        channelOffset: Int = 0
    ) {
        self.order = max(1, order)
        self.ordering = ordering
        self.normalization = normalization
        self.channelOffset = max(0, channelOffset)
    }

    /// Channels a complete stream of this order occupies: (order + 1)².
    public var channelCount: Int { (order + 1) * (order + 1) }

    /// The ambisonic order a channel count implies, or nil when the count is
    /// not a perfect square. 4 → 1, 9 → 2, 16 → 3.
    ///
    /// This is a NECESSARY condition, never a sufficient one: a 4-channel file
    /// may be FOA or may be four unrelated microphones, and this function
    /// cannot tell the difference. Callers must record the result as
    /// `.inferred`.
    public static func order(forChannelCount count: Int) -> Int? {
        guard count >= 4 else { return nil }
        let root = Int(Double(count).squareRoot().rounded())
        guard root * root == count else { return nil }
        return root - 1
    }

    public var label: String {
        switch order {
        case 1:  return "First Order Ambisonics"
        case 2:  return "Second Order Ambisonics"
        default: return "Third Order Ambisonics".replacingOccurrences(
            of: "Third", with: ordinal(order)
        )
        }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 3: return "Third"
        case 4: return "Fourth"
        case 5: return "Fifth"
        case 6: return "Sixth"
        case 7: return "Seventh"
        default: return "Order-\(n)"
        }
    }
}

// MARK: - Spatial form

/// WHAT THE CHANNELS MEAN. The single most important distinction in this
/// file, and the one the product rule rests on: these are not degrees of a
/// "spatial" flag, they are different KINDS of sound with different authoring
/// semantics. Flattening them into `spatial = true` is what makes an editor
/// offer Position X/Y/Z on a Dolby Atmos mix.
public enum AudioSpatialForm: Codable, Sendable, Equatable {

    /// One channel. The only form that is unambiguously a point source, and
    /// therefore the only one positional playback is a natural fit for.
    case mono

    /// Two channels, conventional L/R.
    case stereo

    /// A named channel bed — 5.1, 7.1, quad. Carries its layout's name.
    case channelBed(layout: String, channels: Int)

    /// A surrounding sound FIELD. Not a point source: it has an orientation,
    /// not a position.
    case ambisonic(AmbisonicSpec)

    /// Apple Spatial Audio Format, as carried by APAC: a higher-order
    /// ambisonic bed PLUS discrete audio objects, in one stream. Both halves
    /// are real and the pair is self-describing — the objects carry their own
    /// positions inside the bitstream, which is exactly why Maestro must not
    /// impose one.
    case appleSpatial(hoaOrder: Int?, objectCount: Int)

    /// Dolby Atmos: E-AC-3 with Joint Object Coding, or a decoded Atmos bed.
    /// `base` is the layout the stream decodes to without JOC (5.1 here).
    case dolbyAtmos(base: String)

    /// More than two channels with no layout and no metadata to explain them.
    /// The honest answer for a bare multitrack WAV, and the state that makes
    /// the "Interpret Audio…" command necessary rather than decorative.
    case unknownMultichannel(channels: Int)

    /// Channels we could not even count.
    case unknown

    /// A short label for a badge — the Timeline's compact identity.
    public var badge: String {
        switch self {
        case .mono:                       return "MONO"
        case .stereo:                     return "STEREO"
        case .channelBed(let layout, _):  return layout.uppercased()
        case .ambisonic(let spec):
            switch spec.order {
            case 1:  return "FOA"
            case 2:  return "SOA"
            default: return "HOA\(spec.order)"
            }
        case .appleSpatial:               return "ASAF"
        case .dolbyAtmos:                 return "ATMOS"
        case .unknownMultichannel(let n): return "\(n) CH"
        case .unknown:                    return "AUDIO"
        }
    }

    /// The Inspector's readable name.
    public var displayName: String {
        switch self {
        case .mono:                       return "Mono"
        case .stereo:                     return "Stereo"
        case .channelBed(let layout, _):  return layout
        case .ambisonic(let spec):        return spec.label
        case .appleSpatial(let order, let objects):
            var parts: [String] = ["Apple Spatial Audio"]
            if let order { parts.append("\(ordinalWord(order))-order bed") }
            if objects > 0 { parts.append("\(objects) object\(objects == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        case .dolbyAtmos(let base):       return "Dolby Atmos (\(base) base)"
        case .unknownMultichannel(let n): return "\(n)-channel, interpretation unknown"
        case .unknown:                    return "Unknown"
        }
    }

    private func ordinalWord(_ n: Int) -> String {
        switch n {
        case 1: return "First"
        case 2: return "Second"
        case 3: return "Third"
        case 4: return "Fourth"
        default: return "Order-\(n)"
        }
    }

    /// True when the form describes a sound field or an already-authored
    /// spatial mix — something that already knows where its content is, and
    /// must therefore never be treated as a point source.
    public var carriesOwnSpatialisation: Bool {
        switch self {
        case .ambisonic, .appleSpatial, .dolbyAtmos: return true
        case .mono, .stereo, .channelBed, .unknownMultichannel, .unknown: return false
        }
    }

    // MARK: Coding
    //
    // Written by hand rather than synthesized. The synthesized shape for an
    // enum with associated values nests them under `_0`, which is both
    // unreadable in a document someone opens in an editor and tied to
    // declaration order — reordering a case's parameters would silently break
    // every saved interpretation. A named `kind` plus named fields survives
    // that, and lets an unknown `kind` DEGRADE instead of throwing, which is
    // the rule the rest of the format follows.

    private enum CodingKeys: String, CodingKey {
        case kind, layout, channels, order, ordering, normalization
        case channelOffset, hoaOrder, objectCount, base
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mono:
            try c.encode("mono", forKey: .kind)
        case .stereo:
            try c.encode("stereo", forKey: .kind)
        case .channelBed(let layout, let channels):
            try c.encode("channelBed", forKey: .kind)
            try c.encode(layout, forKey: .layout)
            try c.encode(channels, forKey: .channels)
        case .ambisonic(let spec):
            try c.encode("ambisonic", forKey: .kind)
            try c.encode(spec.order, forKey: .order)
            try c.encode(spec.ordering, forKey: .ordering)
            try c.encode(spec.normalization, forKey: .normalization)
            if spec.channelOffset != 0 {
                try c.encode(spec.channelOffset, forKey: .channelOffset)
            }
        case .appleSpatial(let hoaOrder, let objectCount):
            try c.encode("appleSpatial", forKey: .kind)
            try c.encodeIfPresent(hoaOrder, forKey: .hoaOrder)
            try c.encode(objectCount, forKey: .objectCount)
        case .dolbyAtmos(let base):
            try c.encode("dolbyAtmos", forKey: .kind)
            try c.encode(base, forKey: .base)
        case .unknownMultichannel(let channels):
            try c.encode("unknownMultichannel", forKey: .kind)
            try c.encode(channels, forKey: .channels)
        case .unknown:
            try c.encode("unknown", forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "mono":   self = .mono
        case "stereo": self = .stereo
        case "channelBed":
            self = .channelBed(
                layout: try c.decodeIfPresent(String.self, forKey: .layout) ?? "Multichannel",
                channels: try c.decodeIfPresent(Int.self, forKey: .channels) ?? 0
            )
        case "ambisonic":
            self = .ambisonic(AmbisonicSpec(
                order: try c.decodeIfPresent(Int.self, forKey: .order) ?? 1,
                ordering: try c.decodeIfPresent(AmbisonicOrdering.self, forKey: .ordering) ?? .acn,
                normalization: try c.decodeIfPresent(
                    AmbisonicNormalization.self, forKey: .normalization
                ) ?? .sn3d,
                channelOffset: try c.decodeIfPresent(Int.self, forKey: .channelOffset) ?? 0
            ))
        case "appleSpatial":
            self = .appleSpatial(
                hoaOrder: try c.decodeIfPresent(Int.self, forKey: .hoaOrder),
                objectCount: try c.decodeIfPresent(Int.self, forKey: .objectCount) ?? 0
            )
        case "dolbyAtmos":
            self = .dolbyAtmos(base: try c.decodeIfPresent(String.self, forKey: .base) ?? "5.1")
        case "unknownMultichannel":
            self = .unknownMultichannel(
                channels: try c.decodeIfPresent(Int.self, forKey: .channels) ?? 0
            )
        default:
            // A form written by a newer tool. `.unknown` is the honest
            // landing place: it offers head-locked playback and invites the
            // author to interpret, which is strictly better than guessing.
            self = .unknown
        }
    }
}

// MARK: - Interpretation

/// THE AUTHOR'S OVERRIDE, kept as a SEPARATE FACT from detection.
///
/// The rule this type enforces: a user interpretation never overwrites the
/// probe's reading. They are stored side by side, so "the file reports eight
/// discrete PCM channels" and "the author says channels 0…3 are AmbiX FOA"
/// remain two statements that can both be true, and the override can be
/// removed to get back to what the file actually says.
///
/// Persisted per SOURCE, because it describes the bytes. A trim, a move or a
/// second occurrence cannot change what a codec is.
public struct AudioInterpretation: Codable, Sendable, Equatable {

    /// nil means "Automatic" — defer entirely to detection.
    public var spatialForm: AudioSpatialForm?

    /// The playback model the author chose, when they chose one. nil means
    /// "use the default this form implies".
    public var playbackModel: AudioPlaybackModel?

    public init(spatialForm: AudioSpatialForm? = nil, playbackModel: AudioPlaybackModel? = nil) {
        self.spatialForm = spatialForm
        self.playbackModel = playbackModel
    }

    public var isAutomatic: Bool { spatialForm == nil && playbackModel == nil }

    /// Resolve detection against the override, keeping provenance honest: an
    /// overridden form is reported as `.userDefined`, never as `.detected`.
    ///
    /// Takes the two detected facts rather than the probe's read-out, because
    /// `AudioFormatIdentity` lives in MaestroKit and the format package must
    /// not depend on it. MaestroKit adds the convenience overload that passes
    /// an identity straight in.
    public func resolved(
        detected form: AudioSpatialForm,
        source: AudioFactSource
    ) -> (form: AudioSpatialForm, source: AudioFactSource) {
        if let spatialForm {
            return (spatialForm, .userDefined)
        }
        return (form, source)
    }

    /// The playback model to use for an occurrence that has not chosen one,
    /// given the resolved form. Always a model the form actually admits.
    public func resolvedPlaybackModel(
        detected form: AudioSpatialForm,
        source: AudioFactSource
    ) -> AudioPlaybackModel {
        resolved(detected: form, source: source).form.coerce(playbackModel)
    }
}

// MARK: - Playback model

/// HOW MAESTRO REPRODUCES THE SOUND. Authored, not detected — the same file
/// can legitimately be head-locked narration in one chapter and a positional
/// source in another.
///
/// This enum is what the Inspector, the Viewer and the runtime all branch on,
/// and the reason the third architectural rule holds: the controls an audio
/// clip offers are a function of its MODEL, and the models a clip may choose
/// are a function of its FORM. Neither step ever consults a filename.
/// HOW AN ENCODED SPATIAL MASTER IS PRESENTED TO THE LISTENER.
///
/// A LISTENING FRAME, NOT A LOCATION. This is the distinction the whole
/// two-pipeline design turns on and it is easy to lose: a `.spatialMix` master
/// already contains its own spatial scene, so it has no X/Y/Z — asking "where
/// is the Atmos mix" is a category error. What an author CAN decide is whether
/// that scene rotates with the head or stays put in the room.
///
/// Contrast `.positional`, where X/Y/Z is a real source location and this
/// property is meaningless. Both are "spatial"; they are not the same idea.
public enum AudioSpatialPresentation: String, Codable, Sendable, CaseIterable, Equatable {
    /// The mix is anchored to the world: turning the head changes which part
    /// of the scene is in front of you, as at a real location.
    case headTracked
    /// The mix travels with the listener, like headphones. Correct for a score
    /// or a narration bed that should not swing when the wearer looks away.
    case fixed

    public var displayName: String {
        switch self {
        case .headTracked: return "Head Tracked"
        case .fixed:       return "Fixed"
        }
    }

    public var explanation: String {
        switch self {
        case .headTracked:
            return "The mix stays anchored to the room. Turning your head changes what is in front of you."
        case .fixed:
            return "The mix travels with you, like headphones."
        }
    }

    /// Unknown values decode as head-tracked — the same tolerant-decode rule as
    /// `GateType` and `ImmersiveField`, and the right default for a master that
    /// was authored with a presentation a newer tool understands.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AudioSpatialPresentation(rawValue: raw) ?? .headTracked
    }
}

public enum AudioPlaybackModel: String, Codable, Sendable, Equatable, CaseIterable {

    /// Follows the listener. Music, narration, a conventional stereo mix.
    case headLocked

    /// A point source in the authored world. Has a position, and that position
    /// can move — this is the only model that gets an emitter and XYZ keys.
    case positional

    /// A surrounding sound field. Has an ORIENTATION, not a position.
    case sceneBased

    /// An already-authored spatial mix whose spatialisation lives in the
    /// stream. Maestro rides its level and otherwise keeps its hands off.
    case spatialMix

    public var displayName: String {
        switch self {
        case .headLocked: return "Head Locked"
        case .positional: return "Positional"
        case .sceneBased: return "Scene Based"
        case .spatialMix: return "Spatial Mix"
        }
    }

    public var explanation: String {
        switch self {
        case .headLocked:
            return "Follows the listener. Music, narration and conventional mixes."
        case .positional:
            return "A sound source at a place in the scene. Can be moved and keyframed."
        case .sceneBased:
            return "A surrounding sound field. Can be rotated, not placed."
        case .spatialMix:
            return "The mix carries its own spatial information. Level only."
        }
    }

    /// Unknown values decode as `.headLocked` rather than throwing — the same
    /// forward-compatibility rule `GateType` and `ImmersiveField` follow. Head
    /// locked is the safe degradation: a sound in the wrong PLACE is a bug an
    /// author can hear, a sound that fails to load is a broken chapter.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AudioPlaybackModel(rawValue: raw) ?? .headLocked
    }

    // MARK: Which controls this model admits

    /// Gain is universal. Every model has a level.
    public var supportsGain: Bool { true }

    /// Stereo pan is a CHANNEL-BASED operation. It is meaningful for a
    /// head-locked stereo or mono track and meaningless — actively destructive
    /// — for a sound field or an object mix, where "left" is not a channel
    /// but a direction the renderer derives.
    public var supportsPan: Bool { self == .headLocked }

    /// Only a point source has a position.
    public var supportsPosition: Bool { self == .positional }

    /// A field has an orientation. A point source only has one if it is
    /// directional, which is a per-emitter property, not a model property —
    /// see `AudioEmitterSpec.directivity`.
    public var supportsFieldOrientation: Bool { self == .sceneBased }

    /// Distance attenuation applies where there is a distance to attenuate
    /// over, which means a point source and nothing else.
    public var supportsAttenuation: Bool { self == .positional }
}

// MARK: - Which models a form may choose

public extension AudioSpatialForm {

    /// The playback models that are VALID for this form, most appropriate
    /// first. The Inspector shows exactly these and no others — "only modes
    /// that are actually valid for the media".
    ///
    /// The judgements, and why:
    ///
    /// - **Mono** can be anything. It is the classic point source, but a mono
    ///   narration track is head-locked, so both are offered.
    /// - **Stereo** defaults to head-locked. It is offered as positional too,
    ///   because placing a stereo source in a scene is a real technique — the
    ///   renderer folds it down — but it is not the default.
    /// - **A channel bed** (5.1/7.1) is a mix. Head-locked is the only honest
    ///   reproduction; treating six channels as one point is nonsense.
    /// - **Ambisonic** is scene-based and nothing else. A sound field has no
    ///   position, and offering "Positional" would invite an author to key XYZ
    ///   on something that cannot have one.
    /// - **ASAF and Atmos** are spatial mixes. They already contain their own
    ///   spatialisation; the ONLY thing Maestro may do is ride the level.
    /// - **Unknown multichannel** gets head-locked only, until the author
    ///   interprets it. That is the point of the unknown state — it does not
    ///   guess, it asks.
    var validPlaybackModels: [AudioPlaybackModel] {
        switch self {
        case .mono:                 return [.positional, .headLocked]
        case .stereo:               return [.headLocked, .positional]
        case .channelBed:           return [.headLocked]
        case .ambisonic:            return [.sceneBased]
        case .appleSpatial:         return [.spatialMix]
        case .dolbyAtmos:           return [.spatialMix]
        case .unknownMultichannel:  return [.headLocked]
        case .unknown:              return [.headLocked]
        }
    }

    /// The model used when the author has not chosen one.
    var defaultPlaybackModel: AudioPlaybackModel {
        validPlaybackModels.first ?? .headLocked
    }

    /// Guard for the authored value: an out-of-range model falls back to the
    /// default rather than being honoured. This is what stops a document that
    /// once said "positional" from keeping XYZ semantics after its source was
    /// reinterpreted as ambisonic.
    func coerce(_ model: AudioPlaybackModel?) -> AudioPlaybackModel {
        guard let model, validPlaybackModels.contains(model) else {
            return defaultPlaybackModel
        }
        return model
    }
}
