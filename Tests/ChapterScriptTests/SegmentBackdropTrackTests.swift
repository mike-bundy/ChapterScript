import XCTest
@testable import ChapterScript

/// Multiple backdrops per segment, on a timeline, with exactly one active at
/// any instant.
///
/// The exclusivity guarantee is the point of these tests: a cue has a start
/// and no end, so an overlap cannot be expressed. If someone later "improves"
/// this into a range model, these tests are what should stop them.
final class SegmentBackdropTrackTests: XCTestCase {

    private let sky360 = ImmersiveBackdropSpec.video(
        file: "sky.mp4", layout: .mono, field: .equirect360,
        radius: 1000, loop: true, audioEnabled: false
    )
    private let reef180 = ImmersiveBackdropSpec.video(
        file: "reef.aivu", layout: .multiviewHEVC, field: .equirect180,
        radius: 1000, loop: false, audioEnabled: true
    )
    private let still = ImmersiveBackdropSpec.image(file: "dusk.heic", field: .equirect360, radius: 1000)
    private let set = ImmersiveBackdropSpec.usdz(assetId: "stage.usdz")

    private func cue(_ id: String, _ start: Double, _ spec: ImmersiveBackdropSpec?) -> BackdropCue {
        BackdropCue(id: id, startTime: start, spec: spec)
    }

    // MARK: - Resolution

    func testEachKindCanBeCued() {
        let track = [cue("a", 0, sky360), cue("b", 5, set), cue("c", 10, still), cue("d", 15, reef180)]
        func at(_ t: Double) -> ImmersiveBackdropSpec? {
            SegmentBackdropTimeline.backdrop(at: t, track: track)
        }
        XCTAssertEqual(at(0), sky360)
        XCTAssertEqual(at(4.9), sky360)
        XCTAssertEqual(at(5), set)
        XCTAssertEqual(at(12), still)
        XCTAssertEqual(at(99), reef180, "the last cue governs to the end")
    }

    /// A cue takes effect exactly AT its start time, not a frame later.
    func testCueIsActiveAtItsOwnStartTime() {
        let track = [cue("a", 0, sky360), cue("b", 5, still)]
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 5, track: track), still)
    }

    /// Before the first cue there is no backdrop. Snapping the first cue to
    /// zero would make "start the backdrop at 4s" unauthorable.
    func testNoBackdropBeforeTheFirstCue() {
        let track = [cue("a", 4, sky360)]
        XCTAssertNil(SegmentBackdropTimeline.backdrop(at: 0, track: track))
        XCTAssertNil(SegmentBackdropTimeline.backdrop(at: 3.9, track: track))
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 4, track: track), sky360)
    }

    /// A nil-spec cue is how a backdrop is turned OFF mid-segment.
    func testNilCueClearsTheBackdrop() {
        let track = [cue("a", 0, sky360), cue("b", 6, nil)]
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 5, track: track), sky360)
        XCTAssertNil(SegmentBackdropTimeline.backdrop(at: 6, track: track))
        XCTAssertNil(SegmentBackdropTimeline.backdrop(at: 100, track: track))
    }

    /// Cues authored out of order still resolve by time — an editor may append
    /// a cue before retiming it.
    func testUnsortedCuesResolveByTime() {
        let track = [cue("c", 10, still), cue("a", 0, sky360), cue("b", 5, set)]
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 6, track: track), set)
        XCTAssertEqual(SegmentBackdropTimeline.effectiveCues(track: track, legacy: nil).map(\.id),
                       ["a", "b", "c"])
    }

    // MARK: - Exclusivity

    /// THE guarantee: whatever the cue list, at most one backdrop is active,
    /// and the drawn regions never overlap.
    func testRegionsTileTheSegmentWithoutOverlap() {
        let track = [cue("a", 0, sky360), cue("b", 5, set), cue("c", 12, still)]
        let regions = SegmentBackdropTimeline.regions(track: track, segmentDuration: 20)
        XCTAssertEqual(regions.map(\.cue.id), ["a", "b", "c"])
        XCTAssertEqual(regions.map(\.endTime), [5, 12, 20])
        // Each region ends exactly where the next begins — no gap, no overlap.
        for (index, region) in regions.enumerated() where index + 1 < regions.count {
            XCTAssertEqual(region.endTime, regions[index + 1].cue.startTime, accuracy: 1e-9)
        }
    }

    /// Two cues at the SAME instant is the one way to express ambiguity. The
    /// later one in the sorted list wins, deterministically, and the earlier
    /// draws as zero-width rather than negative.
    func testCoincidentCuesResolveDeterministically() {
        let track = [cue("a", 5, sky360), cue("b", 5, still)]
        let resolved = SegmentBackdropTimeline.backdrop(at: 5, track: track)
        XCTAssertEqual(resolved, still)
        let regions = SegmentBackdropTimeline.regions(track: track, segmentDuration: 20)
        XCTAssertEqual(regions[0].endTime, 5)
        XCTAssertGreaterThanOrEqual(regions[0].endTime, regions[0].cue.startTime)
    }

    /// A cue dragged past the segment end must not draw backwards.
    func testRegionWidthNeverGoesNegative() {
        let track = [cue("a", 30, sky360)]
        let regions = SegmentBackdropTimeline.regions(track: track, segmentDuration: 20)
        XCTAssertGreaterThanOrEqual(regions[0].endTime, regions[0].cue.startTime)
    }

    func testNegativeStartTimeIsClamped() {
        XCTAssertEqual(BackdropCue(startTime: -5, spec: nil).startTime, 0)
    }

    // MARK: - Back-compatibility

    /// A document written before the track existed must behave EXACTLY as
    /// before: its single backdrop covers the whole segment.
    func testLegacySingleBackdropFoldsIntoOneCue() {
        let cues = SegmentBackdropTimeline.effectiveCues(track: [], legacy: sky360)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].startTime, 0)
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 0, track: [], legacy: sky360), sky360)
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 999, track: [], legacy: sky360), sky360)
    }

    /// An authored track wins outright — the two must never composite.
    func testAuthoredTrackOverridesLegacyField() {
        let track = [cue("a", 0, still)]
        XCTAssertEqual(SegmentBackdropTimeline.backdrop(at: 3, track: track, legacy: sky360), still)
    }

    func testNoTrackAndNoLegacyIsNoBackdrop() {
        XCTAssertNil(SegmentBackdropTimeline.backdrop(at: 0, track: [], legacy: nil))
        XCTAssertTrue(SegmentBackdropTimeline.effectiveCues(track: [], legacy: nil).isEmpty)
    }

    // MARK: - Assets

    func testReferencedAssetsCoversEveryKindAndDeduplicates() {
        let track = [cue("a", 0, sky360), cue("b", 5, set), cue("c", 10, still),
                     cue("d", 15, nil), cue("e", 20, sky360)]
        XCTAssertEqual(SegmentBackdropTimeline.referencedAssets(track: track),
                       ["sky.mp4", "stage.usdz", "dusk.heic"])
    }

    // MARK: - Wire format

    func testCueRoundTrips() throws {
        for spec in [sky360, reef180, still, set] {
            let original = BackdropCue(id: "x", startTime: 3.5, spec: spec)
            let data = try JSONEncoder().encode(original)
            XCTAssertEqual(try JSONDecoder().decode(BackdropCue.self, from: data), original)
        }
    }

    func testNilSpecCueRoundTrips() throws {
        let original = BackdropCue(id: "off", startTime: 8, spec: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackdropCue.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.spec)
    }

    /// Hand-authored JSON without an id must still be addressable.
    func testCueWithoutIdGetsOne() throws {
        let json = #"{"startTime":2}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BackdropCue.self, from: json)
        XCTAssertFalse(decoded.id.isEmpty)
        XCTAssertEqual(decoded.startTime, 2)
    }

    func testSegmentWithoutBackdropTrackDecodesToEmpty() throws {
        let json = """
        {"id":"s1","name":"S1","phase":"immersive","steps":[],
         "visibility":{},"onComplete":{"kind":"holdOnLastStep"}}
        """.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(SegmentDefinitionDTO.self, from: json).backdropTrack.isEmpty)
    }

    func testSegmentBackdropTrackRoundTrips() throws {
        var segment = SegmentDefinitionDTO(id: "s1", name: "S1", phase: "immersive", steps: [])
        segment.backdropTrack = [cue("a", 0, sky360), cue("b", 5, set), cue("c", 9, nil)]
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(SegmentDefinitionDTO.self, from: data)
        XCTAssertEqual(decoded.backdropTrack, segment.backdropTrack)
    }
}
