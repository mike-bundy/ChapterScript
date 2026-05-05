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
        let doc = try ChapterScriptFormat.makeDecoder().decode(ExperienceDocument.self, from: raw)
        XCTAssertEqual(doc.id, "minimal")
        XCTAssertEqual(doc.formatVersion, ChapterScriptFormat.currentFormatVersion)
        XCTAssertGreaterThanOrEqual(doc.chapters.count, 1)

        let reencoded = try ChapterScriptFormat.makeEncoder().encode(doc)
        let redecoded = try ChapterScriptFormat.makeDecoder().decode(ExperienceDocument.self, from: reencoded)
        XCTAssertEqual(doc, redecoded)
    }

    func testRepresentativeFixtureRoundTrips() throws {
        let raw = try loadFixture("representative")
        let doc = try ChapterScriptFormat.makeDecoder().decode(ExperienceDocument.self, from: raw)
        XCTAssertEqual(doc.id, "voyage-prologue")
        XCTAssertGreaterThanOrEqual(doc.chapters.count, 2)

        // Sanity: every step action should round-trip.
        for chapter in doc.chapters {
            for step in chapter.steps {
                for action in step.actions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(action)
                    let back = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged: \(action)")
                }
            }
        }
    }

    /// SharedVisions's eight-chapter documentary, used as an end-to-end fidelity
    /// fixture. If the format evolves in a way that breaks this decode, downstream
    /// players ship broken too — fail loudly here.
    func testDocumentaryFixtureDecodesAndRoundTrips() throws {
        let raw = try loadFixture("documentary")
        let doc = try ChapterScriptFormat.makeDecoder().decode(ExperienceDocument.self, from: raw)
        XCTAssertEqual(doc.id, "shared-visions-documentary")
        XCTAssertEqual(doc.chapters.count, 8, "documentary should have 8 chapters")

        // Verify chapter ids are stable so the SharedVisions timeline UI keeps lining up.
        let expectedIds = [
            "chapter_01_primitives",
            "chapter_02_color_drift",
            "chapter_03_geometric_dance",
            "chapter_04_particle_symphony",
            "chapter_05_scale_study",
            "chapter_06_orbital_ballet",
            "chapter_07_video_gallery",
            "chapter_08_finale"
        ]
        XCTAssertEqual(doc.chapters.map(\.id), expectedIds)

        // Round-trip every action across every step in every chapter.
        for chapter in doc.chapters {
            for step in chapter.steps {
                for action in step.actions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(action)
                    let back = try ChapterScriptFormat.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged in \(chapter.id)/\(step.id): \(action)")
                }
                for scheduled in step.scheduledActions {
                    let data = try ChapterScriptFormat.makeEncoder().encode(scheduled)
                    let back = try ChapterScriptFormat.makeDecoder().decode(ScheduledActionDTO.self, from: data)
                    XCTAssertEqual(scheduled, back, "scheduled action diverged in \(chapter.id)/\(step.id)")
                }
            }
        }

        // Auto-advance chain should connect 1→2→…→7→8, with finale holding.
        for (i, chapter) in doc.chapters.enumerated() where i < doc.chapters.count - 1 {
            guard case .autoAdvance(let nextId) = chapter.onComplete else {
                XCTFail("\(chapter.id) should auto-advance to the next chapter"); continue
            }
            XCTAssertEqual(nextId, expectedIds[i + 1], "\(chapter.id) auto-advance points at wrong target")
        }
        if case .holdOnLastStep = doc.chapters.last?.onComplete {
            // expected
        } else {
            XCTFail("finale should holdOnLastStep")
        }
    }
}
