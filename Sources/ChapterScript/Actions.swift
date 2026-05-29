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

    public init(
        entity: String,
        position: Vec3? = nil,
        headRelativePosition: Vec3? = nil,
        headYOnly: Bool = false,
        scale: Vec3? = nil,
        fadeIn: Double = 0
    ) {
        self.entity = entity
        self.position = position
        self.headRelativePosition = headRelativePosition
        self.headYOnly = headYOnly
        self.scale = scale
        self.fadeIn = fadeIn
    }
}

// MARK: - Audio

public enum AudioScope: String, Codable, Sendable, Equatable {
    case chapter
    case ambient
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

    public init(
        file: String,
        channel: String,
        scope: AudioScope = .chapter,
        volume: Float = 1.0,
        loop: Bool = false,
        fadeIn: Double? = nil,
        spatial: SpatialAudioConfigDTO? = nil,
        category: String? = nil,
        crossfade: Double? = nil,
        loopConfig: LoopConfigDTO? = nil
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

    public init(
        file: String,
        channel: String,
        volume: Float = 1.0,
        loop: Bool = false,
        presentation: VideoPresentation = .attachment(id: "video"),
        layout: VideoLayout = .mono
    ) {
        self.file = file
        self.channel = channel
        self.volume = volume
        self.loop = loop
        self.presentation = presentation
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey {
        case file, channel, volume, loop, presentation, layout
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
public enum ImmersiveField: String, Codable, Sendable, Equatable {
    /// Full 360° equirectangular sphere — standard immersive video.
    case equirect360
    /// Front 180° hemisphere — typical VR180 / spatial video.
    case equirect180
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
