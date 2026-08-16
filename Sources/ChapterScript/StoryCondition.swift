//
//  StoryCondition.swift
//  ChapterScript
//
//  READING WHAT THE STORY REMEMBERS.
//
//  A condition asks one question of one Story State. A group asks several and
//  says whether ALL or ANY of them must hold. That is the entire model:
//
//      Match All                       Match Any
//          Radio Heard is Yes              Radio Heard is Yes
//          Objects Found is at least 2     Camera Examined is Yes
//
//  ── DELIBERATELY NOT AN EXPRESSION LANGUAGE ─────────────────────────────────
//
//  Exactly one level. No nesting, no parentheses, no mixed AND/OR hierarchy, no
//  arithmetic on the right-hand side, and no condition that compares one state
//  to another. Every one of those is a small, reasonable-looking step, and the
//  sum of them is a scripting language inside a film editor. An author writing
//  a documentary should be able to read a whole condition group out loud.
//
//  ── ONE EVALUATOR, TWO RUNTIMES ─────────────────────────────────────────────
//
//  `GateActivation.satisfies` established the shape: whether a story advances is
//  arithmetic over authored values, so it lives in the format package and both
//  the Mac's preview and `ChapterPlayer` call it. Two implementations of "is
//  Objects Found at least 2" is two chances to disagree, and the disagreement
//  would only ever be discovered on a headset.
//

import Foundation

// MARK: - Reading current values

/// Whatever can answer “what does this Story State hold right now?”.
///
/// The evaluator takes this rather than a concrete store, so the runtime ledger,
/// a Mac preview and a test fixture all evaluate through one implementation.
public protocol StoryStateReading {
    /// The current value, or `nil` when the Chapter defines no such state.
    /// `nil` is not “false” — it is a reference the author needs to repair, and
    /// the evaluator reports it rather than quietly answering no.
    func storyStateValue(_ stateId: String) -> StoryStateValue?
}

/// A plain dictionary reads as a state store. Useful for tests, for evaluating
/// against a hypothetical, and for the initial values of a Chapter.
extension Dictionary: StoryStateReading where Key == String, Value == StoryStateValue {
    public func storyStateValue(_ stateId: String) -> StoryStateValue? { self[stateId] }
}

// MARK: - Comparisons

/// How a Number is compared.
///
/// THREE, not five. Numbers are whole (see `StoryState.swift`), so “is more
/// than 2” and “is at least 3” are the same sentence — offering both would put
/// two spellings of one idea in the same menu and leave the author choosing
/// between them for no reason.
public enum StoryNumberComparison: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case equals
    case atLeast
    case atMost

    public func holds(_ value: Int, _ operand: Int) -> Bool {
        switch self {
        case .equals:  return value == operand
        case .atLeast: return value >= operand
        case .atMost:  return value <= operand
        }
    }
}

/// The right-hand side of one condition.
///
/// Which comparisons are available is decided by the state's KIND, and the
/// editor never offers a combination that cannot be true — “Radio Heard is at
/// least 3” is not authorable, rather than authorable and then refused at
/// runtime.
public enum StoryComparison: Sendable, Equatable, Hashable {
    /// Yes/No — “is Yes” (`true`) or “is No” (`false`).
    case yesNo(Bool)
    case number(StoryNumberComparison, Int)
    /// Choice — “is” (`matches: true`) or “is not” this option.
    case choice(matches: Bool, optionId: String)
    /// A comparison written by a newer tool. Never satisfied, preserved on save,
    /// and reported to the author rather than being read as one of the above.
    case unsupported(kind: String, raw: AnyCodableValue?)

    /// Which state kind this comparison belongs to. `nil` for `.unsupported`.
    public var appliesTo: StoryStateKind? {
        switch self {
        case .yesNo:       return .yesNo
        case .number:      return .number
        case .choice:      return .choice
        case .unsupported: return nil
        }
    }

    // Discriminator hashing; see `StoryStateValue.hash(into:)`.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .yesNo(let flag):
            hasher.combine(0); hasher.combine(flag)
        case .number(let comparison, let operand):
            hasher.combine(1); hasher.combine(comparison); hasher.combine(operand)
        case .choice(let matches, let optionId):
            hasher.combine(2); hasher.combine(matches); hasher.combine(optionId)
        case .unsupported(let kind, _):
            hasher.combine(3); hasher.combine(kind)
        }
    }
}

extension StoryComparison: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, yesNo, comparison, number, matches, optionId, raw
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .yesNo(let flag):
            try c.encode("yesNo", forKey: .kind)
            try c.encode(flag, forKey: .yesNo)
        case .number(let comparison, let operand):
            try c.encode("number", forKey: .kind)
            try c.encode(comparison, forKey: .comparison)
            try c.encode(operand, forKey: .number)
        case .choice(let matches, let optionId):
            try c.encode("choice", forKey: .kind)
            try c.encode(matches, forKey: .matches)
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
        case "yesNo":
            self = .yesNo((try? c.decode(Bool.self, forKey: .yesNo)) ?? true)
        case "number":
            // An unrecognised comparison is NOT silently `.equals`: it becomes
            // unsupported, because “at least 2” quietly read as “exactly 2” is a
            // gate that never opens and a branch that never fires.
            guard let comparison = try? c.decode(StoryNumberComparison.self, forKey: .comparison)
            else {
                self = .unsupported(kind: kind,
                                    raw: try? c.decode(AnyCodableValue.self, forKey: .raw))
                return
            }
            self = .number(comparison, (try? c.decode(Int.self, forKey: .number)) ?? 0)
        case "choice":
            self = .choice(matches: (try? c.decode(Bool.self, forKey: .matches)) ?? true,
                           optionId: (try? c.decode(String.self, forKey: .optionId)) ?? "")
        default:
            self = .unsupported(kind: kind, raw: try? c.decode(AnyCodableValue.self, forKey: .raw))
        }
    }
}

// MARK: - Condition

/// One question about one Story State.
public struct StoryCondition: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Stable, so an editor can reorder and edit a list of conditions without
    /// identity being an array index.
    public var id: String
    /// The state's stable id. Never its name.
    public var stateId: String
    public var comparison: StoryComparison

    public init(id: String = StoryCondition.newID(),
                stateId: String,
                comparison: StoryComparison) {
        self.id = id
        self.stateId = stateId
        self.comparison = comparison
    }

    public static func newID() -> String { "cnd_" + UUID().uuidString.prefix(12).lowercased() }

    private enum CodingKeys: String, CodingKey { case id, stateId, comparison }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? StoryCondition.newID()
        self.stateId = try c.decodeIfPresent(String.self, forKey: .stateId) ?? ""
        self.comparison = try c.decodeIfPresent(StoryComparison.self, forKey: .comparison)
            ?? .unsupported(kind: "", raw: nil)
    }
}

/// Several conditions, and whether all or any of them must hold.
public struct StoryConditionGroup: Codable, Sendable, Equatable, Hashable {

    public enum Match: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
        case all
        case any

        /// Tolerant: an unknown match mode falls back to `all`, the STRICTER of
        /// the two. A group that should have opened on any one condition and
        /// instead waits for every one is a story that pauses; the reverse is a
        /// story that runs ahead of what the author checked for.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Match(rawValue: raw) ?? .all
        }
    }

    public var match: Match
    public var conditions: [StoryCondition]

    public init(match: Match = .all, conditions: [StoryCondition] = []) {
        self.match = match
        self.conditions = conditions
    }

    public var isEmpty: Bool { conditions.isEmpty }

    private enum CodingKeys: String, CodingKey { case match, conditions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.match = try c.decodeIfPresent(Match.self, forKey: .match) ?? .all
        self.conditions = try c.decodeIfPresent([StoryCondition].self, forKey: .conditions) ?? []
    }
}

// MARK: - Evaluation

public enum StoryConditionEvaluator {

    /// Why a condition could not be answered as written. Empty for a condition
    /// that simply is not true yet — that is an ordinary narrative state, not a
    /// problem.
    public enum Problem: Sendable, Equatable {
        /// The condition names a Story State the Chapter does not define.
        case unknownState(String)
        /// The comparison is for a different kind than the state holds.
        case kindMismatch(stateId: String, held: StoryStateKind)
        /// A comparison this build does not implement.
        case unsupported(String)

        public var message: String {
            switch self {
            case .unknownState(let id):
                return "This condition refers to a Story State (“\(id)”) that is not in this Chapter."
            case .kindMismatch(let id, let held):
                return "“\(id)” holds a \(held.rawName) value, which this condition cannot compare."
            case .unsupported(let kind):
                return "This version of Maestro does not support the condition “\(kind)”."
            }
        }
    }

    /// Is ONE condition true right now?
    ///
    /// A condition that cannot be answered is FALSE and carries a problem. It is
    /// never treated as true: a gate whose condition refers to a deleted state
    /// must not silently open, and a branch must not silently fire.
    ///
    /// EXHAUSTIVE with no `default`.
    public static func evaluate(_ condition: StoryCondition,
                                in state: some StoryStateReading)
    -> (satisfied: Bool, problem: Problem?) {
        guard let value = state.storyStateValue(condition.stateId) else {
            return (false, .unknownState(condition.stateId))
        }
        switch condition.comparison {
        case .yesNo(let expected):
            guard let held = value.boolValue else {
                return (false, .kindMismatch(stateId: condition.stateId, held: value.kind))
            }
            return (held == expected, nil)

        case .number(let comparison, let operand):
            guard let held = value.numberValue else {
                return (false, .kindMismatch(stateId: condition.stateId, held: value.kind))
            }
            return (comparison.holds(held, operand), nil)

        case .choice(let matches, let optionId):
            guard value.kind == .choice else {
                return (false, .kindMismatch(stateId: condition.stateId, held: value.kind))
            }
            // An UNSET choice is not equal to any option, and IS “not Radio”.
            // Both readings are the honest one: before the viewer chooses, the
            // route is not Radio.
            let isThatOption = value.choiceValue == optionId
            return (matches ? isThatOption : !isThatOption, nil)

        case .unsupported(let kind, _):
            return (false, .unsupported(kind))
        }
    }

    /// Is the whole group satisfied?
    ///
    /// AN EMPTY GROUP IS SATISFIED, in both modes. A gate carrying no conditions
    /// imposes no story requirement, and “Match Any of nothing” blocking forever
    /// would turn removing the last condition into a deadlock. Authoring removes
    /// the group rather than leaving an empty one, so this is a safety net for
    /// hand-edited and peer-authored documents.
    public static func evaluate(_ group: StoryConditionGroup,
                                in state: some StoryStateReading) -> Bool {
        guard !group.conditions.isEmpty else { return true }
        switch group.match {
        case .all:
            return group.conditions.allSatisfy { evaluate($0, in: state).satisfied }
        case .any:
            return group.conditions.contains { evaluate($0, in: state).satisfied }
        }
    }

    /// Everything wrong with a group, for the author. Order follows the authored
    /// conditions so a reported problem can be pointed at.
    public static func problems(_ group: StoryConditionGroup,
                                in state: some StoryStateReading)
    -> [(condition: StoryCondition, problem: Problem)] {
        group.conditions.compactMap { condition in
            guard let problem = evaluate(condition, in: state).problem else { return nil }
            return (condition, problem)
        }
    }
}
