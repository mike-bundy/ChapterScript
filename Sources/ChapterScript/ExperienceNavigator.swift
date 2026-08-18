//
//  ExperienceNavigator.swift
//  ChapterScript
//
//  ONE AUTHORITY FOR MOVEMENT BETWEEN SEQUENCES.
//
//  `SequenceEngine`, `InteractionController`, completion handling and the
//  Story Region runtime do not navigate. They emit a `NavigationRequest`; this
//  decides what happens and hands back one `NavigationOutcome` for the host to
//  perform. Two engines that both start Sequences is how a chapter ends up
//  playing two at once, and Phase 8's Go To would have made a third.
//
//  ── WHY THIS IS A PURE MODEL ────────────────────────────────────────────────
//
//  Navigation decides which Sequence the audience is in. That is not something
//  to discover on a headset, so the decision is arithmetic over visits and
//  authored ids, unit-tested at scale, and the host performs the result. The
//  same reasoning that put `GateActivation` here.
//
//  ── RETURN IS VISIT-BASED, NOT SEQUENCE-BASED ───────────────────────────────
//
//  `A1 → B1 → A2 → B2`: returning from B2 goes to A2, not to A1, and not to
//  "the previous Sequence id". A1 and A2 are the same authored Sequence and
//  different runtime visits, so history holds VISITS.
//
//  ── BOUNDED, BECAUSE AN HOUR IS LONG ────────────────────────────────────────
//
//  A one-hour narrative can navigate thousands of times. History is capped and
//  drops its OLDEST entries, which are the ones an audience can no longer
//  reach anyway — an unbounded stack is a leak with a narrative excuse. What a
//  suspended visit RETAINS is the host's problem and is deliberately small
//  here: an id, a Sequence id and an authored position. See §15 of
//  `docs/EXPERIENCE_FLOW.md`.
//

import Foundation

/// What the host must actually do. The navigator changes no scene and starts no
/// player — it says what should happen next, once.
public enum NavigationOutcome: Sendable, Equatable {
    /// Begin this Sequence as a fresh visit. `resumingFrom` is nil for a fresh
    /// entry and carries the authored seconds to resume at otherwise.
    case enter(sequenceId: String, visit: SequenceVisit, resumingFrom: TimeInterval?)
    /// Playback is over. Tear everything down.
    case finish
    /// Nothing to do — the request was a no-op (Hold, or a transition that does
    /// not move between Sequences).
    case stay
    /// The request could not be honoured, with a reason the author can read.
    case refused(NavigationRefusal)
}

public enum NavigationRefusal: Sendable, Equatable {
    /// The target is not in this Chapter.
    case unknownTarget(String)
    /// `Return` with nothing to return to.
    case noOrigin
    /// The Chapter has no resolvable start.
    case noStart
    /// Navigation was requested with nothing playing.
    case notPlaying
    /// The document asks for a navigation this build does not implement.
    case unsupportedNavigation(String)

    public var message: String {
        switch self {
        case .unknownTarget(let id):
            return "“\(id)” is not in this Chapter, so there is nowhere to go."
        case .noOrigin:
            return "There is nowhere to go back to — nothing led here."
        case .noStart:
            return "This Chapter has no Sequence to start with."
        case .notPlaying:
            return "Nothing is playing."
        case .unsupportedNavigation(let kind):
            return "This navigation action (“\(kind)”) isn't supported by this version of Maestro. Nothing happened."
        }
    }
}

/// A visit that has been left but not discarded, so it can be resumed.
///
/// DELIBERATELY SMALL. It holds identity and an authored position — not a
/// scene, not players, not entities. Retaining a live runtime graph per visit
/// is how an hour-long chapter accumulates one complete scene per navigation;
/// the host tears its runtime down and rebuilds from `resumeAt`.
public struct SuspendedVisit: Sendable, Equatable {
    public let visit: SequenceVisit
    /// Authored seconds to resume at. The AUTHORED clock, never a wall clock.
    public var resumeAt: TimeInterval

    public init(visit: SequenceVisit, resumeAt: TimeInterval) {
        self.visit = visit
        self.resumeAt = resumeAt
    }
}

public struct ExperienceNavigator: Sendable {

    /// How many suspended visits are retained.
    ///
    /// Finite on purpose. Deep enough for any nesting an audience can perceive,
    /// and small enough that a chapter navigating for an hour cannot grow
    /// without bound. Exceeding it drops the OLDEST entry — the one furthest
    /// from the audience — and reports that it did.
    public static let historyLimit = 32

    /// The visit currently executing. `nil` before Start and after End.
    public private(set) var current: SequenceVisit?
    /// Where the current visit came from, oldest first. Not exposed to authors
    /// as a stack — "Return" is the only word they ever see.
    public private(set) var history: [SuspendedVisit] = []
    /// Entries dropped because the history bound was reached. A diagnostic, so
    /// a chapter that navigates pathologically says so instead of silently
    /// losing the ability to return.
    public private(set) var droppedHistoryCount: Int = 0

    public init() {}

    public var suspendedCount: Int { history.count }
    public var canReturn: Bool { !history.isEmpty }

    // MARK: - The one entry point

    /// Decide what a request means. Pure: the same navigator and request always
    /// produce the same outcome.
    ///
    /// `resolver` answers whether a target exists and what the start is —
    /// through the single Sequence-reference authority, never an ad-hoc scan.
    /// `currentPosition` is the authored time the current visit has reached,
    /// captured by the host so a suspended visit knows where to resume.
    ///
    /// `storyState` is what the Chapter remembers, and it is consulted for
    /// exactly one thing: resolving a `.branch`. It defaults to an empty ledger
    /// so every existing call site is unchanged — a Chapter with no Story State
    /// remembers nothing, which is the same reading.
    public mutating func handle(
        _ request: NavigationRequest,
        exists: (String) -> Bool,
        start: () -> String?,
        currentPosition: TimeInterval = 0,
        storyState: any StoryStateReading = StoryStateLedger()
    ) -> NavigationOutcome {
        switch request.intent {

        case .branch:
            // A BRANCH IS A DECISION, NOT A DESTINATION. Resolve it to a real
            // intent and perform THAT through the same path everything else
            // takes — so a conditional Go To and a plain one suspend the same
            // visit, push the same history and honour the same refusals.
            //
            // `resolving` never yields another branch, so this recurses once.
            guard let resolved = request.intent.resolving(in: storyState) else {
                // No case matched and there is no Otherwise. That is Hold: the
                // story stays exactly where it is, and nothing is invented.
                return .stay
            }
            return handle(NavigationRequest(intent: resolved, source: request.source),
                          exists: exists, start: start,
                          currentPosition: currentPosition, storyState: storyState)

        case .start:
            guard let id = start(), exists(id) else { return .refused(.noStart) }
            history.removeAll()
            droppedHistoryCount = 0
            return enterFresh(id)

        case .goTo(let target):
            guard exists(target) else { return .refused(.unknownTarget(target)) }
            // The visit we are leaving becomes returnable. A Go To from
            // nothing (a host jumping in) simply has no origin to suspend.
            if let leaving = current {
                suspend(leaving, at: currentPosition)
            }
            return enterFresh(target)

        case .back(let policy):
            guard current != nil else { return .refused(.notPlaying) }
            guard let origin = history.popLast() else { return .refused(.noOrigin) }
            guard exists(origin.visit.sequenceId) else {
                // The Sequence we came from has been deleted mid-run. Refuse
                // rather than silently redirecting somewhere plausible.
                return .refused(.unknownTarget(origin.visit.sequenceId))
            }
            switch policy {
            case .resume:
                // THE SAME VISIT CONTINUES. Its id is unchanged, so `.once`
                // stays spent and runtime enablement stays as the audience
                // left it — that is the whole difference from Restart.
                current = origin.visit
                return .enter(sequenceId: origin.visit.sequenceId,
                              visit: origin.visit,
                              resumingFrom: origin.resumeAt)
            case .restart:
                return enterFresh(origin.visit.sequenceId)
            }

        case .restart:
            guard let visit = current else { return .refused(.notPlaying) }
            // A FRESH VISIT OF THE SAME SEQUENCE. Restart is not a Go To to
            // oneself: it discards this visit's runtime state without touching
            // the history that led here.
            return enterFresh(visit.sequenceId)

        case .end:
            current = nil
            history.removeAll()
            droppedHistoryCount = 0
            return .finish

        case .unsupported(let kind, _):
            // FAILS INERTLY. A navigation this build does not understand must
            // not invent a destination and must not end the Chapter — the story
            // simply carries on as if the action were not there, and the
            // validator tells the author why. Refusing (rather than staying) is
            // deliberate: it is reported, not silently absorbed.
            return .refused(.unsupportedNavigation(kind))
        }
    }

    /// The current visit finished and its completion says what to do.
    ///
    /// Legacy `autoAdvance` arrives here exactly like a Go To, which is the
    /// convergence §10 requires.
    public mutating func handleCompletion(
        _ completion: CompletionActionDTO,
        from sequenceId: String,
        exists: (String) -> Bool,
        start: () -> String?,
        currentPosition: TimeInterval = 0,
        storyState: any StoryStateReading = StoryStateLedger()
    ) -> NavigationOutcome {
        guard let intent = NavigationIntent.forCompletion(completion) else { return .stay }
        return handle(NavigationRequest(intent: intent,
                                        source: .completion(from: sequenceId)),
                      exists: exists, start: start, currentPosition: currentPosition,
                      storyState: storyState)
    }

    // MARK: - Internals

    private mutating func enterFresh(_ sequenceId: String) -> NavigationOutcome {
        let visit = SequenceVisit(sequenceId: sequenceId)
        current = visit
        return .enter(sequenceId: sequenceId, visit: visit, resumingFrom: nil)
    }

    private mutating func suspend(_ visit: SequenceVisit, at position: TimeInterval) {
        history.append(SuspendedVisit(visit: visit, resumeAt: max(0, position)))
        while history.count > Self.historyLimit {
            history.removeFirst()
            droppedHistoryCount += 1
        }
    }
}
