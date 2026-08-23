import Foundation

public struct Vec3: Codable, Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(x: Float = 0, y: Float = 0, z: Float = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)
}

public struct ColorRGBA: Codable, Sendable, Equatable, Hashable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let white = ColorRGBA(r: 1, g: 1, b: 1)
    public static let black = ColorRGBA(r: 0, g: 0, b: 0)
    public static let clear = ColorRGBA(r: 0, g: 0, b: 0, a: 0)
}

public struct TransformData: Codable, Sendable, Equatable {
    public var position: Vec3
    /// Quaternion (x, y, z, w). Identity rotation = (0, 0, 0, 1).
    public var rotation: Quat
    public var scale: Vec3

    public init(
        position: Vec3 = .zero,
        rotation: Quat = .identity,
        scale: Vec3 = Vec3(1, 1, 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    public static let identity = TransformData()

    /// TOLERANT DECODE, like the rest of the format.
    ///
    /// The synthesized decoder required all three keys, so a transform
    /// written with only a position — by an older build, a hand-authored
    /// fixture, or another tool — failed the whole document. There is
    /// nothing to guess: an absent rotation is identity and an absent
    /// scale is unit, which is exactly what `init` already says they are.
    ///
    /// ENCODING IS UNCHANGED: all three keys are always written, so
    /// existing files re-save byte-identically.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.position = try c.decodeIfPresent(Vec3.self, forKey: .position) ?? .zero
        self.rotation = try c.decodeIfPresent(Quat.self, forKey: .rotation) ?? .identity
        self.scale = try c.decodeIfPresent(Vec3.self, forKey: .scale) ?? Vec3(1, 1, 1)
    }
}

public struct Quat: Codable, Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)
}

/// Mirror of SwiftUI's Visibility — kept here because SwiftUI is unavailable cross-platform
/// and SwiftUI.Visibility is not Codable.
public enum VisibilityKind: String, Codable, Sendable, Equatable {
    case automatic
    case visible
    case hidden
}
