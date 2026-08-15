import XCTest
@testable import ChapterScript

/// Keyframed audio volume: the mixing rule, the master bus, and the
/// compatibility guarantees.
///
/// Before this, volume was a single static float on `playAudio` plus linear
/// `fadeAudio` ramps authored as discrete step actions — no curve, nothing to
/// edit, and nothing on the timeline to see.
final class SequenceAudioAutomationTests: XCTestCase {

    private func curve(_ points: [(Double, Float)]) -> AnimationCurve {
        AnimationCurve(keys: points.map {
            AnimationKey(time: $0.0, value: $0.1, interpolation: .linear)
        })
    }

    private func track(_ channel: String, _ points: [(Double, Float)]) -> AudioAutomationTrack {
        var t = AudioAutomationTrack(channel: channel)
        t[.volume] = curve(points)
        return t
    }

    // MARK: - Defaults / compatibility

    /// A document with no automation must mix EXACTLY as it did before the
    /// feature existed, so this can be sampled unconditionally every frame.
    func testNoAutomationIsUnityGain() {
        XCTAssertEqual(SequenceAudioAutomation.volumeMultiplier(for: "audio-vo", at: 3, in: []), 1.0)
        XCTAssertEqual(
            SequenceAudioAutomation.effectiveVolume(base: 0.6, channel: "audio-vo", at: 3, in: []),
            0.6, accuracy: 1e-6
        )
        XCTAssertFalse(SequenceAudioAutomation.hasAutomation([]))
    }

    /// A track that exists but has no keys is still unity — an emptied curve
    /// must not silence the channel.
    func testEmptyTrackIsUnityGain() {
        let empty = AudioAutomationTrack(channel: "audio-vo")
        XCTAssertFalse(empty.hasAnyKeys)
        XCTAssertEqual(SequenceAudioAutomation.volumeMultiplier(for: "audio-vo", at: 1, in: [empty]), 1.0)
    }

    /// Setting an emptied curve REMOVES it, so `hasAnyKeys` can't be fooled by
    /// a track full of empty curves.
    func testEmptiedCurveIsDropped() {
        var t = track("audio-vo", [(0, 1)])
        XCTAssertTrue(t.hasAnyKeys)
        t[.volume] = AnimationCurve()
        XCTAssertFalse(t.hasAnyKeys)
        XCTAssertTrue(t.curves.isEmpty)
    }

    // MARK: - The mixing rule

    /// base × channel × master. Each factor independent, which is what makes
    /// "turn this clip down" and "fade everything out" separate operations.
    func testEffectiveVolumeMultipliesBaseChannelAndMaster() {
        let tracks = [
            track("audio-music", [(0, 0.5)]),
            track(AudioAutomationTrack.masterChannel, [(0, 0.4)])
        ]
        XCTAssertEqual(
            SequenceAudioAutomation.effectiveVolume(base: 1.0, channel: "audio-music", at: 0, in: tracks),
            0.2, accuracy: 1e-6
        )
        // A different base scales it, and does not disturb the curves.
        XCTAssertEqual(
            SequenceAudioAutomation.effectiveVolume(base: 0.5, channel: "audio-music", at: 0, in: tracks),
            0.1, accuracy: 1e-6
        )
    }

    /// The master bus rides EVERY channel, including ones with no track.
    func testMasterAppliesToUnautomatedChannels() {
        let tracks = [track(AudioAutomationTrack.masterChannel, [(0, 0.25)])]
        XCTAssertEqual(
            SequenceAudioAutomation.volumeMultiplier(for: "audio-anything", at: 0, in: tracks),
            0.25, accuracy: 1e-6
        )
    }

    /// A channel curve must not leak onto a different channel.
    func testChannelCurvesAreIndependent() {
        let tracks = [track("audio-music", [(0, 0.2)])]
        XCTAssertEqual(SequenceAudioAutomation.volumeMultiplier(for: "audio-music", at: 0, in: tracks), 0.2, accuracy: 1e-6)
        XCTAssertEqual(SequenceAudioAutomation.volumeMultiplier(for: "audio-vo", at: 0, in: tracks), 1.0, accuracy: 1e-6)
    }

    /// The master track must never be resolvable as a normal channel, or a
    /// `playAudio` on a channel literally named "master" would silently
    /// double-apply the bus.
    func testMasterTrackIsNotAlsoANormalChannel() {
        let tracks = [track(AudioAutomationTrack.masterChannel, [(0, 0.5)])]
        // Looked up as a plain channel it contributes nothing extra; the only
        // 0.5 in the result comes from the master factor.
        XCTAssertEqual(
            SequenceAudioAutomation.value(.volume, for: AudioAutomationTrack.masterChannel, at: 0, in: tracks),
            1.0, accuracy: 1e-6
        )
        XCTAssertEqual(
            SequenceAudioAutomation.volumeMultiplier(for: AudioAutomationTrack.masterChannel, at: 0, in: tracks),
            0.5, accuracy: 1e-6
        )
    }

    // MARK: - Curve behaviour

    /// The duck: full, down under the VO, back up. Sampling between keys
    /// interpolates rather than stepping.
    func testDuckRidesBetweenKeys() {
        let tracks = [track("audio-music", [(0, 1.0), (4, 0.25), (9, 1.0)])]
        func at(_ t: Double) -> Float {
            SequenceAudioAutomation.volumeMultiplier(for: "audio-music", at: t, in: tracks)
        }
        XCTAssertEqual(at(0), 1.0, accuracy: 1e-5)
        XCTAssertEqual(at(4), 0.25, accuracy: 1e-5)
        XCTAssertEqual(at(9), 1.0, accuracy: 1e-5)
        // Halfway into the duck, linear interpolation puts it between the keys.
        let mid = at(2)
        XCTAssertLessThan(mid, 1.0)
        XCTAssertGreaterThan(mid, 0.25)
    }

    /// Before the first key and after the last, a curve holds — it must not
    /// fall back to the rest value and jump.
    func testCurveHoldsOutsideItsKeyedRange() {
        let tracks = [track("audio-music", [(5, 0.3), (10, 0.3)])]
        XCTAssertEqual(SequenceAudioAutomation.volumeMultiplier(for: "audio-music", at: 0, in: tracks), 0.3, accuracy: 1e-5)
        XCTAssertEqual(SequenceAudioAutomation.volumeMultiplier(for: "audio-music", at: 99, in: tracks), 0.3, accuracy: 1e-5)
    }

    /// Bezier handles legitimately overshoot past a key. Volume must not.
    func testEffectiveVolumeIsClamped() {
        let tracks = [track("audio-music", [(0, 1.0)]), track(AudioAutomationTrack.masterChannel, [(0, 1.0)])]
        XCTAssertEqual(
            SequenceAudioAutomation.effectiveVolume(base: 4.0, channel: "audio-music", at: 0, in: tracks),
            1.0, accuracy: 1e-6, "volume must clamp to 1"
        )
        let negative = [track("audio-music", [(0, -3)])]
        XCTAssertEqual(
            SequenceAudioAutomation.effectiveVolume(base: 1, channel: "audio-music", at: 0, in: negative),
            0, accuracy: 1e-6, "volume must clamp to 0"
        )
    }

    // MARK: - Track metadata

    func testKeyTimesAndSpan() {
        let t = track("audio-music", [(0, 1), (4, 0.25), (9, 1)])
        XCTAssertEqual(t.keyTimes, [0, 4, 9])
        XCTAssertEqual(t.timeSpan, 0...9)
        XCTAssertNil(AudioAutomationTrack(channel: "audio-vo").timeSpan)
    }

    // MARK: - Wire format

    func testTrackRoundTrips() throws {
        let original = track("audio-music", [(0, 1.0), (4, 0.25)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioAutomationTrack.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// Curves encode as a keyed object, not the array-pair a dictionary with an
    /// enum key would produce — a `chapter.json` has to stay readable.
    func testCurvesEncodeAsAKeyedObject() throws {
        let data = try JSONEncoder().encode(track("audio-music", [(0, 1)]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let curves = try XCTUnwrap(json["curves"] as? [String: Any])
        XCTAssertNotNil(curves["volume"])
    }

    /// A newer tool's unknown curve must not fail the whole document.
    ///
    /// This test used `pan` as its example, and pan has since SHIPPED (audio
    /// pass, 2026-08-14) — which is the tolerance working exactly as designed:
    /// documents written by the newer tool opened in builds that predated it.
    /// The example moved to a parameter that does not exist yet; the rule is
    /// unchanged.
    func testUnknownParameterDecodesRatherThanThrowing() throws {
        let json = """
        {"channel":"audio-music","curves":{"lowpass":{"keys":[{"time":0,"value":0.5}]}}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AudioAutomationTrack.self, from: json)
        XCTAssertEqual(decoded.channel, "audio-music")
        XCTAssertFalse(decoded.hasAnyKeys)
    }

    /// And the other half of that transition: a `pan` curve is now a REAL
    /// parameter and must decode into keys rather than being dropped.
    func testPanDecodesAsARealParameter() throws {
        let json = """
        {"channel":"audio-music","curves":{"pan":{"keys":[{"time":0,"value":-1},{"time":2,"value":1}]}}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AudioAutomationTrack.self, from: json)
        XCTAssertTrue(decoded.hasAnyKeys)
        XCTAssertTrue(decoded[.pan].isAnimated)
        XCTAssertEqual(
            SequenceAudioAutomation.pan(for: "audio-music", at: 0, in: [decoded]), -1, accuracy: 0.001
        )
        XCTAssertEqual(
            SequenceAudioAutomation.pan(for: "audio-music", at: 2, in: [decoded]), 1, accuracy: 0.001
        )
    }

    /// A sequence written before this feature has no `audioTracks` key at all.
    func testSequenceWithoutAudioTracksDecodesToEmpty() throws {
        let json = """
        {"id":"s1","name":"S1","phase":"immersive","steps":[],
         "visibility":{},"onComplete":{"kind":"holdOnLastStep"}}
        """.data(using: .utf8)!
        let sequence = try JSONDecoder().decode(SequenceDefinitionDTO.self, from: json)
        XCTAssertTrue(sequence.audioTracks.isEmpty)
    }

    func testSequenceAudioTracksRoundTrip() throws {
        var sequence = SequenceDefinitionDTO(id: "s1", name: "S1", phase: "immersive", steps: [])
        sequence.audioTracks = [
            track("audio-music", [(0, 1.0), (4, 0.25)]),
            track(AudioAutomationTrack.masterChannel, [(0, 1.0), (12, 0)])
        ]
        let data = try JSONEncoder().encode(sequence)
        let decoded = try JSONDecoder().decode(SequenceDefinitionDTO.self, from: data)
        XCTAssertEqual(decoded.audioTracks, sequence.audioTracks)
        XCTAssertTrue(SequenceAudioAutomation.hasAutomation(decoded.audioTracks))
    }
}
