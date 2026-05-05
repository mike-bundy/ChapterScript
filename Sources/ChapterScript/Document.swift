import Foundation

/// Top-level immersive experience document. Lives at `experience.json` inside a `.chapterscript` bundle.
public struct ExperienceDocument: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var id: String
    public var displayName: String
    public var description: String?
    public var entities: [EntityDefinition]
    public var chapters: [ChapterDefinitionDTO]
    public var particlePresets: [ParticleEmitterPreset]
    public var manifest: AssetManifest
    /// Initial chapter id played when the experience loads. Defaults to first chapter.
    public var defaultChapterId: String?

    public init(
        formatVersion: Int = ChapterScript.currentFormatVersion,
        id: String,
        displayName: String,
        description: String? = nil,
        entities: [EntityDefinition] = [],
        chapters: [ChapterDefinitionDTO] = [],
        particlePresets: [ParticleEmitterPreset] = [],
        manifest: AssetManifest = AssetManifest(),
        defaultChapterId: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.entities = entities
        self.chapters = chapters
        self.particlePresets = particlePresets
        self.manifest = manifest
        self.defaultChapterId = defaultChapterId
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
/// The full RealityKit ParticleEmitterComponent surface is large and platform-specific —
/// this struct holds the small, format-relevant parameter set that matters for authoring.
/// Players translate it into RealityKit emitter settings at load time.
public struct ParticleEmitterPreset: Codable, Sendable, Equatable {
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
        loops: Bool = true
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
    }
}

public enum ParticleEmitterShape: String, Codable, Sendable, Equatable {
    case point, sphere, hemisphere, cone, plane, box
}

// MARK: - Format constants

/// Static format-level constants and helpers.
public enum ChapterScript {
    /// Current schema version. Increment when emitting a breaking change; pair with a `Migrator` rule.
    public static let currentFormatVersion: Int = 1

    /// File name inside a `.chapterscript` directory bundle.
    public static let documentFileName = "experience.json"

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
