import Foundation
import simd

// MARK: - Segment-level animation tracks (v0.7.0)
//
// Keyframe animation lives on the SEGMENT, not inside steps. Each entity a
// segment animates gets one `EntityAnimationTrack`: up to ten scalar curves
// (translate/rotate/scale per axis, plus opacity) whose keys sit at ABSOLUTE
// seconds from segment start. Steps remain the event system (reveal, video,
// audio, gates); animation is a continuous layer sampled on the segment
// clock, so it survives step retimes, crosses step boundaries, and scrubs
// identically in every editor and player.
//
// Rotation channels are Euler DEGREES with an explicit rotate order,
// converted to quaternions only at application time. Curves are bezier-
// native: each key carries in/out tangent handles as (dt seconds, dv value)
// offsets — exactly a cubic Bézier control point in (time, value) space.

/// One scalar channel of an entity's animation track.
public enum AnimationChannel: String, Codable, Sendable, CaseIterable, Hashable {
    case tx, ty, tz
    case rx, ry, rz
    case sx, sy, sz
    case opacity

    public var isRotation: Bool { self == .rx || self == .ry || self == .rz }
    public var isScale: Bool { self == .sx || self == .sy || self == .sz }
    public var isTranslation: Bool { self == .tx || self == .ty || self == .tz }

    /// 0/1/2 for x/y/z-flavored channels; nil for opacity.
    public var axisIndex: Int? {
        switch self {
        case .tx, .rx, .sx: return 0
        case .ty, .ry, .sy: return 1
        case .tz, .rz, .sz: return 2
        case .opacity: return nil
        }
    }
}

/// Euler application order for the rotation channels. `.xyz` = rotate about
/// X first, then Y, then Z: the composed quaternion is q_z · q_y · q_x.
public enum AnimationRotationOrder: String, Codable, Sendable, CaseIterable, Equatable {
    case xyz, yzx, zxy, xzy, yxz, zyx

    /// (first, second, third) applied axis indices.
    public var axes: (Int, Int, Int) {
        switch self {
        case .xyz: return (0, 1, 2)
        case .yzx: return (1, 2, 0)
        case .zxy: return (2, 0, 1)
        case .xzy: return (0, 2, 1)
        case .yxz: return (1, 0, 2)
        case .zyx: return (2, 1, 0)
        }
    }

    /// Even permutations of (x, y, z) — determines extraction signs.
    public var isCyclic: Bool {
        switch self {
        case .xyz, .yzx, .zxy: return true
        case .xzy, .yxz, .zyx: return false
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self = AnimationRotationOrder(rawValue: (try? c.decode(String.self)) ?? "xyz") ?? .xyz
    }
}

/// One tangent handle, stored as an offset from its key in (time, value)
/// space. `dt` is always positive: the in-handle points back in time, the
/// out-handle forward. Maps 1:1 onto a cubic Bézier control point.
public struct AnimationTangent: Codable, Sendable, Equatable, Hashable {
    public var dt: Double
    public var dv: Float

    public init(dt: Double = 0.25, dv: Float = 0) {
        self.dt = dt
        self.dv = dv
    }
}

/// Segment interpolation, keyed on the LEFT key of each segment.
public enum AnimationInterpolation: String, Codable, Sendable, Equatable {
    case bezier     // default — smooth spline shaped by tangent handles
    case linear
    case stepped    // hold until the next key

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self = AnimationInterpolation(rawValue: (try? c.decode(String.self)) ?? "bezier") ?? .bezier
    }
}

/// Whether a key's two tangent handles mirror each other (smooth) or move
/// independently (a sharp point / contact key).
public enum AnimationTangentMode: String, Codable, Sendable, Equatable {
    case unified
    case broken

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self = AnimationTangentMode(rawValue: (try? c.decode(String.self)) ?? "unified") ?? .unified
    }
}

/// One key on one scalar channel. `time` is ABSOLUTE seconds from segment
/// start. Rotation-channel values are degrees (and may accumulate past
/// ±360° — they are unwrapped, not normalized).
public struct AnimationKey: Codable, Sendable, Equatable, Hashable {
    public var time: Double
    public var value: Float
    public var interpolation: AnimationInterpolation
    public var inTangent: AnimationTangent
    public var outTangent: AnimationTangent
    public var tangentMode: AnimationTangentMode
    /// nil/true = tangents are auto-managed (refreshed on neighboring key
    /// edits); false = the author shaped them by hand — auto-refresh keeps
    /// hands off.
    public var autoTangents: Bool?

    public init(
        time: Double,
        value: Float,
        interpolation: AnimationInterpolation = .bezier,
        inTangent: AnimationTangent = AnimationTangent(),
        outTangent: AnimationTangent = AnimationTangent(),
        tangentMode: AnimationTangentMode = .unified,
        autoTangents: Bool? = nil
    ) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
        self.inTangent = inTangent
        self.outTangent = outTangent
        self.tangentMode = tangentMode
        self.autoTangents = autoTangents
    }

    private enum CodingKeys: String, CodingKey {
        case time, value, interpolation, inTangent, outTangent, tangentMode, autoTangents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.time = try c.decode(Double.self, forKey: .time)
        self.value = try c.decode(Float.self, forKey: .value)
        self.interpolation = try c.decodeIfPresent(AnimationInterpolation.self, forKey: .interpolation) ?? .bezier
        self.inTangent = try c.decodeIfPresent(AnimationTangent.self, forKey: .inTangent) ?? AnimationTangent()
        self.outTangent = try c.decodeIfPresent(AnimationTangent.self, forKey: .outTangent) ?? AnimationTangent()
        self.tangentMode = try c.decodeIfPresent(AnimationTangentMode.self, forKey: .tangentMode) ?? .unified
        self.autoTangents = try c.decodeIfPresent(Bool.self, forKey: .autoTangents)
    }
}

/// One channel's key list, kept sorted by time with at most one key per
/// instant (within `AnimationCurve.timeEpsilon`).
public struct AnimationCurve: Codable, Sendable, Equatable {
    /// Two keys closer than this are the same instant — set replaces.
    public static let timeEpsilon: Double = 0.004

    public private(set) var keys: [AnimationKey]

    public init(keys: [AnimationKey] = []) {
        self.keys = keys.sorted { $0.time < $1.time }
    }

    public var isAnimated: Bool { !keys.isEmpty }

    /// Insert-or-replace at `key.time`, preserving sort order.
    public mutating func setKey(_ key: AnimationKey) {
        if let i = keys.firstIndex(where: { $0.time >= key.time - Self.timeEpsilon }) {
            if abs(keys[i].time - key.time) <= Self.timeEpsilon {
                keys[i] = key
            } else {
                keys.insert(key, at: i)
            }
        } else {
            keys.append(key)
        }
    }

    public mutating func removeKey(at index: Int) {
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
    }

    public mutating func removeKey(near time: Double, tolerance: Double = AnimationCurve.timeEpsilon) {
        keys.removeAll { abs($0.time - time) <= tolerance }
    }

    public mutating func updateKey(at index: Int, _ mutate: (inout AnimationKey) -> Void) {
        guard keys.indices.contains(index) else { return }
        var key = keys[index]
        mutate(&key)
        keys[index] = key
        keys.sort { $0.time < $1.time }
    }

    /// Wholesale replacement (editor surgery); re-sorts to keep the invariant.
    public mutating func replaceKeys(_ newKeys: [AnimationKey]) {
        keys = newKeys.sorted { $0.time < $1.time }
    }

    public func indexOfKey(near time: Double, tolerance: Double = AnimationCurve.timeEpsilon) -> Int? {
        keys.firstIndex { abs($0.time - time) <= tolerance }
    }
}

/// All animation for one entity within a segment: up to ten scalar curves
/// plus the Euler rotate order. Channels without keys fall back to the
/// entity's rest value (its base transform / full opacity).
public struct EntityAnimationTrack: Codable, Sendable, Equatable {
    public var entity: String
    public var rotationOrder: AnimationRotationOrder
    public var curves: [AnimationChannel: AnimationCurve]

    public init(
        entity: String,
        rotationOrder: AnimationRotationOrder = .xyz,
        curves: [AnimationChannel: AnimationCurve] = [:]
    ) {
        self.entity = entity
        self.rotationOrder = rotationOrder
        self.curves = curves
    }

    public subscript(_ channel: AnimationChannel) -> AnimationCurve {
        get { curves[channel] ?? AnimationCurve() }
        set { curves[channel] = newValue.isAnimated ? newValue : nil }
    }

    public var hasAnyKeys: Bool { curves.values.contains { $0.isAnimated } }

    /// Union of key times across every channel (pose-key markers), sorted,
    /// deduplicated within the curve epsilon.
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

    /// Earliest and latest key across all channels, nil when empty.
    public var timeSpan: ClosedRange<Double>? {
        let all = curves.values.flatMap { $0.keys.map(\.time) }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        return lo...hi
    }

    private enum CodingKeys: String, CodingKey { case entity, rotationOrder, curves }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.entity = try c.decode(String.self, forKey: .entity)
        self.rotationOrder = try c.decodeIfPresent(AnimationRotationOrder.self, forKey: .rotationOrder) ?? .xyz
        // String-keyed on the wire; unknown channel names are dropped so a
        // newer document degrades gracefully on an older player.
        let raw = try c.decodeIfPresent([String: AnimationCurve].self, forKey: .curves) ?? [:]
        var curves: [AnimationChannel: AnimationCurve] = [:]
        for (name, curve) in raw {
            if let channel = AnimationChannel(rawValue: name) { curves[channel] = curve }
        }
        self.curves = curves
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entity, forKey: .entity)
        try c.encode(rotationOrder, forKey: .rotationOrder)
        var raw: [String: AnimationCurve] = [:]
        for (channel, curve) in curves where curve.isAnimated {
            raw[channel.rawValue] = curve
        }
        try c.encode(raw, forKey: .curves)
    }
}

// MARK: - Sampled pose

/// The result of sampling an entity's track at a segment time. Unkeyed
/// channels carry the rest value; `opacity` is nil when the opacity channel
/// has no keys (the step/action system owns visibility then).
public struct AnimationSampledPose: Sendable, Equatable {
    public var position: Vec3
    public var rotation: Quat
    public var scale: Vec3
    public var opacity: Float?

    public init(position: Vec3, rotation: Quat, scale: Vec3, opacity: Float? = nil) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.opacity = opacity
    }
}

// MARK: - Evaluation

/// Scalar curve evaluation — the one interpolation truth for segment
/// animation tracks, shared by players and editors. Pure math.
public enum SegmentAnimationEvaluator {

    /// Sample one curve at `time` (absolute segment seconds). Holds flat
    /// before the first and after the last key; `rest` when empty.
    public static func evaluate(_ curve: AnimationCurve, at time: Double, rest: Float) -> Float {
        let keys = curve.keys
        guard let first = keys.first, let last = keys.last else { return rest }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }

        // Binary search for the segment [k0, k1] containing `time`.
        var lo = 0
        var hi = keys.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if keys[mid].time <= time { lo = mid } else { hi = mid }
        }
        let k0 = keys[lo]
        let k1 = keys[hi]

        switch k0.interpolation {
        case .stepped:
            return k0.value
        case .linear:
            let t = Float((time - k0.time) / max(k1.time - k0.time, 1e-6))
            return k0.value + (k1.value - k0.value) * t
        case .bezier:
            return bezier(from: k0, to: k1, at: time)
        }
    }

    /// Cubic Bézier in (time, value) space. Control times are clamped
    /// inside the segment so x(t) stays monotonic — Newton then converges
    /// fast, with a bisection safety net.
    static func bezier(from k0: AnimationKey, to k1: AnimationKey, at time: Double) -> Float {
        let x0 = k0.time
        let x3 = k1.time
        let x1 = min(max(k0.time + k0.outTangent.dt, x0), x3)
        let x2 = min(max(k1.time - k1.inTangent.dt, x0), x3)
        let y0 = k0.value
        let y1 = k0.value + k0.outTangent.dv
        let y2 = k1.value - k1.inTangent.dv
        let y3 = k1.value
        let t = solveT(x: time, x0: x0, x1: x1, x2: x2, x3: x3)
        return cubic(t, y0, y1, y2, y3)
    }

    private static func cubic(_ t: Float, _ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float) -> Float {
        let u = 1 - t
        return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }

    /// Solve the cubic-x for the parameter where x(t) == x. Because control
    /// times are clamped in-segment, x(t) is monotonic: Newton from the
    /// linear seed converges in a handful of iterations; bisection catches
    /// degenerate derivatives.
    private static func solveT(x: Double, x0: Double, x1: Double, x2: Double, x3: Double) -> Float {
        let span = x3 - x0
        guard span > 1e-9 else { return 0 }
        var t = Float((x - x0) / span)
        let fx0 = Float(x0), fx1 = Float(x1), fx2 = Float(x2), fx3 = Float(x3)
        let target = Float(x)

        for _ in 0..<8 {
            let current = cubic(t, fx0, fx1, fx2, fx3)
            let u = 1 - t
            let derivative = 3 * u * u * (fx1 - fx0) + 6 * u * t * (fx2 - fx1) + 3 * t * t * (fx3 - fx2)
            guard abs(derivative) > 1e-6 else { break }
            let next = t - (current - target) / derivative
            if abs(next - t) < 1e-5 {
                return min(max(next, 0), 1)
            }
            t = min(max(next, 0), 1)
        }

        // Bisection fallback.
        var lo: Float = 0
        var hi: Float = 1
        for _ in 0..<32 {
            let mid = (lo + hi) / 2
            if cubic(mid, fx0, fx1, fx2, fx3) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Recompute auto-managed tangents across a whole curve: smooth
    /// through-slope between same-direction neighbors, FLAT at local
    /// extrema (so a bounce apex never overshoots) and at the end keys.
    /// Keys the author shaped by hand (`autoTangents == false`) are left
    /// untouched. Handles sit one-third of the neighboring span out.
    public static func refreshAutoTangents(_ curve: inout AnimationCurve) {
        let keys = curve.keys
        guard !keys.isEmpty else { return }
        for i in keys.indices {
            let key = keys[i]
            if key.autoTangents == false { continue }
            let prevSpan = i > 0 ? key.time - keys[i - 1].time
                : (i + 1 < keys.count ? keys[i + 1].time - key.time : 1)
            let nextSpan = i + 1 < keys.count ? keys[i + 1].time - key.time : prevSpan
            var slope: Float = 0
            if i > 0 && i + 1 < keys.count {
                let dvPrev = key.value - keys[i - 1].value
                let dvNext = keys[i + 1].value - key.value
                if dvPrev * dvNext > 0 {
                    slope = (keys[i + 1].value - keys[i - 1].value)
                        / Float(max(keys[i + 1].time - keys[i - 1].time, 1e-6))
                }
            }
            curve.updateKey(at: i) { k in
                k.inTangent = AnimationTangent(
                    dt: max(prevSpan / 3, 0.001),
                    dv: slope * Float(prevSpan / 3)
                )
                k.outTangent = AnimationTangent(
                    dt: max(nextSpan / 3, 0.001),
                    dv: slope * Float(nextSpan / 3)
                )
            }
        }
    }

    /// Sample a full pose from a track. `rest` supplies values for unkeyed
    /// channels (the entity's base transform); rotation rest is extracted
    /// as Euler degrees in the track's rotate order.
    public static func samplePose(
        _ track: EntityAnimationTrack, at time: Double, rest: TransformData
    ) -> AnimationSampledPose {
        let restEuler = AnimationEulerMath.quatToEuler(
            simd_quatf(vector: SIMD4(rest.rotation.x, rest.rotation.y, rest.rotation.z, rest.rotation.w)),
            order: track.rotationOrder
        )
        func channel(_ ch: AnimationChannel, rest restValue: Float) -> Float {
            evaluate(track[ch], at: time, rest: restValue)
        }
        let position = Vec3(
            channel(.tx, rest: rest.position.x),
            channel(.ty, rest: rest.position.y),
            channel(.tz, rest: rest.position.z)
        )
        let eulerDegrees = SIMD3<Float>(
            channel(.rx, rest: restEuler.x),
            channel(.ry, rest: restEuler.y),
            channel(.rz, rest: restEuler.z)
        )
        let scale = Vec3(
            channel(.sx, rest: rest.scale.x),
            channel(.sy, rest: rest.scale.y),
            channel(.sz, rest: rest.scale.z)
        )
        let q = AnimationEulerMath.eulerToQuat(eulerDegrees, order: track.rotationOrder)
        let opacity: Float? = track[.opacity].isAnimated
            ? min(max(channel(.opacity, rest: 1), 0), 1)
            : nil
        return AnimationSampledPose(
            position: position,
            rotation: Quat(x: q.vector.x, y: q.vector.y, z: q.vector.z, w: q.vector.w),
            scale: scale,
            opacity: opacity
        )
    }
}

// MARK: - Euler math

/// Quaternion ↔ Euler conversion for all six rotate orders. Angles are in
/// DEGREES; order `.xyz` applies X first, so q = q_z · q_y · q_x. The most
/// convention-sensitive math in the format — round-tripped by unit tests
/// for every order.
public enum AnimationEulerMath {

    /// Compose a quaternion from Euler angles (degrees) in the given order.
    public static func eulerToQuat(_ degrees: SIMD3<Float>, order: AnimationRotationOrder) -> simd_quatf {
        let radians = degrees * (.pi / 180)
        let (i, j, k) = order.axes
        let qFirst = simd_quatf(angle: radians[i], axis: axisVector(i))
        let qMiddle = simd_quatf(angle: radians[j], axis: axisVector(j))
        let qLast = simd_quatf(angle: radians[k], axis: axisVector(k))
        return qLast * qMiddle * qFirst
    }

    /// Extract Euler angles (degrees) from a quaternion for the given order.
    public static func quatToEuler(_ q: simd_quatf, order: AnimationRotationOrder) -> SIMD3<Float> {
        let m = simd_float3x3(simd_normalize(q))
        let (i, j, k) = order.axes
        let sigma: Float = order.isCyclic ? 1 : -1

        // element(row, col); simd matrices are column-major.
        func element(_ row: Int, _ col: Int) -> Float { m[col][row] }

        let sinMiddle = max(-1, min(1, -sigma * element(k, i)))
        var first: Float
        let middle = asin(sinMiddle)
        var last: Float

        if abs(sinMiddle) < 0.99999 {
            first = atan2(sigma * element(k, j), element(k, k))
            last = atan2(sigma * element(j, i), element(i, i))
        } else {
            // Gimbal pole: first and last rotate about the same world axis,
            // so only their combination is defined. Convention: last = 0,
            // then recover first from the residual quaternion.
            last = 0
            let qMiddle = simd_quatf(angle: middle, axis: axisVector(j))
            let qFirst = qMiddle.inverse * simd_normalize(q)
            let v = qFirst.vector
            first = 2 * atan2(v[i], v.w)
        }

        var out = SIMD3<Float>()
        out[i] = first
        out[j] = middle
        out[k] = last
        return out * (180 / .pi)
    }

    /// Wrap into (−180, 180].
    public static func normalized180(_ angle: Float) -> Float {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a <= -180 { a += 360 }
        return a
    }

    /// The multiple-of-360 representative of `angle` nearest to `reference`.
    public static func unwound(_ angle: Float, toward reference: Float) -> Float {
        reference + normalized180(angle - reference)
    }

    /// Decompose a quaternion into Euler angles CONTINUOUS with a reference
    /// (the previous known channel values). Considers both Euler solutions
    /// of the rotation, unwinds each axis by whole turns toward the
    /// reference, and returns the closer one — so channels accumulate past
    /// 360° instead of snapping back (a live Euler filter).
    public static func continuousEuler(
        _ q: simd_quatf, order: AnimationRotationOrder, reference: SIMD3<Float>
    ) -> SIMD3<Float> {
        let primary = quatToEuler(q, order: order)
        let (i, j, k) = order.axes
        // The second Euler solution of the same rotation:
        // first+180, mirrored middle, last+180.
        var alternate = SIMD3<Float>()
        alternate[i] = normalized180(primary[i] + 180)
        alternate[j] = normalized180(copysign(180, primary[j]) - primary[j])
        alternate[k] = normalized180(primary[k] + 180)

        func unwind(_ e: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(unwound(e.x, toward: reference.x),
                  unwound(e.y, toward: reference.y),
                  unwound(e.z, toward: reference.z))
        }
        let c1 = unwind(primary)
        let c2 = unwind(alternate)
        let d1 = abs(c1.x - reference.x) + abs(c1.y - reference.y) + abs(c1.z - reference.z)
        let d2 = abs(c2.x - reference.x) + abs(c2.y - reference.y) + abs(c2.z - reference.z)
        return d1 <= d2 ? c1 : c2
    }

    private static func axisVector(_ index: Int) -> SIMD3<Float> {
        switch index {
        case 0: return [1, 0, 0]
        case 1: return [0, 1, 0]
        default: return [0, 0, 1]
        }
    }
}
