import Foundation

/// Declarative description of a named entity that the player should construct
/// when an experience loads. Entities are referenced by `id` from `StepActionDTO` cases.
public struct EntityDefinition: Codable, Sendable, Equatable {
    /// STABLE, OPAQUE IDENTITY. The string every reference in the format uses —
    /// `StepActionDTO` entity names, `EntityAnimationTrack.entity`,
    /// `StepGateDTO.targetEntity`, `VideoPresentation.entity`.
    ///
    /// It is NOT a label and must never be treated as one. Historically the
    /// editors minted it from a filename (`"IMG_0071.MOV"`), which is why
    /// renaming a row meant rewriting every reference in the document and why
    /// one file could only ever be one destination. New content mints opaque
    /// ids; `displayName` carries what the author reads. Existing ids are
    /// preserved forever — they are opaque, and a document that says
    /// `"IMG_0071.MOV"` keeps saying it.
    public var id: String
    /// What the author reads and may freely change — "Main Screen", "Radio".
    ///
    /// Renaming writes HERE and touches nothing else, so a rename is no longer
    /// document-wide reference surgery. `nil` means "no authored label", and
    /// readers fall back to `id` (see `resolvedDisplayName`) — which is exactly
    /// what every document written before this field existed means, so those
    /// documents render identically and re-save byte-identically.
    ///
    /// Deliberately NOT unique and NOT an identifier. Two destinations may both
    /// be called "Screen"; they remain distinct objects.
    public var displayName: String?
    public var kind: EntityKind
    public var transform: TransformData
    /// Initial enabled state. `false` keeps the entity in the registry but hidden until `showEntity`.
    public var initiallyEnabled: Bool
    public var gestureEnabled: Bool

    // Per-kind specs (only one is non-nil; matched to `kind`)
    public var primitive: PrimitiveSpec?
    public var usdzAssetId: String?           // AssetEntry.id of a USDZ in the manifest
    /// Built-in USDZ animation playback (models often embed skeletal /
    /// transform clips). nil = the model renders static.
    public var usdzAnimation: UsdzAnimationSpec?
    public var text: TextSpec?
    public var light: LightSpec?
    public var videoPanel: VideoPanelSpec?
    /// Set only when `kind == .placeholder`: blocking content standing in for
    /// media that does not exist yet. Carries NO file reference — see
    /// `PlaceholderSpec`.
    public var placeholder: PlaceholderSpec?
    public var particlePresetId: String?      // references ParticleEmitterPreset.id
    public var customFactoryId: String?       // app-registered factory key for `kind == .custom`
    /// Free-form parameters passed to a custom factory. Players may interpret as JSON.
    public var customParameters: [String: AnyCodableValue]?

    /// The label to show, never empty. Falls back to `id` so a caller can use
    /// this unconditionally — no view should ever write `displayName ?? id`
    /// itself, because half of them would forget and show a raw filename.
    public var resolvedDisplayName: String {
        guard let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return id }
        return displayName
    }

    public init(
        id: String,
        displayName: String? = nil,
        kind: EntityKind,
        transform: TransformData = .identity,
        initiallyEnabled: Bool = false,
        gestureEnabled: Bool = false,
        primitive: PrimitiveSpec? = nil,
        usdzAssetId: String? = nil,
        usdzAnimation: UsdzAnimationSpec? = nil,
        text: TextSpec? = nil,
        light: LightSpec? = nil,
        videoPanel: VideoPanelSpec? = nil,
        placeholder: PlaceholderSpec? = nil,
        particlePresetId: String? = nil,
        customFactoryId: String? = nil,
        customParameters: [String: AnyCodableValue]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.transform = transform
        self.initiallyEnabled = initiallyEnabled
        self.gestureEnabled = gestureEnabled
        self.primitive = primitive
        self.usdzAssetId = usdzAssetId
        self.usdzAnimation = usdzAnimation
        self.text = text
        self.light = light
        self.videoPanel = videoPanel
        self.placeholder = placeholder
        self.particlePresetId = particlePresetId
        self.customFactoryId = customFactoryId
        self.customParameters = customParameters
    }
}

/// Playback settings for a USDZ model's EMBEDDED animation clips.
/// Players walk the loaded model's subtree and play every available
/// clip. Additive/tolerant — absent means static.
public struct UsdzAnimationSpec: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Repeat forever (default) vs play the clip once per reveal.
    public var loop: Bool
    /// Playback rate multiplier (1 = authored speed).
    public var speed: Float

    public init(enabled: Bool = true, loop: Bool = true, speed: Float = 1) {
        self.enabled = enabled
        self.loop = loop
        self.speed = speed
    }
}

public enum EntityKind: String, Codable, Sendable, Equatable {
    case primitive
    case usdz
    case text3D
    case light
    case videoPanel
    case particles
    /// Blocking content — an authored stand-in for media that does not exist
    /// yet. Carries `EntityDefinition.placeholder`. A player that does not
    /// know this case decodes it as `.custom` (below) and, having no factory
    /// registered for it, renders nothing — which is the right behaviour for
    /// an unfinished shot on an older runtime.
    case placeholder
    /// A POSITIONAL AUDIO SOURCE'S PLACE IN THE SCENE. Carries no geometry
    /// and nothing to look at — it exists so a `playAudio` occurrence can name
    /// something whose transform is animated like any other entity, which is
    /// how a sound moves through a room without a second animation system.
    ///
    /// The runtime builds a bare `Entity()` for it, exactly as it does for a
    /// light. That bare entity is not decoration: it is what makes the emitter
    /// findable in `entityRegistry`, which is what
    /// `EntityActionExecutor.applySequenceAnimationTracks` needs to write a
    /// pose, and what `SpatialAudioManager.playSpatial` needs to parent the
    /// sound to. An emitter that is not registered is an emitter that cannot
    /// move.
    ///
    /// An older player decodes this as `.custom`, finds no factory, and builds
    /// nothing — so `attachToEntity` misses and the sound falls back to
    /// `SpatialAudioConfigDTO.position`, playing at a fixed point rather than
    /// not playing at all. That is the right degradation.
    ///
    /// See `docs/AUDIO_ARCHITECTURE.md` §2.
    case audioEmitter
    case custom

    /// Unknown kinds decode as `.custom` rather than throwing. A `.custom`
    /// entity with no registered factory is inert, so an entity written by a
    /// newer tool is silently skipped instead of taking the whole document
    /// down with it — the same degradation rule as `GateType` and
    /// `ImmersiveField`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        self = EntityKind(rawValue: raw) ?? .custom
    }
}

public struct PrimitiveSpec: Codable, Sendable, Equatable {
    public var shape: PrimitiveShape
    /// Interpretation depends on shape:
    /// - sphere: x = radius
    /// - box: x/y/z = full extents
    /// - cylinder: x = radius, y = height
    /// - cone: x = radius, y = height
    /// - plane: x = width, y = height
    public var size: Vec3
    public var material: MaterialSpec
    public var attachedParticlePresetId: String?

    public init(
        shape: PrimitiveShape,
        size: Vec3,
        material: MaterialSpec = .default,
        attachedParticlePresetId: String? = nil
    ) {
        self.shape = shape
        self.size = size
        self.material = material
        self.attachedParticlePresetId = attachedParticlePresetId
    }
}

public enum PrimitiveShape: String, Codable, Sendable, Equatable {
    case sphere, box, cylinder, cone, plane
}

public struct MaterialSpec: Codable, Sendable, Equatable {
    public var baseColor: ColorRGBA
    public var metallic: Float
    public var roughness: Float
    public var emissiveColor: ColorRGBA
    public var emissiveIntensity: Float
    public var blending: MaterialBlending

    public init(
        baseColor: ColorRGBA = .white,
        metallic: Float = 0,
        roughness: Float = 0.5,
        emissiveColor: ColorRGBA = .black,
        emissiveIntensity: Float = 0,
        blending: MaterialBlending = .opaque
    ) {
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.emissiveColor = emissiveColor
        self.emissiveIntensity = emissiveIntensity
        self.blending = blending
    }

    public static let `default` = MaterialSpec()
}

public enum MaterialBlending: String, Codable, Sendable, Equatable {
    case opaque
    case additive
    case alpha
}

public struct TextSpec: Codable, Sendable, Equatable {
    public var text: String
    public var fontSize: Float
    public var color: ColorRGBA
    public var maxWidth: Float?

    public init(text: String, fontSize: Float = 0.1, color: ColorRGBA = .white, maxWidth: Float? = nil) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.maxWidth = maxWidth
    }
}

public struct LightSpec: Codable, Sendable, Equatable {
    public var kind: LightKind
    public var color: ColorRGBA
    public var intensity: Float
    /// For point/spot lights, in meters. Ignored for directional.
    public var range: Float?
    /// For spot lights, in degrees. Ignored otherwise.
    public var spotAngle: Float?

    public init(
        kind: LightKind,
        color: ColorRGBA = .white,
        intensity: Float = 1000,
        range: Float? = nil,
        spotAngle: Float? = nil
    ) {
        self.kind = kind
        self.color = color
        self.intensity = intensity
        self.range = range
        self.spotAngle = spotAngle
    }
}

public enum LightKind: String, Codable, Sendable, Equatable {
    case directional
    case point
    case spot
    case ambient
}

public struct VideoPanelSpec: Codable, Sendable, Equatable {
    public var width: Float
    public var height: Float
    /// Optional placeholder color shown before video binds.
    public var placeholderColor: ColorRGBA?
    /// Rounded panel corners, in meters (nil/0 = square). Players clip
    /// the video plane's geometry; the texture stays rect-mapped.
    public var cornerRadius: Float?

    public init(
        width: Float,
        height: Float,
        placeholderColor: ColorRGBA? = nil,
        cornerRadius: Float? = nil
    ) {
        self.width = width
        self.height = height
        self.placeholderColor = placeholderColor
        self.cornerRadius = cornerRadius
    }
}

/// Codable wrapper for arbitrary JSON values. Used for custom factory parameters
/// where the format can't predict the schema. Players interpret the contents.
public enum AnyCodableValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([AnyCodableValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: AnyCodableValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported AnyCodableValue payload.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
