//
//  Effect.swift
//  ChapterScript
//
//  FL-09: the Effect stack's format types. One ordered stack per
//  occurrence — order IS evaluation order — and the sharpest tolerant-
//  decode requirement in the roadmap (G7): an unrecognised Effect keeps
//  its id, EVERY parameter (including unrecognised keys and unrecognised
//  value shapes), its position in the stack and its enabled flag, and
//  re-saves byte-identically. An older build must never destroy a newer
//  build's work.
//
//  Parameters encode as BARE JSON values (a number is 5, a colour is
//  {r,g,b,a}, a point is {x,y}), so the format reads naturally and an
//  unknown shape falls into `.raw` — a lossless JSON tree that re-encodes
//  identically under the format's sorted-keys encoder.
//

import Foundation

// MARK: - The lossless escape

/// Any JSON, kept whole. `.raw` values round-trip through this tree; the
/// format encoder's sorted keys make re-encoding deterministic.
public indirect enum JSONFragment: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONFragment])
    case object([String: JSONFragment])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONFragment].self) {
            self = .array(a)
        } else {
            self = .object(try container.decode([String: JSONFragment].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - A normalized 2D point

/// The format's 2D point (an Effect's `point` parameters — normalized,
/// with the space declared by the schema).
public struct EffectPoint: Codable, Sendable, Equatable, Hashable {
    public var x: Float
    public var y: Float
    public init(x: Float, y: Float) { self.x = x; self.y = y }
}

// MARK: - The value union (F-3: typed, with a raw escape)

/// Typed access to everything this build knows; lossless round-tripping
/// of everything it does not. Object-shaped values (colour, point, and
/// anything newer) keep their ORIGINAL fragment and re-encode it
/// verbatim — decoding a colour into Floats and re-printing it would
/// change bytes, which is G7's failure mode. Typed access is through the
/// accessors; `.raw` is never rendered.
public enum EffectValue: Codable, Sendable, Equatable, Hashable {
    case number(Double)
    case bool(Bool)
    /// A choice's case name.
    case string(String)
    /// Any object, array or null — colours and points included, kept
    /// whole. The accessors below interpret it.
    case raw(JSONFragment)

    public init(from decoder: Decoder) throws {
        let fragment = try JSONFragment(from: decoder)
        switch fragment {
        case .number(let n): self = .number(n)
        case .bool(let b): self = .bool(b)
        case .string(let s): self = .string(s)
        case .null, .array, .object: self = .raw(fragment)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .string(let s): try container.encode(s)
        case .raw(let fragment): try container.encode(fragment)
        }
    }

    // MARK: Typed constructors (what THIS build writes)

    public static func color(_ c: ColorRGBA) -> EffectValue {
        .raw(.object(["r": .number(Double(c.r)), "g": .number(Double(c.g)),
                      "b": .number(Double(c.b)), "a": .number(Double(c.a))]))
    }

    public static func point(_ p: EffectPoint) -> EffectValue {
        .raw(.object(["x": .number(Double(p.x)), "y": .number(Double(p.y))]))
    }

    // MARK: Typed accessors (how a renderer reads)

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var colorValue: ColorRGBA? {
        guard case .raw(.object(let o)) = self, o.count == 4,
              case .number(let r)? = o["r"], case .number(let g)? = o["g"],
              case .number(let b)? = o["b"], case .number(let a)? = o["a"]
        else { return nil }
        return ColorRGBA(r: Float(r), g: Float(g), b: Float(b), a: Float(a))
    }

    public var pointValue: EffectPoint? {
        guard case .raw(.object(let o)) = self, o.count == 2,
              case .number(let x)? = o["x"], case .number(let y)? = o["y"]
        else { return nil }
        return EffectPoint(x: Float(x), y: Float(y))
    }
}

// MARK: - The instance

/// One Effect in an occurrence's ordered stack. `effectId` is a stable
/// STRING, never an enum ordinal, so an unrecognised one is expressible;
/// the instance id is durable and minted, so a Key container can address
/// it and reordering does not change identity.
public struct EffectInstance: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var effectId: String
    /// The author's toggle. Bypass removes the Effect from evaluation
    /// entirely — it costs nothing, not merely looks like nothing.
    public var enabled: Bool
    /// RAW, by design. Unrecognised keys are preserved verbatim.
    public var parameters: [String: EffectValue]

    public init(id: String = "fx_" + UUID().uuidString.prefix(8),
                effectId: String,
                enabled: Bool = true,
                parameters: [String: EffectValue] = [:]) {
        self.id = id
        self.effectId = effectId
        self.enabled = enabled
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey {
        case id, effectId, enabled, parameters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        effectId = try c.decode(String.self, forKey: .effectId)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        parameters = try c.decodeIfPresent([String: EffectValue].self,
                                           forKey: .parameters) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(effectId, forKey: .effectId)
        try c.encode(enabled, forKey: .enabled)
        if !parameters.isEmpty { try c.encode(parameters, forKey: .parameters) }
    }
}

// MARK: - The Key container (G6 / T-7)

/// Effect parameter Keys: a sibling CONTAINER, never a sibling engine.
/// The curve type, the Key type, the tangent model and the evaluator are
/// the EXISTING animation ones — only the addressing is new:
/// `(instanceId, parameterKey)`.
public struct EffectKeyTrack: Codable, Sendable, Equatable {
    /// → `EffectInstance.id`.
    public var instanceId: String
    /// Parameter key → the existing curve type.
    public var channels: [String: AnimationCurve]

    public init(instanceId: String, channels: [String: AnimationCurve] = [:]) {
        self.instanceId = instanceId
        self.channels = channels
    }

    /// Setting an emptied curve REMOVES it, so hasAnyKeys cannot be
    /// fooled by a track full of empty curves - the rule every sibling
    /// track type follows.
    public subscript(_ parameterKey: String) -> AnimationCurve {
        get { channels[parameterKey] ?? AnimationCurve() }
        set { channels[parameterKey] = newValue.isAnimated ? newValue : nil }
    }

    public var hasAnyKeys: Bool { channels.values.contains { $0.isAnimated } }

    /// Union of key times across parameters - the dope-sheet diamonds.
    public var keyTimes: [Double] {
        var times = Set<Double>()
        for curve in channels.values {
            for key in curve.keys { times.insert(key.time) }
        }
        return times.sorted()
    }
}
