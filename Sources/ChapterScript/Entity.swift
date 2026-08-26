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
    /// Set only when `kind == .imagePanel`: a still shown on a flat plate in
    /// the scene, at the source's own aspect ratio. Additive — an older
    /// player decodes the kind as `.custom`, finds no factory and builds
    /// nothing, which is the right degradation for a picture it cannot draw.
    public var imagePanel: ImagePanelSpec?
    /// Set only when `kind == .placeholder`: blocking content standing in for
    /// media that does not exist yet. Carries NO file reference — see
    /// `PlaceholderSpec`.
    public var placeholder: PlaceholderSpec?
    public var particlePresetId: String?      // references ParticleEmitterPreset.id
    public var customFactoryId: String?       // app-registered factory key for `kind == .custom`
    /// Free-form parameters passed to a custom factory. Players may interpret as JSON.
    public var customParameters: [String: AnyCodableValue]?

    /// WHAT THE VIEWER CAN DO TO THIS OBJECT.
    ///
    /// Interactions attach to the OBJECT, not to a timeline position and not to
    /// the media that happens to be playing on it — a door is a door whether or
    /// not a clip is running, and a screen with three films on it is still one
    /// interactive surface. See `Interaction.swift` for why this is not a gate.
    ///
    /// Optional, and normalized to `nil` when emptied (`didSet`), so an entity
    /// with no interactions emits NO key and every document written before this
    /// field existed re-saves byte-identically.
    public var interactions: [InteractionSpec]? {
        didSet { if interactions?.isEmpty == true { interactions = nil } }
    }

    /// How this object signals that it can be interacted with. `nil` =
    /// `.automatic`, the platform's own affordance.
    ///
    /// The authored CHOICE lives here. Whether the viewer is looking at it
    /// right now does not: that is transient runtime state, and storing it
    /// would put a gesture-rate value in the document.
    public var interactionFeedback: InteractionFeedbackSpec?

    /// Interactions, never nil — readers use this so no view writes
    /// `interactions ?? []` and half of them forget.
    public var resolvedInteractions: [InteractionSpec] { interactions ?? [] }

    /// True when this object does anything at all when the viewer acts on it.
    /// A disabled interaction still counts as authored behaviour: the Timeline
    /// and the Scene browser must show that the object HAS behaviour, or the
    /// author cannot find the switch that turned it off.
    public var isInteractive: Bool { !(interactions ?? []).isEmpty }

    /// The feedback actually in force.
    public var resolvedInteractionFeedback: InteractionFeedbackSpec {
        interactionFeedback ?? .automatic
    }

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
        imagePanel: ImagePanelSpec? = nil,
        placeholder: PlaceholderSpec? = nil,
        particlePresetId: String? = nil,
        customFactoryId: String? = nil,
        customParameters: [String: AnyCodableValue]? = nil,
        interactions: [InteractionSpec]? = nil,
        interactionFeedback: InteractionFeedbackSpec? = nil
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
        self.imagePanel = imagePanel
        self.placeholder = placeholder
        self.particlePresetId = particlePresetId
        self.customFactoryId = customFactoryId
        self.customParameters = customParameters
        // Normalized here as well as in `didSet`: a property observer does not
        // run during initialization, so an empty array passed in would
        // otherwise encode as `"interactions": []`.
        self.interactions = (interactions?.isEmpty ?? true) ? nil : interactions
        self.interactionFeedback = interactionFeedback
    }

    /// TOLERANT DECODE.
    ///
    /// This used the synthesized decoder, which makes EVERY non-optional
    /// stored property a required key — so each field added over the
    /// life of the format silently became mandatory, and a Chapter
    /// written before it could no longer be opened at all.
    /// `initiallyEnabled` is the one that surfaced it; the fix is the
    /// class of problem, not that field.
    ///
    /// `id` and `kind` stay REQUIRED: an entity without them is not an
    /// entity, and defaulting them would turn a corrupt file into a
    /// silently wrong scene. Everything else takes the same default the
    /// memberwise initializer already declares — so an absent field
    /// means exactly what it has always meant.
    ///
    /// ENCODING IS UNCHANGED, so existing documents re-save
    /// byte-identically.
    ///
    /// THE COST OF WRITING THIS BY HAND: a property added later and not
    /// added HERE is silently dropped on every load — the field encodes,
    /// and comes back nil. That happened while this was being written
    /// (`interactionFeedback`), and the round-trip test caught it. Any
    /// new stored property must be added to this decoder, and the
    /// round-trip tests are what will tell you if it was not.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(EntityKind.self, forKey: .kind)
        self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        self.transform = try c.decodeIfPresent(TransformData.self, forKey: .transform)
            ?? .identity
        self.initiallyEnabled = try c.decodeIfPresent(Bool.self, forKey: .initiallyEnabled)
            ?? false
        self.gestureEnabled = try c.decodeIfPresent(Bool.self, forKey: .gestureEnabled)
            ?? false
        self.primitive = try c.decodeIfPresent(PrimitiveSpec.self, forKey: .primitive)
        self.usdzAssetId = try c.decodeIfPresent(String.self, forKey: .usdzAssetId)
        self.usdzAnimation = try c.decodeIfPresent(UsdzAnimationSpec.self, forKey: .usdzAnimation)
        self.text = try c.decodeIfPresent(TextSpec.self, forKey: .text)
        self.light = try c.decodeIfPresent(LightSpec.self, forKey: .light)
        self.videoPanel = try c.decodeIfPresent(VideoPanelSpec.self, forKey: .videoPanel)
        self.imagePanel = try c.decodeIfPresent(ImagePanelSpec.self, forKey: .imagePanel)
        self.placeholder = try c.decodeIfPresent(PlaceholderSpec.self, forKey: .placeholder)
        self.particlePresetId = try c.decodeIfPresent(String.self, forKey: .particlePresetId)
        self.customFactoryId = try c.decodeIfPresent(String.self, forKey: .customFactoryId)
        self.customParameters = try c.decodeIfPresent(
            [String: AnyCodableValue].self, forKey: .customParameters)
        self.interactions = try c.decodeIfPresent(
            [InteractionSpec].self, forKey: .interactions)
        self.interactionFeedback = try c.decodeIfPresent(
            InteractionFeedbackSpec.self, forKey: .interactionFeedback)
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
    /// A STILL SHOWN ON A FLAT PLATE. The image sibling of `.videoPanel`, and
    /// a real kind rather than a tagged `.custom`, because an image that can
    /// only ever feed a skybox picker is not first-class media. Carries
    /// `EntityDefinition.imagePanel`.
    case imagePanel
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

    /// Tolerant, for the reason `EntityDefinition`'s decoder is: `shape`
    /// and `size` define the primitive and stay required; `material` has
    /// an unambiguous default and became mandatory only because the
    /// synthesized decoder made it so.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.shape = try c.decode(PrimitiveShape.self, forKey: .shape)
        self.size = try c.decode(Vec3.self, forKey: .size)
        self.material = try c.decodeIfPresent(MaterialSpec.self, forKey: .material) ?? .default
        self.attachedParticlePresetId = try c.decodeIfPresent(
            String.self, forKey: .attachedParticlePresetId)
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

    /// WHAT AN UNSET FIELD ACTUALLY MEANS AT RUNTIME.
    ///
    /// `range` and `spotAngle` are optional, so every consumer needs a
    /// fallback — and for a while each one picked its own. The runtime lit
    /// 5 m while MaestroVision's Inspector displayed 10 m for the same
    /// light, which is a control reporting a number nothing uses. These are
    /// the runtime's values, and they live on the model so the renderer,
    /// the editors and the Director's light guides cannot drift apart
    /// again. NOT serialized: an unset field stays unset.
    public static let defaultRange: Float = 5
    public static let defaultSpotAngleDegrees: Float = 45

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

/// HOW A FLAT PANEL PRESENTS SPATIAL VIDEO.
///
/// Two cases, because two is what the platform actually offers. visionOS 26's
/// `RealityKit.VideoPlayerComponent` exposes `desiredSpatialVideoMode`
/// (`.screen` / `.spatial`) and `isPassthroughTintingEnabled`, and NOTHING
/// resembling a strength, threshold or feather. A slider for those would be a
/// control with no runtime behind it on either end.
public enum SpatialVideoPresentation: String, Codable, Sendable, Equatable, CaseIterable {
    /// The panel is a rectangle with the picture on it — one eye of a stereo
    /// master. What every Chapter written before this field does, and the
    /// default, so nothing changes for them.
    case flat
    /// visionOS's own spatial-video presentation: stereo, with the system's
    /// edge treatment. `SpatialVideoPresentation` is a REQUEST — a source with
    /// no second eye simply presents as it always did.
    case spatial

    /// Unknown value from a newer tool degrades to the presentation every
    /// existing document has, rather than failing the load — the same rule
    /// `GateType` and `ImmersiveField` follow.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SpatialVideoPresentation(rawValue: raw) ?? .flat
    }
}

public struct VideoPanelSpec: Codable, Sendable, Equatable {
    public var width: Float
    public var height: Float
    /// Optional placeholder color shown before video binds.
    public var placeholderColor: ColorRGBA?
    /// Rounded panel corners, in meters (nil/0 = square). Players clip
    /// the video plane's geometry; the texture stays rect-mapped.
    public var cornerRadius: Float?
    /// How this panel presents a spatial (MV-HEVC) source. `nil` = `.flat`,
    /// and absent writes no key.
    public var spatialPresentation: SpatialVideoPresentation?
    /// Let the picture tint the passthrough around it, the way the system's
    /// own player does. Only consulted under `.spatial`; `nil` = off.
    public var passthroughTinting: Bool?

    public init(
        width: Float,
        height: Float,
        placeholderColor: ColorRGBA? = nil,
        cornerRadius: Float? = nil,
        spatialPresentation: SpatialVideoPresentation? = nil,
        passthroughTinting: Bool? = nil
    ) {
        self.width = width
        self.height = height
        self.placeholderColor = placeholderColor
        self.cornerRadius = cornerRadius
        self.spatialPresentation = spatialPresentation
        self.passthroughTinting = passthroughTinting
    }
}

/// A still image shown on a flat plate in the scene.
///
/// `width` and `height` are METRES and carry the source's own aspect ratio —
/// an image panel is a photograph on a wall, so it is never cropped and never
/// stretched to a house shape. The authoring side computes them from the
/// probed pixel dimensions once, at import; the runtime just builds the quad.
public struct ImagePanelSpec: Codable, Sendable, Equatable {
    /// Manifest filename of the still. The panel IS this file — replacing it
    /// is a media replacement, not a property edit.
    public var file: String
    public var width: Float
    public var height: Float
    /// Rounded corners, in metres. nil/0 = square.
    public var cornerRadius: Float?
    /// PRESENT THE TWO EYES OF AN APPLE SPATIAL PHOTO, where the platform can.
    ///
    /// `nil` means "whatever the platform does by default", which on a runtime
    /// with no stereo image path is a monoscopic plate. It is deliberately NOT
    /// a claim that the file IS spatial — that is read from the bytes every
    /// time and never stored.
    public var preferStereoPresentation: Bool?

    public init(file: String,
                width: Float,
                height: Float,
                cornerRadius: Float? = nil,
                preferStereoPresentation: Bool? = nil) {
        self.file = file
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.preferStereoPresentation = preferStereoPresentation
    }

    /// Tolerant for the reason every spec here is: a field added later must
    /// not make an existing document unopenable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.file = try c.decode(String.self, forKey: .file)
        self.width = try c.decodeIfPresent(Float.self, forKey: .width) ?? 1.6
        self.height = try c.decodeIfPresent(Float.self, forKey: .height) ?? 0.9
        self.cornerRadius = try c.decodeIfPresent(Float.self, forKey: .cornerRadius)
        self.preferStereoPresentation = try c.decodeIfPresent(
            Bool.self, forKey: .preferStereoPresentation)
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
