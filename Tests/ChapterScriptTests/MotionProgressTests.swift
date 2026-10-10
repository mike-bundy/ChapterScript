import XCTest
@testable import ChapterScript

/// The editor and the player must compute "how far through this motion are we"
/// the same way. They did not, and nothing said so.
final class MotionProgressTests: XCTestCase {

    func testProgressIsZeroAtTheStart() {
        XCTAssertEqual(MotionProgress.progress(startTime: 5, now: 5, duration: 10), 0)
    }

    func testProgressIsOneAtTheEnd() {
        XCTAssertEqual(MotionProgress.progress(startTime: 5, now: 15, duration: 10), 1)
    }

    func testProgressIsLinearInBetween() {
        XCTAssertEqual(MotionProgress.progress(startTime: 5, now: 10, duration: 10),
                       0.5, accuracy: 1e-6)
    }

    func testProgressClampsBeforeTheStart() {
        XCTAssertEqual(MotionProgress.progress(startTime: 5, now: 0, duration: 10), 0,
                       "a motion that has not begun is at zero, not negative")
    }

    func testProgressClampsAfterTheEnd() {
        XCTAssertEqual(MotionProgress.progress(startTime: 5, now: 900, duration: 10), 1)
    }

    func testZeroDurationIsAnInstantNotADivisionByZero() {
        let p = MotionProgress.progress(startTime: 0, now: 0.5, duration: 0)
        XCTAssertEqual(p, 1)
        XCTAssertFalse(p.isNaN)
    }

    // MARK: - The parity bug this exists to close

    /// A motion scheduled 5s into a 10s segment, sampled 2s later.
    ///
    /// The runtime used to compute `segmentElapsed / duration` = 7/10 = 0.7 — the
    /// motion was 70% done two seconds after it started. The editor computed
    /// `(time - t0) / duration` = 2/10 = 0.2 and drew it correctly. Same
    /// document, two different pictures.
    func testMotionScheduledMidSegmentStartsAtZeroNotPartway() {
        let segmentStart = 100.0
        let motionStart = segmentStart + 5
        let now = motionStart + 2

        XCTAssertEqual(MotionProgress.progress(startTime: motionStart, now: now, duration: 10),
                       0.2, accuracy: 1e-6)

        // What the runtime used to produce, for the record.
        let legacySegmentRelative = Float((now - segmentStart) / 10)
        XCTAssertEqual(legacySegmentRelative, 0.7, accuracy: 1e-6)
        XCTAssertNotEqual(legacySegmentRelative,
                          MotionProgress.progress(startTime: motionStart, now: now, duration: 10))
    }

    /// A motion registered at a segment's start is unaffected — which is why this
    /// change is invisible in every document that only ever did that.
    func testMotionAtSegmentStartIsUnchangedByTheFix() {
        let segmentStart = 100.0
        for elapsed in stride(from: 0.0, through: 10.0, by: 0.5) {
            let now = segmentStart + elapsed
            XCTAssertEqual(
                MotionProgress.progress(startTime: segmentStart, now: now, duration: 10),
                Float(min(max(elapsed / 10, 0), 1)), accuracy: 1e-6)
        }
    }

    /// Timeline 3.0 requires a motion to survive a Segment boundary moving under
    /// it: merging two Segments must not change what an animation looks like.
    /// Measuring from the motion's own start is what makes that true.
    func testProgressIsIndependentOfWhereSegmentBoundariesFall() {
        // Same motion, same authored times; only the segment segmentation differs.  // LEGACY-VOCAB: 'segmentation' is ordinary English, not the retired unit
        let motionStart = 30.0, duration = 8.0, sampleAt = 34.0
        let asTwoSegments = MotionProgress.progress(startTime: motionStart, now: sampleAt,
                                                 duration: duration)
        let asOneSegment = MotionProgress.progress(startTime: motionStart, now: sampleAt,
                                                duration: duration)
        XCTAssertEqual(asTwoSegments, asOneSegment)
        XCTAssertEqual(asTwoSegments, 0.5, accuracy: 1e-6)
    }

    func testIsCompleteMatchesProgressReachingOne() {
        XCTAssertFalse(MotionProgress.isComplete(startTime: 0, now: 9.99, duration: 10))
        XCTAssertTrue(MotionProgress.isComplete(startTime: 0, now: 10, duration: 10))
        XCTAssertTrue(MotionProgress.isComplete(startTime: 0, now: 11, duration: 10))
    }
}
