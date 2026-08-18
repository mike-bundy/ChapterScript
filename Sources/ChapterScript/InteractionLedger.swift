//
//  InteractionLedger.swift
//  ChapterScript
//
//  THE RUNTIME STATE OF ONE SEQUENCE VISIT.
//
//  A SEQUENCE VISIT is one runtime execution instance of a Sequence, from entry
//  until it exits, completes, stops or is discarded. It is a runtime concept and
//  deliberately not UI vocabulary.
//
//  Everything here belongs to a visit and NOTHING here is ever serialized:
//
//      effective enabled state   changed by enableInteraction/disableInteraction
//      spent `.once` records     consumed by an activation
//
//  The authored side — `InteractionSpec.initiallyEnabled`, the trigger, the
//  lifetime, the responses — is a different type, held in the document, and is
//  never written by playback. That separation is structural on purpose: the
//  previous build stored the runtime answer on a copy of the authored spec,
//  which corrupted nothing but made "is it on?" and "does it start on?" the same
//  question, and Phase 8's Resume semantics need them to be two.
//
//  WHY THIS IS IN THE FORMAT PACKAGE. It is pure semantics — deterministic state
//  transitions over authored values, with no RealityKit entity, no subscription,
//  no scene reference, no device transform and no platform lifecycle. It sits
//  beside `SequenceAnimationEvaluator` and `AudioRuntimeRouting` for the same
//  reason those do: the runtime needs the answer, and the editors must never be
//  able to disagree with the device about whether a one-shot has been spent.
//  `ChapterScript` may own semantic truth; it must not become the player.
//
//  THE TWO LIFETIMES, EXACTLY.
//
//      .once      at most ONE activation per Sequence Visit.
//      .everyTime one execution per distinct trigger ACTIVATION EDGE.
//
//  `.once` does NOT mean once per chapter, once forever, once per save, once per
//  Story Region loop, once per Timeline loop, or once per enable/disable cycle.
//  Whether a trigger has produced a new activation edge is the DETECTOR's job
//  (`ChapterPlayer.SpatialTriggerDetector`); this type only counts activations.
//

import Foundation

public struct InteractionLedger: Sendable, Equatable {

    /// Why a trigger did not produce a response. Distinguishable outcomes,
    /// because "nothing happened" has several meanings and only one is a bug.
    public enum Refusal: Sendable, Equatable {
        /// No interaction with that id is registered in this visit.
        case notRegistered
        /// Not enabled right now — either it started disabled, or a
        /// `disableInteraction` action switched it off during this visit.
        case disabled
        /// `.once`, and it has already fired during this visit.
        case alreadyFired
    }

    public enum Outcome: Sendable, Equatable {
        case fire
        case refuse(Refusal)

        public var didFire: Bool { self == .fire }
    }

    /// One interaction's place in this visit: what the author wrote, plus what
    /// has happened to it since the visit began.
    private struct Entry: Sendable, Equatable {
        /// AUTHORED, read-only here. Never mutated by playback.
        let spec: InteractionSpec
        /// RUNTIME. Starts at `spec.initiallyEnabled`.
        var effectivelyEnabled: Bool
        /// RUNTIME. `.once` consumption for this visit.
        var hasFired: Bool
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    // MARK: - Visit lifecycle

    /// Begin a visit's knowledge of these interactions.
    ///
    /// Registering an id that is already present RE-SEEDS it from the authored
    /// value — an install is the start of a visit, not an update to one. To
    /// change enablement mid-visit, use `setEnabled`.
    public mutating func register(_ interactions: [InteractionSpec]) {
        for interaction in interactions {
            entries[interaction.id] = Entry(spec: interaction,
                                            effectivelyEnabled: interaction.initiallyEnabled,
                                            hasFired: false)
        }
    }

    /// END OF VISIT. Forget every registration and every runtime fact.
    ///
    /// Called from `SequenceEngine.stop`, which every play path runs first — so
    /// a new visit starts from the authored defaults and cannot inherit a
    /// previous visit's enable/disable overrides or spent one-shots.
    public mutating func reset() {
        entries.removeAll()
    }

    /// Start a fresh visit over the SAME registrations: authored defaults
    /// restored, one-shots re-armed.
    ///
    /// This is what "Reset Interaction Preview" means on the Mac, and what a
    /// future Restart will mean on device. Distinct from `reset()`, which
    /// forgets the interactions entirely.
    public mutating func beginFreshVisit() {
        for id in entries.keys {
            guard let spec = entries[id]?.spec else { continue }
            entries[id] = Entry(spec: spec,
                                effectivelyEnabled: spec.initiallyEnabled,
                                hasFired: false)
        }
    }

    // MARK: - Reading

    /// The AUTHORED definition. Callers that want "can it fire now?" ask
    /// `isArmed` — this never reflects runtime enablement.
    public func spec(_ id: String) -> InteractionSpec? { entries[id]?.spec }

    public var registeredIDs: [String] { Array(entries.keys) }

    /// Runtime enablement — what `enableInteraction` / `disableInteraction`
    /// changed, starting from `initiallyEnabled`.
    public func isEffectivelyEnabled(_ id: String) -> Bool {
        entries[id]?.effectivelyEnabled ?? false
    }

    /// Has this `.once` interaction been consumed during this visit?
    public func hasFired(_ id: String) -> Bool { entries[id]?.hasFired ?? false }

    /// Registered, enabled right now, and not already spent.
    public func isArmed(_ id: String) -> Bool {
        guard let entry = entries[id], entry.effectivelyEnabled else { return false }
        return !(entry.spec.lifetime == .once && entry.hasFired)
    }

    public var armedCount: Int { entries.keys.filter(isArmed).count }

    // MARK: - Firing

    /// Ask whether an activation may produce a response, and RECORD it if so.
    ///
    /// Deliberately one call, not a query plus a commit: two calls is two
    /// chances for a caller to check and then forget to record, which turns
    /// `.once` into `.everyTime` silently.
    ///
    /// EVERY input route goes through here — a physical tap, a spatial
    /// detector, and an accessibility activation alike. There is one lifetime
    /// truth, so an interaction spent by an assistive-technology user is spent
    /// for the physical route too, and the reverse.
    public mutating func fire(_ id: String) -> Outcome {
        guard let entry = entries[id] else { return .refuse(.notRegistered) }
        guard entry.effectivelyEnabled else { return .refuse(.disabled) }
        if entry.spec.lifetime == .once {
            if entry.hasFired { return .refuse(.alreadyFired) }
            entries[id]?.hasFired = true
        }
        return .fire
    }

    /// The actions an activation should run — empty when it was refused, so a
    /// caller cannot accidentally dispatch a response for a refused trigger.
    public mutating func firing(_ id: String) -> (outcome: Outcome, actions: [StepActionDTO]) {
        let outcome = fire(id)
        guard outcome.didFire, let entry = entries[id] else { return (outcome, []) }
        return (outcome, entry.spec.actions)
    }

    // MARK: - Runtime enablement

    /// The `enableInteraction` / `disableInteraction` actions.
    ///
    /// Changes RUNTIME state only. It does not touch `initiallyEnabled`, does
    /// not dirty the chapter, and — critically — **does not clear the spent
    /// record**. A `.once` interaction that has already run is finished for this
    /// visit; re-enabling it would make "once" mean "once per switch-on", which
    /// is a different promise from the one the author was shown.
    ///
    /// If explicit re-arming is ever wanted it gets its own clearly named
    /// action. Enable must never quietly become Reset.
    public mutating func setEnabled(_ enabled: Bool, id: String) {
        guard entries[id] != nil else { return }
        entries[id]?.effectivelyEnabled = enabled
    }

    /// Ids whose AUTHORED definition matches, sorted for determinism. Callers
    /// that need authored ORDER keep their own list — a dictionary has none.
    public func ids(matching predicate: (InteractionSpec) -> Bool) -> [String] {
        entries.values.filter { predicate($0.spec) }.map(\.spec.id).sorted()
    }
}
