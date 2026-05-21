import Foundation

public struct ChapterDefinitionDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var phase: String
    /// Whether this chapter expects the player to be in an immersive space
    /// or in a flat / windowed presentation. Players consult this on chapter
    /// start to open / dismiss the immersive space as the experience moves
    /// between presentation modes.
    public var presentation: ChapterPresentation
    /// Optional immersive backdrop (skybox video or USDZ scene) shown while
    /// this chapter plays. Only meaningful when `presentation == .immersive`;
    /// players may ignore for `.windowed` chapters.
    public var immersiveBackdrop: ImmersiveBackdropSpec?
    public var steps: [StepDefinitionDTO]
    public var visibility: VisibilityStateDTO
    public var onComplete: CompletionActionDTO

    public init(
        id: String,
        name: String,
        phase: String,
        presentation: ChapterPresentation = .immersive,
        immersiveBackdrop: ImmersiveBackdropSpec? = nil,
        steps: [StepDefinitionDTO],
        visibility: VisibilityStateDTO = VisibilityStateDTO(),
        onComplete: CompletionActionDTO = .holdOnLastStep
    ) {
        self.id = id
        self.name = name
        self.phase = phase
        self.presentation = presentation
        self.immersiveBackdrop = immersiveBackdrop
        self.steps = steps
        self.visibility = visibility
        self.onComplete = onComplete
    }

    public var totalDuration: Double {
        steps.reduce(0) { $0 + $1.duration }
    }

    // Decode-if-present for `presentation` and `immersiveBackdrop` so docs
    // authored before this format revision keep loading. `phase` is kept
    // independent — it remains a free-form routing tag — but if a legacy
    // doc explicitly used `phase == "windowed"`, fall back to that.
    private enum CodingKeys: String, CodingKey {
        case id, name, phase, presentation, immersiveBackdrop
        case steps, visibility, onComplete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        let phase = try c.decode(String.self, forKey: .phase)
        self.phase = phase
        if let decoded = try c.decodeIfPresent(ChapterPresentation.self, forKey: .presentation) {
            self.presentation = decoded
        } else {
            self.presentation = phase == "windowed" ? .windowed : .immersive
        }
        self.immersiveBackdrop = try c.decodeIfPresent(ImmersiveBackdropSpec.self, forKey: .immersiveBackdrop)
        self.steps = try c.decode([StepDefinitionDTO].self, forKey: .steps)
        self.visibility = try c.decodeIfPresent(VisibilityStateDTO.self, forKey: .visibility) ?? VisibilityStateDTO()
        self.onComplete = try c.decodeIfPresent(CompletionActionDTO.self, forKey: .onComplete) ?? .holdOnLastStep
    }
}

/// Whether a chapter expects the player in an immersive space, a mixed
/// (passthrough) space, or a flat windowed scene. The SharedVisions
/// player maps these to visionOS `ImmersionStyle` values:
///
///   • `.immersive` → `.full` — the user's real environment is hidden;
///     ideal for skybox videos and fully-authored 3D backdrops.
///   • `.mixed` → `.mixed` — passthrough stays visible while RealityKit
///     content places into world space. Good for chapters that need
///     3D depth (entities anchored in the user's room) without
///     replacing the real environment.
///   • `.windowed` — the immersive space is dismissed entirely, so
///     only flat windowed UI remains.
///
/// Decode is tolerant: unknown raw values fall back to `.immersive` so
/// a v0.3.1 doc containing `.mixed` loads on a v0.3.0 player as full
/// immersive (the safest interpretation of "needs 3D space").
public enum ChapterPresentation: String, Codable, Sendable, Equatable, CaseIterable {
    case immersive
    case mixed
    case windowed

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        self = ChapterPresentation(rawValue: raw) ?? .immersive
    }
}

/// Ambient backdrop content for an immersive chapter. The player binds
/// one of these at chapter start (and tears down the previous one):
///
///   • `.video` — a flat video projected onto a sphere (360° / 180°)
///     or a stereoscopic MV-HEVC / Apple Immersive Video file. Player
///     uses `VideoPlayerComponent` for proper per-eye projection.
///   • `.image` — a static equirectangular image (HEIC / JPG / PNG)
///     wrapped onto a sphere mesh via an UnlitMaterial. Cheap, no
///     stereo. Good for matte-painting style environments and
///     360° photos.
///   • `.usdz` — a USDZ scene loaded under the immersive scene root.
///
/// Players may ignore for `.windowed` chapters.
public enum ImmersiveBackdropSpec: Codable, Sendable, Equatable {
    /// Immersive video. `file` references an entry in the asset manifest.
    /// `layout` and `field` mirror the same hints used by `VideoActionDTO`
    /// for skybox playback; `radius` controls the sphere size in meters.
    case video(file: String, layout: VideoLayout, field: ImmersiveField, radius: Float, loop: Bool)
    /// Static equirectangular image skybox. `field` is `.equirect360` for
    /// full-sphere panoramas, `.equirect180` for half-sphere captures.
    /// `radius` is the sphere size in meters (Player default ~1000m).
    case image(file: String, field: ImmersiveField, radius: Float)
    /// USDZ scene loaded under the immersive scene root. The asset id
    /// must exist in the document's manifest. The player parents the
    /// loaded entity under the immersive root before the first chapter
    /// step runs.
    case usdz(assetId: String)

    private enum CodingKeys: String, CodingKey {
        case kind, file, layout, field, radius, loop, assetId
    }
    private enum Kind: String, Codable { case video, image, usdz }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .video(let file, let layout, let field, let radius, let loop):
            try c.encode(Kind.video, forKey: .kind)
            try c.encode(file, forKey: .file)
            try c.encode(layout, forKey: .layout)
            try c.encode(field, forKey: .field)
            try c.encode(radius, forKey: .radius)
            try c.encode(loop, forKey: .loop)
        case .image(let file, let field, let radius):
            try c.encode(Kind.image, forKey: .kind)
            try c.encode(file, forKey: .file)
            try c.encode(field, forKey: .field)
            try c.encode(radius, forKey: .radius)
        case .usdz(let assetId):
            try c.encode(Kind.usdz, forKey: .kind)
            try c.encode(assetId, forKey: .assetId)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .video:
            self = .video(
                file: try c.decode(String.self, forKey: .file),
                layout: try c.decodeIfPresent(VideoLayout.self, forKey: .layout) ?? .mono,
                field: try c.decodeIfPresent(ImmersiveField.self, forKey: .field) ?? .equirect360,
                radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? 1000,
                loop: try c.decodeIfPresent(Bool.self, forKey: .loop) ?? true
            )
        case .image:
            self = .image(
                file: try c.decode(String.self, forKey: .file),
                field: try c.decodeIfPresent(ImmersiveField.self, forKey: .field) ?? .equirect360,
                radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? 1000
            )
        case .usdz:
            self = .usdz(assetId: try c.decode(String.self, forKey: .assetId))
        }
    }
}

public struct StepDefinitionDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var duration: Double
    public var actions: [StepActionDTO]
    public var scheduledActions: [ScheduledActionDTO]
    public var gate: StepGateDTO?

    public init(
        id: String,
        name: String,
        duration: Double,
        actions: [StepActionDTO],
        scheduledActions: [ScheduledActionDTO] = [],
        gate: StepGateDTO? = nil
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.actions = actions
        self.scheduledActions = scheduledActions
        self.gate = gate
    }
}

public struct ScheduledActionDTO: Codable, Sendable, Equatable {
    /// Seconds after the step starts at which `action` fires. 0 = immediate.
    public var at: Double
    public var action: StepActionDTO

    public init(at: Double, action: StepActionDTO) {
        self.at = at
        self.action = action
    }
}

public struct StepGateDTO: Codable, Sendable, Equatable {
    public var type: GateType
    public var timeout: Double?
    public var prompt: String?

    public init(type: GateType, timeout: Double? = nil, prompt: String? = nil) {
        self.type = type
        self.timeout = timeout
        self.prompt = prompt
    }
}

public enum GateType: String, Codable, Sendable, Equatable {
    case tap
    case orchestrator
    case any
}

public enum CompletionActionDTO: Codable, Sendable, Equatable {
    case holdOnLastStep
    case transitionTo(phase: String, visibility: VisibilityStateDTO)
    case autoAdvance(nextChapterId: String)
    case dismissToHome

    private enum CodingKeys: String, CodingKey { case kind, phase, visibility, nextChapterId }
    private enum Kind: String, Codable {
        case holdOnLastStep, transitionTo, autoAdvance, dismissToHome
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .holdOnLastStep:
            try c.encode(Kind.holdOnLastStep, forKey: .kind)
        case .transitionTo(let phase, let visibility):
            try c.encode(Kind.transitionTo, forKey: .kind)
            try c.encode(phase, forKey: .phase)
            try c.encode(visibility, forKey: .visibility)
        case .autoAdvance(let nextChapterId):
            try c.encode(Kind.autoAdvance, forKey: .kind)
            try c.encode(nextChapterId, forKey: .nextChapterId)
        case .dismissToHome:
            try c.encode(Kind.dismissToHome, forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .holdOnLastStep:
            self = .holdOnLastStep
        case .transitionTo:
            self = .transitionTo(
                phase: try c.decode(String.self, forKey: .phase),
                visibility: try c.decode(VisibilityStateDTO.self, forKey: .visibility)
            )
        case .autoAdvance:
            self = .autoAdvance(nextChapterId: try c.decode(String.self, forKey: .nextChapterId))
        case .dismissToHome:
            self = .dismissToHome
        }
    }
}

/// SharedVisions's existing VisibilityState is a fixed snapshot of named entity flags.
/// In the format we generalize to a string-keyed map so any experience can declare its own
/// entity names. Players may use a subset they recognize.
public struct VisibilityStateDTO: Codable, Sendable, Equatable {
    public var entities: [String: Bool]

    public init(_ entities: [String: Bool] = [:]) {
        self.entities = entities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.entities = (try? c.decode([String: Bool].self)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entities)
    }
}
