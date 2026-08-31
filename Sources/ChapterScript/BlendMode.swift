//
//  BlendMode.swift
//  ChapterScript
//
//  FL-11: the display blend — a property of the OCCURRENCE, never an
//  Effect-stack member: it is stage 5, it happens once, after everything,
//  and a reorderable blend has no meaning. Eleven modes in three named
//  families (the families are the mental model), plus Normal and Replace.
//
//  An unrecognised mode RENDERS as `.normal` — the weakest visual claim,
//  so an unknown mode from a newer build renders conservatively — and the
//  raw value ROUND-TRIPS verbatim (the AssetKind rule): an older build
//  must never rewrite a newer build's blend.
//

import Foundation

public enum BlendMode: Codable, Sendable, Equatable, Hashable {
    case normal, replace
    // Darken / Lighten
    case darken, multiply, lighten, screen
    // Contrast
    case overlay, softLight, hardLight
    // Arithmetic / Difference
    case add, subtract, difference
    /// A mode this build does not know, preserved VERBATIM and rendered
    /// as `.normal`.
    case unknown(String)

    public var rawValueForWire: String {
        switch self {
        case .normal: return "normal"
        case .replace: return "replace"
        case .darken: return "darken"
        case .multiply: return "multiply"
        case .lighten: return "lighten"
        case .screen: return "screen"
        case .overlay: return "overlay"
        case .softLight: return "softLight"
        case .hardLight: return "hardLight"
        case .add: return "add"
        case .subtract: return "subtract"
        case .difference: return "difference"
        case .unknown(let raw): return raw
        }
    }

    public init(wire raw: String) {
        switch raw {
        case "normal": self = .normal
        case "replace": self = .replace
        case "darken": self = .darken
        case "multiply": self = .multiply
        case "lighten": self = .lighten
        case "screen": self = .screen
        case "overlay": self = .overlay
        case "softLight": self = .softLight
        case "hardLight": self = .hardLight
        case "add": self = .add
        case "subtract": self = .subtract
        case "difference": self = .difference
        default: self = .unknown(raw)
        }
    }

    /// How this mode RENDERS on a build that does not know it.
    public var renderedMode: BlendMode {
        if case .unknown = self { return .normal }
        return self
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self.init(wire: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValueForWire)
    }
}
