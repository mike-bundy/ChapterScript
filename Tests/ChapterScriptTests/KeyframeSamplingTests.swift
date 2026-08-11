import XCTest
@testable import ChapterScript

final class KeyframeSamplingTests: XCTestCase {

    private func key(_ t: Float, _ x: Float, _ mode: InterpolationMode = .linear,
                     inTan: Vec3? = nil, outTan: Vec3? = nil) -> KeyframePoint {
        KeyframePoint(time: t, value: Vec3(x: x, y: 0, z: 0),
                      interpolation: mode, inTangent: inTan, outTangent: outTan)
    }

    func testEmptyAndSingle() {
        XCTAssertEqual(KeyframeSampling.sample([], at: 0.5), .zero)
        XCTAssertEqual(KeyframeSampling.sample([key(0.5, 3)], at: 0.9).x, 3)
    }

    func testClampsOutsideRange() {
        let pts = [key(0.2, 1), key(0.8, 5)]
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 0).x, 1)
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 1).x, 5)
    }

    func testLinearAndStep() {
        let linear = [key(0, 0), key(1, 10)]
        XCTAssertEqual(KeyframeSampling.sample(linear, at: 0.25).x, 2.5, accuracy: 0.001)
        let stepped = [key(0, 0, .step), key(1, 10)]
        XCTAssertEqual(KeyframeSampling.sample(stepped, at: 0.99).x, 0)
    }

    func testEaseInOutHitsMidpoint() {
        let pts = [key(0, 0, .easeInOut), key(1, 10)]
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 0.5).x, 5, accuracy: 0.001)
        // Slow start: quarter-time is well under linear's 2.5.
        XCTAssertLessThan(KeyframeSampling.sample(pts, at: 0.25).x, 2.0)
    }

    func testBezierAutoTangentsInterpolateThroughKeys() {
        // Catmull-Rom auto tangents must pass exactly through every key.
        let pts = [key(0, 0, .bezier), key(0.5, 8, .bezier), key(1, 2, .bezier)]
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 0).x, 0, accuracy: 0.001)
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 0.5).x, 8, accuracy: 0.01)
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 1).x, 2, accuracy: 0.001)
        // Smooth mid-sequence: strictly between neighbors near the peak.
        let v = KeyframeSampling.sample(pts, at: 0.4).x
        XCTAssertGreaterThan(v, 4)
        XCTAssertLessThan(v, 9)
    }

    func testBezierExplicitFlatTangentsEaseInPlace() {
        // Zero in/out tangents = Maya "flat" keys — no overshoot ever.
        let pts = [key(0, 0, .bezier, outTan: .zero), key(1, 10, .bezier, inTan: .zero)]
        let quarter = KeyframeSampling.sample(pts, at: 0.25).x
        let half = KeyframeSampling.sample(pts, at: 0.5).x
        XCTAssertEqual(half, 5, accuracy: 0.01)   // symmetric S-curve midpoint
        XCTAssertGreaterThan(quarter, 0)
        XCTAssertLessThan(quarter, 2.5)           // slower than linear at t=0.25
    }

    func testSpringSettlesAtTarget() {
        XCTAssertEqual(KeyframeSampling.springEase(0), 0)
        XCTAssertEqual(KeyframeSampling.springEase(1), 1)
        // Overshoots somewhere in the middle…
        let peak = stride(from: Float(0.05), to: 1, by: 0.05)
            .map(KeyframeSampling.springEase).max() ?? 0
        XCTAssertGreaterThan(peak, 1.0)
        XCTAssertLessThan(peak, 1.35)
        let pts = [key(0, 0, .spring), key(1, 10)]
        XCTAssertEqual(KeyframeSampling.sample(pts, at: 1).x, 10, accuracy: 0.001)
    }
}
