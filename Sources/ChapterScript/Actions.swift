import Foundation

// MARK: - Move

public struct MoveActionDTO: Codable, Sendable, Equatable {
    public var entity: String
    public var positionOffset: Vec3?
    public var absolutePosition: Vec3?
    public var headRelativePosition: Vec3?
    public var headYOnly: Bool
    public var scaleMultiplier: Float?
    public var absoluteScale: Vec3?
    /// Final orientation as Euler angles in DEGREES (YXZ order, matching
    /// the editor's transform convention). When set, the entity animates
    /// to this absolute orientation over `duration`.
    public var absoluteRotation: Vec3?
    /// Relative orientation change as Euler angles in DEGREES (YXZ),
    /// composed onto the entity's current orientation. Mutually exclusive
    /// with `absoluteRotation`; if both are set, absolute wins.
    public var rotationOffset: Vec3?
    public var duration: Double
    public var timing: StepTimingFunction

    public init(
        entity: String,
        positionOffset: Vec3? = nil,
        absolutePosition: Vec3? = nil,
        headRelativePosition: Vec3? = nil,
        headYOnly: Bool = false,
        scaleMultiplier: Float? = nil,
        absoluteScale: Vec3? = nil,
        absoluteRotation: Vec3? = nil,
        rotationOffset: Vec3? = nil,
        duration: Double = 1.0,
        timing: StepTimingFunction = .easeInOut
    ) {
        self.entity = entity
        self.positionOffset = positionOffset
        self.absolutePosition = absolutePosition
        self.headRelativePosition = headRelativePosition
        self.headYOnly = headYOnly
        self.scaleMultiplier = scaleMultiplier
        self.absoluteScale = absoluteScale
        self.absoluteRotation = absoluteRotation
        self.rotationOffset = rotationOffset
        self.duration = duration
        self.timing = timing
    }
}

// MARK: - Fade

public struct FadeActionDTO: Codable, Sendable, Equatable {
    public var entity: String
    public var opacity: Float
    public var duration: Double
    public var timing: StepTimingFunction

    public init(entity: String, opacity: Float, duration: Double = 1.0, timing: StepTimingFunction = .easeInOut) {
        self.entity = entity
        self.opacity = opacity
        self.duration = duration
        self.timing = timing
    }
}

// MARK: - Reveal

public struct RevealActionDTO: Codable, Sendable, Equatable {
    public var entity: String
    public var position: Vec3?
    public var headRelativePosition: Vec3?
    public var headYOnly: Bool
    public var scale: Vec3?
    public var fadeIn: Double
    /// When true, the revealed entity becomes directly manipulable by the
    /// viewer's hands on device (RealityKit `ManipulationComponent` —
    /// grab / move / rotate / scale). Optional (nil == off) so older
    /// documents decode unchanged and the key is omitted when unset.
    public var manipulable: Bool?

    public init(
        entity: String,
        position: Vec3? = nil,
        headRelativePosition: Vec3? = nil,
        headYOnly: Bool = false,
        scale: Vec3? = nil,
        fadeIn: Double = 0,
        manipulable: Bool? = nil
    ) {
        self.entity = entity
        self.position = position
        self.headRelativePosition = headRelativePosition
        self.headYOnly = headYOnly
        self.scale = scale
        self.fadeIn = fadeIn
        self.manipulable = manipulable
    }
}

// MARK: - Audio

public enum AudioScope: String, Codable, Sendable, Equatable {
    /// Bound to the sequence: the sound stops when the sequence does.
    case sequence
    /// Survives sequence changes.
    case ambient

    /// Tolerant decode, for the same reason `GateType` has one — plus one that is
    /// specific to this enum.
    ///
    /// `.sequence` was spelled `"segment"` in format v2, so the old vocabulary is  LEGACY-VOCAB
    /// baked into the DATA. `Migrator` rewrites it when a v2 *document* is opened,
    /// but documents are not the only way an `AudioActionDTO` arrives: live-sync
    /// `EditOp` payloads (`POST /ops`) are decoded directly and never see the
    /// migrator. A peer still running a v2 build would otherwise fail to apply —
    /// or, under a less careful decoder, land on `.ambient` and leave a sound
    /// playing past the end of its sequence.
    ///
    /// Unknown values resolve to `.sequence` rather than throwing, matching the
    /// format's forward-compatibility rule: a newer tool's document must not fail
    /// a whole load over one field.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "segment" {   // LEGACY-VOCAB: v2 spelling, must keep decoding
            self = .sequence
            return
        }
        self = AudioScope(rawValue: raw) ?? .sequence
    }
}

public struct AudioActionDTO: Codable, Sendable, Equatable {
    public var file: String
    public var channel: String
    public var scope: AudioScope
    public var volume: Float
    public var loop: Bool
    public var fadeIn: Double?
    public var spatial: SpatialAudioConfigDTO?
    public var category: String?
    public var crossfade: Double?
    public var loopConfig: LoopConfigDTO?
    /// Non-destructive source trim, seconds into the MASTER file where
    /// playback begins. `nil` (default) plays from the file's start — which
    /// is what every document written before audio had marks means.
    ///
    /// Same rules, same type and same wire shape as `VideoActionDTO`'s: see
    /// `MediaSourceRange`, and prefer the `sourceRange` accessor below to
    /// touching these two fields directly.
    public var sourceIn: Double?
    /// Non-destructive source trim, exclusive end in master-file seconds.
    /// `nil` (default) plays through the file's natural end. Looping loops
    /// the `[sourceIn, sourceOut)` window rather than the whole master.
    public var sourceOut: Double?

    /// HOW THIS OCCURRENCE IS REPRODUCED — head-locked, positional,
    /// scene-based or an already-authored spatial mix.
    ///
    /// Authored per OCCURRENCE, not per source, because the same file can
    /// legitimately be head-locked narration in one cue and a positional
    /// source in another. `nil` means "whatever this source's spatial form
    /// implies" — see `AudioSpatialForm.defaultPlaybackModel` — which is what
    /// every document written before this field means, so absent stays absent
    /// and existing bundles re-save byte-identically.
    ///
    /// This is the field the Inspector, the Viewer and the runtime branch on.
    /// It is NOT a spatial flag: `.positional` gets an emitter and XYZ keys,
    /// `.sceneBased` gets an orientation, `.spatialMix` gets a level and
    /// nothing else. See `docs/AUDIO_ARCHITECTURE.md` §4.
    public var playbackModel: AudioPlaybackModel?

    /// The listening frame for an ENCODED SPATIAL MASTER — head-tracked or
    /// fixed. Meaningful only for `.spatialMix`; ignored elsewhere.
    ///
    /// NOT A TRANSFORM. A mastered mix carries its own spatial scene, so it has
    /// no location; this says whether that scene is anchored to the room or
    /// travels with the listener. `.positional`'s X/Y/Z is the other idea and
    /// the two are deliberately separate fields.
    ///
    /// `nil` = head-tracked, which is what an encoded master is for. Absent
    /// stays absent, so existing bundles re-save byte-identically.
    public var spatialPresentation: AudioSpatialPresentation?

    /// CLIP MARKERS (FL-06) — see `VideoActionDTO.markers`. Same clock,
    /// same rules, because a sound's beat is a note about its source too.
    public var markers: [Marker]?
    /// THE RETIME CURVE (FL-13) — same rules as `VideoActionDTO.retime`.
    public var retime: RetimeCurve?
    /// Pitch under retime. Absent means `.followsSpeed`.
    public var pitch: PitchHandling?

    public init(
        file: String,
        channel: String,
        scope: AudioScope = .sequence,
        volume: Float = 1.0,
        loop: Bool = false,
        fadeIn: Double? = nil,
        spatial: SpatialAudioConfigDTO? = nil,
        category: String? = nil,
        crossfade: Double? = nil,
        loopConfig: LoopConfigDTO? = nil,
        sourceIn: Double? = nil,
        sourceOut: Double? = nil,
        playbackModel: AudioPlaybackModel? = nil,
        spatialPresentation: AudioSpatialPresentation? = nil,
        markers: [Marker]? = nil,
        retime: RetimeCurve? = nil,
        pitch: PitchHandling? = nil
    ) {
        self.file = file
        self.channel = channel
        self.scope = scope
        self.volume = volume
        self.loop = loop
        self.fadeIn = fadeIn
        self.spatial = spatial
        self.category = category
        self.crossfade = crossfade
        self.loopConfig = loopConfig
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.playbackModel = playbackModel
        self.spatialPresentation = spatialPresentation
        self.markers = markers
        self.retime = retime
        self.pitch = pitch
    }
}

public struct LoopConfigDTO: Codable, Sendable, Equatable {
    public var intro: String?
    public var loop: String
    public var outro: String?
    public var crossfade: Double

    public init(intro: String? = nil, loop: String, outro: String? = nil, crossfade: Double = 1.0) {
        self.intro = intro
        self.loop = loop
        self.outro = outro
        self.crossfade = crossfade
    }
}

/// Where a POSITIONAL occurrence sounds from.
///
/// `attachToEntity` is the load-bearing field, and it is how keyframed audio
/// motion works without a second animation system. The runtime
/// (`SpatialAudioManager.playSpatial`) parents the sound's entity to the named
/// entity; `EntityActionExecutor.applySequenceAnimationTracks` samples that
/// entity's `EntityAnimationTrack` every frame on the authored sequence clock;
/// RealityKit carries the child along. So a sound moves through the room
/// because its EMITTER is animated like any other scene object — same
/// evaluator, same Set Key, same Auto-Key, same graph editor, same gizmo, and
/// it holds still at a gate for the same reason a transform does.
///
/// `position` is the STATIC fallback for an emitter that never moves. Once an
/// entity is named, its animated transform wins — do not write both and expect
/// `position` to offset it.
///
/// Two occurrences of one file name two different emitters, which is what
/// makes their positions independent by construction rather than by a guard.
/// The full argument is `docs/AUDIO_ARCHITECTURE.md` §2.
public struct SpatialAudioConfigDTO: Codable, Sendable, Equatable {
    public var position: Vec3?
    public var attachToEntity: String?

    public init(position: Vec3? = nil, attachToEntity: String? = nil) {
        self.position = position
        self.attachToEntity = attachToEntity
    }
}

public struct SoundVariationDTO: Codable, Sendable, Equatable {
    public var pool: [String]
    public var mode: SelectionMode

    public init(pool: [String], mode: SelectionMode = .shuffle) {
        self.pool = pool
        self.mode = mode
    }
}

public enum SelectionMode: String, Codable, Sendable, Equatable {
    case random
    case sequential
    case shuffle
}

public struct AudioZoneDTO: Codable, Sendable, Equatable {
    public var id: String
    public var center: Vec3
    public var radius: Float
    public var falloffStart: Float
    public var audio: AudioActionDTO
    public var fadeInDuration: Double
    public var fadeOutDuration: Double

    public init(
        id: String,
        center: Vec3,
        radius: Float,
        falloffStart: Float,
        audio: AudioActionDTO,
        fadeInDuration: Double = 1.0,
        fadeOutDuration: Double = 1.0
    ) {
        self.id = id
        self.center = center
        self.radius = radius
        self.falloffStart = falloffStart
        self.audio = audio
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
    }
}

public enum AudioEffectDTO: Codable, Sendable, Equatable {
    case reverb(wetDryMix: Float)
    case compressor(threshold: Float, ratio: Float)

    private enum CodingKeys: String, CodingKey { case kind, wetDryMix, threshold, ratio }
    private enum Kind: String, Codable { case reverb, compressor }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reverb(let mix):
            try c.encode(Kind.reverb, forKey: .kind)
            try c.encode(mix, forKey: .wetDryMix)
        case .compressor(let threshold, let ratio):
            try c.encode(Kind.compressor, forKey: .kind)
            try c.encode(threshold, forKey: .threshold)
            try c.encode(ratio, forKey: .ratio)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .reverb:
            self = .reverb(wetDryMix: try c.decode(Float.self, forKey: .wetDryMix))
        case .compressor:
            self = .compressor(
                threshold: try c.decode(Float.self, forKey: .threshold),
                ratio: try c.decode(Float.self, forKey: .ratio)
            )
        }
    }
}

public struct DuckingRuleDTO: Codable, Sendable, Equatable {
    public var trigger: String
    public var targets: [DuckTargetDTO]

    public init(trigger: String, targets: [DuckTargetDTO]) {
        self.trigger = trigger
        self.targets = targets
    }
}

public struct DuckTargetDTO: Codable, Sendable, Equatable {
    public var channel: String
    public var duckLevel: Float
    public var fadeInDuration: Double
    public var fadeOutDuration: Double

    public init(channel: String, duckLevel: Float, fadeInDuration: Double, fadeOutDuration: Double) {
        self.channel = channel
        self.duckLevel = duckLevel
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
    }
}

// MARK: - Video

public struct VideoActionDTO: Codable, Sendable, Equatable {
    public var file: String
    public var channel: String
    public var volume: Float
    public var loop: Bool
    public var presentation: VideoPresentation
    /// Stereoscopic / immersive packing of the video file. Defaults to `.mono`.
    /// Players use this hint to drive AVPlayer's stereo mode (MV-HEVC) or to
    /// split a side-by-side / over-under stream into per-eye textures.
    public var layout: VideoLayout
    /// Non-destructive source trim, seconds into the MASTER file where
    /// playback begins. `nil` (default) plays from the file's start. The
    /// master's bytes are never re-encoded or duplicated — a trim is pure
    /// metadata, so asset hashes (and live-sync caches) stay stable.
    public var sourceIn: Double?
    /// Non-destructive source trim, exclusive end in master-file seconds.
    /// `nil` (default) plays through the file's natural end. Looping loops
    /// the `[sourceIn, sourceOut)` window. Multiple clips cut from one
    /// master are just multiple playVideo actions with different windows
    /// over the same `file`.
    public var sourceOut: Double?
    /// Optional normalized spatial crop of the video frame, applied by the
    /// player at render time. `nil` shows the full frame.
    public var crop: VideoCropRect?
    /// This occurrence's CONVERGENCE: where the source's stereo content sits
    /// in depth relative to its Video Panel, as a fraction of image width.
    ///
    /// `nil` and `0` mean the same thing and both mean "the source's own
    /// stereo relationship" — the file's embedded disparity adjustment is
    /// still honoured underneath. It is NOT "no disparity", and nothing here
    /// ever writes to source media: three occurrences of one file can carry
    /// three different convergences and the file is untouched.
    ///
    /// Rides on top of this come from `SequenceDefinitionDTO.stereoTracks`;
    /// `SequenceStereoAutomation.effectiveConvergence` is the one rule that
    /// combines them.
    public var convergence: Float?

    /// CLIP MARKERS (FL-06): notes at SOURCE seconds on THIS occurrence.
    /// Source-relative so a slip moves the note with the picture and a trim
    /// hides rather than destroys; per occurrence because two uses of one
    /// master legitimately carry different notes. Additive, tolerant.
    public var markers: [Marker]?
    /// THE EFFECT STACK (FL-09): ordered, owned by THIS occurrence — order
    /// IS evaluation order. Additive and tolerant; absent means none, and
    /// an unrecognised Effect round-trips losslessly (G7).
    public var effects: [EffectInstance]?
    /// THE DISPLAY BLEND (FL-11): stage 5, a property of the occurrence.
    /// Absent ⇒ `.normal`; an unrecognised mode renders as `.normal` and
    /// its raw value round-trips verbatim.
    public var blendMode: BlendMode?
    /// A TWO-SOURCE TRANSITION (FL-12), stored on the INCOMING
    /// occurrence — the one whose arrival does the fading. Absent ⇒ no
    /// transition; an unrecognised kind means NO transition (never a look
    /// the author did not author) and the raw value round-trips.
    public var videoTransition: VideoTransitionSpec?
    /// THE RETIME CURVE (FL-13): the occurrence's own Sequence-time to
    /// source-time statement. Absent means the identity — today's exact
    /// behaviour at zero cost. See `RetimeCurve`.
    public var retime: RetimeCurve?
    /// How a retimed occurrence's embedded audio handles pitch. Absent
    /// means `.followsSpeed`.
    public var pitch: PitchHandling?

    public init(
        file: String,
        channel: String,
        volume: Float = 1.0,
        loop: Bool = false,
        presentation: VideoPresentation = .attachment(id: "video"),
        layout: VideoLayout = .mono,
        sourceIn: Double? = nil,
        sourceOut: Double? = nil,
        crop: VideoCropRect? = nil,
        convergence: Float? = nil,
        markers: [Marker]? = nil,
        effects: [EffectInstance]? = nil,
        blendMode: BlendMode? = nil,
        videoTransition: VideoTransitionSpec? = nil,
        retime: RetimeCurve? = nil,
        pitch: PitchHandling? = nil
    ) {
        self.file = file
        self.channel = channel
        self.volume = volume
        self.loop = loop
        self.presentation = presentation
        self.layout = layout
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.crop = crop
        self.convergence = convergence
        self.markers = markers
        self.effects = effects
        self.blendMode = blendMode
        self.videoTransition = videoTransition
        self.retime = retime
        self.pitch = pitch
    }

    private enum CodingKeys: String, CodingKey {
        case file, channel, volume, loop, presentation, layout, sourceIn, sourceOut, crop
        case convergence, markers, effects, blendMode, videoTransition, retime, pitch
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.file = try c.decode(String.self, forKey: .file)
        self.channel = try c.decode(String.self, forKey: .channel)
        self.volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        self.loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        self.presentation = try c.decodeIfPresent(VideoPresentation.self, forKey: .presentation)
            ?? .attachment(id: "video")
        self.layout = try c.decodeIfPresent(VideoLayout.self, forKey: .layout) ?? .mono
        self.sourceIn = try c.decodeIfPresent(Double.self, forKey: .sourceIn)
        self.sourceOut = try c.decodeIfPresent(Double.self, forKey: .sourceOut)
        self.crop = try c.decodeIfPresent(VideoCropRect.self, forKey: .crop)
        self.convergence = try c.decodeIfPresent(Float.self, forKey: .convergence)
        self.markers = try c.decodeIfPresent([Marker].self, forKey: .markers)
        self.effects = try c.decodeIfPresent([EffectInstance].self, forKey: .effects)
        self.blendMode = try c.decodeIfPresent(BlendMode.self, forKey: .blendMode)
        self.videoTransition = try c.decodeIfPresent(VideoTransitionSpec.self,
                                                     forKey: .videoTransition)
        self.retime = try c.decodeIfPresent(RetimeCurve.self, forKey: .retime)
        self.pitch = try c.decodeIfPresent(PitchHandling.self, forKey: .pitch)
    }

    /// Duration of the trimmed source window when both endpoints are known.
    ///
    /// Kept as a named property because four call sites read it, but the
    /// arithmetic itself belongs to `MediaSourceRange` — this is the
    /// "master length unknown" case of `duration(masterDuration:)`, and
    /// having it compute its own subtraction is exactly the duplication that
    /// lets two source-time answers drift apart.
    public var sourceWindowDuration: Double? {
        sourceOut == nil ? nil : sourceRange.duration(masterDuration: nil)
    }
}

/// Normalized (0…1) crop rectangle over a video frame; origin is the
/// frame's top-left. Pure metadata — the master file is untouched.
public struct VideoCropRect: Codable, Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// How a video file packs its eye(s) on disk. The player consults this to know
/// whether to render flat, route to AVPlayer's automatic stereoscopic decoder
/// (MV-HEVC for Apple spatial video), or split a frame-packed image manually.
public enum VideoLayout: String, Codable, Sendable, Equatable {
    /// Standard 2D video — one eye, no stereo.
    case mono
    /// Frame-packed left-right side-by-side stereo. Player splits horizontally.
    case sideBySide
    /// Frame-packed top-bottom over-under stereo. Player splits vertically.
    case overUnder
    /// Apple's stereoscopic format (MV-HEVC). AVPlayer auto-detects per-eye
    /// streams; the player just hands the URL to AVPlayer and binds the
    /// resulting `AVStereoVideo`-aware material.
    case multiviewHEVC
}

public enum VideoPresentation: Codable, Sendable, Equatable {
    /// Flat video rendered into the player's SwiftUI attachment slot
    /// identified by `id`. Typical for floating panel UI.
    case attachment(id: String)

    /// Flat video rendered onto a named entity (a quad / panel in the scene).
    /// `width` and `height` are in meters.
    case entity(name: String, width: Float, height: Float)

    /// Immersive 360°/180° video rendered onto a sphere of radius `radius`
    /// centered around the user. The player applies the supplied `layout`
    /// hint to swap in the stereo material when appropriate. `field` selects
    /// between full equirectangular (360°) and front-half (180°) projections.
    case immersive(radius: Float, field: ImmersiveField)

    private enum CodingKeys: String, CodingKey {
        case kind, id, name, width, height, radius, field
    }
    private enum Kind: String, Codable { case attachment, entity, immersive }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .attachment(let id):
            try c.encode(Kind.attachment, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .entity(let name, let width, let height):
            try c.encode(Kind.entity, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(width, forKey: .width)
            try c.encode(height, forKey: .height)
        case .immersive(let radius, let field):
            try c.encode(Kind.immersive, forKey: .kind)
            try c.encode(radius, forKey: .radius)
            try c.encode(field, forKey: .field)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .attachment:
            self = .attachment(id: try c.decode(String.self, forKey: .id))
        case .entity:
            self = .entity(
                name: try c.decode(String.self, forKey: .name),
                width: try c.decode(Float.self, forKey: .width),
                height: try c.decode(Float.self, forKey: .height)
            )
        case .immersive:
            self = .immersive(
                radius: try c.decode(Float.self, forKey: .radius),
                field: try c.decodeIfPresent(ImmersiveField.self, forKey: .field) ?? .equirect360
            )
        }
    }
}

/// Spherical projection for immersive video.
///
/// The two equirectangular cases are the originals and still encode as the
/// bare strings `"equirect360"` / `"equirect180"`, so existing documents are
/// unchanged byte for byte.
///
/// `appleImmersive` exists because **Apple Immersive Video is not 180°**.
/// Half-equirectangular 180° stops dead at the ±90° plane; Apple's parametric
/// fisheye projection reaches past it into the periphery, so mapping an AIVU
/// onto a 180° hemisphere throws away real picture at both edges. It is a
/// named case rather than a `custom` with a number because the projection
/// itself differs — a renderer that learns Apple's lens math needs to know it
/// is looking at one, not merely that the sweep is wide.
///
/// Coverage is carried as degrees because rigs differ and Apple publishes no
/// single figure; 190° is the project's working assumption (it matches the
/// Viewer's Immersive Guides default), not a specification.
public enum ImmersiveField: Codable, Sendable, Equatable, Hashable {
    /// Full 360° equirectangular sphere — standard immersive video.
    case equirect360
    /// Front 180° hemisphere — typical VR180 / spatial video.
    case equirect180
    /// Apple Immersive Video — Apple's parametric projection, wider than 180°.
    case appleImmersive(degrees: Float)
    /// Any other horizontal sweep, authored directly.
    case custom(degrees: Float)

    /// Working assumption for Apple Immersive coverage. Not a spec — see the
    /// type comment.
    public static let appleImmersiveDefaultDegrees: Float = 190

    /// Apple Immersive at the default coverage.
    ///
    /// NOT named `appleImmersive`: a static property sharing a case's name
    /// shadows it, and `.appleImmersive` in expression position then resolves
    /// to the property — including inside the property's own initializer,
    /// which is an infinite recursion that segfaults at first use rather than
    /// failing to compile.
    public static let appleImmersiveDefault = ImmersiveField
        .appleImmersive(degrees: appleImmersiveDefaultDegrees)

    /// Horizontal sweep in degrees, clamped to something a mesh can be built
    /// from. This is the ONE place a field turns into an angle.
    public var horizontalDegrees: Float {
        switch self {
        case .equirect360: return 360
        case .equirect180: return 180
        case .appleImmersive(let degrees), .custom(let degrees):
            return min(max(degrees, 1), 360)
        }
    }

    /// True when the source uses Apple's parametric projection rather than a
    /// plain equirectangular map.
    public var isAppleParametric: Bool {
        if case .appleImmersive = self { return true }
        return false
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case kind, degrees }

    public init(from decoder: Decoder) throws {
        // Legacy (and forward-compatible) form: a bare string.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            switch raw {
            case "equirect180":    self = .equirect180
            case "appleImmersive": self = .appleImmersiveDefault
            case "custom":         self = .custom(degrees: 180)
            // UNKNOWN VALUES DEGRADE, THEY DO NOT THROW. A document written by
            // a newer tool must not fail to open wholesale over one projection
            // name — same rule as `GateType`, which decodes unknowns as `.tap`.
            default:               self = .equirect360
            }
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "equirect360"
        let degrees = try c.decodeIfPresent(Float.self, forKey: .degrees)
        switch kind {
        case "equirect180":    self = .equirect180
        case "appleImmersive": self = .appleImmersive(degrees: degrees ?? Self.appleImmersiveDefaultDegrees)
        case "custom":         self = .custom(degrees: degrees ?? 180)
        default:               self = .equirect360
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .equirect360, .equirect180:
            // Bare string, exactly as before — old readers keep working.
            var c = encoder.singleValueContainer()
            try c.encode(self == .equirect180 ? "equirect180" : "equirect360")
        case .appleImmersive(let degrees):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("appleImmersive", forKey: .kind)
            try c.encode(degrees, forKey: .degrees)
        case .custom(let degrees):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("custom", forKey: .kind)
            try c.encode(degrees, forKey: .degrees)
        }
    }
}

// MARK: - Effect Configs

public struct PulseRingConfigDTO: Codable, Sendable, Equatable {
    public var radius: Float
    public var height: Float
    public var ringCount: Int
    public var baseIntensity: Float
    public var peakIntensity: Float
    public var pulseSpeed: Float
    public var discRadius: Float
    public var color: ColorRGBA

    public init(
        radius: Float = 1.5,
        height: Float = 1.2,
        ringCount: Int = 24,
        baseIntensity: Float = 0.4,
        peakIntensity: Float = 1.6,
        pulseSpeed: Float = 0.5,
        discRadius: Float = 0.04,
        color: ColorRGBA = ColorRGBA(r: 0.3, g: 0.85, b: 1.0)
    ) {
        self.radius = radius
        self.height = height
        self.ringCount = ringCount
        self.baseIntensity = baseIntensity
        self.peakIntensity = peakIntensity
        self.pulseSpeed = pulseSpeed
        self.discRadius = discRadius
        self.color = color
    }
}

public struct SparkBurstConfigDTO: Codable, Sendable, Equatable {
    public var position: Vec3
    public var burstRadius: Float
    public var particleBirthRate: Float
    public var particleLifeSpan: Float
    public var duration: Double
    public var particleSize: Float
    public var tint: ColorRGBA

    public init(
        position: Vec3 = Vec3(0, 1.0, -1.5),
        burstRadius: Float = 0.5,
        particleBirthRate: Float = 300,
        particleLifeSpan: Float = 1.2,
        duration: Double = 2.0,
        particleSize: Float = 0.02,
        tint: ColorRGBA = ColorRGBA(r: 1.0, g: 0.7, b: 0.2)
    ) {
        self.position = position
        self.burstRadius = burstRadius
        self.particleBirthRate = particleBirthRate
        self.particleLifeSpan = particleLifeSpan
        self.duration = duration
        self.particleSize = particleSize
        self.tint = tint
    }
}

// MARK: - Animate Motion (new declarative per-frame motion action payload)

public struct AnimateMotionActionDTO: Codable, Sendable, Equatable {
    public var entity: String
    public var position: MotionCurve?
    public var scale: MotionCurve?
    public var rotation: MotionCurve?
    public var duration: Double

    public init(
        entity: String,
        position: MotionCurve? = nil,
        scale: MotionCurve? = nil,
        rotation: MotionCurve? = nil,
        duration: Double
    ) {
        self.entity = entity
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.duration = duration
    }
}
