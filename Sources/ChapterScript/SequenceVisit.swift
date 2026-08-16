//
//  SequenceVisit.swift
//  ChapterScript
//
//  ONE RUNTIME EXECUTION OF A SEQUENCE.
//
//  A visit is the boundary every piece of transient playback state hangs from:
//  the interaction ledger, Story Region runtime, gate state, elapsed time.
//  Phase 6 established the SEMANTICS ("`.once` means at most one activation per
//  visit") and the runtime honoured them by rebuilding state on each play — but
//  nothing ever NAMED a visit, so nothing could tell two of them apart.
//
//  That is fine until Phase 8, where Return and Resume have to distinguish
//  "the museum, again" from "the museum, still" — and where a stale reference
//  to a finished visit must be recognisable as stale rather than silently
//  treated as the current one.
//
//  DELIBERATELY NOT `Codable`, and asserted so by test. A visit describes a
//  moment of playback, not authored content. It is never serialized, never
//  synced, never undoable and never enters a document. Runtime state that
//  reaches the document is the bug this type exists to make obvious.
//

import Foundation

/// Opaque identity for one execution of one Sequence.
///
/// Not derived from the Sequence id, the time, or a counter that could restart
/// — two visits of the same Sequence must never compare equal, including across
/// a stop and an immediate replay.
public struct SequenceVisitID: Hashable, Sendable, CustomStringConvertible {
    private let raw: UUID

    public init() { raw = UUID() }

    /// For tests that need a stable value.
    public init(raw: UUID) { self.raw = raw }

    public var description: String { "visit:\(raw.uuidString.prefix(8))" }
}

/// One runtime execution instance of a Sequence.
public struct SequenceVisit: Sendable, Equatable {
    public let id: SequenceVisitID
    /// The Sequence this is a visit OF — by stable id, never by name or index.
    public let sequenceId: String

    /// Begin a new visit. Every entry mints a fresh identity; there is no way
    /// to "reuse" one, because reusing one is what Resume will mean and Resume
    /// does not exist yet.
    public init(sequenceId: String) {
        self.id = SequenceVisitID()
        self.sequenceId = sequenceId
    }

    /// Test seam.
    public init(id: SequenceVisitID, sequenceId: String) {
        self.id = id
        self.sequenceId = sequenceId
    }

    public static func == (a: SequenceVisit, b: SequenceVisit) -> Bool {
        a.id == b.id && a.sequenceId == b.sequenceId
    }

    /// Is this a visit of that Sequence? Phase 8 will ask constantly; asking by
    /// id keeps it from asking by name.
    public func isVisit(of sequenceId: String) -> Bool {
        self.sequenceId == sequenceId
    }
}
