import XCTest
@testable import ChapterScript

/// The exact encode → write → read → decode round trip `performSave` does.
/// Saving is the one operation whose failure loses work, so the path gets a
/// test rather than an assumption.
final class SavePathCheckTests: XCTestCase {

    func testDocumentRoundTripsThroughDiskLikeASave() throws {
        var doc = ChapterDocument(id: "c", displayName: "Chapter")
        doc.segments = [SegmentDefinitionDTO(
            id: "s", name: "Intro", phase: "immersive",
            steps: [StepDefinitionDTO(id: "step_1", name: "Step 1", duration: 5,
                                      actions: [], scheduledActions: [], gate: nil)],
            visibility: VisibilityStateDTO(), onComplete: .holdOnLastStep
        )]
        var meta = EditorMetadata()
        meta.bins = [MediaBin(name: "Immersive", assets: ["a.mov"])]
        doc.editorMetadata = meta

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("savecheck-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try ChapterScriptFormat.makeEncoder().encode(doc)
        try data.write(to: url)

        let decoded = try JSONDecoder().decode(
            ChapterDocument.self, from: Data(contentsOf: url)
        )
        XCTAssertEqual(decoded.segments.count, 1)
        XCTAssertEqual(decoded.segments[0].name, "Intro")
        XCTAssertEqual(decoded.editorMetadata?.bins.first?.assets, ["a.mov"])
    }

    /// A chapter with no Bins must still encode — `editorMetadata` is omitted
    /// entirely in that case, and an omitted key must not break the encoder.
    func testDocumentWithoutEditorMetadataEncodes() throws {
        let doc = ChapterDocument(id: "c", displayName: "Chapter")
        let data = try ChapterScriptFormat.makeEncoder().encode(doc)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("editorMetadata"))
        XCTAssertNoThrow(try JSONDecoder().decode(ChapterDocument.self, from: data))
    }
}
