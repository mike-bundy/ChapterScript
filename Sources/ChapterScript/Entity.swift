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

    /// PER-SLOT MATERIAL OVERRIDES (FL-14) for imported models. Absent
    /// means the file's own materials, byte-identically. Primitives keep
    /// `PrimitiveSpec.material`; Titles keep `TextSpec.slotMaterials`.
    public var materialOverrides: [MaterialOverrideSpec]?

    /// RIG MEMBERS (FL-15), by ID, in a FLAT array - `entities` stays a
    /// flat lookup table and nesting definitions is still forbidden. The
    /// bind lives on the MEMBERSHIP record: a member that leaves takes it
    /// with it. Absent means what today means: no members.
    public var members: [RigMember]?

    /// A VECTOR OBJECT'S SPEC (FL-22). Set only when `kind == .vector`.
    public var vector: VectorSpec?

    /// USD SUB-ELEMENT OVERRIDES (FL-16): which named parts of an imported
    /// model the author addressed, by PRIM PATH. Additive and
    /// UNCONDITIONAL - the reference is written and read whether or not
    /// this system can resolve it (Option C's whole obligation), so a
    /// Chapter authored where USDKit exists opens elsewhere with its
    /// references kept and reported, never dropped.
    public var subElements: [SubElementOverride]?

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
        materialOverrides: [MaterialOverrideSpec]? = nil,
        members: [RigMember]? = nil,
        subElements: [SubElementOverride]? = nil,
        vector: VectorSpec? = nil,
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
        self.materialOverrides = materialOverrides
        self.members = members
        self.subElements = subElements
        self.vector = vector
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
        self.materialOverrides = try c.decodeIfPresent(
            [MaterialOverrideSpec].self, forKey: .materialOverrides)
        // Tolerant: the shape GROUP_RIGS.md originally proposed was a bare
        // [String]; each id reads as a member with an identity bind.
        if let full = try? c.decodeIfPresent([RigMember].self, forKey: .members) {
            self.members = full
        } else if let bare = try? c.decodeIfPresent([String].self, forKey: .members) {
            self.members = bare.map { RigMember(id: $0) }
        } else {
            self.members = nil
        }
        self.subElements = try c.decodeIfPresent([SubElementOverride].self,
                                                  forKey: .subElements)
        self.vector = try c.decodeIfPresent(VectorSpec.self, forKey: .vector)
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
    /// CD-25 (FL-16): play ONE embedded clip, by the file's own name.
    /// Absent = today's behaviour, every clip - checked deliberately: the
    /// other fallback would silently stop existing models animating.
    /// Naming a clip the file does not have plays NOTHING, and reports.
    public var clipName: String?

    public init(enabled: Bool = true, loop: Bool = true, speed: Float = 1,
                clipName: String? = nil) {
        self.enabled = enabled
        self.loop = loop
        self.speed = speed
        self.clipName = clipName
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
    /// A RIG (FL-15): an Object with a transform, NO geometry, and
    /// members. It composes their world pose and never rewrites them. An
    /// older player decodes it as `.custom`, builds nothing, and the
    /// members simply keep their own authored motion - the right
    /// degradation for a parent that does not exist there.
    case rig
    case audioEmitter
    /// AN IMPORTED SVG AS A THING IN A ROOM (FL-22): generated geometry
    /// from a vector Source, extruded like a Title. Carries
    /// `EntityDefinition.vector`. An older player decodes it as `.custom`,
    /// builds nothing, and every authored fact survives — restored the
    /// moment a newer build opens it, because the raw value round-trips.
    case vector
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

/// Horizontal text alignment (FL-07). `natural` follows the string's own
/// direction — an RTL string leads from the right.
public enum TextAlignmentX: String, Codable, Sendable, Equatable, CaseIterable {
    case leading, centre, trailing, justified, natural
}

/// Vertical anchoring of the laid-out block within the Object.
public enum TextAlignmentY: String, Codable, Sendable, Equatable, CaseIterable {
    case top, centre, baseline, bottom
}

/// Which extrusion caps are filled. Flat text is zero extrusion with BOTH
/// caps; `.none` with zero depth draws nothing and is refused at the
/// authoring boundary.
public enum TextCapFill: String, Codable, Sendable, Equatable, CaseIterable {
    case front, back, both, none
}

/// Per-face materials for an extruded Title (FL-07): the five slots the
/// extruder assigns. A nil slot takes the spec's base `material`.
public struct TextSlotMaterials: Codable, Sendable, Equatable {
    public var front: MaterialSpec?
    public var back: MaterialSpec?
    public var sides: MaterialSpec?
    public var frontBevel: MaterialSpec?
    public var backBevel: MaterialSpec?

    public init(front: MaterialSpec? = nil, back: MaterialSpec? = nil,
                sides: MaterialSpec? = nil, frontBevel: MaterialSpec? = nil,
                backBevel: MaterialSpec? = nil) {
        self.front = front
        self.back = back
        self.sides = sides
        self.frontBevel = frontBevel
        self.backBevel = backBevel
    }

    public var isEmpty: Bool {
        front == nil && back == nil && sides == nil
            && frontBevel == nil && backBevel == nil
    }
}

/// AN IMPORTED VECTOR OBJECT (FL-22). The SVG is an ORDINARY Source
/// (`sourceId`); the parsed contours are NEVER persisted — they are
/// re-derived from the Source's bytes on every open, the same rule that
/// keeps a prim tree out of the format. Four of these fields are the
/// SAME TYPES a Title uses — one cap-fill enum, one bevel-profile
/// reference, one five-slot material assignment — which is the shared
/// contour-to-mesh contract delivering.
public struct VectorSpec: Codable, Sendable, Equatable {
    /// The SVG, an ordinary Source — relinks, replaces and consolidates
    /// exactly as media does. Missing keeps every authored fact.
    public var sourceId: String
    /// nil ⇒ 0 ⇒ FLAT (both caps) — the same toggle-not-mode as a Title.
    public var extrusionDepth: Float?
    /// SHARED with TextSpec. Unrecognised ⇒ `.both`, the most complete shape.
    public var capFill: TextCapFill?
    public var bevelRadius: Float?
    /// A preset-library reference, shared with a Title. Unresolved ⇒ no
    /// bevel, reference KEPT and reported.
    public var bevelProfileId: String?
    public var bevelSegments: Int?
    /// SHARED — the extruder's five slots.
    public var slotMaterials: TextSlotMaterials?
    /// Metres; nil ⇒ derived from the viewBox at a default scale.
    public var physicalWidth: Float?

    public init(sourceId: String,
                extrusionDepth: Float? = nil,
                capFill: TextCapFill? = nil,
                bevelRadius: Float? = nil,
                bevelProfileId: String? = nil,
                bevelSegments: Int? = nil,
                slotMaterials: TextSlotMaterials? = nil,
                physicalWidth: Float? = nil) {
        self.sourceId = sourceId
        self.extrusionDepth = extrusionDepth
        self.capFill = capFill
        self.bevelRadius = bevelRadius
        self.bevelProfileId = bevelProfileId
        self.bevelSegments = bevelSegments
        self.slotMaterials = slotMaterials
        self.physicalWidth = physicalWidth
    }

    private enum CodingKeys: String, CodingKey {
        case sourceId, extrusionDepth, capFill, bevelRadius
        case bevelProfileId, bevelSegments, slotMaterials, physicalWidth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceId = try c.decode(String.self, forKey: .sourceId)
        self.extrusionDepth = try c.decodeIfPresent(Float.self, forKey: .extrusionDepth)
        // Tolerant enum: a cap written by a newer tool reads as absent
        // (⇒ .both at build time), never as a failed document.
        self.capFill = (try? c.decodeIfPresent(String.self, forKey: .capFill))
            .flatMap { TextCapFill(rawValue: $0) }
        self.bevelRadius = try c.decodeIfPresent(Float.self, forKey: .bevelRadius)
        self.bevelProfileId = try c.decodeIfPresent(String.self, forKey: .bevelProfileId)
        self.bevelSegments = try c.decodeIfPresent(Int.self, forKey: .bevelSegments)
        self.slotMaterials = try c.decodeIfPresent(TextSlotMaterials.self, forKey: .slotMaterials)
        self.physicalWidth = try c.decodeIfPresent(Float.self, forKey: .physicalWidth)
    }
}

/// A TITLE'S AUTHORED SPEC (FL-07). The string and its typographic
/// parameters are the source of truth; geometry is derived, wholesale
/// regenerated on change, never itself authoritative.
///
/// Every field beyond the original four is optional and TOLERANTLY decoded
/// (an unrecognised enum case reads as absent), and ABSENT means the
/// constant the Mac hardcoded before this campaign — so a Chapter written
/// earlier renders exactly as it did and re-saves byte-identically.
///
/// `fontSize` is METRES OF CAP HEIGHT in Object space, before the Object's
/// own scale (F-2): a Title is an Object in a room, and points are a
/// 2D-display unit with no meaning at a distance. Existing values were
/// already effectively metres, so no migration.
public struct TextSpec: Codable, Sendable, Equatable {
    public var text: String
    public var fontSize: Float
    public var color: ColorRGBA
    public var maxWidth: Float?

    // Typography (FL-07). Absent ⇒ the system font, regular, the font's own
    // tracking and leading.
    public var fontFamily: String?
    /// A numeric weight (100…900, 400 = regular), never a filename.
    public var fontWeight: Int?
    public var fontIsItalic: Bool?
    /// K11: a font as an ordinary Source. Carried now; resolution rides the
    /// Source pipeline.
    public var fontSourceId: String?
    /// Additional tracking in metres (at cap-height scale). Absent ⇒ the
    /// font's own.
    public var tracking: Float?
    /// Line height in metres. Absent ⇒ the font's own leading.
    public var leading: Float?

    // Layout. Absent ⇒ centre / centre — today's `alignment: .center`.
    public var alignmentX: TextAlignmentX?
    public var alignmentY: TextAlignmentY?

    // Geometry. Absent extrusion ⇒ 0.02 — today's MAC constant, chosen
    // because the editor is where the author judged it; device playback of
    // an old Chapter changes 0.005 → 0.02 as a correction toward what they
    // saw. 0 ⇒ flat (with both caps).
    public var extrusionDepth: Float?
    public var capFill: TextCapFill?
    public var bevelRadius: Float?
    /// A preset-library reference. Unresolved ⇒ no bevel, reference KEPT.
    public var bevelProfileId: String?
    public var bevelSegments: Int?

    // Material. Absent ⇒ a lit material tinted by `color`.
    public var material: MaterialSpec?
    public var slotMaterials: TextSlotMaterials?

    /// K12: the two-tier template split, expressed as an EXPLICIT FLAG ON
    /// THE FIELD — never a magic-string sentinel. In a LOCKED template the
    /// consumer edits exactly the flagged text and nothing else. Absent
    /// means `false`: locked by default in a locked template.
    public var isConsumerEditable: Bool?

    public init(text: String, fontSize: Float = 0.1, color: ColorRGBA = .white,
                maxWidth: Float? = nil,
                fontFamily: String? = nil, fontWeight: Int? = nil,
                fontIsItalic: Bool? = nil, fontSourceId: String? = nil,
                tracking: Float? = nil, leading: Float? = nil,
                alignmentX: TextAlignmentX? = nil, alignmentY: TextAlignmentY? = nil,
                extrusionDepth: Float? = nil, capFill: TextCapFill? = nil,
                bevelRadius: Float? = nil, bevelProfileId: String? = nil,
                bevelSegments: Int? = nil,
                material: MaterialSpec? = nil,
                slotMaterials: TextSlotMaterials? = nil,
                isConsumerEditable: Bool? = nil) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.maxWidth = maxWidth
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontIsItalic = fontIsItalic
        self.fontSourceId = fontSourceId
        self.tracking = tracking
        self.leading = leading
        self.alignmentX = alignmentX
        self.alignmentY = alignmentY
        self.extrusionDepth = extrusionDepth
        self.capFill = capFill
        self.bevelRadius = bevelRadius
        self.bevelProfileId = bevelProfileId
        self.bevelSegments = bevelSegments
        self.material = material
        self.slotMaterials = slotMaterials
        self.isConsumerEditable = isConsumerEditable
    }

    private enum CodingKeys: String, CodingKey {
        case text, fontSize, color, maxWidth
        case fontFamily, fontWeight, fontIsItalic, fontSourceId, tracking, leading
        case alignmentX, alignmentY
        case extrusionDepth, capFill, bevelRadius, bevelProfileId, bevelSegments
        case material, slotMaterials
        case isConsumerEditable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decode(String.self, forKey: .text)
        self.fontSize = try c.decodeIfPresent(Float.self, forKey: .fontSize) ?? 0.1
        self.color = try c.decodeIfPresent(ColorRGBA.self, forKey: .color) ?? .white
        self.maxWidth = try c.decodeIfPresent(Float.self, forKey: .maxWidth)
        self.fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
        self.fontWeight = try c.decodeIfPresent(Int.self, forKey: .fontWeight)
        self.fontIsItalic = try c.decodeIfPresent(Bool.self, forKey: .fontIsItalic)
        self.fontSourceId = try c.decodeIfPresent(String.self, forKey: .fontSourceId)
        self.tracking = try c.decodeIfPresent(Float.self, forKey: .tracking)
        self.leading = try c.decodeIfPresent(Float.self, forKey: .leading)
        // ENUMS DECODE TOLERANTLY: a case written by a newer tool reads as
        // absent (today's constant), never as a failed document.
        self.alignmentX = (try? c.decodeIfPresent(String.self, forKey: .alignmentX))
            .flatMap { TextAlignmentX(rawValue: $0) }
        self.alignmentY = (try? c.decodeIfPresent(String.self, forKey: .alignmentY))
            .flatMap { TextAlignmentY(rawValue: $0) }
        self.extrusionDepth = try c.decodeIfPresent(Float.self, forKey: .extrusionDepth)
        self.capFill = (try? c.decodeIfPresent(String.self, forKey: .capFill))
            .flatMap { TextCapFill(rawValue: $0) }
        self.bevelRadius = try c.decodeIfPresent(Float.self, forKey: .bevelRadius)
        self.bevelProfileId = try c.decodeIfPresent(String.self, forKey: .bevelProfileId)
        self.bevelSegments = try c.decodeIfPresent(Int.self, forKey: .bevelSegments)
        self.material = try c.decodeIfPresent(MaterialSpec.self, forKey: .material)
        self.slotMaterials = try c.decodeIfPresent(TextSlotMaterials.self, forKey: .slotMaterials)
        self.isConsumerEditable = try c.decodeIfPresent(Bool.self, forKey: .isConsumerEditable)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(maxWidth, forKey: .maxWidth)
        try c.encodeIfPresent(fontFamily, forKey: .fontFamily)
        try c.encodeIfPresent(fontWeight, forKey: .fontWeight)
        try c.encodeIfPresent(fontIsItalic, forKey: .fontIsItalic)
        try c.encodeIfPresent(fontSourceId, forKey: .fontSourceId)
        try c.encodeIfPresent(tracking, forKey: .tracking)
        try c.encodeIfPresent(leading, forKey: .leading)
        try c.encodeIfPresent(alignmentX, forKey: .alignmentX)
        try c.encodeIfPresent(alignmentY, forKey: .alignmentY)
        try c.encodeIfPresent(extrusionDepth, forKey: .extrusionDepth)
        try c.encodeIfPresent(capFill, forKey: .capFill)
        try c.encodeIfPresent(bevelRadius, forKey: .bevelRadius)
        try c.encodeIfPresent(bevelProfileId, forKey: .bevelProfileId)
        try c.encodeIfPresent(bevelSegments, forKey: .bevelSegments)
        try c.encodeIfPresent(material, forKey: .material)
        try c.encodeIfPresent(slotMaterials, forKey: .slotMaterials)
        try c.encodeIfPresent(isConsumerEditable, forKey: .isConsumerEditable)
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

/// One Rig membership (FL-15). `bindParentRest` is the Rig's AUTHORED rest
/// as it was when this member joined - the frozen bind correction's input.
/// Stored as the rest (always TRS-representable, and it READS: "this member
/// joined when the Rig was here"); the inverse is taken at evaluation, in
/// matrix space. nil means identity - a join at the origin, and what the
/// bare-[String] proposal shape means.
///
/// NOTHING here ever touches the member's own transform or its keys:
/// joining is byte-identity on the member, by construction.
public struct RigMember: Codable, Sendable, Equatable {
    public var id: String
    public var bindParentRest: TransformData?

    public init(id: String, bindParentRest: TransformData? = nil) {
        self.id = id
        self.bindParentRest = bindParentRest
    }

    private enum CodingKeys: String, CodingKey { case id, bindParentRest }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.bindParentRest = try c.decodeIfPresent(TransformData.self,
                                                    forKey: .bindParentRest)
    }
}
