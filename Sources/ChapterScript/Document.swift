import Foundation

/// Top-level immersive experience document. Lives at `chapter.json` inside a `.chapterscript` bundle.
public struct ChapterDocument: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var id: String
    public var displayName: String
    public var description: String?
    public var entities: [EntityDefinition]
    public var segments: [SegmentDefinitionDTO]
    public var particlePresets: [ParticleEmitterPreset]
    /// Global scene environment (lighting preset + fog). Optional and additive:
    /// documents authored before this field existed decode as `nil`, and
    /// players fall back to their own defaults.
    public var environment: EnvironmentSpec?
    public var manifest: AssetManifest
    /// Initial segment id played when the experience loads. Defaults to first segment.
    public var defaultSegmentId: String?
    /// EDITOR-ONLY organisation. Never read by ChapterPlayer.
    ///
    /// Optional and tolerant: documents authored before this field existed
    /// decode as `nil`, and a player that has never heard of it ignores the
    /// key. It lives in the document rather than in `UserDefaults` so a
    /// project's organisation travels with the bundle — open the same
    /// `.chapterscript` on another Mac and the Bins are still there.
    public var editorMetadata: EditorMetadata?

    public init(
        formatVersion: Int = ChapterScriptFormat.currentFormatVersion,
        id: String,
        displayName: String,
        description: String? = nil,
        entities: [EntityDefinition] = [],
        segments: [SegmentDefinitionDTO] = [],
        particlePresets: [ParticleEmitterPreset] = [],
        environment: EnvironmentSpec? = nil,
        manifest: AssetManifest = AssetManifest(),
        defaultSegmentId: String? = nil,
        editorMetadata: EditorMetadata? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.entities = entities
        self.segments = segments
        self.particlePresets = particlePresets
        self.environment = environment
        self.manifest = manifest
        self.defaultSegmentId = defaultSegmentId
        self.editorMetadata = editorMetadata
    }

    // Decode-if-present for `environment` so documents authored before
    // this format revision keep loading. Encode stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, displayName, description
        case entities, segments, particlePresets, environment
        case manifest, defaultSegmentId, editorMetadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.entities = try c.decode([EntityDefinition].self, forKey: .entities)
        self.segments = try c.decode([SegmentDefinitionDTO].self, forKey: .segments)
        self.particlePresets = try c.decode([ParticleEmitterPreset].self, forKey: .particlePresets)
        self.environment = try c.decodeIfPresent(EnvironmentSpec.self, forKey: .environment)
        self.manifest = try c.decode(AssetManifest.self, forKey: .manifest)
        self.defaultSegmentId = try c.decodeIfPresent(String.self, forKey: .defaultSegmentId)
        self.editorMetadata = try c.decodeIfPresent(EditorMetadata.self, forKey: .editorMetadata)
    }
}

/// EDITOR-ONLY project organisation. Runtime-inert by contract: ChapterPlayer
/// must never read this, and nothing here may affect playback.
///
/// Kept deliberately small. Anything that changes what the experience DOES
/// belongs in the document proper, not here.
public struct EditorMetadata: Codable, Sendable, Equatable {
    /// Virtual asset collections. Bins never move or copy files inside the
    /// bundle — they are labels over `manifest` entries, so deleting a Bin
    /// cannot delete media.
    public var bins: [MediaBin]

    public init(bins: [MediaBin] = []) {
        self.bins = bins
    }

    private enum CodingKeys: String, CodingKey { case bins }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bins = try c.decodeIfPresent([MediaBin].self, forKey: .bins) ?? []
    }
}

/// A virtual collection of project media. Editor-only.
public struct MediaBin: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Asset filenames, matching `AssetEntry` ids used elsewhere in the
    /// editor. An asset may belong to several Bins; membership is a label,
    /// not ownership.
    public var assets: [String]
    /// Marks the single built-in staging collection, so the editor can pin it
    /// and refuse to delete it. Free-form rather than a separate type: a
    /// staging Bin IS a Bin, and giving it its own persistence would be a
    /// second system for no gain.
    public var isStaging: Bool

    public init(id: String = UUID().uuidString, name: String, assets: [String] = [], isStaging: Bool = false) {
        self.id = id
        self.name = name
        self.assets = assets
        self.isStaging = isStaging
    }

    private enum CodingKeys: String, CodingKey { case id, name, assets, isStaging }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Bin"
        self.assets = try c.decodeIfPresent([String].self, forKey: .assets) ?? []
        self.isStaging = try c.decodeIfPresent(Bool.self, forKey: .isStaging) ?? false
    }
}

/// Global scene environment authored by editors: a free-form lighting preset
/// tag plus a simple distance-fog toggle. Players map `lighting` onto their
/// own rendering setup (image-based lighting, exposure, background tint) and
/// may ignore tags they don't recognize.
public struct EnvironmentSpec: Codable, Sendable, Equatable {
    /// Free preset tag (e.g. "studio", "natural", "sunset", "night", "overcast").
    public var lighting: String
    public var fogEnabled: Bool
    public var fogDensity: Float

    public init(
        lighting: String = "studio",
        fogEnabled: Bool = false,
        fogDensity: Float = 0.02
    ) {
        self.lighting = lighting
        self.fogEnabled = fogEnabled
        self.fogDensity = fogDensity
    }

    // Field-tolerant decode: partially-specified environments (or fields
    // added later) fall back to the defaults above.
    private enum CodingKeys: String, CodingKey {
        case lighting, fogEnabled, fogDensity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lighting = try c.decodeIfPresent(String.self, forKey: .lighting) ?? "studio"
        self.fogEnabled = try c.decodeIfPresent(Bool.self, forKey: .fogEnabled) ?? false
        self.fogDensity = try c.decodeIfPresent(Float.self, forKey: .fogDensity) ?? 0.02
    }
}

public struct AssetManifest: Codable, Sendable, Equatable {
    public var entries: [AssetEntry]

    public init(entries: [AssetEntry] = []) {
        self.entries = entries
    }

    public func entry(id: String) -> AssetEntry? {
        entries.first { $0.id == id }
    }
}

public struct AssetEntry: Codable, Sendable, Equatable {
    public var id: String
    public var relativePath: String      // path within the .chapterscript/assets/ folder
    public var kind: AssetKind
    public var sha256: String?
    public var byteSize: Int64?
    public var durationMs: Int?           // for audio/video
    public var width: Int?                 // for images/video
    public var height: Int?

    public init(
        id: String,
        relativePath: String,
        kind: AssetKind,
        sha256: String? = nil,
        byteSize: Int64? = nil,
        durationMs: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.sha256 = sha256
        self.byteSize = byteSize
        self.durationMs = durationMs
        self.width = width
        self.height = height
    }
}

public enum AssetKind: String, Codable, Sendable, Equatable {
    case audio
    case video
    case usdz
    case image
    case other
}

/// Particle emitter preset reference. Authored by editors (e.g. Maestro's Afterburn UI),
/// played back by the player as a `ParticleEmitterComponent`-equivalent.
///
/// The original 14 fields (id…loops) are the compact authoring surface and keep their
/// exact names/semantics. Everything after them is the full-fidelity Afterburn knob set
/// (mirroring Maestro's `SavedParticle.EmitterData`), added additively: every extended
/// field decodes-if-present with the Afterburn `EmitterSettings` default, so documents
/// authored before this revision decode unchanged and render identically.
///
/// Units/semantics worth calling out:
/// - `spreadAngle` is DEGREES (players convert to radians) — unchanged.
/// - `endSize` stays the absolute end-of-lifespan size; players derive RealityKit's
///   `sizeMultiplierAtEndOfLifespan` as `endSize / startSize` (end size wins when
///   `startSize == 0`). `sizeMultiplierAtEndOfLifespanPower` shapes that ramp.
/// - `gravity` remains the constant acceleration vector (RealityKit `acceleration`).
/// - `angle`/`angleVariation`/`angularSpeed`/`angularSpeedVariation` are RADIANS,
///   passed straight through to RealityKit — matching what Afterburn's viewport
///   actually renders (its `create(from:)` does no conversion).
/// - `colorSetting == .constant` (the default) preserves the legacy rendering:
///   a single `color` whose alpha ramps `startOpacity → endOpacity`. `.evolving`
///   (and `.random`, which players may approximate as evolving) blends
///   `color@startOpacity → color2@endOpacity` shaped by `colorEvolutionPower`.
/// - `burstCount == nil` keeps the legacy non-looping burst sizing
///   (`birthRate × lifeSpan`); a value overrides it.
/// - `mainImage`: `nil`/`"none"` = untextured; `"default"` = the soft radial
///   sprite; anything else is an SF Symbol name rendered white.
public struct ParticleEmitterPreset: Codable, Sendable, Equatable {
    // MARK: Original compact surface (unchanged)
    public var id: String
    public var displayName: String
    public var birthRate: Float
    public var lifeSpan: Float
    public var speed: Float
    public var emitterShape: ParticleEmitterShape
    public var spreadAngle: Float
    public var color: ColorRGBA
    public var startSize: Float
    public var endSize: Float
    public var startOpacity: Float
    public var endOpacity: Float
    public var blending: MaterialBlending
    public var gravity: Vec3
    public var loops: Bool

    // MARK: Emission
    public var birthRateVariation: Float
    public var emitterShapeSize: Vec3
    public var birthDirection: ParticleBirthDirection
    public var birthLocation: ParticleBirthLocation
    public var emissionDirection: Vec3
    public var radialAmount: Float
    public var torusInnerRadius: Float
    /// Burst size for non-looping presets (and explicit `burst()` calls).
    /// `nil` = derive `birthRate × lifeSpan` like the legacy player did.
    public var burstCount: Int?
    public var particlesInheritTransform: Bool

    // MARK: Lifespan & size
    public var lifeSpanVariation: Float
    public var sizeVariation: Float
    public var sizeMultiplierAtEndOfLifespanPower: Float

    // MARK: Physics
    public var mass: Float
    public var massVariation: Float
    public var angle: Float
    public var angleVariation: Float
    public var angularSpeed: Float
    public var angularSpeedVariation: Float
    public var dampingFactor: Float
    public var stretchFactor: Float

    // MARK: Color
    public var colorSetting: ParticleColorMode
    public var color2: ColorRGBA
    public var colorEvolutionPower: Float

    // MARK: Visual
    public var opacityCurve: ParticleOpacityCurve
    public var billboardMode: ParticleBillboardMode
    public var isLightingEnabled: Bool
    public var sortOrder: ParticleSortOrder
    public var mainImage: String?

    // MARK: Force fields
    public var noiseStrength: Float
    public var noiseScale: Float
    public var noiseAnimationSpeed: Float
    public var attractionStrength: Float
    public var attractionCenter: Vec3
    public var vortexStrength: Float
    public var vortexDirection: Vec3

    // MARK: Spawned (secondary) emitter
    public var spawn: SpawnedEmitterSpec?

    public init(
        id: String,
        displayName: String,
        birthRate: Float = 100,
        lifeSpan: Float = 1.5,
        speed: Float = 0.5,
        emitterShape: ParticleEmitterShape = .point,
        spreadAngle: Float = 30,
        color: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
        startSize: Float = 0.02,
        endSize: Float = 0.0,
        startOpacity: Float = 1,
        endOpacity: Float = 0,
        blending: MaterialBlending = .additive,
        gravity: Vec3 = Vec3(0, 0, 0),
        loops: Bool = true,
        birthRateVariation: Float = 0,
        emitterShapeSize: Vec3 = Vec3(0.1, 0.1, 0.1),
        birthDirection: ParticleBirthDirection = .normal,
        birthLocation: ParticleBirthLocation = .surface,
        emissionDirection: Vec3 = Vec3(0, 1, 0),
        radialAmount: Float = 6.283,
        torusInnerRadius: Float = 0.5,
        burstCount: Int? = nil,
        particlesInheritTransform: Bool = false,
        lifeSpanVariation: Float = 0,
        sizeVariation: Float = 0,
        sizeMultiplierAtEndOfLifespanPower: Float = 1.0,
        mass: Float = 1.0,
        massVariation: Float = 0,
        angle: Float = 0,
        angleVariation: Float = 0,
        angularSpeed: Float = 0,
        angularSpeedVariation: Float = 0,
        dampingFactor: Float = 0,
        stretchFactor: Float = 0,
        colorSetting: ParticleColorMode = .constant,
        color2: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
        colorEvolutionPower: Float = 1.0,
        opacityCurve: ParticleOpacityCurve = .constant,
        billboardMode: ParticleBillboardMode = .billboard,
        isLightingEnabled: Bool = false,
        sortOrder: ParticleSortOrder = .unsorted,
        mainImage: String? = nil,
        noiseStrength: Float = 0,
        noiseScale: Float = 1.0,
        noiseAnimationSpeed: Float = 0,
        attractionStrength: Float = 0,
        attractionCenter: Vec3 = Vec3(0, 0, 0),
        vortexStrength: Float = 0,
        vortexDirection: Vec3 = Vec3(0, 1, 0),
        spawn: SpawnedEmitterSpec? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.birthRate = birthRate
        self.lifeSpan = lifeSpan
        self.speed = speed
        self.emitterShape = emitterShape
        self.spreadAngle = spreadAngle
        self.color = color
        self.startSize = startSize
        self.endSize = endSize
        self.startOpacity = startOpacity
        self.endOpacity = endOpacity
        self.blending = blending
        self.gravity = gravity
        self.loops = loops
        self.birthRateVariation = birthRateVariation
        self.emitterShapeSize = emitterShapeSize
        self.birthDirection = birthDirection
        self.birthLocation = birthLocation
        self.emissionDirection = emissionDirection
        self.radialAmount = radialAmount
        self.torusInnerRadius = torusInnerRadius
        self.burstCount = burstCount
        self.particlesInheritTransform = particlesInheritTransform
        self.lifeSpanVariation = lifeSpanVariation
        self.sizeVariation = sizeVariation
        self.sizeMultiplierAtEndOfLifespanPower = sizeMultiplierAtEndOfLifespanPower
        self.mass = mass
        self.massVariation = massVariation
        self.angle = angle
        self.angleVariation = angleVariation
        self.angularSpeed = angularSpeed
        self.angularSpeedVariation = angularSpeedVariation
        self.dampingFactor = dampingFactor
        self.stretchFactor = stretchFactor
        self.colorSetting = colorSetting
        self.color2 = color2
        self.colorEvolutionPower = colorEvolutionPower
        self.opacityCurve = opacityCurve
        self.billboardMode = billboardMode
        self.isLightingEnabled = isLightingEnabled
        self.sortOrder = sortOrder
        self.mainImage = mainImage
        self.noiseStrength = noiseStrength
        self.noiseScale = noiseScale
        self.noiseAnimationSpeed = noiseAnimationSpeed
        self.attractionStrength = attractionStrength
        self.attractionCenter = attractionCenter
        self.vortexStrength = vortexStrength
        self.vortexDirection = vortexDirection
        self.spawn = spawn
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, birthRate, lifeSpan, speed, emitterShape, spreadAngle
        case color, startSize, endSize, startOpacity, endOpacity, blending, gravity, loops
        case birthRateVariation, emitterShapeSize, birthDirection, birthLocation
        case emissionDirection, radialAmount, torusInnerRadius, burstCount
        case particlesInheritTransform
        case lifeSpanVariation, sizeVariation, sizeMultiplierAtEndOfLifespanPower
        case mass, massVariation, angle, angleVariation, angularSpeed
        case angularSpeedVariation, dampingFactor, stretchFactor
        case colorSetting, color2, colorEvolutionPower
        case opacityCurve, billboardMode, isLightingEnabled, sortOrder, mainImage
        case noiseStrength, noiseScale, noiseAnimationSpeed
        case attractionStrength, attractionCenter, vortexStrength, vortexDirection
        case spawn
    }

    // Field-tolerant decode: every field beyond id/displayName is
    // decode-if-present with the default above, and enum strings fall back to
    // their default when unrecognized — so old documents decode unchanged and
    // future additive fields never break this revision.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.birthRate = try c.decodeIfPresent(Float.self, forKey: .birthRate) ?? 100
        self.lifeSpan = try c.decodeIfPresent(Float.self, forKey: .lifeSpan) ?? 1.5
        self.speed = try c.decodeIfPresent(Float.self, forKey: .speed) ?? 0.5
        self.emitterShape = c.tolerantEnum(.emitterShape, default: .point)
        self.spreadAngle = try c.decodeIfPresent(Float.self, forKey: .spreadAngle) ?? 30
        self.color = try c.decodeIfPresent(ColorRGBA.self, forKey: .color) ?? ColorRGBA(r: 1, g: 1, b: 1)
        self.startSize = try c.decodeIfPresent(Float.self, forKey: .startSize) ?? 0.02
        self.endSize = try c.decodeIfPresent(Float.self, forKey: .endSize) ?? 0.0
        self.startOpacity = try c.decodeIfPresent(Float.self, forKey: .startOpacity) ?? 1
        self.endOpacity = try c.decodeIfPresent(Float.self, forKey: .endOpacity) ?? 0
        self.blending = c.tolerantEnum(.blending, default: .additive)
        self.gravity = try c.decodeIfPresent(Vec3.self, forKey: .gravity) ?? Vec3(0, 0, 0)
        self.loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? true
        self.birthRateVariation = try c.decodeIfPresent(Float.self, forKey: .birthRateVariation) ?? 0
        self.emitterShapeSize = try c.decodeIfPresent(Vec3.self, forKey: .emitterShapeSize) ?? Vec3(0.1, 0.1, 0.1)
        self.birthDirection = c.tolerantEnum(.birthDirection, default: .normal)
        self.birthLocation = c.tolerantEnum(.birthLocation, default: .surface)
        self.emissionDirection = try c.decodeIfPresent(Vec3.self, forKey: .emissionDirection) ?? Vec3(0, 1, 0)
        self.radialAmount = try c.decodeIfPresent(Float.self, forKey: .radialAmount) ?? 6.283
        self.torusInnerRadius = try c.decodeIfPresent(Float.self, forKey: .torusInnerRadius) ?? 0.5
        self.burstCount = try c.decodeIfPresent(Int.self, forKey: .burstCount)
        self.particlesInheritTransform = try c.decodeIfPresent(Bool.self, forKey: .particlesInheritTransform) ?? false
        self.lifeSpanVariation = try c.decodeIfPresent(Float.self, forKey: .lifeSpanVariation) ?? 0
        self.sizeVariation = try c.decodeIfPresent(Float.self, forKey: .sizeVariation) ?? 0
        self.sizeMultiplierAtEndOfLifespanPower = try c.decodeIfPresent(Float.self, forKey: .sizeMultiplierAtEndOfLifespanPower) ?? 1.0
        self.mass = try c.decodeIfPresent(Float.self, forKey: .mass) ?? 1.0
        self.massVariation = try c.decodeIfPresent(Float.self, forKey: .massVariation) ?? 0
        self.angle = try c.decodeIfPresent(Float.self, forKey: .angle) ?? 0
        self.angleVariation = try c.decodeIfPresent(Float.self, forKey: .angleVariation) ?? 0
        self.angularSpeed = try c.decodeIfPresent(Float.self, forKey: .angularSpeed) ?? 0
        self.angularSpeedVariation = try c.decodeIfPresent(Float.self, forKey: .angularSpeedVariation) ?? 0
        self.dampingFactor = try c.decodeIfPresent(Float.self, forKey: .dampingFactor) ?? 0
        self.stretchFactor = try c.decodeIfPresent(Float.self, forKey: .stretchFactor) ?? 0
        self.colorSetting = c.tolerantEnum(.colorSetting, default: .constant)
        self.color2 = try c.decodeIfPresent(ColorRGBA.self, forKey: .color2) ?? ColorRGBA(r: 1, g: 1, b: 1)
        self.colorEvolutionPower = try c.decodeIfPresent(Float.self, forKey: .colorEvolutionPower) ?? 1.0
        self.opacityCurve = c.tolerantEnum(.opacityCurve, default: .constant)
        self.billboardMode = c.tolerantEnum(.billboardMode, default: .billboard)
        self.isLightingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isLightingEnabled) ?? false
        self.sortOrder = c.tolerantEnum(.sortOrder, default: .unsorted)
        self.mainImage = try c.decodeIfPresent(String.self, forKey: .mainImage)
        self.noiseStrength = try c.decodeIfPresent(Float.self, forKey: .noiseStrength) ?? 0
        self.noiseScale = try c.decodeIfPresent(Float.self, forKey: .noiseScale) ?? 1.0
        self.noiseAnimationSpeed = try c.decodeIfPresent(Float.self, forKey: .noiseAnimationSpeed) ?? 0
        self.attractionStrength = try c.decodeIfPresent(Float.self, forKey: .attractionStrength) ?? 0
        self.attractionCenter = try c.decodeIfPresent(Vec3.self, forKey: .attractionCenter) ?? Vec3(0, 0, 0)
        self.vortexStrength = try c.decodeIfPresent(Float.self, forKey: .vortexStrength) ?? 0
        self.vortexDirection = try c.decodeIfPresent(Vec3.self, forKey: .vortexDirection) ?? Vec3(0, 1, 0)
        self.spawn = try c.decodeIfPresent(SpawnedEmitterSpec.self, forKey: .spawn)
    }

    /// Secondary (spawned) particle emitter — RealityKit's `spawnedEmitter`
    /// plus the spawn-behavior knobs that live on the component. Mirrors
    /// Maestro's `SavedParticle.EmitterData.SpawnedEmitterData` + spawn
    /// settings. Presence of this spec = secondary particles enabled.
    ///
    /// Units match the parent preset: `spreadAngle` is degrees; `angle` /
    /// `angularSpeed` (and their variations) are radians passed straight
    /// through, matching Afterburn's viewport.
    public struct SpawnedEmitterSpec: Codable, Sendable, Equatable {
        // Spawn behavior (lives on the component)
        public var spawnOccasion: ParticleSpawnOccasion
        public var spawnSpreadFactor: Float
        public var spawnVelocityFactor: Float
        public var spawnInheritsParentColor: Bool
        /// Spawned-particle texture: nil/"none" = untextured, "default" = soft
        /// radial sprite, else SF Symbol name.
        public var image: String?

        // Emission
        public var birthRate: Float
        public var birthRateVariation: Float

        // Lifespan & size
        public var lifeSpan: Float
        public var lifeSpanVariation: Float
        public var size: Float
        public var sizeVariation: Float
        public var sizeMultiplierAtEndOfLifespan: Float
        public var sizeMultiplierAtEndOfLifespanPower: Float

        // Physics
        public var mass: Float
        public var massVariation: Float
        public var acceleration: Vec3
        public var angle: Float
        public var angleVariation: Float
        public var angularSpeed: Float
        public var angularSpeedVariation: Float
        public var dampingFactor: Float
        public var spreadAngle: Float
        public var stretchFactor: Float

        // Color
        public var colorSetting: ParticleColorMode
        public var color: ColorRGBA
        public var color2: ColorRGBA
        public var colorEvolutionPower: Float

        // Visual
        public var opacityCurve: ParticleOpacityCurve
        public var billboardMode: ParticleBillboardMode
        public var blending: MaterialBlending
        public var isLightingEnabled: Bool
        public var sortOrder: ParticleSortOrder

        // Force fields
        public var noiseStrength: Float
        public var noiseScale: Float
        public var noiseAnimationSpeed: Float
        public var attractionStrength: Float
        public var attractionCenter: Vec3
        public var vortexStrength: Float
        public var vortexDirection: Vec3

        public init(
            spawnOccasion: ParticleSpawnOccasion = .onBirth,
            spawnSpreadFactor: Float = 0,
            spawnVelocityFactor: Float = 0,
            spawnInheritsParentColor: Bool = false,
            image: String? = nil,
            birthRate: Float = 50,
            birthRateVariation: Float = 0,
            lifeSpan: Float = 1.0,
            lifeSpanVariation: Float = 0,
            size: Float = 0.03,
            sizeVariation: Float = 0,
            sizeMultiplierAtEndOfLifespan: Float = 1.0,
            sizeMultiplierAtEndOfLifespanPower: Float = 1.0,
            mass: Float = 1.0,
            massVariation: Float = 0,
            acceleration: Vec3 = Vec3(0, 0, 0),
            angle: Float = 0,
            angleVariation: Float = 0,
            angularSpeed: Float = 0,
            angularSpeedVariation: Float = 0,
            dampingFactor: Float = 0,
            spreadAngle: Float = 0,
            stretchFactor: Float = 0,
            colorSetting: ParticleColorMode = .constant,
            color: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
            color2: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
            colorEvolutionPower: Float = 1.0,
            opacityCurve: ParticleOpacityCurve = .constant,
            billboardMode: ParticleBillboardMode = .billboard,
            blending: MaterialBlending = .additive,
            isLightingEnabled: Bool = false,
            sortOrder: ParticleSortOrder = .unsorted,
            noiseStrength: Float = 0,
            noiseScale: Float = 1.0,
            noiseAnimationSpeed: Float = 0,
            attractionStrength: Float = 0,
            attractionCenter: Vec3 = Vec3(0, 0, 0),
            vortexStrength: Float = 0,
            vortexDirection: Vec3 = Vec3(0, 1, 0)
        ) {
            self.spawnOccasion = spawnOccasion
            self.spawnSpreadFactor = spawnSpreadFactor
            self.spawnVelocityFactor = spawnVelocityFactor
            self.spawnInheritsParentColor = spawnInheritsParentColor
            self.image = image
            self.birthRate = birthRate
            self.birthRateVariation = birthRateVariation
            self.lifeSpan = lifeSpan
            self.lifeSpanVariation = lifeSpanVariation
            self.size = size
            self.sizeVariation = sizeVariation
            self.sizeMultiplierAtEndOfLifespan = sizeMultiplierAtEndOfLifespan
            self.sizeMultiplierAtEndOfLifespanPower = sizeMultiplierAtEndOfLifespanPower
            self.mass = mass
            self.massVariation = massVariation
            self.acceleration = acceleration
            self.angle = angle
            self.angleVariation = angleVariation
            self.angularSpeed = angularSpeed
            self.angularSpeedVariation = angularSpeedVariation
            self.dampingFactor = dampingFactor
            self.spreadAngle = spreadAngle
            self.stretchFactor = stretchFactor
            self.colorSetting = colorSetting
            self.color = color
            self.color2 = color2
            self.colorEvolutionPower = colorEvolutionPower
            self.opacityCurve = opacityCurve
            self.billboardMode = billboardMode
            self.blending = blending
            self.isLightingEnabled = isLightingEnabled
            self.sortOrder = sortOrder
            self.noiseStrength = noiseStrength
            self.noiseScale = noiseScale
            self.noiseAnimationSpeed = noiseAnimationSpeed
            self.attractionStrength = attractionStrength
            self.attractionCenter = attractionCenter
            self.vortexStrength = vortexStrength
            self.vortexDirection = vortexDirection
        }

        private enum CodingKeys: String, CodingKey {
            case spawnOccasion, spawnSpreadFactor, spawnVelocityFactor
            case spawnInheritsParentColor, image
            case birthRate, birthRateVariation
            case lifeSpan, lifeSpanVariation, size, sizeVariation
            case sizeMultiplierAtEndOfLifespan, sizeMultiplierAtEndOfLifespanPower
            case mass, massVariation, acceleration, angle, angleVariation
            case angularSpeed, angularSpeedVariation, dampingFactor, spreadAngle, stretchFactor
            case colorSetting, color, color2, colorEvolutionPower
            case opacityCurve, billboardMode, blending, isLightingEnabled, sortOrder
            case noiseStrength, noiseScale, noiseAnimationSpeed
            case attractionStrength, attractionCenter, vortexStrength, vortexDirection
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.spawnOccasion = c.tolerantEnum(.spawnOccasion, default: .onBirth)
            self.spawnSpreadFactor = try c.decodeIfPresent(Float.self, forKey: .spawnSpreadFactor) ?? 0
            self.spawnVelocityFactor = try c.decodeIfPresent(Float.self, forKey: .spawnVelocityFactor) ?? 0
            self.spawnInheritsParentColor = try c.decodeIfPresent(Bool.self, forKey: .spawnInheritsParentColor) ?? false
            self.image = try c.decodeIfPresent(String.self, forKey: .image)
            self.birthRate = try c.decodeIfPresent(Float.self, forKey: .birthRate) ?? 50
            self.birthRateVariation = try c.decodeIfPresent(Float.self, forKey: .birthRateVariation) ?? 0
            self.lifeSpan = try c.decodeIfPresent(Float.self, forKey: .lifeSpan) ?? 1.0
            self.lifeSpanVariation = try c.decodeIfPresent(Float.self, forKey: .lifeSpanVariation) ?? 0
            self.size = try c.decodeIfPresent(Float.self, forKey: .size) ?? 0.03
            self.sizeVariation = try c.decodeIfPresent(Float.self, forKey: .sizeVariation) ?? 0
            self.sizeMultiplierAtEndOfLifespan = try c.decodeIfPresent(Float.self, forKey: .sizeMultiplierAtEndOfLifespan) ?? 1.0
            self.sizeMultiplierAtEndOfLifespanPower = try c.decodeIfPresent(Float.self, forKey: .sizeMultiplierAtEndOfLifespanPower) ?? 1.0
            self.mass = try c.decodeIfPresent(Float.self, forKey: .mass) ?? 1.0
            self.massVariation = try c.decodeIfPresent(Float.self, forKey: .massVariation) ?? 0
            self.acceleration = try c.decodeIfPresent(Vec3.self, forKey: .acceleration) ?? Vec3(0, 0, 0)
            self.angle = try c.decodeIfPresent(Float.self, forKey: .angle) ?? 0
            self.angleVariation = try c.decodeIfPresent(Float.self, forKey: .angleVariation) ?? 0
            self.angularSpeed = try c.decodeIfPresent(Float.self, forKey: .angularSpeed) ?? 0
            self.angularSpeedVariation = try c.decodeIfPresent(Float.self, forKey: .angularSpeedVariation) ?? 0
            self.dampingFactor = try c.decodeIfPresent(Float.self, forKey: .dampingFactor) ?? 0
            self.spreadAngle = try c.decodeIfPresent(Float.self, forKey: .spreadAngle) ?? 0
            self.stretchFactor = try c.decodeIfPresent(Float.self, forKey: .stretchFactor) ?? 0
            self.colorSetting = c.tolerantEnum(.colorSetting, default: .constant)
            self.color = try c.decodeIfPresent(ColorRGBA.self, forKey: .color) ?? ColorRGBA(r: 1, g: 1, b: 1)
            self.color2 = try c.decodeIfPresent(ColorRGBA.self, forKey: .color2) ?? ColorRGBA(r: 1, g: 1, b: 1)
            self.colorEvolutionPower = try c.decodeIfPresent(Float.self, forKey: .colorEvolutionPower) ?? 1.0
            self.opacityCurve = c.tolerantEnum(.opacityCurve, default: .constant)
            self.billboardMode = c.tolerantEnum(.billboardMode, default: .billboard)
            self.blending = c.tolerantEnum(.blending, default: .additive)
            self.isLightingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isLightingEnabled) ?? false
            self.sortOrder = c.tolerantEnum(.sortOrder, default: .unsorted)
            self.noiseStrength = try c.decodeIfPresent(Float.self, forKey: .noiseStrength) ?? 0
            self.noiseScale = try c.decodeIfPresent(Float.self, forKey: .noiseScale) ?? 1.0
            self.noiseAnimationSpeed = try c.decodeIfPresent(Float.self, forKey: .noiseAnimationSpeed) ?? 0
            self.attractionStrength = try c.decodeIfPresent(Float.self, forKey: .attractionStrength) ?? 0
            self.attractionCenter = try c.decodeIfPresent(Vec3.self, forKey: .attractionCenter) ?? Vec3(0, 0, 0)
            self.vortexStrength = try c.decodeIfPresent(Float.self, forKey: .vortexStrength) ?? 0
            self.vortexDirection = try c.decodeIfPresent(Vec3.self, forKey: .vortexDirection) ?? Vec3(0, 1, 0)
        }
    }
}

/// `cylinder` and `torus` are additive (Afterburn parity). `hemisphere` predates
/// the parity pass; players without a native hemisphere fall back to sphere.
public enum ParticleEmitterShape: String, Codable, Sendable, Equatable {
    case point, sphere, hemisphere, cone, plane, box, cylinder, torus
}

/// How newborn particles pick their initial travel direction.
public enum ParticleBirthDirection: String, Codable, Sendable, Equatable {
    case normal, world, local
}

/// Where on the emitter shape particles are born. Players without a native
/// `vertices` mode fall back to `surface` (matching Afterburn's viewport).
public enum ParticleBirthLocation: String, Codable, Sendable, Equatable {
    case surface, volume, vertices
}

/// Color behavior over a particle's lifetime. `.constant` keeps the legacy
/// single-color + opacity-ramp rendering; `.evolving` blends `color → color2`;
/// `.random` picks per-particle (players may approximate as evolving).
public enum ParticleColorMode: String, Codable, Sendable, Equatable {
    case constant, random, evolving
}

/// Opacity-over-lifetime curve, multiplied on top of the start/end opacity ramp.
public enum ParticleOpacityCurve: String, Codable, Sendable, Equatable {
    case constant, fadeIn, fadeOut, fadeInOut, linearFadeIn, linearFadeOut
}

/// Particle orientation mode. Players without free/velocity-aligned rotation
/// fall back to `billboard` (matching Afterburn's viewport).
public enum ParticleBillboardMode: String, Codable, Sendable, Equatable {
    case billboard, billboardYAligned, freeRotating, velocityAligned
}

/// Particle draw-order sorting.
public enum ParticleSortOrder: String, Codable, Sendable, Equatable {
    case unsorted, depthAscending, depthDescending, ageAscending, ageDescending
}

/// When a spawned (secondary) emitter emits relative to its parent particle.
public enum ParticleSpawnOccasion: String, Codable, Sendable, Equatable {
    case onBirth, onDeath, onUpdate
}

// Tolerant string-raw enum decoding: absent OR unrecognized values fall back
// to the field's documented default instead of failing the whole document.
private extension KeyedDecodingContainer {
    func tolerantEnum<E: RawRepresentable>(_ key: Key, default fallback: E) -> E where E.RawValue == String {
        guard let raw = ((try? decodeIfPresent(String.self, forKey: key)) ?? nil) else { return fallback }
        return E(rawValue: raw) ?? fallback
    }
}

// MARK: - Format constants

/// Static format-level constants and helpers.
/// Named distinctly from the `ChapterScript` module to avoid collision when the module is imported.
public enum ChapterScriptFormat {
    /// Current schema version. Increment when emitting a breaking change; pair with a `Migrator` rule.
    public static let currentFormatVersion: Int = 2   // v2: segments/ChapterDocument vocabulary (breaking; no v1 migration by design)

    /// File name inside a `.chapterscript` directory bundle.
    public static let documentFileName = "chapter.json"

    /// Subfolder inside a `.chapterscript` directory bundle that holds referenced media.
    public static let assetsFolderName = "assets"

    /// Encoder configured for stable, diffable format output: sorted keys, pretty-printed JSON.
    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Decoder configured for the format. Currently default; reserved for future tuning.
    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
