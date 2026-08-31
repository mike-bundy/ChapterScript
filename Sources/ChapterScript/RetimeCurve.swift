//
//  RetimeCurve.swift
//  ChapterScript
//
//  THE RETIME CURVE (FL-13): a keyed, piecewise, TIMELINE-position →
//  SOURCE-position mapping. The already-integrated position curve, stored
//  and queried directly — NEVER a rate curve integrated at query time.
//
//  One curve expresses everything:
//
//    • Constant speed  — the degenerate curve: endpoints, nothing between.
//    • Reverse         — a negative-slope span. There is NO reverse flag.
//    • Freeze          — a zero-slope span. There is NO freeze branch.
//    • No retime       — the ABSENCE of the field (`retime == nil` on the
//      carrier), which is today's exact behaviour at zero cost. `.identity`
//      here is the in-memory stand-in for that absence and is never
//      persisted as an empty object.
//
//  `timelinePosition` is normalized 0…1 across the Clip's span because a
//  trim changes the span but not the curve — the curve's domain must be
//  span-relative. `sourcePosition` is absolute master-file seconds because
//  it is a fact about the master.
//
//  THE THREE CLOCKS: a retime curve is a function from Sequence time to
//  media source time. It NEVER touches Object animation Key time, which is
//  absolute Sequence seconds and not media time.
//

import Foundation

/// How output frames between source frames are produced under a retime.
/// Exactly two real modes — optical flow is a deliberate rejection.
///
/// An unrecognised future mode decodes as `.nearest` — the cheaper and more
/// conservative of the two, so an unknown mode never silently costs an
/// author playback performance — and its raw value round-trips verbatim.
public enum FrameSampling: Codable, Sendable, Equatable, Hashable {
    case nearest
    case blend
    case unknown(String)

    public static let nearestKind = "nearest"
    public static let blendKind = "blend"

    public var rawKind: String {
        switch self {
        case .nearest: return Self.nearestKind
        case .blend: return Self.blendKind
        case .unknown(let raw): return raw
        }
    }

    /// What a renderer actually does — unknown modes sample nearest.
    public var effective: FrameSampling {
        if case .unknown = self { return .nearest }
        return self
    }

    public init(rawKind: String) {
        switch rawKind {
        case Self.nearestKind: self = .nearest
        case Self.blendKind: self = .blend
        default: self = .unknown(rawKind)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(rawKind: (try? c.decode(String.self)) ?? Self.nearestKind)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawKind)
    }
}

/// How a retimed occurrence's AUDIO pitch is handled. An occurrence
/// property beside the curve — never an export-only flag and never a
/// build-time gate.
public enum PitchHandling: String, Codable, Sendable, Equatable {
    /// The cheap default: pitch shifts with rate, like tape.
    case followsSpeed
    /// Pitch preserved through a time-pitch unit.
    case locked
    /// The occurrence has no audio to pitch.
    case notApplicable

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self = PitchHandling(rawValue: (try? c.decode(String.self)) ?? "followsSpeed")
            ?? .followsSpeed
    }
}

/// One key of the retime curve. Reuses the EXISTING interpolation and
/// tangent model (`AnimationInterpolation`, `AnimationTangent`) — a ramp is
/// a curve an author shapes, the Graph Editor is the one place they shape
/// curves, and a second key type would need a second editor (F-5).
public struct RetimeKey: Codable, Sendable, Equatable, Hashable {
    /// 0…1 across the Clip's CURRENT Timeline span.
    public var timelinePosition: Double
    /// Absolute seconds into the master file.
    public var sourcePosition: Double
    public var interpolation: AnimationInterpolation
    /// Optional shaped tangents, in (timeline-fraction, source-seconds)
    /// space. Absent ⇒ auto (a smooth default the editor manages) — and
    /// absent stays absent, so constant curves stay two plain keys.
    public var inTangent: AnimationTangent?
    public var outTangent: AnimationTangent?

    public init(timelinePosition: Double,
                sourcePosition: Double,
                interpolation: AnimationInterpolation = .linear,
                inTangent: AnimationTangent? = nil,
                outTangent: AnimationTangent? = nil) {
        self.timelinePosition = timelinePosition
        self.sourcePosition = sourcePosition
        self.interpolation = interpolation
        self.inTangent = inTangent
        self.outTangent = outTangent
    }

    private enum CodingKeys: String, CodingKey {
        case timelinePosition, sourcePosition, interpolation, inTangent, outTangent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.timelinePosition = try c.decode(Double.self, forKey: .timelinePosition)
        self.sourcePosition = try c.decode(Double.self, forKey: .sourcePosition)
        self.interpolation = try c.decodeIfPresent(AnimationInterpolation.self,
                                                   forKey: .interpolation) ?? .linear
        self.inTangent = try c.decodeIfPresent(AnimationTangent.self, forKey: .inTangent)
        self.outTangent = try c.decodeIfPresent(AnimationTangent.self, forKey: .outTangent)
    }
}

/// The curve itself: keys sorted by `timelinePosition`, queried directly.
public struct RetimeCurve: Codable, Sendable, Equatable, Hashable {
    public var keys: [RetimeKey]
    public var sampling: FrameSampling

    public init(keys: [RetimeKey], sampling: FrameSampling = .nearest) {
        self.keys = keys
        self.sampling = sampling
    }

    private enum CodingKeys: String, CodingKey { case keys, sampling }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.keys = try c.decodeIfPresent([RetimeKey].self, forKey: .keys) ?? []
        self.sampling = try c.decodeIfPresent(FrameSampling.self, forKey: .sampling) ?? .nearest
    }

    /// The in-memory stand-in for "no retime". NEVER persisted — a carrier
    /// with no retime stores nothing, and a curve that IS the identity is
    /// removed from the carrier rather than written empty.
    public static let identity = RetimeCurve(keys: [])

    /// True when this curve changes nothing — no keys, or fewer than two.
    /// A single key cannot express a mapping.
    public var isIdentity: Bool { keys.count < 2 }

    /// A constant-speed curve over a source window: the degenerate two-key
    /// form. `speed` is the rate through the window (2 = double speed);
    /// negative speeds are expressed by callers via reversed endpoints, not
    /// by a flag here.
    public static func constant(sourceIn: Double, sourceOut: Double,
                                sampling: FrameSampling = .nearest) -> RetimeCurve {
        RetimeCurve(keys: [
            RetimeKey(timelinePosition: 0, sourcePosition: sourceIn),
            RetimeKey(timelinePosition: 1, sourcePosition: sourceOut),
        ], sampling: sampling)
    }

    /// True when any span runs backwards through the source — the property
    /// long-GOP eligibility gates on. A span, never a flag.
    public var containsReverseSpan: Bool {
        let sorted = keys.sorted { $0.timelinePosition < $1.timelinePosition }
        guard sorted.count > 1 else { return false }
        for i in 1..<sorted.count where sorted[i].sourcePosition < sorted[i - 1].sourcePosition - 1e-12 {
            return true
        }
        return false
    }

    /// The absolute source position for a normalized Timeline fraction.
    ///
    /// Piecewise over the sorted keys; before the first key it holds the
    /// first source position, past the last it holds the last — the curve's
    /// statement simply extends. `stepped` holds the left key; `linear` and
    /// `bezier` interpolate (bezier through shaped tangents when present,
    /// smooth-through-linear otherwise: a position curve's auto tangents are
    /// the linear ones, so an unshaped bezier equals linear rather than
    /// inventing overshoot in TIME, where overshoot means frames the author
    /// never chose).
    public func sourcePosition(atFraction fraction: Double) -> Double? {
        let sorted = keys.sorted { $0.timelinePosition < $1.timelinePosition }
        guard let first = sorted.first, let last = sorted.last, sorted.count > 1 else {
            return sorted.first?.sourcePosition
        }
        if fraction <= first.timelinePosition { return first.sourcePosition }
        if fraction >= last.timelinePosition { return last.sourcePosition }
        for i in 1..<sorted.count {
            let a = sorted[i - 1], b = sorted[i]
            guard fraction <= b.timelinePosition + 1e-12 else { continue }
            let span = b.timelinePosition - a.timelinePosition
            guard span > 1e-12 else { return b.sourcePosition }
            let t = (fraction - a.timelinePosition) / span
            switch a.interpolation {
            case .stepped:
                return a.sourcePosition
            case .linear:
                return a.sourcePosition + (b.sourcePosition - a.sourcePosition) * t
            case .bezier:
                return Self.bezier(a: a, b: b, t: t, span: span)
            }
        }
        return last.sourcePosition
    }

    /// The instantaneous rate — source seconds per TIMELINE second — at a
    /// fraction of a clip whose span is `clipSpan`. 1 on the identity, the
    /// slope on a constant curve, the LOCAL slope on a ramp, 0 in a freeze,
    /// negative through a reverse span. Finite-difference on the position
    /// curve: the stored form is the position, so rate is derived — never
    /// stored, never integrated.
    public func sourceRate(atFraction fraction: Double, clipSpan: Double) -> Double {
        guard !isIdentity, clipSpan > 0 else { return 1 }
        let df = 1e-4
        let f0 = min(max(fraction, 0), 1 - df)
        guard let a = sourcePosition(atFraction: f0),
              let b = sourcePosition(atFraction: f0 + df) else { return 1 }
        return (b - a) / (df * clipSpan)
    }

    /// Cubic Bézier in (fraction, source) space, solved for the source value
    /// at fraction parameter — bisection on the monotone-in-x curve.
    private static func bezier(a: RetimeKey, b: RetimeKey, t: Double, span: Double) -> Double {
        // Control points. Absent tangents ⇒ the linear ones (one third in).
        let third = span / 3.0
        let outDT = a.outTangent.map { min(max($0.dt, 0), span) } ?? third
        let inDT = b.inTangent.map { min(max($0.dt, 0), span) } ?? third
        let linearSlope = (b.sourcePosition - a.sourcePosition) / span
        let outDV = a.outTangent.map { Double($0.dv) } ?? linearSlope * third
        let inDV = b.inTangent.map { Double($0.dv) } ?? linearSlope * third
        let x0 = 0.0, x1 = outDT / span, x2 = 1 - inDT / span, x3 = 1.0
        let y0 = a.sourcePosition
        let y1 = a.sourcePosition + outDV
        let y2 = b.sourcePosition - inDV
        let y3 = b.sourcePosition
        // Solve bezierX(u) = t by bisection (x is monotone: 0 ≤ x1,x2 ≤ 1).
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let x = cubic(x0, x1, x2, x3, mid)
            if x < t { lo = mid } else { hi = mid }
        }
        let u = (lo + hi) / 2
        return cubic(y0, y1, y2, y3, u)
    }

    private static func cubic(_ p0: Double, _ p1: Double, _ p2: Double,
                              _ p3: Double, _ u: Double) -> Double {
        let v = 1 - u
        return v * v * v * p0 + 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u * p3
    }
}
