//
//  MaterialKeyTrack.swift
//  ChapterScript
//
//  KEYED MATERIAL PROPERTIES (FL-14, the animation half).
//
//  A SIBLING CONTAINER, NEVER A SIBLING ENGINE — the rule `EffectKeyTrack`
//  set and the reason this is a third file rather than a third animation
//  system. The curve type, the key type, the tangent model and the
//  evaluator are the EXISTING animation ones. `AnimationChannel` and
//  `KeyframeCapabilities` are untouched, because the ten channels describe
//  an ENTITY'S TRANSFORM and a material is not a transform; adding
//  `roughness` to them would make every rig, gizmo and pose walk answer a
//  question about paint.
//
//  ADDRESSED BY (entityId, slot) — the same identity the override itself
//  uses, and for the same reason: a mesh guarantees its material count and
//  order, while names are whatever the file happened to say. A track whose
//  slot the (relinked) file no longer offers is KEPT, exactly as an
//  orphaned override is; it is not this type's business to decide the file
//  will never come back.
//
//  COLORS KEY PER COMPONENT. An `AnimationCurve` carries one scalar, and
//  giving it a vector flavor would fork the curve type for one caller — so
//  a color is four channels sharing one property, which is what every
//  keyframe system that kept one curve type does. Six PROPERTIES are
//  keyable; they occupy eleven channels between them.
//
//  SAMPLING PRODUCES AN OVERRIDE, and the override goes into the resolver
//  unchanged. That is the whole integration: `MaterialResolution.resolve`,
//  every host adapter, the exporter and ChapterPlayer already consume a
//  `MaterialOverrideSpec` and none of them learns that a value was keyed.
//  A keyed material is a material whose override happens to depend on time.
//

import Foundation

/// One scalar channel of a keyed material slot.
///
/// The raw values are the wire format and are deliberately readable: a
/// document is diffed by people, and `baseColor.r` says what
/// `mk0` would not.
public enum MaterialKeyChannel: String, Codable, Sendable, CaseIterable, Hashable {
    case baseColorRed = "baseColor.r"
    case baseColorGreen = "baseColor.g"
    case baseColorBlue = "baseColor.b"
    case baseColorAlpha = "baseColor.a"
    case roughness
    case metallic
    case opacity
    case emissiveRed = "emissiveColor.r"
    case emissiveGreen = "emissiveColor.g"
    case emissiveBlue = "emissiveColor.b"
    case emissiveIntensity

    /// The six keyable PROPERTIES, in Inspector order. A color's four
    /// channels appear once, under the property that owns them.
    public enum Property: String, Codable, Sendable, CaseIterable, Hashable {
        case baseColor, roughness, metallic, opacity
        case emissiveColor, emissiveIntensity

        public var channels: [MaterialKeyChannel] {
            switch self {
            case .baseColor:
                return [.baseColorRed, .baseColorGreen, .baseColorBlue, .baseColorAlpha]
            case .roughness:         return [.roughness]
            case .metallic:          return [.metallic]
            case .opacity:           return [.opacity]
            case .emissiveColor:
                return [.emissiveRed, .emissiveGreen, .emissiveBlue]
            case .emissiveIntensity: return [.emissiveIntensity]
            }
        }

        /// How this reads in the Inspector.
        public var displayName: String {
            switch self {
            case .baseColor:         return "Base Color"
            case .roughness:         return "Roughness"
            case .metallic:          return "Metallic"
            case .opacity:           return "Opacity"
            case .emissiveColor:     return "Emissive Color"
            case .emissiveIntensity: return "Emissive Intensity"
            }
        }
    }

    /// The property this channel belongs to.
    public var property: Property {
        switch self {
        case .baseColorRed, .baseColorGreen, .baseColorBlue, .baseColorAlpha:
            return .baseColor
        case .roughness:         return .roughness
        case .metallic:          return .metallic
        case .opacity:           return .opacity
        case .emissiveRed, .emissiveGreen, .emissiveBlue:
            return .emissiveColor
        case .emissiveIntensity: return .emissiveIntensity
        }
    }

    /// The legal range for a rendered value, or nil where the property is
    /// not bounded. Applied at SAMPLING, never to the stored curve: an
    /// author may overshoot a handle and the document keeps what they drew.
    public var renderRange: ClosedRange<Float>? {
        switch self {
        case .emissiveIntensity: return nil
        default:                 return 0...1
        }
    }
}

/// Keys for one Object's one material slot.
public struct MaterialKeyTrack: Codable, Sendable, Equatable {
    /// → the Object's entity id. Never a display name.
    public var entityId: String
    /// → `MaterialOverrideSpec.slot`. THE identity, as it is there.
    public var slot: Int
    /// Channel raw value → the existing curve type.
    ///
    /// A `[String:]` rather than `[MaterialKeyChannel:]` so a channel a
    /// newer build writes round-trips verbatim instead of being dropped by
    /// this one — G7's discipline, one level down.
    public var channels: [String: AnimationCurve]

    public init(entityId: String, slot: Int, channels: [String: AnimationCurve] = [:]) {
        self.entityId = entityId
        self.slot = slot
        self.channels = channels
    }

    /// Setting an emptied curve REMOVES it, so `hasAnyKeys` cannot be
    /// fooled by a track full of empty curves — the rule every sibling
    /// track type follows.
    public subscript(_ channel: MaterialKeyChannel) -> AnimationCurve {
        get { channels[channel.rawValue] ?? AnimationCurve() }
        set { channels[channel.rawValue] = newValue.isAnimated ? newValue : nil }
    }

    public var hasAnyKeys: Bool { channels.values.contains { $0.isAnimated } }

    /// True when this track says anything about that property.
    public func isKeyed(_ property: MaterialKeyChannel.Property) -> Bool {
        property.channels.contains { self[$0].isAnimated }
    }

    /// Union of key times across channels — the dope-sheet diamonds.
    public var keyTimes: [Double] {
        var times = Set<Double>()
        for curve in channels.values {
            for key in curve.keys { times.insert(key.time) }
        }
        return times.sorted()
    }

    /// The channels this build understands, animated, in a stable order.
    public var animatedChannels: [MaterialKeyChannel] {
        MaterialKeyChannel.allCases.filter { self[$0].isAnimated }
    }
}
