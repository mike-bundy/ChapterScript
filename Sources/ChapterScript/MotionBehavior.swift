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
    /// CYCLES AROUND the rest pose, indefinitely.
    ///
    /// The first kind whose progress is not a ramp from one state to another:
    /// an ambient behavior has a PERIOD rather than an end, so `duration` is
    /// one cycle and the phase is deliberately NOT clamped. Its purpose is to
    /// say "this thing is alive / available / interactive" without the author
    /// hand-keying a loop, which is what `docs/ACTIONS.md` calls Idle Float.
    case ambient
}

/// What an ambient behavior does over its cycle.
///
/// A small closed set on purpose. Each is one dominant idea, at a comfortable
/// default amplitude: the failure mode this feature invites is a scene where
/// everything bobs, so there is no "combine three of these" style.
public enum MotionAmbientStyle: String, Codable, Sendable, Equatable, CaseIterable {
    /// Rises and settles. `distance` is the peak rise.
    case float
    /// Turns steadily about its own up axis. `distance` is unused; one cycle
    /// is one full revolution.
    case spin
    /// Breathes larger and back. `awayScale` is the peak size.
    case pulse
    /// TRAVELS A CIRCLE AROUND THE ORIGIN, on the plane perpendicular to
    /// `ambientAxis`, keeping its distance. One cycle is one full revolution.
    ///
    /// Unlike the other three this needs to know where the object IS: a float
    /// is the same wherever it happens, an orbit is defined by its centre. The
    /// resolver takes the rest position for exactly this case.
    case orbit
}

/// Where an entrance comes FROM, or an exit goes TO.
public enum MotionStartPlace: String, Codable, Sendable, Equatable, CaseIterable {
    /// An offset along `direction` by `distance`. Every behavior authored
    /// before this field existed, and still the default.
    case direction
    /// The world origin — the centre of the scene, and the viewer's own
    /// position in both the Mac Viewer and on device.
    case sceneCentre

    public var displayName: String {
        switch self {
        case .direction:   return "A direction"
        case .sceneCentre: return "The centre of the scene"
        }
    }
}

/// Which axis an ambient behavior turns about — a SPIN turns about it in
/// place, an ORBIT draws its circle in the plane perpendicular to it. One
/// field, because it is one idea: two would have to be kept in step by hand,
/// and the picker an author sees is the same picker either way.
public enum MotionAmbientAxis: String, Codable, Sendable, Equatable, CaseIterable {
    case x, y, z

    public var unitVector: SIMD3<Float> {
        switch self {
        case .x: return SIMD3(1, 0, 0)
        case .y: return SIMD3(0, 1, 0)
        case .z: return SIMD3(0, 0, 1)
        }
    }

    /// The two axes the circle is drawn on, in order, so a positive phase
    /// turns the same way for every axis.
    var plane: (SIMD3<Float>, SIMD3<Float>) {
        switch self {
        case .x: return (SIMD3(0, 1, 0), SIMD3(0, 0, 1))
        case .y: return (SIMD3(0, 0, 1), SIMD3(1, 0, 0))
        case .z: return (SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        }
    }

    public var displayName: String {
        switch self {
        case .x: return "X (side to side)"
        case .y: return "Y (upright)"
        case .z: return "Z (front to back)"
        }
    }
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
    /// What an `.ambient` behavior does. Absent for every other kind, and an
    /// ambient behavior with no style reads as `.float` so a document written
    /// by a newer tool still plays.
    public var ambientStyle: MotionAmbientStyle?

    /// HOW LONG AN AMBIENT BEHAVIOR RUNS FOR, in seconds from its start.
    ///
    /// `duration` is an ambient behavior's CYCLE, not its lifetime — a Pulse
    /// with a 2 s duration breathes once every two seconds, forever. Drawing
    /// that cycle as the clip's length made the Timeline lie: the clip ended at
    /// two seconds and the object went on pulsing, which is what the author
    /// reported.
    ///
    /// Nil means "until the object leaves", which is the sensible default for a
    /// cue that says "this is interactive". A number is the author trimming the
    /// clip. Meaningless for the other kinds, which end when their ramp does.
    public var span: Double?

    /// Which axis a `.spin` or an `.orbit` turns about. Absent reads as `.y`,
    /// the upright turntable, which is what an author almost always means.
    public var ambientAxis: MotionAmbientAxis?

    /// WHERE THE AWAY POSE IS, for an entrance or an exit.
    ///
    /// Absent reads as `.direction`, which is every existing behavior: an
    /// offset along `direction` by `distance` from the object's rest pose.
    /// `.sceneCentre` is the other thing authors mean by "comes in from the
    /// middle" — the away pose is the world origin itself, wherever the object
    /// rests. It is exact rather than a direction that happens to point at the
    /// centre, which would need re-aiming every time the object moved.
    ///
    /// There is deliberately no "out of frame": the format has no camera and
    /// no field of view, so the distance that clears one would be a guess
    /// dressed as a rule.
    public var startPlace: MotionStartPlace?

    /// Turn the other way. A separate flag rather than a negative period,
    /// because a negative duration is not a thing and every consumer would
    /// have to remember to take its absolute value.
    public var ambientReversed: Bool?

    /// How far from the axis an orbit runs, in metres. Absent or zero keeps the
    /// object's OWN distance — an orbit that silently moved a carefully placed
    /// prop to a default radius would be the more surprising answer.
    public var orbitRadius: Float?

    /// Whether the object keeps facing the centre as it goes round.
    ///
    /// Absent reads as TRUE: an object that orbits without turning drifts
    /// sideways past the viewer, which reads as a mistake rather than as a
    /// display turntable.
    public var orbitFacesCentre: Bool?

    public init(
        entity: String,
        kind: MotionBehaviorKind,
        direction: MotionDirection? = nil,
        space: MotionSpace = .viewer,
        distance: Float = MotionBehaviorLimits.defaultDistance,
        duration: Double = MotionBehaviorLimits.defaultDuration,
        easing: StepTimingFunction? = nil,
        fade: Bool = true,
        awayScale: Float? = nil,
        ambientStyle: MotionAmbientStyle? = nil,
        span: Double? = nil,
        startPlace: MotionStartPlace? = nil,
        ambientAxis: MotionAmbientAxis? = nil,
        ambientReversed: Bool? = nil,
        orbitRadius: Float? = nil,
        orbitFacesCentre: Bool? = nil
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
        self.ambientStyle = ambientStyle
        self.span = span
        self.startPlace = startPlace
        self.ambientAxis = ambientAxis
        self.ambientReversed = ambientReversed
        self.orbitRadius = orbitRadius
        self.orbitFacesCentre = orbitFacesCentre
    }

    // Tolerant decode: every field but `entity` and `kind` has a default, so a
    // document written by a newer tool with more fields still reads.
    private enum CodingKeys: String, CodingKey {
        case entity, kind, direction, space, distance, duration, easing, fade, awayScale
        case ambientStyle, span
        case startPlace
        case ambientAxis, ambientReversed, orbitRadius, orbitFacesCentre
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
        // TOLERANT, like every other field here: a style written by a newer
        // tool that this build does not recognise reads as absent, and an
        // absent style resolves as `.float` rather than as no motion at all.
        ambientStyle = try? c.decodeIfPresent(MotionAmbientStyle.self, forKey: .ambientStyle)
        span = try? c.decodeIfPresent(Double.self, forKey: .span)
        startPlace = try? c.decodeIfPresent(MotionStartPlace.self, forKey: .startPlace)
        ambientAxis = try? c.decodeIfPresent(MotionAmbientAxis.self, forKey: .ambientAxis)
        ambientReversed = try? c.decodeIfPresent(Bool.self, forKey: .ambientReversed)
        orbitRadius = try? c.decodeIfPresent(Float.self, forKey: .orbitRadius)
        orbitFacesCentre = try? c.decodeIfPresent(Bool.self, forKey: .orbitFacesCentre)
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
        // A cycle that eases at both ends reads as breathing rather than as a
        // machine; linear would give a spin a constant rate but make a float
        // and a pulse tick.
        // An orbit is LINEAR: easing inside a revolution stutters once per lap.
        case .ambient: return .linear
        }
    }

    /// How long a behavior OCCUPIES on a Timeline.
    ///
    /// For a ramp that is its duration. For an ambient cue it is its span, and
    /// when it has none it is indefinite — the caller draws it to the end of
    /// the object's presence rather than to one cycle.
    public static func timelineSpan(of behavior: MotionBehaviorDTO) -> Double? {
        guard behavior.kind == .ambient else { return behavior.duration }
        return behavior.span
    }

    /// One cycle. Slow on purpose: an ambient cue that competes for attention
    /// has stopped being a cue.
    public static let defaultAmbientPeriod: Double = 4.0
    /// Peak rise for an Idle Float, in metres. Small enough to read as "alive"
    /// and never as "moving".
    public static let defaultAmbientRise: Float = 0.02
    /// Peak size for a Pulse.
    public static let defaultAmbientPulseScale: Float = 1.04
    /// One full revolution per cycle, in degrees.
    public static let ambientSpinDegrees: Float = 360
}

// MARK: - The resolved offset

/// What a motion contributes at one instant. Deliberately a DELTA, not a pose.
public struct MotionOffset: Sendable, Equatable {
    public var positionDelta: SIMD3<Float>
    /// EULER DEGREES, added to the authored orientation.
    ///
    /// Added for `MotionAmbientStyle.spin`, which cannot be expressed any other
    /// way. Degrees rather than a quaternion because it ADDS, and because the
    /// rest of this format speaks Euler degrees for authored rotation
    /// (`MoveActionDTO.absoluteRotation`, `EntityAnimationTrack`'s `rx/ry/rz`).
    /// A spin past 360 is a real value here, exactly as a continuous Euler
    /// curve is in Animation 2.0.
    public var rotationDelta: SIMD3<Float>
    public var scaleMultiplier: Float
    public var opacityMultiplier: Float

    public static let identity = MotionOffset(
        positionDelta: .zero, rotationDelta: .zero,
        scaleMultiplier: 1, opacityMultiplier: 1
    )

    public init(positionDelta: SIMD3<Float> = .zero,
                rotationDelta: SIMD3<Float> = .zero,
                scaleMultiplier: Float = 1,
                opacityMultiplier: Float = 1) {
        self.positionDelta = positionDelta
        self.rotationDelta = rotationDelta
        self.scaleMultiplier = scaleMultiplier
        self.opacityMultiplier = opacityMultiplier
    }

    /// Stacking two motions on one entity. Position adds, scale and opacity
    /// multiply — the only combination that is associative and that leaves an
    /// identity offset genuinely inert.
    public static func combine(_ a: MotionOffset, _ b: MotionOffset) -> MotionOffset {
        MotionOffset(
            positionDelta: a.positionDelta + b.positionDelta,
            rotationDelta: a.rotationDelta + b.rotationDelta,
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
    /// - Parameter restPosition: where the object sits when nothing is acting
    ///   on it. Needed ONLY by `.orbit`, which is defined by its centre rather
    ///   than by a displacement — every other behavior is a delta and does not
    ///   care where it starts. Absent, an orbit falls back to a circle through
    ///   the origin's forward axis rather than guessing.
    public static func offset(
        _ behavior: MotionBehaviorDTO,
        progress: Float,
        viewerYaw: Float? = nil,
        restPosition: SIMD3<Float>? = nil
    ) -> MotionOffset {
        // AN AMBIENT BEHAVIOR HAS A PERIOD, NOT AN END. Its `progress` arrives
        // UNCLAMPED — cycles elapsed, which grows without bound — because
        // clamping it at 1 would freeze the cue after one cycle. Every other
        // kind is a ramp and is clamped exactly as before.
        if behavior.kind == .ambient {
            // PAST ITS SPAN IT IS OVER, and over means the authored pose — not
            // frozen at whatever phase it happened to reach, which would leave
            // an object permanently tilted or swollen.
            if let span = behavior.span, span > 0 {
                let elapsed = Double(progress) * max(MotionProgress.minimumDuration,
                                                     behavior.duration)
                if elapsed >= span { return .identity }
            }
            return ambientOffset(behavior, cycles: progress, restPosition: restPosition)
        }
        let t = max(0, min(1, progress))
        let eased = ease(t, behavior.easing)

        // How far along the AWAY→REST axis this instant sits, where 1 means
        // fully away. An enter runs 1→0, an exit and a drift run 0→1.
        let awayness: Float
        switch behavior.kind {
        case .enter: awayness = 1 - eased
        case .exit, .drift: awayness = eased
        // Unreachable: `.ambient` returned above. Spelled out rather than
        // defaulted so a fourth kind breaks the build here too.
        case .ambient: awayness = 0
        }

        var offset = MotionOffset.identity

        // THE AWAY POSE IS THE SCENE CENTRE, EXACTLY. Expressing it as a
        // direction that happens to point at the origin would need re-aiming
        // every time the object moved; the away vector is the origin minus
        // where the object rests, so it is right wherever that is.
        if behavior.startPlace == .sceneCentre {
            if let rest = restPosition {
                offset.positionDelta = -rest * awayness
            }
            // With no rest position there is no vector to the centre, so the
            // behavior contributes no translation rather than an invented one.
        } else if let direction = behavior.direction, behavior.distance != 0 {
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

    /// One instant of a cycling behavior.
    ///
    /// PHASE IS TAKEN MODULO ONE so the value is identical at cycle 3.25 and
    /// cycle 900.25: an hour-long chapter must not accumulate float error into
    /// a visibly different amplitude, and a scrub to the same authored second
    /// must draw the same frame every time.
    static func ambientOffset(_ behavior: MotionBehaviorDTO, cycles: Float,
                              restPosition: SIMD3<Float>? = nil) -> MotionOffset {
        var offset = MotionOffset.identity
        let style = behavior.ambientStyle ?? .float
        let phase = cycles - floor(cycles)

        switch style {
        case .float:
            // A full sine, so the object passes through its authored pose
            // twice per cycle and never sits parked above it.
            let rise = behavior.distance == 0 ? MotionBehaviorLimits.defaultAmbientRise
                                              : behavior.distance
            offset.positionDelta = SIMD3(0, sin(phase * 2 * .pi) * rise, 0)
        case .spin:
            // LINEAR IN PHASE, whatever the easing says. A spin that eases
            // within each cycle stutters once per revolution, which is the one
            // thing a steady turn must not do.
            let axis = (behavior.ambientAxis ?? .y).unitVector
            let turn = phase * MotionBehaviorLimits.ambientSpinDegrees
            offset.rotationDelta = axis * (behavior.ambientReversed == true ? -turn : turn)
        case .pulse:
            let peak = behavior.awayScale ?? MotionBehaviorLimits.defaultAmbientPulseScale
            // 0…1…0 over the cycle, so it returns to the authored size.
            let swell = (1 - cos(phase * 2 * .pi)) / 2
            offset.scaleMultiplier = 1 + (peak - 1) * swell
        case .orbit:
            return orbitOffset(behavior, phase: phase, restPosition: restPosition)
        }
        return offset
    }

    /// One instant of an orbit.
    ///
    /// THE OFFSET IS A DELTA FROM REST, like every other behavior, so the
    /// circle is computed in world terms and the object's own rest position is
    /// subtracted back out. That keeps orbit composable with the rest of the
    /// stack — a Fade In and an Orbit still add up — and means removing the
    /// behavior restores the authored pose exactly.
    ///
    /// THE RADIUS DEFAULTS TO THE OBJECT'S OWN DISTANCE. An orbit that silently
    /// moved a carefully placed prop onto a default circle would be the more
    /// surprising answer; the author asks for a different radius when they want
    /// one.
    static func orbitOffset(_ behavior: MotionBehaviorDTO, phase: Float,
                            restPosition: SIMD3<Float>?) -> MotionOffset {
        let axis = behavior.ambientAxis ?? .y
        let (u, v) = axis.plane
        let rest = restPosition ?? .zero

        // Where rest sits on the circle: its components in the orbit plane give
        // both the starting angle and, when the author has not chosen one, the
        // radius.
        let ru = simd_dot(rest, u), rv = simd_dot(rest, v)
        let restRadius = (ru * ru + rv * rv).squareRoot()
        let radius = (behavior.orbitRadius.map { $0 > 0 ? $0 : restRadius }) ?? restRadius
        // A start angle of zero is the right reading for an object sitting ON
        // the axis: it has no angle to preserve, so it begins on +u.
        let startAngle = restRadius > 1e-5 ? atan2(rv, ru) : 0

        let sweep = phase * 2 * Float.pi
        let angle = startAngle + (behavior.ambientReversed == true ? -sweep : sweep)
        let orbited = u * (radius * cos(angle)) + v * (radius * sin(angle))
        // The component ALONG the axis is untouched: an orbit goes round, it
        // does not lift.
        let restInPlane = u * ru + v * rv

        var offset = MotionOffset.identity
        offset.positionDelta = orbited - restInPlane
        // FACING THE CENTRE IS A TURN, NOT A LOOK-AT. If the object faces the
        // centre at rest, turning it by the same angle it has travelled keeps
        // it facing the centre — no world matrix, no camera, nothing that could
        // disagree between the editor and the device.
        if behavior.orbitFacesCentre ?? true {
            offset.rotationDelta = axis.unitVector
                * (behavior.ambientReversed == true ? -phase * 360 : phase * 360)
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
