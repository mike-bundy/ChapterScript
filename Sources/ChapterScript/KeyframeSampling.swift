import Foundation

/// Canonical keyframe-curve sampling — the ONE interpolation truth shared
/// by every runtime (ChapterPlayer playback, MaestroStudio's graph editor,
/// MaestroVision's motion trails). Pure math on format types; no
/// platform dependencies.
///
/// Interpolation semantics (Maya-style, keyed on the SEGMENT's left
/// keyframe):
///   .step      hold the left value until the next key
///   .linear    straight lerp
///   .easeIn/.easeOut/.easeInOut   classic quadratic eases on the lerp
///   .bezier    cubic Hermite. Tangent slopes come from the left key's
///              `outTangent` and the right key's `inTangent` when present
///              (value-units per normalized-time-unit); missing tangents
///              fall back to Catmull-Rom auto-tangents from the
///              neighboring keys — Maya's "smooth/auto" behavior.
///   .spring    a lightly-overshooting settle into the right value
///              (elastic-out flavored, deterministic).
public enum KeyframeSampling {

    /// Sample a keyframe array at normalized time `t` (0…1). Keys must be
    /// sorted by time (the authoring layer maintains this). Out-of-range
    /// times clamp to the end keys; an empty array returns `.zero`.
    public static func sample(_ points: [KeyframePoint], at t: Float) -> Vec3 {
        guard let first = points.first else { return .zero }
        guard points.count > 1 else { return first.value }
        if t <= first.time { return first.value }
        guard let last = points.last, t < last.time else { return points[points.count - 1].value }

        // Find the segment containing t.
        var i = 0
        while i + 1 < points.count && points[i + 1].time <= t { i += 1 }
        let k0 = points[i]
        let k1 = points[min(i + 1, points.count - 1)]
        let span = max(k1.time - k0.time, 0.0001)
        let local = (t - k0.time) / span

        switch k0.interpolation {
        case .step:
            return k0.value
        case .linear:
            return mix(k0.value, k1.value, local)
        case .easeIn:
            return mix(k0.value, k1.value, local * local)
        case .easeOut:
            return mix(k0.value, k1.value, 1 - (1 - local) * (1 - local))
        case .easeInOut:
            let e = local < 0.5 ? 2 * local * local : 1 - pow(-2 * local + 2, 2) / 2
            return mix(k0.value, k1.value, e)
        case .bezier:
            let prev = i > 0 ? points[i - 1] : nil
            let next = i + 2 < points.count ? points[i + 2] : nil
            return hermite(k0: k0, k1: k1, prev: prev, next: next, local: local, span: span)
        case .spring:
            return mix(k0.value, k1.value, springEase(local))
        }
    }

    // MARK: - Cubic Hermite (bezier / auto tangents)

    /// Cubic Hermite basis with per-axis tangent slopes. Explicit tangents
    /// are slopes in value-units per SEGMENT (already scaled); auto
    /// tangents use Catmull-Rom over the neighbors, scaled to the segment.
    private static func hermite(
        k0: KeyframePoint, k1: KeyframePoint,
        prev: KeyframePoint?, next: KeyframePoint?,
        local: Float, span: Float
    ) -> Vec3 {
        let m0 = k0.outTangent.map { scale($0, by: span) }
            ?? autoTangent(before: prev, at: k0, after: k1, span: span)
        let m1 = k1.inTangent.map { scale($0, by: span) }
            ?? autoTangent(before: k0, at: k1, after: next, span: span)

        let t = local
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return Vec3(
            x: h00 * k0.value.x + h10 * m0.x + h01 * k1.value.x + h11 * m1.x,
            y: h00 * k0.value.y + h10 * m0.y + h01 * k1.value.y + h11 * m1.y,
            z: h00 * k0.value.z + h10 * m0.z + h01 * k1.value.z + h11 * m1.z
        )
    }

    /// Catmull-Rom auto tangent at `at`, scaled into the sampling
    /// segment's parameter space. End keys ease flat toward their single
    /// neighbor (Maya's "auto" flattens at curve ends).
    private static func autoTangent(
        before: KeyframePoint?, at: KeyframePoint, after: KeyframePoint?, span: Float
    ) -> Vec3 {
        switch (before, after) {
        case (nil, nil):
            return .zero
        case (nil, .some(let n)):
            let dt = max(n.time - at.time, 0.0001)
            return scale(delta(n.value, at.value), by: span / dt * 0.5)
        case (.some(let p), nil):
            let dt = max(at.time - p.time, 0.0001)
            return scale(delta(at.value, p.value), by: span / dt * 0.5)
        case (.some(let p), .some(let n)):
            let dt = max(n.time - p.time, 0.0001)
            return scale(delta(n.value, p.value), by: span / dt)
        }
    }

    // MARK: - Spring

    /// Deterministic elastic-out settle with a single gentle overshoot
    /// (~8%), landing exactly at 1.
    static func springEase(_ t: Float) -> Float {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        let decay = exp(-6 * t)
        return 1 - decay * cos(4.5 * .pi * t * 0.6) * (1 - t * 0.2)
    }

    // MARK: - Vec3 helpers

    private static func mix(_ a: Vec3, _ b: Vec3, _ t: Float) -> Vec3 {
        Vec3(x: a.x + (b.x - a.x) * t,
             y: a.y + (b.y - a.y) * t,
             z: a.z + (b.z - a.z) * t)
    }
    private static func delta(_ a: Vec3, _ b: Vec3) -> Vec3 {
        Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }
    private static func scale(_ v: Vec3, by s: Float) -> Vec3 {
        Vec3(x: v.x * s, y: v.y * s, z: v.z * s)
    }
}
