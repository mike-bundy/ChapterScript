//
//  SubElementKeyTrack.swift
//  ChapterScript
//
//  KEYED PART OFFSETS (FL-16, the animation half).
//
//  A SIBLING CONTAINER, NEVER A SIBLING ENGINE — the rule `EffectKeyTrack`
//  set and `MaterialKeyTrack` follows. THE TEN CHANNELS ARE THE EXISTING
//  ONES, verbatim: a part's offset is a transform, so it keys through
//  `AnimationChannel` and `AnimationRotationOrder` exactly as an entity's
//  pose does, and `KeyframeCapabilities` is untouched.
//
//  WHY IT IS NOT AN `EntityAnimationTrack`. That type keys by ENTITY NAME,
//  and a part is not an entity: it is `(objectId, primPath)`, which is the
//  identity the override itself uses and the whole reason FL-16 exists.
//  Reusing the entity track would have meant minting a synthetic entity
//  name per part — inventing an identity the format deliberately does not
//  have, and the exact "an entity name is never a prim path" rule this
//  campaign is built on. So the ADDRESSING is new and nothing else is.
//
//  SAMPLING PRODUCES A `TransformData` OFFSET, and the offset goes into
//  `SubElementResolution` unchanged. That is the whole integration: the
//  resolver, both hosts' realization and the exporter already compose an
//  offset onto a part's loaded transform, and none of them learns that a
//  value came from a curve. A keyed part is a part whose offset happens to
//  depend on time.
//

import Foundation

/// Keys for one Object's one part.
public struct SubElementKeyTrack: Codable, Sendable, Equatable {
    /// → the Object's entity id.
    public var entityId: String
    /// → `SubElementOverride.primPath`. THE identity, as it is there.
    public var primPath: String
    /// Euler application order, the same choice a pose track carries — a
    /// rotation is meaningless without it.
    public var rotationOrder: AnimationRotationOrder
    /// The EXISTING ten channels. `opacity` is accepted and ignored by the
    /// offset composer: a part's visibility is `isVisible`, a boolean fact,
    /// and fading one is FL-14's material opacity rather than a transform.
    /// It is not rejected at the type level because a document written by a
    /// newer build must round-trip whatever it carries.
    public var curves: [AnimationChannel: AnimationCurve]

    public init(entityId: String,
                primPath: String,
                rotationOrder: AnimationRotationOrder = .xyz,
                curves: [AnimationChannel: AnimationCurve] = [:]) {
        self.entityId = entityId
        self.primPath = primPath
        self.rotationOrder = rotationOrder
        self.curves = curves
    }

    /// Setting an emptied curve REMOVES it — the rule every sibling track
    /// type follows, so `hasAnyKeys` cannot be fooled by empty curves.
    public subscript(_ channel: AnimationChannel) -> AnimationCurve {
        get { curves[channel] ?? AnimationCurve() }
        set { curves[channel] = newValue.isAnimated ? newValue : nil }
    }

    public var hasAnyKeys: Bool { curves.values.contains { $0.isAnimated } }

    /// Union of key times across every channel — the dope-sheet diamonds,
    /// deduplicated within the curve epsilon exactly as a pose track's are.
    public var keyTimes: [Double] {
        var times: [Double] = []
        for curve in curves.values {
            for key in curve.keys {
                if !times.contains(where: { abs($0 - key.time) <= AnimationCurve.timeEpsilon }) {
                    times.append(key.time)
                }
            }
        }
        return times.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case entityId, primPath, rotationOrder, curves
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.entityId = try c.decode(String.self, forKey: .entityId)
        self.primPath = try c.decode(String.self, forKey: .primPath)
        // An unrecognised order reads as `.xyz` rather than throwing: a
        // track written by a newer tool must not stop a project opening.
        self.rotationOrder = try c.decodeIfPresent(
            AnimationRotationOrder.self, forKey: .rotationOrder) ?? .xyz
        // STRING-KEYED ON THE WIRE, exactly as `EntityAnimationTrack` is:
        // an unknown channel name is dropped so a newer document degrades
        // gracefully rather than refusing to open.
        let raw = try c.decodeIfPresent([String: AnimationCurve].self,
                                        forKey: .curves) ?? [:]
        var curves: [AnimationChannel: AnimationCurve] = [:]
        for (name, curve) in raw {
            if let channel = AnimationChannel(rawValue: name) { curves[channel] = curve }
        }
        self.curves = curves
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entityId, forKey: .entityId)
        try c.encode(primPath, forKey: .primPath)
        try c.encode(rotationOrder, forKey: .rotationOrder)
        var raw: [String: AnimationCurve] = [:]
        for (channel, curve) in curves where curve.isAnimated {
            raw[channel.rawValue] = curve
        }
        try c.encode(raw, forKey: .curves)
    }
}
