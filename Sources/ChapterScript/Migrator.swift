import Foundation

/// JSON-to-JSON schema migrator. Migrators run **before** typed decoding so that older
/// documents can be brought up to the current format without losing fields the typed model
/// would otherwise reject.
///
/// To add a new migration: bump `ChapterScriptFormat.currentFormatVersion`, then add a migration
/// keyed at the previous version inside `Migrator.migrations`.
public enum Migrator {
    public enum MigrationError: Error {
        /// The source version is newer than this build of ChapterScript can handle.
        case sourceVersionTooNew(Int, supported: Int)
        /// The migrator chain is missing a required migration.
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
            guard let migration = migrations[version] else {
                throw MigrationError.noMigrationFrom(version)
            }
            current = try migration(current)
            version += 1
            current["formatVersion"] = version
        }
        return try JSONSerialization.data(withJSONObject: current, options: [.sortedKeys, .prettyPrinted])
    }

    /// Migrations keyed by the source version. The one at key `N` migrates `N → N+1`.
    private static let migrations: [Int: @Sendable ([String: Any]) throws -> [String: Any]] = [
        2: migrateV2ToV3,
        3: migrateV3ToV4
    ]

    // MARK: - v3 → v4   (two action buckets → one authored list with stable ids)

    /// v3 stored a segment's actions in two arrays: `actions` (fired at the segment's
    /// start) and `scheduledActions` (`{at, action}`). v4 stores ONE
    /// `authoredActions` list, each entry carrying `{id, at, action}`.
    ///
    /// ORDERING IS THE ENTIRE CONTRACT, and it is easy to get wrong. At runtime
    /// v3 awaited every `actions` entry in array order BEFORE the timing loop
    /// started, and only then fired scheduled actions as their `at` elapsed. So
    /// at t = 0 the segment-start actions ran first, in order, followed by any
    /// scheduled at +0. Emitting them in exactly that order — immediate first,
    /// then scheduled — and sorting stably by `at` reproduces the same
    /// execution sequence, action for action.
    ///
    /// Ids are DETERMINISTIC, derived from the legacy location. Two machines
    /// migrating the same document independently must agree, or a tethered peer
    /// and the Mac would hold different ids for the same authored action and
    /// every op between them would miss. The legacy location is a safe source
    /// for this precisely because the v3 document has finished being edited.
    /// After migration the string is ordinary authored identity and nothing
    /// re-derives it from position again.
    ///
    /// Idempotent: a segment that already has `authoredActions` is left alone.
    ///
    /// Everything else is copied through untouched — segment ids, durations, gates,
    /// animation tracks and their absolute key times, audio automation, backdrop
    /// cues, source ranges, placeholders, entity ids, editorMetadata.
    @Sendable
    private static func migrateV3ToV4(_ document: [String: Any]) throws -> [String: Any] {
        var out = document
        guard let sequences = document["sequences"] as? [[String: Any]] else { return out }

        out["sequences"] = sequences.map { sequence -> [String: Any] in
            var sequence = sequence
            guard let segments = sequence["steps"] as? [[String: Any]] else { return sequence }
            sequence["steps"] = segments.map(unifySegmentActions)
            return sequence
        }
        return out
    }

    private static func unifySegmentActions(_ segment: [String: Any]) -> [String: Any] {
        var segment = segment
        // Already migrated — leave it exactly as it is.
        guard segment["authoredActions"] == nil else {
            segment.removeValue(forKey: "actions")
            segment.removeValue(forKey: "scheduledActions")
            return segment
        }

        let segmentId = segment["id"] as? String ?? "step"
        var authored: [[String: Any]] = []

        for (index, action) in (segment["actions"] as? [[String: Any]] ?? []).enumerated() {
            authored.append([
                "id": migratedActionID(segmentId: segmentId, isScheduled: false, index: index),
                "at": 0,
                "action": action
            ])
        }
        for (index, entry) in (segment["scheduledActions"] as? [[String: Any]] ?? []).enumerated() {
            guard let action = entry["action"] as? [String: Any] else { continue }
            authored.append([
                "id": migratedActionID(segmentId: segmentId, isScheduled: true, index: index),
                "at": entry["at"] as? Double ?? 0,
                "action": action
            ])
        }

        segment["authoredActions"] = authored
        segment.removeValue(forKey: "actions")
        segment.removeValue(forKey: "scheduledActions")
        return segment
    }

    /// Must produce the same string as `AuthoredAction.migratedID`. The typed
    /// decoder's tolerant path and this JSON migration both run in the wild — a
    /// document migrated on disk and the same document arriving over live sync
    /// have to end up with identical ids.
    private static func migratedActionID(segmentId: String, isScheduled: Bool, index: Int) -> String {
        "act_\(segmentId)_\(isScheduled ? "s" : "i")\(index)"
    }

    // MARK: - v2 → v3   (Segment → Sequence)

    /// v2 called the timed unit inside a chapter a "segment". v3 calls it a
    /// **sequence**. Nothing else changed: this is a pure vocabulary migration.
    ///
    /// SEMANTIC IDENTITY IS THE WHOLE CONTRACT. A v2 document and its migrated
    /// v3 form must describe the same experience frame for frame, so this migration
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
    /// Everything else — ids, names, phase, presentation, the "steps" array and its
    /// durations, actions, scheduledActions, gates, animationTracks and their
    /// **absolute key times**, audioTracks, backdropTrack cues, sourceIn /
    /// sourceOut, editorColorIndex, editorMetadata — is copied through byte for
    /// byte. Timing is never recomputed and identifiers are never regenerated:
    /// a curve that peaked at 12.5 s still peaks at 12.5 s.
    ///
    /// The walk is RECURSIVE and keyed on names rather than on a hard-coded path
    /// through the document. Enumerating document → sequences → "steps" →
    /// actions by hand is how a nesting level gets missed when the format later
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

        // Scalars pass through untouched — this is what makes the migration an identity
        // everywhere the four names above do not appear.
        return node
    }
}
