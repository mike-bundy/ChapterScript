import XCTest
@testable import ChapterScript

/// Verifies that bundled JSON fixtures (committed under Tests/Fixtures/) decode cleanly
/// and re-encode to the same logical document. Acts as a regression gate against
/// accidental schema changes — when intentional, regenerate fixtures.
///
/// THE FIXTURES ARE DELIBERATELY FROZEN AT FORMAT v2. They were written before the
/// Segment → Sequence rename and they are not regenerated, because their value is
/// precisely that they are old: every load here exercises the real v2 → v3 migration
/// path that a customer's existing `.chapterscript` bundle takes. Regenerating them
/// as v3 would turn this suite into a test of the encoder against itself.
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

    /// Load a fixture the way the app does: migrate the raw JSON forward, then decode.
    /// `ProjectManager` and `VisionHandoffController` both call `Migrator.migrate`
    /// before decoding, so anything that skips it is testing a path no user takes.
    private func decodeFixture(_ name: String) throws -> ChapterDocument {
        let migrated = try Migrator.migrate(try loadFixture(name))
        return try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: migrated)
    }

    func testMinimalFixtureRoundTrips() throws {
        let doc = try decodeFixture("minimal")
        XCTAssertEqual(doc.id, "minimal")
        XCTAssertEqual(doc.formatVersion, ChapterScriptFormat.currentFormatVersion)
        XCTAssertGreaterThanOrEqual(doc.sequences.count, 1)

        let reencoded = try ChapterScriptFormat.makeEncoder().encode(doc)
        let redecoded = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: reencoded)
        XCTAssertEqual(doc, redecoded)
    }

    func testRepresentativeFixtureRoundTrips() throws {
        let doc = try decodeFixture("representative")
        XCTAssertEqual(doc.id, "voyage-prologue")
        XCTAssertGreaterThanOrEqual(doc.sequences.count, 2)

        // Sanity: every step action should round-trip.
        for sequence in doc.sequences {
            for step in sequence.steps {
                for action in step.actions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(action)
                    let back = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged: \(action)")
                }
            }
        }
    }

    /// SharedVisions's eight-sequence documentary, used as an end-to-end fidelity
    /// fixture. If the format evolves in a way that breaks this decode, downstream
    /// players ship broken too — fail loudly here.
    func testDocumentaryFixtureDecodesAndRoundTrips() throws {
        let doc = try decodeFixture("documentary")
        XCTAssertEqual(doc.id, "shared-visions-documentary")
        XCTAssertEqual(doc.sequences.count, 8, "documentary should have 8 sequences")

        // Verify sequence ids are stable so the SharedVisions timeline UI keeps lining up.
        //
        // THESE STAY `segment_*` ON PURPOSE — do not "fix" them to `sequence_*`.
        // An id is an opaque authored string, not vocabulary, and the v2 → v3
        // migration renames KEYS, never VALUES. A document authored before the
        // rename keeps the ids it was saved with, forever: rewriting them would
        // break every `autoAdvance` target, every `EntityAnimationTrack.entity`
        // reference and every gate that names a sequence, in exactly the silent
        // way this migration exists to avoid. That this fixture still reads
        // `segment_01_primitives` after migrating is the assertion.
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
        XCTAssertEqual(doc.sequences.map(\.id), expectedIds)

        // Round-trip every action across every step in every sequence.
        for sequence in doc.sequences {
            for step in sequence.steps {
                for action in step.actions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(action)
                    let back = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged in \(sequence.id)/\(step.id): \(action)")
                }
                for scheduled in step.scheduledActions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(scheduled)
                    let back = try ChapterScriptFormat.makeDecoder().decode(ScheduledActionDTO.self, from: data)
                    XCTAssertEqual(scheduled, back, "scheduled action diverged in \(sequence.id)/\(step.id)")
                }
            }
        }

        // Auto-advance chain should connect 1→2→…→7→8, with finale holding.
        for (i, sequence) in doc.sequences.enumerated() where i < doc.sequences.count - 1 {
            guard case .autoAdvance(let nextId) = sequence.onComplete else {
                XCTFail("\(sequence.id) should auto-advance to the next sequence"); continue
            }
            XCTAssertEqual(nextId, expectedIds[i + 1], "\(sequence.id) auto-advance points at wrong target")
        }
        if case .holdOnLastStep = doc.sequences.last?.onComplete {
            // expected
        } else {
            XCTFail("finale should holdOnLastStep")
        }
    }
}
