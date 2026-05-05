import Foundation

public enum StepTimingFunction: String, Codable, Sendable, Equatable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
}

public enum InterpolationMode: String, Codable, Sendable, Equatable {
    case step
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case bezier
    case spring
}

public struct KeyframePoint: Codable, Sendable, Equatable {
    public var time: Float
    public var value: Vec3
    public var interpolation: InterpolationMode
    /// Optional bezier handles. Only consulted when `interpolation == .bezier`.
    public var inTangent: Vec3?
    public var outTangent: Vec3?

    public init(
        time: Float,
        value: Vec3,
        interpolation: InterpolationMode = .linear,
        inTangent: Vec3? = nil,
        outTangent: Vec3? = nil
    ) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
        self.inTangent = inTangent
        self.outTangent = outTangent
    }
}

public enum Waveform: String, Codable, Sendable, Equatable {
    case sine
    case absSine
    case triangle
    case square
}

/// Parametric motion description that an evaluator can sample over a step's progress in [0, 1].
/// Covers the periodic + path motions present in SharedVisions's per-frame code (orbit, spiral,
/// oscillate, rotate, linear) plus a `keyframes` escape hatch for arbitrary author-defined splines.
public indirect enum MotionCurve: Codable, Sendable, Equatable {
    case constant(Vec3)
    case linear(from: Vec3, to: Vec3)
    case orbit(center: Vec3, radius: Float, axis: Vec3, revolutions: Float, phase: Float)
    case spiral(center: Vec3, startRadius: Float, endRadius: Float, axis: Vec3, revolutions: Float, yRise: Float)
    case oscillate(axis: Vec3, amplitude: Float, frequency: Float, waveform: Waveform)
    case rotate(axis: Vec3, revolutions: Float)
    case keyframes([KeyframePoint])
    case sum([MotionCurve])
    case scaled(MotionCurve, by: Float)

    private enum CodingKeys: String, CodingKey { case kind, payload }

    private enum Kind: String, Codable {
        case constant, linear, orbit, spiral, oscillate, rotate, keyframes, sum, scaled
    }

    private struct LinearPayload: Codable { let from: Vec3; let to: Vec3 }
    private struct OrbitPayload: Codable { let center: Vec3; let radius: Float; let axis: Vec3; let revolutions: Float; let phase: Float }
    private struct SpiralPayload: Codable { let center: Vec3; let startRadius: Float; let endRadius: Float; let axis: Vec3; let revolutions: Float; let yRise: Float }
    private struct OscillatePayload: Codable { let axis: Vec3; let amplitude: Float; let frequency: Float; let waveform: Waveform }
    private struct RotatePayload: Codable { let axis: Vec3; let revolutions: Float }
    private struct ScaledPayload: Codable { let curve: MotionCurve; let by: Float }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .constant(let v):
            try c.encode(Kind.constant, forKey: .kind)
            try c.encode(v, forKey: .payload)
        case .linear(let from, let to):
            try c.encode(Kind.linear, forKey: .kind)
            try c.encode(LinearPayload(from: from, to: to), forKey: .payload)
        case .orbit(let center, let radius, let axis, let revolutions, let phase):
            try c.encode(Kind.orbit, forKey: .kind)
            try c.encode(OrbitPayload(center: center, radius: radius, axis: axis, revolutions: revolutions, phase: phase), forKey: .payload)
        case .spiral(let center, let startRadius, let endRadius, let axis, let revolutions, let yRise):
            try c.encode(Kind.spiral, forKey: .kind)
            try c.encode(SpiralPayload(center: center, startRadius: startRadius, endRadius: endRadius, axis: axis, revolutions: revolutions, yRise: yRise), forKey: .payload)
        case .oscillate(let axis, let amplitude, let frequency, let waveform):
            try c.encode(Kind.oscillate, forKey: .kind)
            try c.encode(OscillatePayload(axis: axis, amplitude: amplitude, frequency: frequency, waveform: waveform), forKey: .payload)
        case .rotate(let axis, let revolutions):
            try c.encode(Kind.rotate, forKey: .kind)
            try c.encode(RotatePayload(axis: axis, revolutions: revolutions), forKey: .payload)
        case .keyframes(let pts):
            try c.encode(Kind.keyframes, forKey: .kind)
            try c.encode(pts, forKey: .payload)
        case .sum(let curves):
            try c.encode(Kind.sum, forKey: .kind)
            try c.encode(curves, forKey: .payload)
        case .scaled(let curve, let by):
            try c.encode(Kind.scaled, forKey: .kind)
            try c.encode(ScaledPayload(curve: curve, by: by), forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .constant:
            self = .constant(try c.decode(Vec3.self, forKey: .payload))
        case .linear:
            let p = try c.decode(LinearPayload.self, forKey: .payload)
            self = .linear(from: p.from, to: p.to)
        case .orbit:
            let p = try c.decode(OrbitPayload.self, forKey: .payload)
            self = .orbit(center: p.center, radius: p.radius, axis: p.axis, revolutions: p.revolutions, phase: p.phase)
        case .spiral:
            let p = try c.decode(SpiralPayload.self, forKey: .payload)
            self = .spiral(center: p.center, startRadius: p.startRadius, endRadius: p.endRadius, axis: p.axis, revolutions: p.revolutions, yRise: p.yRise)
        case .oscillate:
            let p = try c.decode(OscillatePayload.self, forKey: .payload)
            self = .oscillate(axis: p.axis, amplitude: p.amplitude, frequency: p.frequency, waveform: p.waveform)
        case .rotate:
            let p = try c.decode(RotatePayload.self, forKey: .payload)
            self = .rotate(axis: p.axis, revolutions: p.revolutions)
        case .keyframes:
            self = .keyframes(try c.decode([KeyframePoint].self, forKey: .payload))
        case .sum:
            self = .sum(try c.decode([MotionCurve].self, forKey: .payload))
        case .scaled:
            let p = try c.decode(ScaledPayload.self, forKey: .payload)
            self = .scaled(p.curve, by: p.by)
        }
    }
}
