//
//  Interaction.swift
//  ChapterScript
//
//  WHAT THE VIEWER DOES TO A THING, AND WHAT THE THING DOES BACK.
//
//  A GATE AND AN INTERACTION ARE NOT THE SAME IDEA.
//
//      Gate         a place authored progression can stall. The story does not
//                   continue until the condition is met. It lives on a STEP.
//      Interaction  the viewer does something to an OBJECT and the object
//                   responds. The story carries on exactly where it was.
//
//  Before this file existed only the first could be expressed, which is why
//  every interactive idea had to be described as a gate — and a gate is a
//  terrible way to say "tapping the radio plays the broadcast", because it
//  stops the film to do it. An interaction attaches to the object, not to the
//  timeline position, and answering "what does this thing do?" is then a
//  property of the thing.
//
//  ONE RESPONSE VOCABULARY, NOT TWO.
//
//  `actions` is `[StepActionDTO]` — the same list a step fires. There is no
//  second engine, no interaction-only action set, and no `playAudioOnTap`.
//  The interaction decides WHEN an existing behaviour runs; it never redefines
//  what that behaviour means. Editors curate which of those cases they OFFER
//  (see `MaestroKit.InteractionResponse`), which is a UI decision and not a
//  format one.
//
//  LIFETIME IS PART OF THE MODEL, NOT AN AFTERTHOUGHT.
//
//  A step action is a one-shot event at a fixed second, so nothing in the
//  format has ever had to answer "and if they do it again?". An object the
//  viewer can tap five times must answer it, and must answer it the same way in
//  both editors and on device — so `lifetime` ships with the first interaction
//  rather than being inferred later from a default nobody wrote down.
//
//  DETECTION IS SHARED WITH GATES.
//
//  `.viewerFacing`, `.approach` and `.grab` mean exactly what the matching
//  `GateType` cases mean, and `ChapterPlayer` runs them through one detector. A
//  second facing/proximity/grab implementation would double the device-QA
//  surface for no new capability.
//
//  MAESTRO DOES NOT KNOW WHERE THE VIEWER IS LOOKING.
//
//  SYSTEM-EYE-INPUT: visionOS deliberately does not give an app precise eye
//  movement or line of sight. The system's own hover effect can respond to
//  actual eye input, but it does so OUTSIDE the app process and the app receives
//  no event from it — a privacy guarantee, not a limitation to work around.
//
//  So `.viewerFacing` is named for what Maestro can actually measure: the
//  VIEWER'S FORWARD SPATIAL DIRECTION (the device pose) held within a cone
//  around the target for a dwell time. SYSTEM-EYE-INPUT: naming it after the
//  eyes would be a claim the product cannot keep, in a category — storytelling
//  for museums, documentary and education — where an author may be making
//  promises to an audience about what is being sensed.
//
//  A future agent reading a discrepancy between the system highlight and
//  `.viewerFacing` must NOT "fix" it by trying to obtain eye data. The two
//  signals are different by design and are allowed to disagree.
//

import Foundation

// MARK: - Trigger

/// What the viewer does. Deliberately the same four things a spatial gate
/// watches for, because they are the same four things a person can do to an
/// object in a headset.
///
/// Encoded as a keyed object (`{"kind": "viewerFacing", "dwell": 1.2}`) rather
/// than a bare string, because two of the four carry a parameter. An unknown
/// kind decodes as `.tap` — the same degradation rule `GateType`, `EntityKind`
/// and `ImmersiveField` follow, and for the same reason: a document written by a
/// newer tool must not fail to open.
public enum InteractionTrigger: Sendable, Equatable, Hashable {
    /// The viewer explicitly activates the object with a supported
    /// selection input.
    case tap
    /// THE VIEWER'S FORWARD DIRECTION STAYS ON THE OBJECT for `dwell` seconds.
    ///
    /// **SYSTEM-EYE-INPUT: this is not eye tracking.** It is derived from the
    /// device/view orientation — where the viewer's head is pointed — held
    /// inside a cone around the target. Maestro never receives the viewer's
    /// precise line of sight, and no part of this product may imply it does.
    ///
    /// `nil` = the player's default (1 s), so a document does not have to
    /// restate a number it never chose.
    case viewerFacing(dwell: Double?)
    /// Come within `radius` metres of the object, measured horizontally.
    /// `nil` = the player's default (1 m).
    case approach(radius: Float?)
    /// A new pinch-grab of the object begins.
    case grab

    /// Stable wire name, also the value editors switch on for icons/labels.
    public var kindName: String {
        switch self {
        case .tap:           return "tap"
        case .viewerFacing:  return "viewerFacing"
        case .approach:      return "approach"
        case .grab:          return "grab"
        }
    }

    /// True when the trigger needs the viewer's head pose or hands — i.e. when
    /// a Mac preview is a SIMULATION rather than the real thing, AND when an
    /// assistive-technology user needs an accessible equivalent because the
    /// physical act may not be available to them.
    public var requiresSpatialInput: Bool {
        switch self {
        case .tap:  return false
        case .viewerFacing, .approach, .grab: return true
        }
    }
}

extension InteractionTrigger: Codable {
    private enum CodingKeys: String, CodingKey { case kind, dwell, radius }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindName, forKey: .kind)
        switch self {
        case .tap, .grab:
            break
        case .viewerFacing(let dwell):
            // An UNSET parameter emits no key. `nil` is not "the default
            // number" — it is the absence of an authored choice, and writing
            // the player's current default would freeze it into the document.
            try c.encodeIfPresent(dwell, forKey: .dwell)
        case .approach(let radius):
            try c.encodeIfPresent(radius, forKey: .radius)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        // LEGACY-INTERACTION-VOCAB: the two spellings the
        // first Phase 6 build wrote. They decode to `.viewerFacing` and are
        // never written again. They are compatibility vocabulary — nothing in
        // this build treats either as a claim about the viewer's eyes.
        case "viewerFacing", "look", "gaze":   // LEGACY-INTERACTION-VOCAB
            self = .viewerFacing(dwell: try c.decodeIfPresent(Double.self, forKey: .dwell))
        case "approach":
            self = .approach(radius: try c.decodeIfPresent(Float.self, forKey: .radius))
        case "grab":
            self = .grab
        default:
            self = .tap
        }
    }
}

// MARK: - Lifetime

/// How often an interaction may respond.
///
/// Only two values ship, and both are fully implemented end to end. The enum is
/// open to more (`whileActive`, `onEnter`, `onExit` are the named candidates in
/// `docs/TIMELINE_3_0.md` D7) — but a case with no runtime is UI that lies, so
/// they arrive with their semantics, not before.
public enum InteractionLifetime: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Responds the first time and never again for the rest of the Sequence.
    case once
    /// Responds every time the viewer does it.
    case everyTime

    /// Tolerant decode. An unknown lifetime falls back to `.once`, which is the
    /// SAFER of the two: a response that should have repeated and did not is a
    /// missing beat, while one that repeats when the author said "only once"
    /// can retrigger narration over itself.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InteractionLifetime(rawValue: raw) ?? .once
    }
}

// MARK: - Interaction

/// One authored behaviour on a scene object: a trigger, how often it may fire,
/// and what happens.
///
/// **`id` is opaque and stable.** It survives save/reopen, reorder, edits to a
/// sibling interaction, sync, undo/redo, placeholder replacement and rename —
/// which is exactly the list of things that break when identity is an array
/// index. Nothing derives meaning from its characters.
public struct InteractionSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Author-facing label. `nil` = editors describe it from its trigger and
    /// response ("On Tap → Play Audio"), which is what most interactions want.
    public var name: String?
    public var trigger: InteractionTrigger
    public var lifetime: InteractionLifetime
    /// THE STATE A FRESH SEQUENCE VISIT STARTS FROM. Authored, persisted.
    ///
    /// Deliberately not `isEnabled`. That name invited being read as "is it on
    /// right now", which is a property of a playback session and not of the
    /// document — and `enableInteraction` at runtime must never write back
    /// here. The runtime's changing answer lives in `InteractionRuntime`.
    public var initiallyEnabled: Bool
    /// The response, in the ONE action vocabulary. Ordered: they run in
    /// sequence, exactly as a step's actions do.
    public var actions: [StepActionDTO]
    /// Spoken label override for assistive technology. `nil` = derived from the
    /// object's `displayName`, which is a far better default than an entity id
    /// (see `InteractionSemantics`).
    public var accessibilityLabel: String?
    /// Spoken hint override — what happens if you activate it. `nil` = derived
    /// from the response.
    public var accessibilityHint: String?

    public init(
        id: String = InteractionSpec.newID(),
        name: String? = nil,
        trigger: InteractionTrigger = .tap,
        lifetime: InteractionLifetime = .everyTime,
        initiallyEnabled: Bool = true,
        actions: [StepActionDTO] = [],
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.lifetime = lifetime
        self.initiallyEnabled = initiallyEnabled
        self.actions = actions
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }

    /// Mint a fresh opaque id. Same shape as `AuthoredAction.newID()` so the
    /// document reads consistently.
    public static func newID() -> String { "ix_" + UUID().uuidString.prefix(12).lowercased() }

    private enum CodingKeys: String, CodingKey {
        case id, name, trigger, lifetime, initiallyEnabled, actions
        case accessibilityLabel, accessibilityHint
        /// LEGACY-INTERACTION-VOCAB: the first Phase 6 build's spelling.
        /// Decoded, never written.
        case isEnabled
    }

    /// Tolerant throughout: everything but `id` has a defensible default, so a
    /// partially-understood interaction still loads as something the author can
    /// see and repair rather than taking the document with it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? InteractionSpec.newID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.trigger = try c.decodeIfPresent(InteractionTrigger.self, forKey: .trigger) ?? .tap
        self.lifetime = try c.decodeIfPresent(InteractionLifetime.self, forKey: .lifetime) ?? .everyTime
        self.initiallyEnabled = try c.decodeIfPresent(Bool.self, forKey: .initiallyEnabled)
            ?? c.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? true
        self.actions = try c.decodeIfPresent([StepActionDTO].self, forKey: .actions) ?? []
        self.accessibilityLabel = try c.decodeIfPresent(String.self, forKey: .accessibilityLabel)
        self.accessibilityHint = try c.decodeIfPresent(String.self, forKey: .accessibilityHint)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(lifetime, forKey: .lifetime)
        try c.encode(initiallyEnabled, forKey: .initiallyEnabled)
        try c.encode(actions, forKey: .actions)
        try c.encodeIfPresent(accessibilityLabel, forKey: .accessibilityLabel)
        try c.encodeIfPresent(accessibilityHint, forKey: .accessibilityHint)
    }
}

// MARK: - Feedback

/// How an interactive object tells the viewer it can be interacted with.
///
/// **This is not a trigger.** A viewer looking at an interactive door may see a
/// focus treatment; that does not mean the door's Face Toward interaction has
/// fired. Feedback communicates AVAILABILITY; the trigger is the act. Keeping
/// them separate is what stops "it lit up" from meaning "it happened".
public enum InteractionFeedbackStyle: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Whatever the platform does for an interactive object by default. The
    /// right answer nearly always, and the one that keeps following the system
    /// as the system changes.
    case automatic
    /// No visual affordance. For objects whose interactivity is established by
    /// the story rather than by the surface — and never a way to make something
    /// secretly interactive: the accessibility semantics are unaffected.
    case none
    /// A distinct, clearly-visible treatment. The choice when the object sits
    /// against busy immersive footage and the default is too polite.
    case highlight
    /// A restrained treatment for calm material — museums, documentary,
    /// anything where a bright rim would read as a UI element in a film.
    case gentle

    /// Tolerant decode: an unknown style falls back to `.automatic`, which is
    /// the one value guaranteed to produce a sensible affordance on any build.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InteractionFeedbackStyle(rawValue: raw) ?? .automatic
    }
}

/// The authored feedback CHOICE. Whether the viewer is hovering right now is
/// transient runtime state and is never stored here, never synced, and never
/// dirties the document.
public struct InteractionFeedbackSpec: Codable, Sendable, Equatable, Hashable {
    public var style: InteractionFeedbackStyle
    /// 0…1 strength for the styles that have one. `nil` = the style's own
    /// default. Ignored by `.automatic` and `.none`, which have nothing to
    /// scale — exposing a slider for them would be a control that does nothing.
    public var intensity: Float?

    public init(style: InteractionFeedbackStyle = .automatic, intensity: Float? = nil) {
        self.style = style
        self.intensity = intensity
    }

    public static let automatic = InteractionFeedbackSpec()

    private enum CodingKeys: String, CodingKey { case style, intensity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.style = try c.decodeIfPresent(InteractionFeedbackStyle.self, forKey: .style) ?? .automatic
        self.intensity = try c.decodeIfPresent(Float.self, forKey: .intensity)
    }
}

// MARK: - Semantics

/// Accessible identity for an interactive object, derived from AUTHORED data.
///
/// The default that matters: an object's `displayName` ("Door to Gallery") is a
/// far stronger spoken label than its opaque id (`ent_9f2c…`) or a filename
/// (`door_final_v3.usdz`). Both editors and the runtime derive it here so a
/// VoiceOver user, a Mac author reading the Inspector and the device agree.
public enum InteractionSemantics {

    /// What the object is called, for assistive technology.
    public static func label(for interaction: InteractionSpec, entity: EntityDefinition) -> String {
        if let authored = interaction.accessibilityLabel, !authored.isEmpty { return authored }
        if let name = interaction.name, !name.isEmpty { return name }
        return entity.resolvedDisplayName
    }

    /// What activating it will do — the SPOKEN half of the affordance, and the
    /// reason feedback is never allowed to be visual-only.
    public static func hint(for interaction: InteractionSpec) -> String {
        if let authored = interaction.accessibilityHint, !authored.isEmpty { return authored }
        let verb = triggerPhrase(interaction.trigger)
        guard let first = interaction.actions.first else { return verb }
        return verb + " to " + responsePhrase(first).lowercased()
    }

    /// Plain-language name of the trigger, used in hints and in both editors'
    /// summaries so one wording exists.
    public static func triggerPhrase(_ trigger: InteractionTrigger) -> String {
        switch trigger {
        case .tap:           return "Tap"
        // "Face Toward", never "Look at": the product must not describe a
        // device-orientation measurement as if it knew where the eyes were.
        case .viewerFacing:  return "Face Toward"
        case .approach:      return "Approach"
        case .grab:          return "Grab"
        }
    }

    /// Plain-language name of ONE response. Deliberately short — it is a row
    /// label and a spoken hint, not documentation.
    public static func responsePhrase(_ action: StepActionDTO) -> String {
        switch action {
        case .showEntity(let n):     return "Show \(n)"
        case .hideEntity(let n):     return "Hide \(n)"
        case .revealEntity(let r):   return "Reveal \(r.entity)"
        case .fadeEntity(let f):     return "Fade \(f.entity)"
        case .moveEntity(let m):     return "Move \(m.entity)"
        case .scaleEntity(let n, _, _, _): return "Scale \(n)"
        case .animateMotion(let m):  return "Animate \(m.entity)"
        case .playAudio(let a):      return "Play \(a.file)"
        case .stopAudio:             return "Stop audio"
        case .fadeAudio:             return "Fade audio"
        case .playVideo(let v):      return "Play \(v.file)"
        case .prepareVideo(let v):   return "Prepare \(v.file)"
        case .stopVideo:             return "Stop video"
        case .enableGesture(let n):  return "Make \(n) grabbable"
        case .disableGesture(let n): return "Make \(n) fixed"
        case .persistEntity(let n):  return "Keep \(n)"
        case .unpersistEntity(let n): return "Release \(n)"
        case .enableInteraction(let entity, _):  return "Turn on an interaction on \(entity)"
        case .disableInteraction(let entity, _): return "Turn off an interaction on \(entity)"
        // NAVIGATION IS NOT "AN ACTION". It fell into the default below, so the
        // single most consequential response an object can carry — the one that
        // moves the audience to another Sequence — was labelled "Run action" in
        // the Inspector row, the Timeline badge and the spoken hint alike.
        //
        // The Sequence is named by its ID here because this package has no
        // Chapter to resolve a display name against; editors that DO have one
        // resolve it (`SequenceTargetPicker`) and never show the id.
        case .navigate(let intent):
            switch intent {
            case .goTo(let id):     return "Go to \(id)"
            case .back(let policy): return policy == .resume ? "Return" : "Return and restart"
            case .restart:          return "Restart this Sequence"
            case .end:              return "End the Chapter"
            case .start:            return "Go to the start"
            case .unsupported:      return "Unsupported navigation"
            // A DECISION, not a destination. The Inspector draws the cases; a
            // one-line phrase says what kind of thing this is, and never picks
            // one branch to name as if it were the answer.
            case .branch:           return "Go somewhere based on the story"
            }
        // WHAT THE STORY REMEMBERS. Named by state ID here for the same reason
        // navigation is: this package has no Chapter to resolve a display name
        // against. Editors that DO have one resolve it and never show the id.
        case .setStoryState(let mutation):
            switch mutation.operation {
            case .setYesNo(let flag):    return flag ? "Remember \(mutation.stateId)"
                                                     : "Forget \(mutation.stateId)"
            case .setNumber:             return "Set \(mutation.stateId)"
            case .changeNumber(let by):  return by < 0 ? "Decrease \(mutation.stateId)"
                                                       : "Increase \(mutation.stateId)"
            case .setChoice:             return "Set \(mutation.stateId)"
            case .unsupported:           return "Unsupported story change"
            }
        // A DISPLAY default, not a walk. Every case that carries an entity or a
        // file is named above; the rest are buses, zones, attachments and
        // system flags, none of which an interaction row needs to spell out.
        default:                     return "Run action"
        }
    }
}
