//
//  MotionBehavior.swift
//  ChapterScript
//
//  MOTION ACTIONS 2.0 — semantic spatial motion, composed as an OFFSET.
//
//  WHY THIS IS NOT `animateMotion`.
//
//  `AnimateMotionActionDTO` carries `MotionCurve`s that are sampled to an
//  ABSOLUTE pose: the runtime writes `entity.position = sample(...)`, and the
//  editor's compositors do the same. That is correct for a procedural path
//  authored in world space (an orbit around a point), and it is exactly wrong
//  for an entrance: "come in from the left" is a statement RELATIVE to wherever
//  the object rests. Expressing it with absolute curves means baking the rest
//  pose at authoring time — after which moving the object leaves the motion
//  flying to the place it used to be, silently. So Motion Actions carry the
//  AUTHOR'S PARAMETERS (direction, distance, duration, easing) and resolve to a
//  DELTA at evaluation time.
//
//  THE COMPOSITION RULE, in one place (and see `docs/ANIMATION_2_0.md`):
//
//      rest pose                    the entity's authored transform
//        ← Animation 2.0 track      overrides the channels it keys
//        ← Motion offsets           ADD position, MULTIPLY scale and opacity
//
//  Motion Actions never write a key, never rebase a track and never replace a
//  channel — so an object with authored keys can also have a Fade In, and
//  neither destroys the other. Two motions on one entity in the same window
//  compose by summing their deltas, which is the only rule that stays
//  associative when an author stacks a Move In and a Scale In.
//
//  RESIDUE IS PART OF THE MEANING. An `enter` resolves to zero offset once it
//  completes (it has arrived, and leaves nothing behind). An `exit` HOLDS its
//  full offset after completing (it has gone). A `drift` holds its end offset
//  too — that is what drift is. Anything else would make a completed motion
//  teleport its object.
//
//  THIS TYPE OWNS NO INTERPOLATION. Easing is `StepTimingFunction`, the same
//  curve the rest of the format uses, and progress is `MotionProgress` — the
//  one authored-clock formula. There is no second easing table here.
//

import Foundation
import simd

// MARK: - Vocabulary

/// What the motion DOES, in author terms. Everything else is a parameter —
/// Rise, Lower, Approach and Recede are directions, not separate kinds, and
/// Fade In / Scale In are an `enter` with no distance.
public enum MotionBehaviorKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// Arrives at the rest pose: the offset runs from full to zero.
    case enter
    /// Departs from the rest pose: the offset runs from zero to full.
    case exit
    /// Travels away from the rest pose and STAYS there.
    case drift
}

/// The frame a direction is expressed in.
///
/// Named explicitly because "left" is meaningless without it — and the same
/// word silently meaning two spaces is the defect this enum exists to prevent.
public enum MotionSpace: String, Codable, Sendable, Equatable, CaseIterable {
    /// Relative to the viewer's LEVEL facing (yaw only). "From my left" stays
    /// horizontal even when the viewer looks up, which is both what an author
    /// means and the comfortable reading.
    case viewer
    /// Chapter world axes.
    case world
}

/// Which way the object sits when it is AWAY from its rest pose.
///
/// ONE meaning, two labels: an `enter` STARTS there, an `exit` and a `drift`
/// END there. The Inspector says "From" or "To" accordingly, so the author
/// never has to hold two conventions at once.
public enum MotionDirection: Codable, Sendable, Equatable {
    case left, right, up, down
    /// Further from the viewer / nearer to the viewer along the level facing.
    case towardViewer, awayFromViewer
    /// An explicit vector, always read in the behavior's `space`.
    case custom(Vec3)

    /// Unit vector in the behavior's space. `custom` is normalised so distance
    /// is always the authority on how far — a direction says only which way.
    public var unitVector: SIMD3<Float> {
        switch self {
        case .left:            return SIMD3(-1, 0, 0)
        case .right:           return SIMD3(1, 0, 0)
        case .up:              return SIMD3(0, 1, 0)
        case .down:            return SIMD3(0, -1, 0)
        // -Z is forward (the way the viewer faces) everywhere in this format,
        // so "away from the viewer" is -Z and "toward" is +Z.
        case .awayFromViewer:  return SIMD3(0, 0, -1)
        case .towardViewer:    return SIMD3(0, 0, 1)
        case .custom(let v):
            let s = SIMD3<Float>(v.x, v.y, v.z)
            let length = simd_length(s)
            return length > 1e-5 ? s / length : SIMD3(0, 0, 1)
        }
    }

    /// True when the direction is only meaningful against the viewer.
    public var requiresViewerSpace: Bool {
        switch self {
        case .towardViewer, .awayFromViewer: return true
        default: return false
        }
    }

    // Tolerant codable: a name, or an object carrying a vector. An unknown
    // name degrades to `.towardViewer`'s opposite — `.awayFromViewer` — which
    // is the SAFE reading: a motion we do not understand must not be resolved
    // into one that pushes content at the viewer's face.
    private enum CodingKeys: String, CodingKey { case kind, vector }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let name = try? single.decode(String.self) {
            self = Self.named(name) ?? .awayFromViewer
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        if kind == "custom" {
            self = .custom(try c.decode(Vec3.self, forKey: .vector))
        } else {
            self = Self.named(kind) ?? .awayFromViewer
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .custom(let v):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode("custom", forKey: .kind)
            try c.encode(v, forKey: .vector)
        default:
            // The four semantic directions encode as bare strings, so a
            // document stays readable and small.
            var c = encoder.singleValueContainer()
            try c.encode(name)
        }
    }

    private static func named(_ name: String) -> MotionDirection? {
        switch name {
        case "left": return .left
        case "right": return .right
        case "up": return .up
        case "down": return .down
        case "towardViewer": return .towardViewer
        case "awayFromViewer": return .awayFromViewer
        default: return nil
        }
    }

    public var name: String {
        switch self {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        case .towardViewer: return "towardViewer"
        case .awayFromViewer: return "awayFromViewer"
        case .custom: return "custom"
        }
    }
}

// MARK: - The authored action

/// One authored motion behavior.
///
/// COMFORT IS A DEFAULT, NOT A LIMIT. The initialiser's defaults are the
/// cinematic, immersive-safe ones (a modest distance over a perceivable
/// duration, easing that settles rather than snaps); an author may exceed them
/// deliberately, and `MotionBehaviorLimits` says where the advisory line is.
public struct MotionBehaviorDTO: Codable, Sendable, Equatable {
    /// The ENTITY ID — never a display name. (See the placeholder cold-open
    /// defect: a name that only exists in one session is not a reference.)
    public var entity: String
    public var kind: MotionBehaviorKind
    /// Absent for a motion that only fades or scales.
    public var direction: MotionDirection?
    public var space: MotionSpace
    /// Metres. Ignored when `direction` is nil.
    public var distance: Float
    public var duration: Double
    public var easing: StepTimingFunction
    /// Fade with the motion: an `enter` fades up, an `exit` fades down.
    public var fade: Bool
    /// The scale the object holds at its AWAY end, as a multiplier of its
    /// resolved scale. `nil` = the motion does not touch scale. Never 0 — see
    /// `MotionBehaviorLimits.minimumScale`.
    public var awayScale: Float?

    public init(
        entity: String,
        kind: MotionBehaviorKind,
        direction: MotionDirection? = nil,
        space: MotionSpace = .viewer,
        distance: Float = MotionBehaviorLimits.defaultDistance,
        duration: Double = MotionBehaviorLimits.defaultDuration,
        easing: StepTimingFunction? = nil,
        fade: Bool = true,
        awayScale: Float? = nil
    ) {
        self.entity = entity
        self.kind = kind
        self.direction = direction
        self.space = space
        self.distance = distance
        self.duration = duration
        // A settle for an arrival, a lean-in for a departure, and a smooth
        // both-ends for a drift. Chosen per kind because "the default easing"
        // is not one curve.
        self.easing = easing ?? MotionBehaviorLimits.defaultEasing(for: kind)
        self.fade = fade
        self.awayScale = awayScale
    }

    // Tolerant decode: every field but `entity` and `kind` has a default, so a
    // document written by a newer tool with more fields still reads.
    private enum CodingKeys: String, CodingKey {
        case entity, kind, direction, space, distance, duration, easing, fade, awayScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entity = try c.decode(String.self, forKey: .entity)
        kind = (try? c.decode(MotionBehaviorKind.self, forKey: .kind)) ?? .enter
        direction = try c.decodeIfPresent(MotionDirection.self, forKey: .direction)
        space = (try? c.decode(MotionSpace.self, forKey: .space)) ?? .viewer
        distance = try c.decodeIfPresent(Float.self, forKey: .distance)
            ?? MotionBehaviorLimits.defaultDistance
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
            ?? MotionBehaviorLimits.defaultDuration
        easing = (try? c.decode(StepTimingFunction.self, forKey: .easing))
            ?? MotionBehaviorLimits.defaultEasing(for: kind)
        fade = try c.decodeIfPresent(Bool.self, forKey: .fade) ?? true
        awayScale = try c.decodeIfPresent(Float.self, forKey: .awayScale)
    }
}

/// The safe envelope, in one place so the editor's advisories and the
/// resolver's clamps cannot drift apart.
public enum MotionBehaviorLimits {
    public static let defaultDistance: Float = 0.6
    public static let defaultDuration: Double = 1.2
    /// A motion toward the viewer is the one direction that can be actively
    /// unpleasant, so it gets its own, shorter default.
    public static let defaultApproachDistance: Float = 0.4
    /// Never 0: an object scaled to a singular transform has no orientation,
    /// no bounds and pops rather than grows.
    public static let minimumScale: Float = 0.05
    public static let defaultAwayScale: Float = 0.85
    /// Beyond this the editor advises, but does not refuse — an author may
    /// deliberately author a big move.
    public static let comfortableDistance: Float = 2.0
    /// Below this a motion is a pop rather than a move.
    public static let comfortableMinimumDuration: Double = 0.3

    public static func defaultEasing(for kind: MotionBehaviorKind) -> StepTimingFunction {
        switch kind {
        case .enter: return .easeOut
        case .exit:  return .easeIn
        case .drift: return .easeInOut
        }
    }
}

// MARK: - The resolved offset

/// What a motion contributes at one instant. Deliberately a DELTA, not a pose.
public struct MotionOffset: Sendable, Equatable {
    public var positionDelta: SIMD3<Float>
    public var scaleMultiplier: Float
    public var opacityMultiplier: Float

    public static let identity = MotionOffset(
        positionDelta: .zero, scaleMultiplier: 1, opacityMultiplier: 1
    )

    public init(positionDelta: SIMD3<Float> = .zero,
                scaleMultiplier: Float = 1,
                opacityMultiplier: Float = 1) {
        self.positionDelta = positionDelta
        self.scaleMultiplier = scaleMultiplier
        self.opacityMultiplier = opacityMultiplier
    }

    /// Stacking two motions on one entity. Position adds, scale and opacity
    /// multiply — the only combination that is associative and that leaves an
    /// identity offset genuinely inert.
    public static func combine(_ a: MotionOffset, _ b: MotionOffset) -> MotionOffset {
        MotionOffset(
            positionDelta: a.positionDelta + b.positionDelta,
            scaleMultiplier: a.scaleMultiplier * b.scaleMultiplier,
            opacityMultiplier: a.opacityMultiplier * b.opacityMultiplier
        )
    }
}

/// THE ONE PLACE a motion behavior becomes numbers.
///
/// ChapterPlayer's runtime, the Mac preview compositor and MaestroVision's
/// scrub all call this, so a motion cannot look one way in the editor and
/// another on the headset. It is pure: no entity, no scene, no clock.
public enum MotionBehaviorResolver {

    /// The viewer's LEVEL yaw, in radians, for viewer-space directions.
    /// `nil` means "no viewer pose available" — the resolver then treats
    /// viewer space as world space rather than guessing, which keeps a
    /// preview deterministic before a head pose exists.
    public static func offset(
        _ behavior: MotionBehaviorDTO,
        progress: Float,
        viewerYaw: Float? = nil
    ) -> MotionOffset {
        let t = max(0, min(1, progress))
        let eased = ease(t, behavior.easing)

        // How far along the AWAY→REST axis this instant sits, where 1 means
        // fully away. An enter runs 1→0, an exit and a drift run 0→1.
        let awayness: Float
        switch behavior.kind {
        case .enter: awayness = 1 - eased
        case .exit, .drift: awayness = eased
        }

        var offset = MotionOffset.identity

        if let direction = behavior.direction, behavior.distance != 0 {
            var vector = direction.unitVector * behavior.distance
            let space = direction.requiresViewerSpace ? .viewer : behavior.space
            if space == .viewer, let yaw = viewerYaw {
                vector = rotateAroundY(vector, radians: yaw)
            }
            offset.positionDelta = vector * awayness
        }

        if let awayScale = behavior.awayScale {
            let safe = max(MotionBehaviorLimits.minimumScale, awayScale)
            // 1 at rest, `awayScale` when fully away.
            offset.scaleMultiplier = 1 + (safe - 1) * awayness
        }

        if behavior.fade {
            // Transparent when away, fully present at rest. A MULTIPLIER, so a
            // Fade In on an object the author authored at 0.5 opacity resolves
            // toward 0.5 — never to a literal 1.0 it never had.
            offset.opacityMultiplier = 1 - awayness
        }

        return offset
    }

    /// Where the entity sits at `progress`, given its already-resolved pose.
    /// Convenience for callers that hold a pose rather than assembling deltas.
    public static func apply(
        _ offset: MotionOffset,
        toPosition position: SIMD3<Float>,
        scale: SIMD3<Float>,
        opacity: Float
    ) -> (position: SIMD3<Float>, scale: SIMD3<Float>, opacity: Float) {
        (position + offset.positionDelta,
         scale * offset.scaleMultiplier,
         opacity * offset.opacityMultiplier)
    }

    /// The format's own timing functions — NOT a second easing table.
    static func ease(_ t: Float, _ function: StepTimingFunction) -> Float {
        switch function {
        case .linear:    return t
        case .easeIn:    return t * t
        case .easeOut:   return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }

    private static func rotateAroundY(_ v: SIMD3<Float>, radians: Float) -> SIMD3<Float> {
        let c = cos(radians), s = sin(radians)
        return SIMD3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
    }
}
