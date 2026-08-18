//
//  StoryState.swift
//  ChapterScript
//
//  WHAT THE STORY REMEMBERS.
//
//  A Chapter can now hold a few facts about what the viewer has done — that they
//  heard the radio, that they have found two objects, that they chose the radio
//  route — and read them back later to decide whether the story may continue and
//  where it goes next.
//
//  ── AUTHORED AND RUNTIME ARE DIFFERENT THINGS ───────────────────────────────
//
//      AUTHORED (this file, persisted in the Chapter)
//          the definitions          what facts exist, and of what kind
//          the initial values       what a fresh run starts from
//          the mutations           `StoryStateMutation`, carried by an action
//          the conditions          `StoryCondition` (see StoryCondition.swift)
//
//      RUNTIME (`StoryStateLedger`, never serialized)
//          the current values      what this run has become
//
//  The same separation `InteractionSpec.initiallyEnabled` and
//  `InteractionLedger` already keep. A viewer's progress is not a property of
//  the document, and writing it there would make playing a Chapter dirty it.
//
//  ── IDENTITY IS OPAQUE AND STABLE, DISPLAY IS NOT ───────────────────────────
//
//  A definition has an `id` nothing derives meaning from and a `name` the author
//  reads. A Choice option has the same pair. Renaming “Radio Heard” to
//  “Recording Heard”, or the option “Radio” to “Broadcast”, must not rewrite a
//  single reference — which is only true because every reference stores the id.
//  Maestro has collapsed source, name and identity into one string before; this
//  is written the other way round from the start.
//
//  ── NUMBER IS AN INTEGER ────────────────────────────────────────────────────
//
//  Deliberately, and it is a product decision rather than a storage one. The
//  storytelling uses are counters: objects found, attempts made, clues
//  discovered. `Objects Found` reaching 2 is a narrative fact; `Objects Found`
//  reaching 2.4 is not one an author can author or an audience can perceive.
//  Integers also make the comparison vocabulary honest — with whole numbers,
//  “is more than 2” and “is at least 3” are the same sentence, so the picker
//  offers three comparisons instead of five that hide two duplicates.
//
//  ── A TYPE IS CHOSEN ONCE ───────────────────────────────────────────────────
//
//  `kind` is immutable after creation. Changing Yes/No to Number would leave
//  every mutation and every condition written against it expressing something
//  the state can no longer mean, and the only ways out are to silently discard
//  the author's logic or to invent a translation for it. Neither is defensible,
//  so the editor offers Duplicate-as and Delete instead. See `docs/STORY_STATE.md`.
//

import Foundation

// MARK: - Kind

/// The three things a Story State can be.
///
/// Tolerant, and tolerant in the careful direction: an unrecognised kind becomes
/// `.unsupported` and is re-emitted verbatim, rather than being mapped onto one
/// of the three. The rule `NavigationIntent` learned the hard way — a fallback
/// that parses is not the same as a fallback that MEANS the right thing. A state
/// this build cannot understand holds no value, satisfies no condition and
/// accepts no mutation, and the author is told so.
public enum StoryStateKind: Sendable, Equatable, Hashable {
    /// Something happened, or it did not. Author-facing values are Yes and No.
    case yesNo
    /// A whole-number counter.
    case number
    /// One of a fixed set of authored options, or none of them yet.
    case choice
    /// A kind written by a newer tool. Inert here, preserved on save.
    case unsupported(raw: String)

    /// Stable wire name.
    public var rawName: String {
        switch self {
        case .yesNo:               return "yesNo"
        case .number:              return "number"
        case .choice:              return "choice"
        case .unsupported(let r):  return r
        }
    }

    public var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    /// The three this build can author. `.unsupported` is deliberately absent —
    /// it is a decode outcome, never a choice.
    public static let authorable: [StoryStateKind] = [.yesNo, .number, .choice]
}

extension StoryStateKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "yesNo":  self = .yesNo
        case "number": self = .number
        case "choice": self = .choice
        default:       self = .unsupported(raw: raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawName)
    }
}

// MARK: - Choice option

/// One option of a Choice state.
///
/// `id` is what conditions and mutations store; `name` is what the author and
/// the Inspector read. Renaming the option changes only the second.
public struct StoryChoiceOption: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String = StoryChoiceOption.newID(), name: String) {
        self.id = id
        self.name = name
    }

    public static func newID() -> String { "opt_" + UUID().uuidString.prefix(12).lowercased() }

    private enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? StoryChoiceOption.newID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

// MARK: - Value

/// What a Story State currently holds, or starts from.
///
/// Self-describing: the discriminator is stored rather than inferred from the
/// definition, so a value that arrives without its definition (a sync payload, a
/// hand-edited file) still says what it is instead of being read as whatever the
/// reader expected.
public enum StoryStateValue: Sendable, Equatable, Hashable {
    case yesNo(Bool)
    case number(Int)
    /// The chosen option's id. `nil` = **nothing has been chosen yet**, which is
    /// a real narrative state and not a missing value: before the viewer picks a
    /// route, “Selected Route is Radio” is simply false. This is why an authored
    /// Choice starts unset by default, and why Otherwise has something to do.
    case choice(optionId: String?)
    /// A value written by a newer tool. Never compared, never mutated, preserved.
    case unsupported(kind: String, raw: AnyCodableValue?)

    public var kind: StoryStateKind {
        switch self {
        case .yesNo:   return .yesNo
        case .number:  return .number
        case .choice:  return .choice
        case .unsupported(let kind, _): return .unsupported(raw: kind)
        }
    }

    /// Does this value belong to a state of that kind? Used to refuse a
    /// mismatched mutation rather than coercing one.
    public func matches(_ kind: StoryStateKind) -> Bool { self.kind == kind }

    public var boolValue: Bool? {
        if case .yesNo(let v) = self { return v }
        return nil
    }
    public var numberValue: Int? {
        if case .number(let v) = self { return v }
        return nil
    }
    /// The chosen option id, or nil for “not chosen” AND for a non-Choice value.
    /// Callers that must tell those apart check `kind` first.
    public var choiceValue: String? {
        if case .choice(let id) = self { return id }
        return nil
    }

    /// What a state of this kind holds before anything has happened to it.
    // `AnyCodableValue` is deliberately not `Hashable` (it can hold a
    // dictionary), so hashing uses the DISCRIMINATOR — the same accommodation
    // `NavigationIntent` makes. Equality still compares the retained payload, so
    // two unsupported values that differ only in it stay distinct.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .yesNo(let v):             hasher.combine(0); hasher.combine(v)
        case .number(let v):            hasher.combine(1); hasher.combine(v)
        case .choice(let id):           hasher.combine(2); hasher.combine(id)
        case .unsupported(let kind, _): hasher.combine(3); hasher.combine(kind)
        }
    }

    public static func `default`(for kind: StoryStateKind) -> StoryStateValue {
        switch kind {
        case .yesNo:  return .yesNo(false)
        case .number: return .number(0)
        case .choice: return .choice(optionId: nil)
        case .unsupported(let raw): return .unsupported(kind: raw, raw: nil)
        }
    }
}

extension StoryStateValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, yesNo, number, optionId, raw }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .yesNo(let v):
            try c.encode("yesNo", forKey: .kind)
            try c.encode(v, forKey: .yesNo)
        case .number(let v):
            try c.encode("number", forKey: .kind)
            try c.encode(v, forKey: .number)
        case .choice(let optionId):
            try c.encode("choice", forKey: .kind)
            // An UNSET choice emits no key. `nil` is the absence of a decision,
            // not an option whose id happens to be empty.
            try c.encodeIfPresent(optionId, forKey: .optionId)
        case .unsupported(let kind, let raw):
            try c.encode(kind, forKey: .kind)
            if let raw { try c.encode(raw, forKey: .raw) }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        switch kind {
        case "yesNo":
            self = .yesNo((try? c.decode(Bool.self, forKey: .yesNo)) ?? false)
        case "number":
            self = .number((try? c.decode(Int.self, forKey: .number)) ?? 0)
        case "choice":
            self = .choice(optionId: try? c.decode(String.self, forKey: .optionId))
        default:
            self = .unsupported(kind: kind, raw: try? c.decode(AnyCodableValue.self, forKey: .raw))
        }
    }
}

// MARK: - Definition

/// One authored fact the story can remember.
///
/// CHAPTER-SCOPED. State survives every navigation — Go To, Return, Restart,
/// entering and leaving Explore — and resets only when a new Chapter playback
/// session begins. A Sequence is not where memory lives; if it were, walking out
/// of a room would forget what happened in it.
public struct StoryStateDefinition: Codable, Sendable, Equatable, Identifiable {
    /// Opaque and stable. Nothing derives meaning from its characters, and
    /// nothing displays it.
    public var id: String
    /// What the author reads and renames freely.
    public var name: String
    /// Chosen once, at creation. See the file header.
    public var kind: StoryStateKind
    /// The options, for a Choice. Empty for the other kinds — a field that is
    /// meaningless for a kind is empty rather than absent, so the shape of the
    /// type does not change with its kind.
    public var options: [StoryChoiceOption]
    /// What a fresh Chapter playback session starts from.
    public var initialValue: StoryStateValue

    public init(
        id: String = StoryStateDefinition.newID(),
        name: String,
        kind: StoryStateKind,
        options: [StoryChoiceOption] = [],
        initialValue: StoryStateValue? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.options = kind == .choice ? options : []
        self.initialValue = initialValue ?? .default(for: kind)
    }

    public static func newID() -> String { "sst_" + UUID().uuidString.prefix(12).lowercased() }

    /// The author-facing name, never empty. Falls back to the id ONLY so a
    /// malformed document still shows something selectable; the editor never
    /// lets an author create one without a name.
    public var resolvedName: String { name.isEmpty ? id : name }

    public func option(_ optionId: String) -> StoryChoiceOption? {
        options.first { $0.id == optionId }
    }

    /// The initial value the runtime should actually seed.
    ///
    /// A value whose kind disagrees with the definition's — only reachable by a
    /// hand edit or a newer tool — is REPLACED by the kind's default rather than
    /// coerced. Coercion would invent a narrative fact; the default is the same
    /// thing a state with no authored initial value starts from.
    public var seedValue: StoryStateValue {
        guard initialValue.matches(kind) else { return .default(for: kind) }
        // A Choice pointing at an option that no longer exists starts unset. The
        // reference is still reported by the editor's inventory, so the author
        // sees it; playback simply does not begin somewhere impossible.
        if case .choice(let optionId) = initialValue, let optionId,
           option(optionId) == nil {
            return .choice(optionId: nil)
        }
        return initialValue
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, options, initialValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? StoryStateDefinition.newID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.kind = try c.decodeIfPresent(StoryStateKind.self, forKey: .kind) ?? .yesNo
        self.options = try c.decodeIfPresent([StoryChoiceOption].self, forKey: .options) ?? []
        self.initialValue = try c.decodeIfPresent(StoryStateValue.self, forKey: .initialValue)
            ?? .default(for: self.kind)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        // Absent when empty, so a Yes/No state does not carry an empty array and
        // a Chapter with no Choice states re-saves byte-identically.
        if !options.isEmpty { try c.encode(options, forKey: .options) }
        try c.encode(initialValue, forKey: .initialValue)
    }
}

// MARK: - Mutation

/// What an authored action does to one Story State.
///
/// Deliberately a small closed vocabulary and NOT arithmetic. There is no
/// expression, no formula and no reference to another state's value: `Objects
/// Found` can be set or stepped, and that is the whole of it. An author writing
/// `x = x * 3 + 2` is an author who has been handed a programming language.
public enum StoryStateOperation: Sendable, Equatable, Hashable {
    /// Yes/No — remember that something is now true, or that it is not.
    case setYesNo(Bool)
    /// Number — set the counter to an exact value.
    case setNumber(Int)
    /// Number — step the counter. Negative steps are how Decrease is written;
    /// one case rather than two keeps “by how much” in one place.
    case changeNumber(by: Int)
    /// Choice — record which option the story is now on.
    case setChoice(optionId: String)
    /// An operation written by a newer tool. Does nothing, preserved on save.
    case unsupported(kind: String, raw: AnyCodableValue?)

    /// Which state kind this operation is meaningful for. `nil` for
    /// `.unsupported`, which belongs to no kind this build knows.
    public var appliesTo: StoryStateKind? {
        switch self {
        case .setYesNo:                    return .yesNo
        case .setNumber, .changeNumber:    return .number
        case .setChoice:                   return .choice
        case .unsupported:                 return nil
        }
    }

    // Discriminator hashing; see `StoryStateValue.hash(into:)`.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .setYesNo(let v):          hasher.combine(0); hasher.combine(v)
        case .setNumber(let v):         hasher.combine(1); hasher.combine(v)
        case .changeNumber(let by):     hasher.combine(2); hasher.combine(by)
        case .setChoice(let id):        hasher.combine(3); hasher.combine(id)
        case .unsupported(let kind, _): hasher.combine(4); hasher.combine(kind)
        }
    }
}

extension StoryStateOperation: Codable {
    private enum CodingKeys: String, CodingKey { case kind, yesNo, number, by, optionId, raw }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setYesNo(let v):
            try c.encode("setYesNo", forKey: .kind)
            try c.encode(v, forKey: .yesNo)
        case .setNumber(let v):
            try c.encode("setNumber", forKey: .kind)
            try c.encode(v, forKey: .number)
        case .changeNumber(let by):
            try c.encode("changeNumber", forKey: .kind)
            try c.encode(by, forKey: .by)
        case .setChoice(let optionId):
            try c.encode("setChoice", forKey: .kind)
            try c.encode(optionId, forKey: .optionId)
        case .unsupported(let kind, let raw):
            try c.encode(kind, forKey: .kind)
            if let raw { try c.encode(raw, forKey: .raw) }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        switch kind {
        case "setYesNo":
            self = .setYesNo((try? c.decode(Bool.self, forKey: .yesNo)) ?? true)
        case "setNumber":
            self = .setNumber((try? c.decode(Int.self, forKey: .number)) ?? 0)
        case "changeNumber":
            self = .changeNumber(by: (try? c.decode(Int.self, forKey: .by)) ?? 0)
        case "setChoice":
            self = .setChoice(optionId: (try? c.decode(String.self, forKey: .optionId)) ?? "")
        default:
            self = .unsupported(kind: kind, raw: try? c.decode(AnyCodableValue.self, forKey: .raw))
        }
    }
}

/// One authored change: which state, and what to do to it.
public struct StoryStateMutation: Codable, Sendable, Equatable, Hashable {
    /// The state's stable id. Never its name.
    public var stateId: String
    public var operation: StoryStateOperation

    public init(stateId: String, operation: StoryStateOperation) {
        self.stateId = stateId
        self.operation = operation
    }

    private enum CodingKeys: String, CodingKey { case stateId, operation }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.stateId = try c.decodeIfPresent(String.self, forKey: .stateId) ?? ""
        self.operation = try c.decodeIfPresent(StoryStateOperation.self, forKey: .operation)
            ?? .unsupported(kind: "", raw: nil)
    }
}

// MARK: - Applying an operation

public enum StoryStateArithmetic {

    /// Why a mutation did nothing. Distinguishable, because “nothing happened”
    /// has several meanings and only some of them are the author's mistake.
    public enum Refusal: Error, Sendable, Equatable {
        /// No state with that id is defined in this Chapter.
        case unknownState(String)
        /// The operation is for a different kind of state than the one it names.
        case kindMismatch(stateId: String, expected: StoryStateKind)
        /// The Choice option named is not one of that state's options.
        case unknownOption(stateId: String, optionId: String)
        /// An operation or a state kind this build does not implement.
        case unsupported(String)

        public var message: String {
            switch self {
            case .unknownState(let id):
                return "There is no Story State “\(id)” in this Chapter."
            case .kindMismatch(let id, let expected):
                return "“\(id)” holds a \(expected.rawName) value, so that change cannot be applied to it."
            case .unknownOption(let id, let optionId):
                return "“\(optionId)” is not one of the choices for “\(id)”."
            case .unsupported(let kind):
                return "This version of Maestro does not support “\(kind)”. Nothing happened."
            }
        }
    }

    /// Apply one operation to one value, given its definition.
    ///
    /// PURE. This is the arithmetic both runtimes share, so the Mac's preview and
    /// a headset can never disagree about what tapping the radio did.
    ///
    /// EXHAUSTIVE with no `default`: a new operation must say what it means.
    public static func apply(_ operation: StoryStateOperation,
                             to value: StoryStateValue,
                             definition: StoryStateDefinition) -> Result<StoryStateValue, Refusal> {
        if case .unsupported(let raw) = definition.kind {
            return .failure(.unsupported(raw))
        }
        switch operation {
        case .setYesNo(let flag):
            guard definition.kind == .yesNo else {
                return .failure(.kindMismatch(stateId: definition.id, expected: definition.kind))
            }
            return .success(.yesNo(flag))

        case .setNumber(let n):
            guard definition.kind == .number else {
                return .failure(.kindMismatch(stateId: definition.id, expected: definition.kind))
            }
            return .success(.number(n))

        case .changeNumber(let by):
            guard definition.kind == .number else {
                return .failure(.kindMismatch(stateId: definition.id, expected: definition.kind))
            }
            // Saturating rather than trapping. A counter is a narrative device;
            // an hour-long chapter that somehow steps one four billion times
            // should hold at the top, not crash the experience.
            let current = value.numberValue ?? 0
            return .success(.number(current.addingReportingOverflow(by).overflow
                                    ? (by > 0 ? Int.max : Int.min)
                                    : current &+ by))

        case .setChoice(let optionId):
            guard definition.kind == .choice else {
                return .failure(.kindMismatch(stateId: definition.id, expected: definition.kind))
            }
            guard definition.option(optionId) != nil else {
                return .failure(.unknownOption(stateId: definition.id, optionId: optionId))
            }
            return .success(.choice(optionId: optionId))

        case .unsupported(let kind, _):
            return .failure(.unsupported(kind))
        }
    }
}
