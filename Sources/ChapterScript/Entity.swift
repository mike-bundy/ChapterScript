import Foundation

/// Declarative description of a named entity that the player should construct
/// when an experience loads. Entities are referenced by `id` from `StepActionDTO` cases.
public struct EntityDefinition: Codable, Sendable, Equatable {
    public var id: String                    // canonical name used in StepAction (e.g. "orb")
    public var kind: EntityKind
    public var transform: TransformData
    /// Initial enabled state. `false` keeps the entity in the registry but hidden until `showEntity`.
    public var initiallyEnabled: Bool
    public var gestureEnabled: Bool

    // Per-kind specs (only one is non-nil; matched to `kind`)
    public var primitive: PrimitiveSpec?
    public var usdzAssetId: String?           // AssetEntry.id of a USDZ in the manifest
    public var text: TextSpec?
    public var light: LightSpec?
    public var videoPanel: VideoPanelSpec?
    public var particlePresetId: String?      // references ParticleEmitterPreset.id
    public var customFactoryId: String?       // app-registered factory key for `kind == .custom`
    /// Free-form parameters passed to a custom factory. Players may interpret as JSON.
    public var customParameters: [String: AnyCodableValue]?

    public init(
        id: String,
        kind: EntityKind,
        transform: TransformData = .identity,
        initiallyEnabled: Bool = false,
        gestureEnabled: Bool = false,
        primitive: PrimitiveSpec? = nil,
        usdzAssetId: String? = nil,
        text: TextSpec? = nil,
        light: LightSpec? = nil,
        videoPanel: VideoPanelSpec? = nil,
        particlePresetId: String? = nil,
        customFactoryId: String? = nil,
        customParameters: [String: AnyCodableValue]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.transform = transform
        self.initiallyEnabled = initiallyEnabled
        self.gestureEnabled = gestureEnabled
        self.primitive = primitive
        self.usdzAssetId = usdzAssetId
        self.text = text
        self.light = light
        self.videoPanel = videoPanel
        self.particlePresetId = particlePresetId
        self.customFactoryId = customFactoryId
        self.customParameters = customParameters
    }
}

public enum EntityKind: String, Codable, Sendable, Equatable {
    case primitive
    case usdz
    case text3D
    case light
    case videoPanel
    case particles
    case custom
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

    public init(width: Float, height: Float, placeholderColor: ColorRGBA? = nil) {
        self.width = width
        self.height = height
        self.placeholderColor = placeholderColor
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
