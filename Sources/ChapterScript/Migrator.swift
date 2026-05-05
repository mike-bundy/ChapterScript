import Foundation

/// JSON-to-JSON schema migrator. Migrators run **before** typed decoding so that older
/// documents can be brought up to the current format without losing fields the typed model
/// would otherwise reject.
///
/// To add a new migration: bump `ChapterScript.currentFormatVersion`, then add a step
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
        to targetVersion: Int = ChapterScript.currentFormatVersion
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
    /// Currently empty since v1 is the inaugural version.
    private static let steps: [Int: @Sendable ([String: Any]) throws -> [String: Any]] = [:]
}
