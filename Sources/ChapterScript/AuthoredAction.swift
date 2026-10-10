import Foundation

/// ONE AUTHORED THING THAT HAPPENS, WITH A STABLE IDENTITY.
///
/// Before format v4 a segment held two arrays — `actions` (fire at the segment's
/// start) and `scheduledActions` (`{at, action}`) — and an action was addressed
/// by `(segmentId, index, isScheduled)`. Position was identity, which meant:
///
///   * inserting an action invalidated every later address, including ones in
///     flight over the live-sync wire;
///   * nothing could be attached to a clip — color, lock, transitions, group
///     membership, notes — because the thing it pointed at moved;
///   * the two buckets were a second identity domain for what is, to an author,
///     the same kind of thing.
///
/// `BackdropCue` already carried a stable id for exactly this reason, and said
/// so in its own doc comment: "positional indices are not usable for this —
/// retiming a cue past its neighbour reorders the list underneath the
/// selection." That reasoning always applied to actions too.
///
/// ORDERING. `at` is the time; the ARRAY's order is the authored tie-break for
/// actions sharing a time. Execution is therefore a STABLE sort by `at` — and
/// Swift's `sorted(by:)` is not guaranteed stable, so every consumer sorts by
/// `(at, index)` explicitly. `SequenceTime.executionOrder(of:)` is the one
/// implementation; do not hand-roll another.
///
/// A segment-start action is simply `at == 0`. There is no second bucket, and no
/// `isScheduled` flag, because the distinction never meant anything to an
/// author and cost a great deal in code.
public struct AuthoredAction: Codable, Sendable, Equatable, Identifiable {
    /// Stable, opaque, minted once and then never changed by any edit that is
    /// not explicitly a duplication. Storage position is NOT identity: sorting,
    /// rebucketing across segments, insertion, deletion and segment normalization all
    /// leave this untouched.
    public var id: String
    /// Seconds from the owning segment's start. Must be within `0...segment.duration`
    /// — an action stored past its segment's end never fires, because the runtime's
    /// timing loop exits while it is still pending.
    public var at: Double
    public var action: SegmentActionDTO
    /// Optional membership in a stored logical Timeline lane. This is
    /// editorial identity only: `action` still names the real playback Object.
    /// Opening and closing actions of one occurrence carry the same value.
    public var logicalTrackId: String?

    public init(id: String = AuthoredAction.newID(), at: Double = 0,
                action: SegmentActionDTO, logicalTrackId: String? = nil) {
        self.id = id
        self.at = at
        self.action = action
        self.logicalTrackId = logicalTrackId
    }

    /// A fresh identity for a newly authored action.
    ///
    /// Deliberately not derived from the action's content, its time or its
    /// position: two identical fades at the same instant on the same object are
    /// two authored things, and duplicating a clip must produce a genuinely new
    /// occurrence rather than an alias of the original.
    public static func newID() -> String {
        "act_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
    }

    /// The deterministic id a v3 action migrates to.
    ///
    /// Deterministic so that two machines migrating the same document
    /// independently agree — a live-sync peer and the Mac must not end up with
    /// different ids for the same authored action, or every subsequent op would
    /// miss. Derived from the legacy LOCATION, which is stable in the source
    /// document precisely because that document is finished being edited.
    ///
    /// After migration this string is ordinary authored identity: it is
    /// persisted, and nothing re-derives it from position again.
    public static func migratedID(segmentId: String, isScheduled: Bool, index: Int) -> String {
        "act_\(segmentId)_\(isScheduled ? "s" : "i")\(index)"
    }
}


// MARK: - Fire order

/// THE ORDER ACTIONS FIRE IN, shared by the editor's Timeline, its playback,
/// export (through the evaluator) and the runtime.
///
/// 1. TIME, to the microsecond. Two instants closer than that are the same
///    instant: a cut computed two ways (a clip's start plus its length, and
///    the next clip's landing converted from Sequence time) differs in the
///    last bits — 52.208333333333336 against 52.20833333333333 — and a
///    strict `<` then fired the second clip's START before the first clip's
///    STOP, so that stop silenced the clip that had just started (driven,
///    2026-10-10: a movie appended on a busy screen was saved and never
///    drawn or played). Compared as integer microseconds, so the ordering is
///    well defined for a sort.
/// 2. At one instant, what ENDS an occurrence goes before what starts one:
///    a cut ends the old clip, then begins the new one, whichever was
///    authored first.
/// 3. Then the authored order, as before.
public enum FireOrder {
    public static func instant(_ seconds: Double) -> Int64 {
        Int64((seconds * 1_000_000).rounded())
    }

    public static func precedes(at a: Double, closes aCloses: Bool, offset aOffset: Int,
                                before b: Double, closes bCloses: Bool, offset bOffset: Int) -> Bool {
        let ia = instant(a), ib = instant(b)
        if ia != ib { return ia < ib }
        if aCloses != bCloses { return aCloses }
        return aOffset < bOffset
    }
}

extension SegmentActionDTO {
    /// Ends an occurrence on its channel or entity (see `FireOrder`).
    public var endsAnOccurrence: Bool {
        switch self {
        case .stopVideo, .stopAudio, .hideEntity: return true
        default: return false
        }
    }
}
