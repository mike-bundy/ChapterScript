//
//  GateActivation.swift
//  ChapterScript
//
//  ONE SEMANTIC ACTIVATION, TWO CONSUMERS.
//
//  A viewer acting on an object can mean two things at once:
//
//      the OBJECT'S OWN BEHAVIOUR      an Interaction responds
//      PERMISSION TO CONTINUE         a Gate is satisfied
//
//  They are different consumers of the same event, with different rules, and
//  this is the rule for the second one: given an activation, does the waiting
//  gate accept it?
//
//  WHY THIS IS PURE, AND HERE.
//
//  It decides whether a story advances. That is not something to discover on a
//  headset — so it lives beside `InteractionLedger` as arithmetic over authored
//  values, and `ChapterPlayer` calls it rather than reimplementing it. The
//  sensing stays on device; the decision does not.
//
//  ACCESSIBILITY IS WHY THIS EXISTS.
//
//  Phase 6 established that an accessible activation is another ROUTE to the
//  same authored intent, not another behaviour engine. Phase 7 then made a
//  Story Region's exit a `StepGateDTO` — at which point a VoiceOver user could
//  activate an object and have its Interaction respond while the story stayed
//  locked, because nothing carried that activation to the gate. A gate BLOCKS
//  progression, so that is not a missing nicety: it is a chapter that ends
//  there for them.
//

import Foundation

/// What a viewer just did, in the vocabulary both consumers share.
public struct SemanticActivation: Sendable, Equatable {
    /// The authored object acted on, resolved through ancestry by the caller.
    /// `nil` when the activation hit nothing named — a tap on empty space.
    public let entityName: String?
    /// Which of the four things happened.
    public let trigger: InteractionTrigger
    /// Did an Interaction on that object respond to this same activation?
    ///
    /// Load-bearing for exactly one case; see `GateActivation.satisfies`.
    public let interactionRan: Bool
    /// True when the activation arrived through assistive technology rather
    /// than through a physical act. Carried for logging and QA only — **it must
    /// never change the decision**, which is the whole point of the route.
    public let isAccessible: Bool

    public init(entityName: String?, trigger: InteractionTrigger,
                interactionRan: Bool = false, isAccessible: Bool = false) {
        self.entityName = entityName
        self.trigger = trigger
        self.interactionRan = interactionRan
        self.isAccessible = isAccessible
    }
}

public enum GateActivation {

    /// The activation a gate type is waiting for, or `nil` when NO act satisfies
    /// it.
    ///
    /// ONE mapping, so a gate and an interaction can never disagree about what
    /// "the same thing" means. Parameters are absent because a gate's dwell and
    /// radius belong to its own detection, not to the question of which KIND of
    /// act satisfies it.
    ///
    /// OPTIONAL BECAUSE `.storyCondition` IS REAL. A story-condition gate is
    /// satisfied by what the Chapter remembers, never by an act — and returning
    /// `.tap` for it "so the signature stays simple" would mean any tap in the
    /// scene silently released a boundary the author gated on a fact.
    public static func trigger(for type: GateType) -> InteractionTrigger? {
        switch type {
        case .viewerFacing:   return .viewerFacing(dwell: nil)
        case .proximity:      return .approach(radius: nil)
        case .grab:           return .grab
        case .tap, .orchestrator, .any: return .tap
        case .storyCondition: return nil
        }
    }

    /// Do two activations mean the same act? Compares KIND only. A `nil` first
    /// operand is "this gate waits for no act", which matches nothing.
    public static func sameKind(_ a: InteractionTrigger?, _ b: InteractionTrigger) -> Bool {
        a?.kindName == b.kindName
    }

    /// **Does this gate accept this activation?**
    ///
    /// Two rules, and the first is Phase 6's, preserved exactly:
    ///
    /// * A gate that names NO entity is satisfied only by an activation that
    ///   ran no Interaction. That is the legacy "tap anywhere targetable" gate,
    ///   and it is what stops touching a prop from advancing the film.
    /// * A gate that NAMES this object is satisfied by acting on it, whatever
    ///   else that action also did. "Continue when Tap Radio" means tapping the
    ///   Radio continues — including when the Radio has its own Interaction,
    ///   and including when the activation arrived through accessibility.
    ///
    /// `.any` accepts either supported route, as it always has.
    ///
    /// Note what is NOT consulted: whether the object has an Interaction at
    /// all, and whether that Interaction is enabled. A gate and an Interaction
    /// are separate consumers, and making progression depend on an unrelated
    /// object's enablement would be exactly the conflation this file prevents.
    ///
    /// Takes the two fields it actually reads rather than a gate value, because
    /// the authored `StepGateDTO` and `ChapterPlayer`'s runtime `StepGate` are
    /// different types and this rule must be the same one for both.
    public static func satisfies(gateType: GateType, gateTarget: String?,
                                 activation: SemanticActivation) -> Bool {
        // `.any` has always accepted any supported route; a story-condition gate
        // accepts none, which is why the mapping is optional.
        guard gateType != .storyCondition else { return false }
        guard sameKind(trigger(for: gateType), activation.trigger) || gateType == .any
        else { return false }

        if let target = gateTarget, !target.isEmpty {
            return target == activation.entityName
        }
        return !activation.interactionRan
    }

    public static func satisfies(gate: StepGateDTO, activation: SemanticActivation) -> Bool {
        satisfies(gateType: gate.type, gateTarget: gate.targetEntity, activation: activation)
    }

    // MARK: - Story State as a gate requirement

    /// Do this gate's Story State conditions hold right now?
    ///
    /// A gate with no conditions imposes no story requirement, so this is true.
    public static func storyConditionsHold(_ gate: StepGateDTO,
                                           in state: some StoryStateReading) -> Bool {
        guard let group = gate.storyConditions else { return true }
        return StoryConditionEvaluator.evaluate(group, in: state)
    }

    /// **Does the story's memory alone continue this boundary?**
    ///
    /// True only for a `.storyCondition` gate whose conditions hold. Every other
    /// gate needs an act, and this must never release one.
    public static func satisfiedByStory(_ gate: StepGateDTO,
                                        in state: some StoryStateReading) -> Bool {
        gate.type == .storyCondition && storyConditionsHold(gate, in: state)
    }

    /// **Does this gate accept this activation, given what the story remembers?**
    ///
    /// The trigger rule above, AND the conditions. The two are combined with AND
    /// deliberately: a condition is a REQUIREMENT the author added to a gate, so
    /// "tap the door once you have the key" cannot be opened by the tap alone.
    ///
    /// Mixed ANY — "a tap OR the key" — is not expressible, and is documented as
    /// a later capability rather than faked. Composing it as OR here would make
    /// the same field mean two opposite things depending on the gate type.
    public static func satisfies(gate: StepGateDTO,
                                 activation: SemanticActivation,
                                 state: some StoryStateReading) -> Bool {
        satisfies(gate: gate, activation: activation) && storyConditionsHold(gate, in: state)
    }

    /// What an assistive-technology user hears and chooses for a waiting gate.
    ///
    /// The author's PROMPT when they wrote one — it is already the sentence they
    /// meant the viewer to act on. Otherwise a plain outcome, never the
    /// implementation trigger name: "Continue" is useful to somebody who cannot
    /// walk to the plinth, and "Approach" is not.
    ///
    /// The accessible route does not pretend the person faced, approached or
    /// grabbed anything. It is the accessible equivalent of satisfying the
    /// authored narrative condition.
    public static func accessibleLabel(prompt: String?) -> String {
        if let prompt, !prompt.isEmpty { return prompt }
        return "Continue"
    }

    public static func accessibleLabel(for gate: StepGateDTO) -> String {
        accessibleLabel(prompt: gate.prompt)
    }
}
