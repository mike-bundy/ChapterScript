import XCTest
import simd
@testable import ChapterScript

final class SegmentAnimationTests: XCTestCase {

    private func key(
        _ time: Double, _ value: Float,
        _ interpolation: AnimationInterpolation = .bezier
    ) -> AnimationKey {
        AnimationKey(time: time, value: value, interpolation: interpolation)
    }

    // MARK: - Curve invariants

    func testSetKeyKeepsSortedAndReplacesAtSameInstant() {
        var curve = AnimationCurve()
        curve.setKey(key(2, 20))
        curve.setKey(key(0.5, 5))
        curve.setKey(key(1, 10))
        XCTAssertEqual(curve.keys.map(\.time), [0.5, 1, 2])
        curve.setKey(key(1.001, 99))    // within epsilon of 1 → replace
        XCTAssertEqual(curve.keys.count, 3)
        XCTAssertEqual(curve.keys[1].value, 99)
    }

    // MARK: - Evaluation

    func testEmptyReturnsRestAndEndsHold() {
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(AnimationCurve(), at: 3, rest: 7), 7)
        let curve = AnimationCurve(keys: [key(1, 2), key(3, 8)])
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(curve, at: 0, rest: 0), 2)
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(curve, at: 10, rest: 0), 8)
    }

    func testLinearAndStepped() {
        let linear = AnimationCurve(keys: [key(0, 0, .linear), key(2, 10)])
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(linear, at: 0.5, rest: 0), 2.5, accuracy: 0.001)
        let stepped = AnimationCurve(keys: [key(0, 0, .stepped), key(2, 10)])
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(stepped, at: 1.99, rest: 0), 0)
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(stepped, at: 2, rest: 0), 10)
    }

    func testBezierWithFlatAutoTangentsPassesThroughKeysMonotonically() {
        var curve = AnimationCurve(keys: [key(0, 0), key(1, 5), key(2, 10)])
        SegmentAnimationEvaluator.refreshAutoTangents(&curve)
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(curve, at: 0, rest: 0), 0)
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(curve, at: 1, rest: 0), 5, accuracy: 0.001)
        XCTAssertEqual(SegmentAnimationEvaluator.evaluate(curve, at: 2, rest: 0), 10)
        // Monotonic ramp stays monotonic.
        var previous: Float = -1
        for i in 0...40 {
            let v = SegmentAnimationEvaluator.evaluate(curve, at: Double(i) * 0.05, rest: 0)
            XCTAssertGreaterThanOrEqual(v + 0.0001, previous)
            previous = v
        }
    }

    func testAutoTangentsFlattenAtExtrema() {
        // A bounce apex: up to 10, back to 0. The apex tangent must be flat
        // so the curve never overshoots above the key value.
        var curve = AnimationCurve(keys: [key(0, 0), key(1, 10), key(2, 0)])
        SegmentAnimationEvaluator.refreshAutoTangents(&curve)
        let apex = curve.keys[1]
        XCTAssertEqual(apex.inTangent.dv, 0)
        XCTAssertEqual(apex.outTangent.dv, 0)
        for i in 0...40 {
            let v = SegmentAnimationEvaluator.evaluate(curve, at: Double(i) * 0.05, rest: 0)
            XCTAssertLessThanOrEqual(v, 10.0001)
        }
    }

    func testHandShapedTangentsSurviveAutoRefresh() {
        var curve = AnimationCurve(keys: [key(0, 0), key(1, 10)])
        curve.updateKey(at: 0) { k in
            k.outTangent = AnimationTangent(dt: 0.9, dv: 42)
            k.autoTangents = false
        }
        SegmentAnimationEvaluator.refreshAutoTangents(&curve)
        XCTAssertEqual(curve.keys[0].outTangent.dv, 42)
        // The auto key still got refreshed.
        XCTAssertNotEqual(curve.keys[1].inTangent.dt, AnimationTangent().dt)
    }

    // MARK: - Pose sampling

    func testSamplePoseUsesRestForUnkeyedChannels() {
        var track = EntityAnimationTrack(entity: "orb")
        track[.ty] = AnimationCurve(keys: [key(0, 0, .linear), key(2, 4)])
        let rest = TransformData(
            position: Vec3(1, 2, 3),
            rotation: .identity,
            scale: Vec3(2, 2, 2)
        )
        let pose = SegmentAnimationEvaluator.samplePose(track, at: 1, rest: rest)
        XCTAssertEqual(pose.position.x, 1)          // rest
        XCTAssertEqual(pose.position.y, 2, accuracy: 0.001)  // keyed midpoint
        XCTAssertEqual(pose.position.z, 3)          // rest
        XCTAssertEqual(pose.scale.x, 2)
        XCTAssertNil(pose.opacity)                  // opacity unkeyed
    }

    func testSamplePoseOpacityClamped() {
        var track = EntityAnimationTrack(entity: "orb")
        track[.opacity] = AnimationCurve(keys: [key(0, -1, .linear), key(1, 2)])
        let pose = SegmentAnimationEvaluator.samplePose(track, at: 0, rest: .identity)
        XCTAssertEqual(pose.opacity, 0)
    }

    // MARK: - Euler math

    func testEulerRoundTripAllOrders() {
        let cases: [SIMD3<Float>] = [
            SIMD3(10, 20, 30), SIMD3(-45, 60, -120), SIMD3(0, 0, 0), SIMD3(179, -1, 2),
        ]
        for order in AnimationRotationOrder.allCases {
            for degrees in cases {
                let q = AnimationEulerMath.eulerToQuat(degrees, order: order)
                let extracted = AnimationEulerMath.quatToEuler(q, order: order)
                let q2 = AnimationEulerMath.eulerToQuat(extracted, order: order)
                // Compare rotations, not raw angles (two Euler solutions exist).
                let dot = abs(simd_dot(q.vector, q2.vector))
                XCTAssertGreaterThan(dot, 0.9999, "order \(order) degrees \(degrees)")
            }
        }
    }

    func testContinuousEulerAccumulatesPast360() {
        // Walk ry through 3 full turns in 10° steps; the unwrapped channel
        // must end near 1080, never snapping back to 0.
        var reference = SIMD3<Float>(0, 0, 0)
        for step in 1...108 {
            let target = Float(step) * 10
            let q = AnimationEulerMath.eulerToQuat(SIMD3(0, target, 0), order: .xyz)
            reference = AnimationEulerMath.continuousEuler(q, order: .xyz, reference: reference)
        }
        XCTAssertEqual(reference.y, 1080, accuracy: 0.5)
    }

    // MARK: - Codable round-trip

    func testTrackRoundTripsThroughJSON() throws {
        var track = EntityAnimationTrack(entity: "hero", rotationOrder: .zxy)
        track[.tx] = AnimationCurve(keys: [
            AnimationKey(time: 0, value: 0),
            AnimationKey(time: 2.5, value: 1.5, interpolation: .linear,
                         inTangent: AnimationTangent(dt: 0.4, dv: 0.2),
                         outTangent: AnimationTangent(dt: 0.6, dv: -0.1),
                         tangentMode: .broken, autoTangents: false),
        ])
        track[.opacity] = AnimationCurve(keys: [AnimationKey(time: 1, value: 0.5)])

        let segment = SegmentDefinitionDTO(
            id: "c1", name: "One", phase: "immersive",
            steps: [StepDefinitionDTO(id: "s1", name: "Step", duration: 5, actions: [])],
            animationTracks: [track]
        )
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(SegmentDefinitionDTO.self, from: data)
        XCTAssertEqual(decoded.animationTracks, [track])
    }

    func testLegacySegmentWithoutTracksDecodes() throws {
        let json = """
        {"id":"c1","name":"One","phase":"immersive",
         "steps":[{"id":"s1","name":"S","duration":3,"actions":[],"scheduledActions":[]}],
         "visibility":{},"onComplete":{"kind":"holdOnLastStep"}}
        """
        let decoded = try JSONDecoder().decode(SegmentDefinitionDTO.self, from: json.data(using: .utf8)!)
        XCTAssertTrue(decoded.animationTracks.isEmpty)
    }

    func testUnknownChannelNamesAreDroppedNotFatal() throws {
        let json = """
        {"entity":"orb","rotationOrder":"xyz",
         "curves":{"tx":{"keys":[{"time":0,"value":1}]},
                   "futureChannel":{"keys":[{"time":0,"value":9}]}}}
        """
        let decoded = try JSONDecoder().decode(EntityAnimationTrack.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.curves.count, 1)
        XCTAssertEqual(decoded[.tx].keys.first?.value, 1)
    }
}
