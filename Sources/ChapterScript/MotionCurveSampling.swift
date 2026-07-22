import Foundation
import simd

/// Canonical evaluator for `MotionCurve` — the ONE motion-sampling truth.
/// ChapterPlayer's runtime delegates here for playback; editors sample the
/// same math for scrub previews, motion trails, and graph rendering, so a
/// curve looks identical everywhere it appears.
///
/// Conventions
/// -----------
/// - `t` is normalized progress through the motion's window, clamped 0…1.
/// - `absoluteTime` is seconds since segment start; `oscillate` uses it
///   for real-time-locked phase.
/// - `rotate(axis, revolutions)` returns `axis * angleInRadians` — the
///   rotation channel treats the Vec3 as an axis-angle vector.
public enum MotionCurveSampling {

    public static func sample(_ curve: MotionCurve, t: Float, absoluteTime: Float) -> SIMD3<Float> {
        let clamped = max(0, min(1, t))
        switch curve {
        case .constant(let v):
            return SIMD3(v.x, v.y, v.z)

        case .linear(let from, let to):
            return mix(SIMD3(from.x, from.y, from.z), SIMD3(to.x, to.y, to.z), t: clamped)

        case .orbit(let center, let radius, let axis, let revolutions, let phase):
            let angle = (clamped * revolutions + phase) * 2 * .pi
            return orbitPoint(center: SIMD3(center.x, center.y, center.z), radius: radius,
                              axis: SIMD3(axis.x, axis.y, axis.z), angle: angle)

        case .spiral(let center, let startRadius, let endRadius, let axis, let revolutions, let yRise):
            let angle = clamped * revolutions * 2 * .pi
            let r = startRadius + (endRadius - startRadius) * clamped
            var p = orbitPoint(center: SIMD3(center.x, center.y, center.z), radius: r,
                               axis: SIMD3(axis.x, axis.y, axis.z), angle: angle)
            p.y += yRise * clamped
            return p

        case .oscillate(let axis, let amplitude, let frequency, let waveform):
            let phase = absoluteTime * frequency * 2 * .pi
            return SIMD3(axis.x, axis.y, axis.z) * (amplitude * waveform.sampleValue(phase: phase))

        case .rotate(let axis, let revolutions):
            let angle = clamped * revolutions * 2 * .pi
            return normalizeOrZero(SIMD3(axis.x, axis.y, axis.z)) * angle

        case .keyframes(let pts):
            let v = KeyframeSampling.sample(pts, at: clamped)
            return SIMD3(v.x, v.y, v.z)

        case .sum(let curves):
            return curves.reduce(SIMD3<Float>.zero) {
                $0 + sample($1, t: clamped, absoluteTime: absoluteTime)
            }

        case .scaled(let inner, let factor):
            return sample(inner, t: clamped, absoluteTime: absoluteTime) * factor
        }
    }

    // MARK: - Helpers

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    private static func normalizeOrZero(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let len = simd_length(v)
        return len > 0 ? v / len : .zero
    }

    /// Point on the circle of `radius` around `center`, normal to `axis`,
    /// at `angle` — orthonormal basis seeded from the axis.
    private static func orbitPoint(
        center: SIMD3<Float>, radius: Float,
        axis: SIMD3<Float>, angle: Float
    ) -> SIMD3<Float> {
        let n = normalizeOrZero(axis)
        if n == .zero { return center }
        let helper: SIMD3<Float> = abs(n.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        let u = normalizeOrZero(simd_cross(n, helper))
        let v = simd_cross(n, u)
        return center + u * (cos(angle) * radius) + v * (sin(angle) * radius)
    }
}

public extension Waveform {
    /// `phase` in radians; output in [-1, 1].
    func sampleValue(phase: Float) -> Float {
        switch self {
        case .sine:
            return sin(phase)
        case .absSine:
            return abs(sin(phase))
        case .triangle:
            let twoPi = 2 * Float.pi
            let p = phase.truncatingRemainder(dividingBy: twoPi)
            let normalized = p < 0 ? p + twoPi : p
            let unit = normalized / twoPi
            return unit < 0.5 ? -1 + 4 * unit : 3 - 4 * unit
        case .square:
            return sin(phase) >= 0 ? 1 : -1
        }
    }
}
