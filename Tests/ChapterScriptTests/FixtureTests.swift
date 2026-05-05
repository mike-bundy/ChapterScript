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
        let doc = try ChapterScript.makeDecoder().decode(ExperienceDocument.self, from: raw)
        XCTAssertEqual(doc.id, "minimal")
        XCTAssertEqual(doc.formatVersion, ChapterScript.currentFormatVersion)
        XCTAssertGreaterThanOrEqual(doc.chapters.count, 1)

        let reencoded = try ChapterScript.makeEncoder().encode(doc)
        let redecoded = try ChapterScript.makeDecoder().decode(ExperienceDocument.self, from: reencoded)
        XCTAssertEqual(doc, redecoded)
    }

    func testRepresentativeFixtureRoundTrips() throws {
        let raw = try loadFixture("representative")
        let doc = try ChapterScript.makeDecoder().decode(ExperienceDocument.self, from: raw)
        XCTAssertEqual(doc.id, "voyage-prologue")
        XCTAssertGreaterThanOrEqual(doc.chapters.count, 2)

        // Sanity: every step action should round-trip.
        for chapter in doc.chapters {
            for step in chapter.steps {
                for action in step.actions {
                    let data = try ChapterScript.makeEncoder().encode(action)
                    let back = try ChapterScript.makeDecoder().decode(StepActionDTO.self, from: data)
                    XCTAssertEqual(action, back, "action diverged: \(action)")
                }
            }
        }
    }
}
