import XCTest
@testable import ChapterScript

/// Format coverage for externally stored sources: `AssetEntry.external`.
///
/// The contract under test:
/// - A Source's identity is the manifest entry's `id`; `external` only says
///   where the bytes currently live. Absent means bundled, exactly as before
///   the field existed.
/// - Additive and tolerant: documents written before the field decode
///   unchanged, and a document that never used it re-encodes with no new key.
/// - `AssetKind` degrades unknown raw values to `.other` instead of failing
///   the whole document load.
final class ExternalMediaTests: XCTestCase {

    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try ChapterScriptFormat.makeEncoder().encode(value)
        let decoded = try ChapterScriptFormat.makeDecoder().decode(T.self, from: data)
        XCTAssertEqual(value, decoded, "round-trip diverged", file: file, line: line)
    }

    // MARK: - Round trips

    func testExternalMediaLocationRoundTrip() throws {
        try roundTrip(ExternalMediaLocation(lastKnownPath: "/Volumes/SSD/Footage/shot01.mov"))
        try roundTrip(ExternalMediaLocation(
            lastKnownPath: "/Volumes/SSD/Footage/shot01.mov",
            previousPaths: ["/Users/p/Movies/shot01.mov"],
            bookmark: Data([0x62, 0x6F, 0x6F, 0x6B]),
            volumeName: "SSD",
            contentModifiedMs: 1_724_800_000_000
        ))
    }

    func testAssetEntryWithExternalRoundTrips() throws {
        try roundTrip(AssetEntry(
            id: "shot01.mov",
            relativePath: "shot01.mov",
            kind: .video,
            sha256: "abc123",
            byteSize: 1_024,
            durationMs: 4_000,
            external: ExternalMediaLocation(lastKnownPath: "/Volumes/SSD/Footage/shot01.mov")
        ))
    }

    // MARK: - Byte stability for documents that never used the field

    func testBundledEntryEncodesNoExternalKey() throws {
        let entry = AssetEntry(id: "a.mov", relativePath: "a.mov", kind: .video, sha256: "s", byteSize: 1)
        let json = String(data: try ChapterScriptFormat.makeEncoder().encode(entry), encoding: .utf8)!
        XCTAssertFalse(json.contains("external"), "a bundled entry must re-save without the key: \(json)")
        XCTAssertFalse(entry.isExternal)
    }

    func testPreExternalEntryJSONDecodesAsBundled() throws {
        let legacy = """
        {"byteSize": 42, "id": "a.mov", "kind": "video", "relativePath": "a.mov", "sha256": "s"}
        """
        let entry = try ChapterScriptFormat.makeDecoder().decode(AssetEntry.self, from: Data(legacy.utf8))
        XCTAssertNil(entry.external)
        XCTAssertFalse(entry.isExternal)
        // Re-encode must not invent the key.
        let json = String(data: try ChapterScriptFormat.makeEncoder().encode(entry), encoding: .utf8)!
        XCTAssertFalse(json.contains("external"))
    }

    func testDocumentWithExternalEntrySurvivesFullDocumentRoundTrip() throws {
        var document = ChapterDocument(
            id: "chapter",
            displayName: "Chapter"
        )
        document.manifest = AssetManifest(entries: [
            AssetEntry(id: "in-bundle.mov", relativePath: "in-bundle.mov", kind: .video),
            AssetEntry(
                id: "outside.mov",
                relativePath: "outside.mov",
                kind: .video,
                sha256: "deadbeef",
                byteSize: 9,
                external: ExternalMediaLocation(
                    lastKnownPath: "/Volumes/Media/outside.mov",
                    volumeName: "Media"
                )
            ),
        ])
        let data = try ChapterScriptFormat.makeEncoder().encode(document)
        let decoded = try ChapterScriptFormat.makeDecoder().decode(ChapterDocument.self, from: data)
        XCTAssertEqual(decoded.manifest.entry(id: "outside.mov")?.external?.lastKnownPath,
                       "/Volumes/Media/outside.mov")
        XCTAssertNil(decoded.manifest.entry(id: "in-bundle.mov")?.external)
    }

    // MARK: - Forward tolerance

    func testExternalLocationToleratesUnknownFutureFields() throws {
        let future = """
        {"lastKnownPath": "/a/b.mov", "futureField": {"nested": true}, "volumeName": "X"}
        """
        let loc = try ChapterScriptFormat.makeDecoder().decode(ExternalMediaLocation.self, from: Data(future.utf8))
        XCTAssertEqual(loc.lastKnownPath, "/a/b.mov")
        XCTAssertEqual(loc.volumeName, "X")
    }

    func testUnknownAssetKindDegradesToOtherInsteadOfThrowing() throws {
        let entry = """
        {"id": "x.newthing", "kind": "hologram", "relativePath": "x.newthing"}
        """
        let decoded = try ChapterScriptFormat.makeDecoder().decode(AssetEntry.self, from: Data(entry.utf8))
        XCTAssertEqual(decoded.kind, .other)
    }

    func testKnownAssetKindsStillDecodeExactly() throws {
        for kind in [AssetKind.audio, .video, .usdz, .image, .other] {
            let data = try ChapterScriptFormat.makeEncoder().encode([kind])
            let decoded = try ChapterScriptFormat.makeDecoder().decode([AssetKind].self, from: data)
            XCTAssertEqual(decoded, [kind])
        }
    }
}
