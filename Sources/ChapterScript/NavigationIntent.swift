//
//  NavigationIntent.swift
//  ChapterScript
//
//  WHERE NARRATIVE EXECUTION GOES BETWEEN SEQUENCES.
//
//  One vocabulary, so every source of navigation — an authored completion, an
//  Interaction response, a host command — says the same seven things, and one
//  authority executes them. Before this, `ChapterPlayerCore.onSequenceComplete`
//  contained its own `while true` chain-walker that resolved targets, applied
//  presentation and called `playAndAwait` inline. That was a second navigator,
//  and Phase 8's Go To would have been a third.
//
//  THE THREE LAYERS, KEPT APART:
//
//      Timeline        what happens INSIDE a Sequence
//      Story Regions   when authored time may DWELL inside a Sequence
//      Flow            where execution goes BETWEEN Sequences
//
//  This is the third. It names no step, no action and no time.
//
//  NOT PERSISTED. An intent is a runtime event. The authored facts it is
//  derived FROM — `CompletionActionDTO`, an Interaction response — are what
//  documents store. See `docs/EXPERIENCE_FLOW.md`.
//

import Foundation

/// The seven things narrative execution can be asked to do.
///
/// Phase 8B adds one more, `.branch`, which chooses between the others from what
/// the story remembers. It is a case of THIS enum on purpose: a branch decides
/// which navigation applies and the existing navigator performs it, so there is
/// still exactly one place a Sequence starts. A `BranchNavigator` would have
/// been the second.
public indirect enum NavigationIntent: Codable, Sendable, Equatable, Hashable {
    /// Begin the Chapter at its canonical start.
    case start
    /// Enter a specific Sequence as a FRESH visit.
    case goTo(sequenceId: String)
    /// Go back to wherever this visit came from.
    ///
    /// Resolved against the runtime visit history, never against "the previous
    /// Sequence id" — `A1 → B1 → A2 → B2` must return `B2 → A2`, and A1 and A2
    /// are the same authored Sequence.
    case back(policy: ReturnPolicy)
    /// Discard the current visit and enter the same Sequence afresh.
    case restart
    /// Finish. Not a Sequence, and not the same as holding on the last step.
    case end
    /// A navigation this build does not understand, kept verbatim.
    ///
    /// ── WHY THIS EXISTS ─────────────────────────────────────────────────────
    ///
    /// The first version of this decoder mapped an unrecognised intent to
    /// `.end`. That was wrong in the most dangerous way available: a newer
    /// tool's "go to the epilogue" would have SILENTLY ENDED THE CHAPTER on an
    /// older build, and nothing would have said so. Forward compatibility must
    /// never invent narrative meaning.
    ///
    /// So an unknown intent becomes this: it names no destination, terminates
    /// nothing, and fails INERTLY at runtime while the validator reports it.
    /// `raw` is retained so an editor can re-emit the document unchanged rather
    /// than quietly downgrading somebody's chapter — the same rule
    /// `StepActionDTO.unknown` already follows.
    case unsupported(kind: String, raw: AnyCodableValue?)

    /// **Go wherever the story's memory says.**
    ///
    ///     If Selected Route is Radio      → Radio Story
    ///     If Selected Route is Camera     → Camera Story
    ///     Otherwise                       → Main Ending
    ///
    /// ORDERED, and the FIRST matching case wins. Two cases can be true at once
    /// — "Objects Found is at least 1" and "Objects Found is at least 3" both
    /// hold at four — and something has to decide. Order is the one rule an
    /// author can see in the Inspector and change by dragging; scoring by
    /// specificity would be invisible and unarguable.
    ///
    /// `otherwise` is a DISTINCT story concept, not "NOT(everything above)".
    /// There is at most one, it carries no condition, and it is always last.
    ///
    /// NO MATCH AND NO OTHERWISE = NO NAVIGATION, which is Hold — exactly what
    /// `forCompletion` already returns for `.holdOnLastStep`. Nothing invents a
    /// destination.
    case branch(cases: [StoryBranchCase], otherwise: NavigationIntent?)

    /// What happens to the visit being returned TO.
    public enum ReturnPolicy: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
        /// Continue the suspended visit where it left off. `.once` stays spent,
        /// runtime enablement stays as it was.
        case resume
        /// Discard it and enter that Sequence fresh.
        case restart
    }

    /// The Sequence this intent names, when it names ONE. Return and End name
    /// none — that is the point of them — and neither does a branch, which names
    /// several. Callers that must find every destination use
    /// `allExplicitTargets`.
    public var explicitTarget: String? {
        if case .goTo(let id) = self { return id }
        return nil
    }

    /// EVERY Sequence this intent can send the audience to, branches included.
    ///
    /// This is what a reference inventory walks. Phase 8A learned what happens
    /// when a new navigation reference exists and nothing enumerates it: a
    /// broken destination is not reported, deleting a Sequence does not say what
    /// it stranded, and the Flow graph draws no edge for it.
    public var allExplicitTargets: [String] {
        switch self {
        case .goTo(let id):
            return [id]
        case .branch(let cases, let otherwise):
            return cases.flatMap { $0.intent.allExplicitTargets }
                 + (otherwise?.allExplicitTargets ?? [])
        case .start, .back, .restart, .end, .unsupported:
            return []
        }
    }

    /// True when this build cannot perform the navigation. The runtime does
    /// nothing and logs; the validator tells the author.
    ///
    /// A BRANCH IS NOT UNSUPPORTED BECAUSE ONE OF ITS DESTINATIONS IS. The rest
    /// of it still works, and reporting the whole decision as unsupported would
    /// hide the destinations that are fine.
    public var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    /// Every unsupported navigation anywhere inside this intent, by kind. Empty
    /// for the ordinary cases; used by the validator to name what a newer tool
    /// wrote that this build cannot run.
    public var unsupportedKinds: [String] {
        switch self {
        case .unsupported(let kind, _):
            return [kind]
        case .branch(let cases, let otherwise):
            return cases.flatMap { $0.intent.unsupportedKinds }
                 + (otherwise?.unsupportedKinds ?? [])
        case .start, .goTo, .back, .restart, .end:
            return []
        }
    }

    // MARK: - Resolving a branch

    /// **The intent that actually applies, given what the story remembers.**
    ///
    /// Returns `nil` when nothing applies — no case matched and there is no
    /// Otherwise — which means no navigation, i.e. Hold. Never a guess.
    ///
    /// PURE, and in the format package, so the Mac's preview and a headset
    /// cannot send the same audience to two different Sequences. `depthLimit`
    /// bounds a branch whose chosen destination is itself a branch: the editor
    /// does not author nested decisions, but a hand-edited or newer-tool
    /// document can contain one, and a cycle must terminate rather than
    /// recursing until the stack ends.
    public func resolving(in state: some StoryStateReading,
                          depthLimit: Int = 8) -> NavigationIntent? {
        guard case .branch(let cases, let otherwise) = self else { return self }
        guard depthLimit > 0 else { return nil }
        for branchCase in cases
        where StoryConditionEvaluator.evaluate(branchCase.conditions, in: state) {
            return branchCase.intent.resolving(in: state, depthLimit: depthLimit - 1)
        }
        return otherwise?.resolving(in: state, depthLimit: depthLimit - 1)
    }

    // `AnyCodableValue` is deliberately not `Hashable` (it can hold a
    // dictionary), so hashing uses the DISCRIMINATOR — which is what callers
    // key on. Equality still compares the retained raw value, so two
    // unsupported intents that differ only in payload stay distinct.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .start:                 hasher.combine(0)
        case .goTo(let id):          hasher.combine(1); hasher.combine(id)
        case .back(let policy):      hasher.combine(2); hasher.combine(policy)
        case .restart:               hasher.combine(3)
        case .end:                   hasher.combine(4)
        case .unsupported(let k, _): hasher.combine(5); hasher.combine(k)
        case .branch(let cases, let otherwise):
            hasher.combine(6); hasher.combine(cases); hasher.combine(otherwise)
        }
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case kind, sequenceId, policy, raw, cases, otherwise
    }
    private enum Kind: String, Codable { case start, goTo, back, restart, end, branch }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start:   try c.encode(Kind.start, forKey: .kind)
        case .restart: try c.encode(Kind.restart, forKey: .kind)
        case .end:     try c.encode(Kind.end, forKey: .kind)
        case .unsupported(let kind, let raw):
            // RE-EMITTED VERBATIM. Saving a chapter in an older build must not
            // silently downgrade a navigation the author wrote in a newer one.
            try c.encode(kind, forKey: .kind)
            if let raw { try c.encode(raw, forKey: .raw) }
        case .goTo(let id):
            try c.encode(Kind.goTo, forKey: .kind)
            try c.encode(id, forKey: .sequenceId)
        case .back(let policy):
            try c.encode(Kind.back, forKey: .kind)
            try c.encode(policy, forKey: .policy)
        case .branch(let cases, let otherwise):
            try c.encode(Kind.branch, forKey: .kind)
            try c.encode(cases, forKey: .cases)
            // Absent when there is no Otherwise, which is a real authored
            // choice: no fallback means the story holds rather than going
            // somewhere the author did not name.
            try c.encodeIfPresent(otherwise, forKey: .otherwise)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // TOLERANT, like `GateType` and `EntityKind`: a newer tool's intent must
        // not fail the whole document. But it must not be GUESSED at either —
        // an unrecognised intent becomes `.unsupported`, which does nothing and
        // is reported. It is never mapped onto a real navigation.
        let name = (try? c.decode(String.self, forKey: .kind)) ?? ""
        guard let kind = Kind(rawValue: name) else {
            self = .unsupported(kind: name,
                                raw: try? c.decode(AnyCodableValue.self, forKey: .raw))
            return
        }
        switch kind {
        case .start:   self = .start
        case .restart: self = .restart
        case .end:     self = .end
        case .goTo:
            self = .goTo(sequenceId: (try? c.decode(String.self, forKey: .sequenceId)) ?? "")
        case .back:
            self = .back(policy: (try? c.decode(ReturnPolicy.self, forKey: .policy)) ?? .resume)
        case .branch:
            self = .branch(cases: (try? c.decode([StoryBranchCase].self, forKey: .cases)) ?? [],
                           otherwise: try? c.decode(NavigationIntent.self, forKey: .otherwise))
        }
    }
}

// MARK: - One branch case

/// One line of a decision: if these conditions hold, go here.
///
/// `id` is stable so the editor can reorder, edit and duplicate cases without
/// identity being an array index — the same lesson `AuthoredAction` carries.
public struct StoryBranchCase: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    /// What must be true. Match All or Match Any, exactly one level.
    public var conditions: StoryConditionGroup
    /// Where the story goes when they hold. The full navigation vocabulary, so
    /// a branch can Return or End as readily as it can Go To.
    public var intent: NavigationIntent

    public init(id: String = StoryBranchCase.newID(),
                conditions: StoryConditionGroup,
                intent: NavigationIntent) {
        self.id = id
        self.conditions = conditions
        self.intent = intent
    }

    public static func newID() -> String { "br_" + UUID().uuidString.prefix(12).lowercased() }

    private enum CodingKeys: String, CodingKey { case id, conditions, intent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? StoryBranchCase.newID()
        self.conditions = try c.decodeIfPresent(StoryConditionGroup.self, forKey: .conditions)
            ?? StoryConditionGroup()
        self.intent = try c.decodeIfPresent(NavigationIntent.self, forKey: .intent)
            ?? .unsupported(kind: "", raw: nil)
    }
}

/// Why a navigation happened. Carried for diagnostics and for the one rule that
/// needs it: an Interaction's explicit Go To leaves a Story Region immediately,
/// while satisfying a Region's exit does not navigate at all.
public enum NavigationSource: Sendable, Equatable, Hashable {
    /// The Sequence finished and its authored completion said where to go.
    case completion(from: String)
    /// An interactive object's response.
    case interaction(entity: String, interactionId: String)
    /// The host, an editor preview, or an orchestrator.
    case host
}

public struct NavigationRequest: Sendable, Equatable {
    public let intent: NavigationIntent
    public let source: NavigationSource

    public init(intent: NavigationIntent, source: NavigationSource) {
        self.intent = intent
        self.source = source
    }
}

// MARK: - Legacy convergence

extension NavigationIntent {

    /// The intent an authored completion means.
    ///
    /// **THIS IS WHERE LEGACY CONVERGES.** `autoAdvance` is not executed by its
    /// own routing any more; it is translated here and run by the same
    /// navigator a Go To uses. Old Chapters therefore behave identically while
    /// there is only one execution path — the rule from §31: migration
    /// normalizes representation, runtime executes current semantics.
    ///
    /// EXHAUSTIVE with no `default`: a new completion kind must state what it
    /// means navigationally rather than silently doing nothing.
    public static func forCompletion(_ completion: CompletionActionDTO) -> NavigationIntent? {
        switch completion {
        case .autoAdvance(let next):
            return .goTo(sequenceId: next)
        case .holdOnLastStep:
            // HOLD IS NOT END. The experience stays alive on its final frame;
            // nothing navigates. Keeping these distinct is why `end` exists as
            // its own case rather than as "hold with no next".
            return nil
        case .dismissToHome:
            return .end
        case .transitionTo:
            // Changes presentation within the same Sequence. Not navigation.
            return nil
        case .navigate(let intent):
            // The full vocabulary — Return and Restart included — which the
            // four legacy cases could not express.
            return intent
        }
    }
}
