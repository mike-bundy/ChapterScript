//
//  StoryRegion.swift
//  ChapterScript
//
//  WHERE THE AUDIENCE GETS TO LOOK AROUND.
//
//  A Sequence is DIRECTED by default: authored Sequence time controls
//  progression, linearly, and nothing has to be drawn to say so. An author adds
//  an EXPLORE REGION only where narrative control changes hands — a span the
//  viewer may spend interacting, during which the story is allowed to stall at
//  the region's boundary until its exit resolves.
//
//  ONLY EXPLORE IS PERSISTED. There is no Directed region, no Directed block to
//  draw over an entire Timeline, and no second Sequence type. Directed time is
//  the ABSENCE of an Explore region, which is why an existing chapter needs no
//  migration and a Sequence with no regions behaves exactly as it always did.
//
//  A REGION IS A CONTROL SPAN, NOT A CONTAINER.
//
//  It does not own the clips underneath it. Moving, resizing or deleting one
//  must never move media, trim a clip, touch `sourceIn`/`sourceOut`, retime an
//  animation key, regroup a track or alter a Scene object. It changes when the
//  story may stall — nothing else.
//
//  TWO CLOCKS, AND ONLY ONE OF THEM IS AUTHORED.
//
//      Authored Sequence time    the Timeline's clock. Drives actions,
//                                Animation 2.0, media scheduling, the playhead.
//                                NEVER runs backward, and never rewinds because
//                                an Explore region is looping.
//      Runtime region elapsed    transient, belongs to one execution of one
//                                region, measured on the runtime's own
//                                pause-aware playback clock. Never serialized,
//                                never an animation key time, never a media
//                                source time.
//
//  See `StoryRegionRuntime` for the state machine and
//  `docs/STORY_REGIONS.md` for the whole contract.
//
//  NARRATIVE CONTROL IS NOT SPATIAL PRESENTATION. Directed/Explore decides who
//  drives progression. Mixed / progressive / full immersion decides how visionOS
//  presents the space. They are orthogonal, and nothing here may change one
//  because of the other.
//

import Foundation

// MARK: - Continuation

/// What one piece of content does while the story is HELD at a region's
/// boundary — the Explore Hold.
///
/// Deliberately small, and deliberately explicit: everything not named by a
/// continuation simply holds. The alternative — inferring "this looks ambient,
/// it should probably loop" — produces a chapter whose behaviour nobody can
/// read off the document.
public enum StoryContinuationBehavior: String, Codable, Sendable, Equatable, CaseIterable {
    /// Freeze where the authored first pass left it. The default for
    /// everything, because it is the only behaviour that is always honest.
    case hold
    /// Repeat the region's authored span, using runtime dwell time. The
    /// authored clock does not move; a sampling overlay does.
    case loop
    /// Keep running on the content's own clock (a video keeps playing past the
    /// boundary). Offered only where the runtime can honestly do it.
    case `continue`
    /// End it at the boundary.
    case stop
}

/// What a continuation applies to, by STABLE AUTHORED IDENTITY.
///
/// Never a filename, never an index, never a Timeline row — those are the four
/// ways this kind of override silently rebinds to the wrong thing after an
/// ordinary edit. An occurrence keeps its `AuthoredAction.id` through trim,
/// slip, blade and retime, so its override survives all of them.
public enum StoryContinuationTarget: Codable, Sendable, Equatable, Hashable {
    /// One media occurrence — the `AuthoredAction.id` of its opening action.
    case occurrence(actionId: String)
    /// One entity's Animation 2.0 track, by authored entity id.
    case entityAnimation(entity: String)
    /// One backdrop cue, by cue id.
    case backdropCue(id: String)

    private enum CodingKeys: String, CodingKey { case kind, id }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .occurrence(let id):
            try c.encode("occurrence", forKey: .kind); try c.encode(id, forKey: .id)
        case .entityAnimation(let entity):
            try c.encode("entityAnimation", forKey: .kind); try c.encode(entity, forKey: .id)
        case .backdropCue(let id):
            try c.encode("backdropCue", forKey: .kind); try c.encode(id, forKey: .id)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        switch try c.decode(String.self, forKey: .kind) {
        case "entityAnimation": self = .entityAnimation(entity: id)
        case "backdropCue":     self = .backdropCue(id: id)
        // Tolerant, as everywhere: a target kind from a newer tool degrades to
        // the most common case rather than failing the document. An occurrence
        // id that matches nothing is simply ignored at runtime.
        default:                self = .occurrence(actionId: id)
        }
    }

    /// The stable id this target names, whatever kind it is.
    public var referencedID: String {
        switch self {
        case .occurrence(let id), .entityAnimation(let id), .backdropCue(let id): return id
        }
    }
}

public struct StoryContinuation: Codable, Sendable, Equatable {
    public var target: StoryContinuationTarget
    public var behavior: StoryContinuationBehavior

    /// Seconds to fade this content's gain to silence when the region resolves
    /// and the story resumes. `nil` = end abruptly, as before.
    ///
    /// SCOPED TO WHAT THE RUNTIME ACTUALLY HAS. This exists because
    /// `AudioActionExecutor.fade(channel:to:duration:)` is a real, per-channel
    /// command that predates Story Regions — the region reuses it and owns no
    /// gain engine of its own. Editors offer it only where
    /// `StoryContinuationCapabilities` says it applies (audio today), so it is
    /// never a control that does nothing.
    ///
    /// Additive and tolerant: absent encodes to no key, so existing chapters
    /// re-save byte-identically.
    public var exitFade: TimeInterval?

    public init(target: StoryContinuationTarget,
                behavior: StoryContinuationBehavior,
                exitFade: TimeInterval? = nil) {
        self.target = target
        self.behavior = behavior
        self.exitFade = exitFade
    }

    private enum CodingKeys: String, CodingKey { case target, behavior, exitFade }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decode(StoryContinuationTarget.self, forKey: .target)
        behavior = try c.decode(StoryContinuationBehavior.self, forKey: .behavior)
        // A non-positive fade is the same statement as no fade, normalized here
        // so nothing downstream has to special-case zero.
        let fade = try c.decodeIfPresent(TimeInterval.self, forKey: .exitFade)
        exitFade = (fade ?? 0) > 0 ? fade : nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(target, forKey: .target)
        try c.encode(behavior, forKey: .behavior)
        try c.encodeIfPresent(exitFade, forKey: .exitFade)
    }
}

// MARK: - Region

/// An authored span of a Sequence where the viewer may explore, and where
/// narrative progression may stall until an exit condition resolves.
public struct StoryRegion: Codable, Sendable, Equatable, Identifiable {
    /// Stable, opaque. Survives save/reopen, reorder, sync, undo and edits to
    /// neighbouring regions — the same rule every other authored id follows.
    public var id: String
    /// What the author calls it: "Radio Room". `nil` = editors describe it as
    /// an unnamed Explore region rather than inventing one.
    public var name: String?
    /// Absolute sequence seconds where the region begins.
    public var startTime: Double
    /// THE AUTHORED PREVIEW SPAN — how much Timeline room the region occupies
    /// so its first pass can be composed and its continuation behaviour
    /// authored. It is NOT how long the viewer will stay; that is runtime dwell
    /// and is not knowable here.
    public var previewDuration: Double

    /// HOW THE STORY IS ALLOWED TO LEAVE.
    ///
    /// A `StepGateDTO` on purpose, not a new condition type: "narrative
    /// progression may continue" is exactly what a gate already means, and the
    /// runtime already has one detector for tap / viewer-facing / approach /
    /// grab. Two representations would be two things to keep in step and two
    /// device-QA surfaces.
    ///
    /// The region OWNS this, and the compiler is the only writer of the gate on
    /// the boundary step — so there is one editable truth, not an authored pair
    /// that can drift.
    public var exit: StepGateDTO

    /// Optional fallback, in seconds, measured from REGION ENTRY — not from the
    /// moment the authored clock starts holding.
    ///
    /// Deliberately separate from `exit.timeout`, which a gate measures from the
    /// moment it begins waiting. "Continue after 30 seconds" means thirty
    /// seconds of being in the room, and a viewer who spent ten of them
    /// watching the authored first pass has already used ten.
    public var fallbackTimeout: Double?

    /// Explicit per-content behaviour during the hold. Anything not named here
    /// holds.
    public var continuations: [StoryContinuation]

    public var endTime: Double { startTime + previewDuration }

    public init(
        id: String = StoryRegion.newID(),
        name: String? = nil,
        startTime: Double,
        previewDuration: Double,
        exit: StepGateDTO = StepGateDTO(type: .tap),
        fallbackTimeout: Double? = nil,
        continuations: [StoryContinuation] = []
    ) {
        self.id = id
        self.name = name
        self.startTime = max(0, startTime)
        self.previewDuration = max(StoryRegion.minimumDuration, previewDuration)
        self.exit = exit
        self.fallbackTimeout = fallbackTimeout
        self.continuations = continuations
    }

    public static func newID() -> String { "sr_" + UUID().uuidString.prefix(12).lowercased() }

    /// A region shorter than a frame is not a span the author can see or aim
    /// at. Clamped rather than refused, so a drag can never produce one.
    public static let minimumDuration: Double = 1.0 / 24.0

    /// The behaviour authored for one target, or `.hold` — the default that
    /// applies to everything nobody said anything about.
    public func behavior(for target: StoryContinuationTarget) -> StoryContinuationBehavior {
        continuations.first { $0.target == target }?.behavior ?? .hold
    }

    /// True when `time` falls inside the authored span. HALF-OPEN: the end
    /// belongs to what comes next, which is the same rule `SequenceTime` uses
    /// for step boundaries and is what stops a boundary action firing twice.
    public func contains(_ time: Double) -> Bool {
        time >= startTime && time < endTime
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startTime, previewDuration, exit, fallbackTimeout, continuations
    }

    /// Tolerant: everything but the span has a defensible default, so a
    /// partially-understood region still loads as something the author can see
    /// and repair.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? StoryRegion.newID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.startTime = max(0, try c.decodeIfPresent(Double.self, forKey: .startTime) ?? 0)
        self.previewDuration = max(StoryRegion.minimumDuration,
                                   try c.decodeIfPresent(Double.self, forKey: .previewDuration) ?? 1)
        self.exit = try c.decodeIfPresent(StepGateDTO.self, forKey: .exit) ?? StepGateDTO(type: .tap)
        self.fallbackTimeout = try c.decodeIfPresent(Double.self, forKey: .fallbackTimeout)
        self.continuations = try c.decodeIfPresent([StoryContinuation].self,
                                                   forKey: .continuations) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(previewDuration, forKey: .previewDuration)
        try c.encode(exit, forKey: .exit)
        try c.encodeIfPresent(fallbackTimeout, forKey: .fallbackTimeout)
        // An empty list emits no key, so a region with no overrides adds
        // nothing to the document.
        if !continuations.isEmpty { try c.encode(continuations, forKey: .continuations) }
    }
}

// MARK: - The one overlap authority

/// Ordering and overlap rules for a Sequence's Explore regions.
///
/// ONE authority, because "may these two spans coexist?" asked in three places
/// is three chances to disagree — and the failure is invisible until a runtime
/// finds two regions claiming the same second.
public enum StoryRegionTimeline {

    /// Regions in authored time order. The stored array's order is never
    /// trusted: a resize can move a region past its neighbour.
    public static func sorted(_ regions: [StoryRegion]) -> [StoryRegion] {
        regions.sorted { $0.startTime < $1.startTime }
    }

    /// The region containing `time`, if any. Half-open, so a boundary belongs
    /// to whatever follows.
    public static func region(at time: Double, in regions: [StoryRegion]) -> StoryRegion? {
        regions.first { $0.contains(time) }
    }

    /// Would `candidate` overlap anything already authored?
    ///
    /// Adjacency is legal and overlap is not: two regions may touch at a
    /// boundary (10–15 and 15–20), because at any instant exactly one of them
    /// is in control.
    public static func overlaps(
        _ candidate: StoryRegion, in regions: [StoryRegion]
    ) -> Bool {
        regions.contains { other in
            guard other.id != candidate.id else { return false }
            return candidate.startTime < other.endTime && other.startTime < candidate.endTime
        }
    }

    /// The largest span starting at `start` that fits before the next region.
    /// `nil` when there is no room at all — a caller refuses rather than
    /// silently trimming somebody else's region.
    public static func availableDuration(
        from start: Double, in regions: [StoryRegion], excluding id: String? = nil,
        limit: Double? = nil
    ) -> Double? {
        let others = regions.filter { $0.id != id }
        if others.contains(where: { $0.contains(start) }) { return nil }
        let nextStart = others.filter { $0.startTime > start }.map(\.startTime).min()
        let ceiling = [nextStart, limit].compactMap { $0 }.min()
        let available = (ceiling ?? .greatestFiniteMagnitude) - start
        return available >= StoryRegion.minimumDuration ? available : nil
    }

    /// Every boundary an Explore region contributes — where the story may
    /// stall, and therefore where a Step must end.
    ///
    /// ONLY THE END. `docs/TIMELINE_3_0.md` D2 is explicit that a step boundary
    /// is "a place the story can stall", and a region's END is exactly that:
    /// its exit gate lives on the step that finishes there. Its START is not a
    /// stall point — the first pass must play straight through it — so putting
    /// a boundary there would either need a gate (which would stall the story
    /// on ENTRY, the one thing Explore must never do) or invent a gateless
    /// pause this format does not have.
    public static func requiredBoundaries(_ regions: [StoryRegion]) -> [Double] {
        Set(sorted(regions).map(\.endTime)).sorted()
    }
}
