import Foundation

/// ONE AUTHORED THING THAT HAPPENS, WITH A STABLE IDENTITY.
///
/// Before format v4 a step held two arrays — `actions` (fire at the step's
/// start) and `scheduledActions` (`{at, action}`) — and an action was addressed
/// by `(stepId, index, isScheduled)`. Position was identity, which meant:
///
///   * inserting an action invalidated every later address, including ones in
///     flight over the live-sync wire;
///   * nothing could be attached to a clip — colour, lock, transitions, group
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
/// A step-start action is simply `at == 0`. There is no second bucket, and no
/// `isScheduled` flag, because the distinction never meant anything to an
/// author and cost a great deal in code.
public struct AuthoredAction: Codable, Sendable, Equatable, Identifiable {
    /// Stable, opaque, minted once and then never changed by any edit that is
    /// not explicitly a duplication. Storage position is NOT identity: sorting,
    /// rebucketing across steps, insertion, deletion and step normalization all
    /// leave this untouched.
    public var id: String
    /// Seconds from the owning step's start. Must be within `0...step.duration`
    /// — an action stored past its step's end never fires, because the runtime's
    /// timing loop exits while it is still pending.
    public var at: Double
    public var action: StepActionDTO

    public init(id: String = AuthoredAction.newID(), at: Double = 0, action: StepActionDTO) {
        self.id = id
        self.at = at
        self.action = action
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
    public static func migratedID(stepId: String, isScheduled: Bool, index: Int) -> String {
        "act_\(stepId)_\(isScheduled ? "s" : "i")\(index)"
    }
}
