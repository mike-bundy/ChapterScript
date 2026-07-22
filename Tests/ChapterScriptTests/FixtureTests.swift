import XCTest
@testable import ChapterScript

/// Verifies that bundled JSON fixtures (committed under Tests/Fixtures/) decode cleanly
/// and re-encode to the same logical document. Acts as a regression gate against
/// accidental schema changes — when intentional, regenerate fixtures.
final class FixtureTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            // Fall back to a search without subdirectory (Bundle.module may flatten).
            if let url = Bundle.module.url(forResource: name, withExtension: "json") {
                return try Data(contentsOf: url)
            }
            XCTFail("missing fixture \(name).json")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    func testMinimalFixtureRoundTrips() throws {
        let raw = try loadFixture("minimal")
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: raw)
        XCTAssertEqual(doc.id, "minimal")
        XCTAssertEqual(doc.formatVersion, ChapterScriptFormat.currentFormatVersion)
        XCTAssertGreaterThanOrEqual(doc.segments.count, 1)

        let reencoded = try ChapterScriptFormat.makeEncoder().encode(doc)
        let redecoded = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: reencoded)
        XCTAssertEqual(doc, redecoded)
    }

    func testRepresentativeFixtureRoundTrips() throws {
        let raw = try loadFixture("representative")
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: raw)
        XCTAssertEqual(doc.id, "voyage-prologue")
        XCTAssertGreaterThanOrEqual(doc.segments.count, 2)

        // Sanity: every step action should round-trip.
        for segment in doc.segments {
            for step in segment.steps {
                for action in step.actions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(action)
                    let back = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged: \(action)")
                }
            }
        }
    }

    /// SharedVisions's eight-segment documentary, used as an end-to-end fidelity
    /// fixture. If the format evolves in a way that breaks this decode, downstream
    /// players ship broken too — fail loudly here.
    func testDocumentaryFixtureDecodesAndRoundTrips() throws {
        let raw = try loadFixture("documentary")
        let doc = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: raw)
        XCTAssertEqual(doc.id, "shared-visions-documentary")
        XCTAssertEqual(doc.segments.count, 8, "documentary should have 8 segments")

        // Verify segment ids are stable so the SharedVisions timeline UI keeps lining up.
        let expectedIds = [
            "segment_01_primitives",
            "segment_02_color_drift",
            "segment_03_geometric_dance",
            "segment_04_particle_symphony",
            "segment_05_scale_study",
            "segment_06_orbital_ballet",
            "segment_07_video_gallery",
            "segment_08_finale"
        ]
        XCTAssertEqual(doc.segments.map(\.id), expectedIds)

        // Round-trip every action across every step in every segment.
        for segment in doc.segments {
            for step in segment.steps {
                for action in step.actions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(action)
                    let back = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged in \(segment.id)/\(step.id): \(action)")
                }
                for scheduled in step.scheduledActions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(scheduled)
                    let back = try ChapterScriptFormat.makeDecoder().decode(ScheduledActionDTO.self, from: data)
                    XCTAssertEqual(scheduled, back, "scheduled action diverged in \(segment.id)/\(step.id)")
                }
            }
        }

        // Auto-advance chain should connect 1→2→…→7→8, with finale holding.
        for (i, segment) in doc.segments.enumerated() where i < doc.segments.count - 1 {
            guard case .autoAdvance(let nextId) = segment.onComplete else {
                XCTFail("\(segment.id) should auto-advance to the next segment"); continue
            }
            XCTAssertEqual(nextId, expectedIds[i + 1], "\(segment.id) auto-advance points at wrong target")
        }
        if case .holdOnLastStep = doc.segments.last?.onComplete {
            // expected
        } else {
            XCTFail("finale should holdOnLastStep")
        }
    }
}
