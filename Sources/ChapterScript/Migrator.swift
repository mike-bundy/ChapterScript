import Foundation

/// JSON-to-JSON schema migrator. Migrators run **before** typed decoding so that older
/// documents can be brought up to the current format without losing fields the typed model
/// would otherwise reject.
///
/// To add a new migration: bump `ChapterScriptFormat.currentFormatVersion`, then add a step
/// keyed at the previous version inside `Migrator.steps`.
public enum Migrator {
    public enum MigrationError: Error {
        /// The source version is newer than this build of ChapterScript can handle.
        case sourceVersionTooNew(Int, supported: Int)
        /// The migrator chain is missing a required step.
        case noMigrationFrom(Int)
        /// The document JSON did not declare a `formatVersion`.
        case missingFormatVersion
    }

    /// Read just the `formatVersion` from raw JSON without doing a full typed decode.
    public static func readFormatVersion(from data: Data) throws -> Int {
        struct Probe: Decodable { let formatVersion: Int }
        do {
            return try JSONDecoder().decode(Probe.self, from: data).formatVersion
        } catch {
            throw MigrationError.missingFormatVersion
        }
    }

    /// Migrate the supplied JSON `Data` forward to `targetVersion`. Returns updated `Data`.
    public static func migrate(
        _ data: Data,
        to targetVersion: Int = ChapterScriptFormat.currentFormatVersion
    ) throws -> Data {
        let sourceVersion = try readFormatVersion(from: data)
        guard sourceVersion <= targetVersion else {
            throw MigrationError.sourceVersionTooNew(sourceVersion, supported: targetVersion)
        }
        guard sourceVersion < targetVersion else { return data }

        var current = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var version = sourceVersion
        while version < targetVersion {
            guard let step = steps[version] else {
                throw MigrationError.noMigrationFrom(version)
            }
            current = try step(current)
            version += 1
            current["formatVersion"] = version
        }
        return try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys, .prettyPrinted])
    }

    /// Migration steps keyed by the source version. A step at key `N` migrates `N → N+1`.
    private static let steps: [Int: @Sendable ([String: Any]) throws -> [String: Any]] = [
        2: migrateV2ToV3
    ]

    // MARK: - v2 → v3   (Segment → Sequence)

    /// v2 called the timed unit inside a chapter a "segment". v3 calls it a
    /// **sequence**. Nothing else changed: this is a pure vocabulary migration.
    ///
    /// SEMANTIC IDENTITY IS THE WHOLE CONTRACT. A v2 document and its migrated
    /// v3 form must describe the same experience frame for frame, so this step
    /// is written as a rename of four *named things* and an explicit refusal to
    /// touch anything else:
    ///
    ///   1. `segments`         → `sequences`          (document)
    ///   2. `defaultSegmentId` → `defaultSequenceId`  (document)
    ///   3. `nextSegmentId`    → `nextSequenceId`     (CompletionActionDTO.autoAdvance)
    ///   4. `"scope": "segment"` → `"scope": "sequence"`  (AudioActionDTO.scope raw value)
    ///
    /// (4) is the one that is easy to miss: `AudioScope` is a `String` raw-value
    /// enum, so the old vocabulary is baked into the *data*, not just the key.
    /// An audio action that stayed `"segment"` would fail to decode — or, worse,
    /// under a lenient decoder silently fall back to a different scope and change
    /// when the sound stops.
    ///
    /// Everything else — ids, names, phase, presentation, steps and their
    /// durations, actions, scheduledActions, gates, animationTracks and their
    /// **absolute key times**, audioTracks, backdropTrack cues, sourceIn /
    /// sourceOut, editorColorIndex, editorMetadata — is copied through byte for
    /// byte. Timing is never recomputed and identifiers are never regenerated:
    /// a curve that peaked at 12.5 s still peaks at 12.5 s.
    ///
    /// The walk is RECURSIVE and keyed on names rather than on a hard-coded path
    /// through the document. Enumerating "document → sequences → steps →
    /// actions" by hand is how a nesting level gets missed when the format later
    /// grows one; matching the key wherever it appears cannot. It is safe to be
    /// this broad because all four names are unique to this concept in the
    /// format — there is no unrelated `segments` array and `scope` appears only
    /// on `AudioActionDTO`.
    @Sendable
    private static func migrateV2ToV3(_ document: [String: Any]) throws -> [String: Any] {
        guard let migrated = renameSequenceVocabulary(in: document) as? [String: Any] else {
            return document
        }
        return migrated
    }

    /// Keys whose *name* carried the old vocabulary.
    private static let v3KeyRenames: [String: String] = [
        "segments": "sequences",
        "defaultSegmentId": "defaultSequenceId",
        "nextSegmentId": "nextSequenceId"
    ]

    private static func renameSequenceVocabulary(in node: Any) -> Any {
        if let object = node as? [String: Any] {
            var result: [String: Any] = [:]
            result.reserveCapacity(object.count)
            for (key, value) in object {
                let newKey = v3KeyRenames[key] ?? key

                // The one raw VALUE that carried the old vocabulary.
                if key == "scope", let raw = value as? String, raw == "segment" {
                    result[newKey] = "sequence"
                    continue
                }

                result[newKey] = renameSequenceVocabulary(in: value)
            }
            return result
        }

        if let array = node as? [Any] {
            return array.map(renameSequenceVocabulary(in:))
        }

        // Scalars pass through untouched — this is what makes the step an identity
        // everywhere the four names above do not appear.
        return node
    }
}
