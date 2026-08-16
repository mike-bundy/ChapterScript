//
//  StoryStateLedger.swift
//  ChapterScript
//
//  WHAT THE STORY REMEMBERS RIGHT NOW.
//
//  The runtime half of Story State, and the exact counterpart of
//  `InteractionLedger`: authored facts live in the document, and what has
//  happened to them during THIS run lives here and is never serialized.
//
//  ── THE ONE LIFETIME THAT MATTERS ───────────────────────────────────────────
//
//  A CHAPTER PLAYBACK SESSION — one run of the experience, from the moment
//  playback begins until it ends. Values are seeded at its start and survive
//  everything inside it:
//
//      Go To                   survives
//      Return (Resume)         survives
//      Return (Restart)        survives
//      Restart this Sequence   survives
//      entering/leaving Explore survives
//      a new playback session  RESET to the authored initial values
//
//  This is the whole point. If state reset when a Sequence restarted, walking
//  back into the gallery would forget that the viewer heard the radio — and the
//  radio is the only reason they were sent anywhere.
//
//  ── NEVER PERSISTED, NEVER UNDOABLE, NEVER SYNCED ───────────────────────────
//
//  Not `Codable`, asserted by test. A viewer's progress is not a property of the
//  Chapter: writing it into the document would mean playing an experience dirties
//  it, saving it would ship somebody else's run inside the file, and an undo
//  stack would have entries for things the audience did rather than things the
//  author did.
//

import Foundation

/// The current value of every Story State in this Chapter playback session.
///
/// A value type, deliberately: a host owns exactly one and mutates it in place,
/// and a test can hold a snapshot to compare against without the store changing
/// underneath it.
public struct StoryStateLedger: StoryStateReading, Sendable, Equatable {

    /// AUTHORED, read-only here. Never mutated by playback.
    private var definitions: [String: StoryStateDefinition] = [:]
    /// Authored order, so a readout lists states the way the author wrote them
    /// rather than in a dictionary's arbitrary order.
    private var order: [String] = []
    /// RUNTIME. Seeded from `definitions`, changed only by `apply`.
    private var values: [String: StoryStateValue] = [:]

    public init() {}

    public init(definitions: [StoryStateDefinition]) {
        begin(definitions)
    }

    // MARK: - Session lifecycle

    /// BEGIN A CHAPTER PLAYBACK SESSION. Every state returns to its authored
    /// initial value.
    ///
    /// The only thing that resets Story State. Called when playback starts, and
    /// deliberately NOT called by anything that navigates: `SequenceEngine.play`
    /// begins a Sequence VISIT, and a visit is not a session.
    public mutating func begin(_ definitions: [StoryStateDefinition]) {
        self.definitions = Dictionary(definitions.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        self.order = definitions.map(\.id)
        self.values = Dictionary(definitions.map { ($0.id, $0.seedValue) },
                                 uniquingKeysWith: { first, _ in first })
    }

    /// END OF SESSION. Forget the definitions and every runtime value.
    public mutating func end() {
        definitions.removeAll()
        order.removeAll()
        values.removeAll()
    }

    /// Reseed the SAME definitions — a fresh session over an unchanged Chapter.
    public mutating func beginFreshSession() {
        for id in order {
            guard let definition = definitions[id] else { continue }
            values[id] = definition.seedValue
        }
    }

    // MARK: - Reading

    public func storyStateValue(_ stateId: String) -> StoryStateValue? { values[stateId] }

    public func definition(_ stateId: String) -> StoryStateDefinition? { definitions[stateId] }

    public var isEmpty: Bool { order.isEmpty }

    /// Every state and its current value, in authored order. For a preview
    /// readout and for tests; never for a render path.
    public var snapshot: [(definition: StoryStateDefinition, value: StoryStateValue)] {
        order.compactMap { id in
            guard let definition = definitions[id], let value = values[id] else { return nil }
            return (definition, value)
        }
    }

    /// The plain map, for handing to an evaluator or asserting on.
    public var valuesByStateID: [String: StoryStateValue] { values }

    // MARK: - Mutation

    /// Apply one authored change.
    ///
    /// The arithmetic is `StoryStateArithmetic.apply`, shared with everything
    /// else that needs to know what an operation means. This adds only the
    /// lookup and the write, so a Mac preview and a headset cannot end a tap on
    /// the radio holding different numbers.
    ///
    /// A refusal changes nothing. It is returned rather than logged-and-ignored
    /// because the author needs to see it, and because a silent no-op is exactly
    /// how a story stops advancing for reasons nobody can find.
    @discardableResult
    public mutating func apply(_ mutation: StoryStateMutation)
    -> Result<StoryStateValue, StoryStateArithmetic.Refusal> {
        guard let definition = definitions[mutation.stateId] else {
            return .failure(.unknownState(mutation.stateId))
        }
        let current = values[mutation.stateId] ?? definition.seedValue
        let result = StoryStateArithmetic.apply(mutation.operation,
                                                to: current,
                                                definition: definition)
        if case .success(let updated) = result {
            values[mutation.stateId] = updated
        }
        return result
    }

    /// Set a value directly. **Not an authoring path** — it exists for a host
    /// restoring a session it owns and for tests, and there is deliberately no
    /// action, op or UI that reaches it.
    public mutating func setValue(_ value: StoryStateValue, for stateId: String) {
        guard definitions[stateId] != nil else { return }
        values[stateId] = value
    }
}
