import Foundation

// LEGACY-FORMAT FILE — the only source file allowed to spell the retired
// name of a Segment (`tools/segment_vocabulary_audit.py` exempts this file
// and nothing else in the format).
//
// Chapters saved before format 5 named a Segment with the retired word: the
// list key, one completion kind, two interpolation values, and the ids and
// automatic names the editor generated. `Migrator.migrateV4ToV5` rewrites all
// of them when an older Chapter opens; the typed decoders consult the helpers
// below only so a pre-5 literal that skipped the Migrator still reads rather
// than silently falling back to a default.

/// How Chapters saved before format 5 spelled what is now called a Segment.
public enum LegacyFormat {

    /// The pre-5 key of a Sequence's Segment list.
    public static let segmentListKey = "steps"

    /// The pre-5 key of a custom template's entry list.
    public static let templateEntryListKey = "steps"

    /// Pre-5 completion kind → current.
    public static let completionKinds: [String: String] = [
        "holdOnLastStep": "holdOnLastSegment"
    ]

    /// Pre-5 interpolation values → current. Keyframe interpolation and
    /// Sequence-animation interpolation each had one.
    public static let interpolations: [String: String] = [
        "step": "hold",
        "stepped": "held"
    ]

    public static func currentCompletionKind(_ raw: String) -> String {
        completionKinds[raw] ?? raw
    }

    public static func currentInterpolation(_ raw: String) -> String {
        interpolations[raw] ?? raw
    }

    /// Reads the pre-5 Segment list from a Sequence's container.
    static func decodeSegmentList<T: Decodable>(_ type: T.Type, from decoder: Decoder) throws -> T? {
        let c = try decoder.container(keyedBy: AnyKey.self)
        return try c.decodeIfPresent(type, forKey: AnyKey(segmentListKey))
    }

    /// Reads the pre-5 entry list of a custom template.
    public static func decodeTemplateEntries<T: Decodable>(_ type: T.Type, from decoder: Decoder) throws -> T? {
        let c = try decoder.container(keyedBy: AnyKey.self)
        return try c.decodeIfPresent(type, forKey: AnyKey(templateEntryListKey))
    }

    /// An editor-generated Segment or action id with the retired word as a
    /// whole token (`step_3`, `act_step_3_s0`, `room_1_step_2`, `step1`,
    /// `step_after_sr_…`) → the same id with `seg`. Nil when the id does not
    /// carry the word, so a chosen id such as `footstep` is never touched.
    public static func currentIdentifier(_ id: String) -> String? {
        let range = NSRange(id.startIndex..., in: id)
        guard identifierToken.firstMatch(in: id, range: range) != nil else { return nil }
        return identifierToken.stringByReplacingMatches(in: id, range: range, withTemplate: "$1eg")
    }

    /// An automatic Segment name the editor generated before format 5
    /// ("Step 3", "step3", "Step") — not a title anybody chose.
    public static func isAutomaticSegmentName(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.hasPrefix("step") else { return false }
        let rest = lower.dropFirst(4).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || Int(rest) != nil
    }

    /// "Step 3" → "Segment 3"; any other name unchanged.
    public static func currentSegmentName(_ name: String) -> String {
        guard isAutomaticSegmentName(name) else { return name }
        let rest = name.trimmingCharacters(in: .whitespaces).dropFirst(4)
            .trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? "Segment" : "Segment \(rest)"
    }

    /// `step`/`Step` as a whole token: not preceded by a letter, not followed
    /// by a lowercase letter. The capture keeps the case of the `s`.
    private static let identifierToken = try! NSRegularExpression(
        pattern: "(?<![A-Za-z])([sS])tep(?![a-z])")

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
