//
//  Preset.swift
//  ChapterScript
//
//  FL-21 (R4): ONE catalog shape for every preset kind. A preset is a
//  VALUE — applying it is a copy through that kind's own existing write
//  path. `PresetEntry.id` exists so a preset can be found, favourited
//  and organised; it NEVER appears in an authored fact, so deleting a
//  preset breaks nothing that was made from it.
//
//  Tolerance is G7's, one level up: an unrecognised `kind` keeps its
//  entry (shown as "made with a newer version", not applicable), and an
//  unrecognised payload round-trips verbatim through `.raw`.
//

import Foundation

// MARK: - Kind

/// What a preset is a preset OF. A struct over a raw string rather than
/// an enum, so a kind written by a newer build is EXPRESSIBLE — it keeps
/// its raw value, round-trips byte-identically, and reads as not-known.
public struct PresetKind: RawRepresentable, Codable, Sendable, Equatable, Hashable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let title = PresetKind(rawValue: "title")
    public static let effect = PresetKind(rawValue: "effect")
    public static let material = PresetKind(rawValue: "material")
    public static let motion = PresetKind(rawValue: "motion")
    public static let curve = PresetKind(rawValue: "curve")
    public static let transform = PresetKind(rawValue: "transform")
    public static let panelStyle = PresetKind(rawValue: "panelStyle")
    public static let look = PresetKind(rawValue: "look")
    public static let sequenceTemplate = PresetKind(rawValue: "sequenceTemplate")
    public static let chapterTemplate = PresetKind(rawValue: "chapterTemplate")

    /// Every kind THIS build can apply. An entry outside this set is kept
    /// and shown, never applied.
    public static let known: Set<PresetKind> = [
        .title, .effect, .material, .motion, .curve,
        .transform, .panelStyle, .look, .sequenceTemplate, .chapterTemplate
    ]

    public var isKnown: Bool { PresetKind.known.contains(self) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.rawValue = try c.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Dependency (R6)

/// What a preset needs from the world. A preset that references media it
/// does not carry DECLARES itself incomplete before application — it
/// never silently instantiates broken.
public struct PresetDependency: Codable, Sendable, Equatable, Hashable {
    public struct Kind: RawRepresentable, Codable, Sendable, Equatable, Hashable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let font = Kind(rawValue: "font")
        public static let media = Kind(rawValue: "media")
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            self.rawValue = try c.decode(String.self)
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(rawValue)
        }
    }

    public var kind: Kind
    /// A font descriptor (family name), or a Source id / filename.
    public var descriptor: String
    /// Carried WITH the preset, or expected present at instantiation.
    public var isCarried: Bool

    public init(kind: Kind, descriptor: String, isCarried: Bool) {
        self.kind = kind
        self.descriptor = descriptor
        self.isCarried = isCarried
    }
}

// MARK: - Payload

/// The typed union with a raw escape (FL-09's `EffectValue` shape, one
/// level up). Typed cases are what THIS build writes and applies; a
/// payload from a newer build keeps its ORIGINAL fragment and re-encodes
/// it verbatim, because printing it through typed fields would change
/// bytes — G7's failure mode.
public enum PresetPayload: Codable, Sendable, Equatable {
    /// A whole `TextSpec`. A *style* preset carries an empty string and
    /// applying preserves the target's text.
    case title(TextSpec)
    /// One Effect: an `effectId` plus a full parameter snapshot.
    /// A saved look (H7) is exactly this, over the bundled colour Effect.
    case effect(EffectInstance)
    /// One slot's override, minus the slot index — the target's current
    /// slot receives it.
    case material(MaterialOverrideSpec)
    /// A named-easing choice or a tangent shape, for a Key or a selection.
    case curve(CurvePresetPayload)
    /// Anything newer, kept whole and re-encoded verbatim.
    case raw(JSONFragment)

    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        // Decode the WHOLE payload as a fragment first, so an unknown
        // type keeps every byte it arrived with.
        let fragment = try JSONFragment(from: decoder)
        guard case .object(let o) = fragment,
              case .string(let type)? = o["type"] else {
            self = .raw(fragment)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch type {
        case "title":    self = .title(try c.decode(TextSpec.self, forKey: .value))
        case "effect":   self = .effect(try c.decode(EffectInstance.self, forKey: .value))
        case "material": self = .material(try c.decode(MaterialOverrideSpec.self, forKey: .value))
        case "curve":    self = .curve(try c.decode(CurvePresetPayload.self, forKey: .value))
        default:         self = .raw(fragment)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .raw(let fragment):
            try fragment.encode(to: encoder)
        case .title(let spec):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("title", forKey: .type)
            try c.encode(spec, forKey: .value)
        case .effect(let instance):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("effect", forKey: .type)
            try c.encode(instance, forKey: .value)
        case .material(let spec):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("material", forKey: .type)
            try c.encode(spec, forKey: .value)
        case .curve(let curve):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("curve", forKey: .type)
            try c.encode(curve, forKey: .value)
        }
    }
}

/// A curve preset: a named-easing choice, or a hand-shaped tangent pair.
public struct CurvePresetPayload: Codable, Sendable, Equatable {
    /// An `AnimationInterpolation` raw value ("easeInOut", "bezier"…).
    public var interpolation: String
    /// Present only when `interpolation` is a hand-shaped bezier.
    public var tangentIn: AnimationTangent?
    public var tangentOut: AnimationTangent?

    public init(interpolation: String,
                tangentIn: AnimationTangent? = nil,
                tangentOut: AnimationTangent? = nil) {
        self.interpolation = interpolation
        self.tangentIn = tangentIn
        self.tangentOut = tangentOut
    }
}

// MARK: - Entry

/// One preset in the Chapter-level library (`ChapterDocument.presets`).
/// USER presets live in Application Support in the SAME shape — the
/// existing store discipline.
public struct PresetEntry: Codable, Sendable, Equatable, Identifiable {
    /// Durable, minted. Used to FIND, FAVOURITE and ORGANISE the preset —
    /// and it NEVER appears in an authored fact. Applying copies values;
    /// the result carries its own identity and no back-reference.
    public var id: String
    public var kind: PresetKind
    public var name: String
    /// A human-organizable path, not a flat list. Empty means the root.
    public var categoryPath: [String]
    public var isFavorite: Bool?
    public var payload: PresetPayload
    /// R6: fonts and media this preset needs. Absent means none.
    public var requires: [PresetDependency]?

    public init(id: String, kind: PresetKind, name: String,
                categoryPath: [String] = [], isFavorite: Bool? = nil,
                payload: PresetPayload, requires: [PresetDependency]? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.categoryPath = categoryPath
        self.isFavorite = isFavorite
        self.payload = payload
        self.requires = requires
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, categoryPath, isFavorite, payload, requires
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(PresetKind.self, forKey: .kind)
        self.name = try c.decode(String.self, forKey: .name)
        self.categoryPath = try c.decodeIfPresent([String].self, forKey: .categoryPath) ?? []
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite)
        self.payload = try c.decode(PresetPayload.self, forKey: .payload)
        self.requires = try c.decodeIfPresent([PresetDependency].self, forKey: .requires)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        if !categoryPath.isEmpty { try c.encode(categoryPath, forKey: .categoryPath) }
        try c.encodeIfPresent(isFavorite, forKey: .isFavorite)
        try c.encode(payload, forKey: .payload)
        try c.encodeIfPresent(requires, forKey: .requires)
    }
}
