import Foundation

public struct ChapterDefinitionDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var phase: String
    public var steps: [StepDefinitionDTO]
    public var visibility: VisibilityStateDTO
    public var onComplete: CompletionActionDTO

    public init(
        id: String,
        name: String,
        phase: String,
        steps: [StepDefinitionDTO],
        visibility: VisibilityStateDTO = VisibilityStateDTO(),
        onComplete: CompletionActionDTO = .holdOnLastStep
    ) {
        self.id = id
        self.name = name
        self.phase = phase
        self.steps = steps
        self.visibility = visibility
        self.onComplete = onComplete
    }

    public var totalDuration: Double {
        steps.reduce(0) { $0 + $1.duration }
    }
}

public struct StepDefinitionDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var duration: Double
    public var actions: [StepActionDTO]
    public var scheduledActions: [ScheduledActionDTO]
    public var gate: StepGateDTO?

    public init(
        id: String,
        name: String,
        duration: Double,
        actions: [StepActionDTO],
        scheduledActions: [ScheduledActionDTO] = [],
        gate: StepGateDTO? = nil
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.actions = actions
        self.scheduledActions = scheduledActions
        self.gate = gate
    }
}

public struct ScheduledActionDTO: Codable, Sendable, Equatable {
    /// Seconds after the step starts at which `action` fires. 0 = immediate.
    public var at: Double
    public var action: StepActionDTO

    public init(at: Double, action: StepActionDTO) {
        self.at = at
        self.action = action
    }
}

public struct StepGateDTO: Codable, Sendable, Equatable {
    public var type: GateType
    public var timeout: Double?
    public var prompt: String?

    public init(type: GateType, timeout: Double? = nil, prompt: String? = nil) {
        self.type = type
        self.timeout = timeout
        self.prompt = prompt
    }
}

public enum GateType: String, Codable, Sendable, Equatable {
    case tap
    case orchestrator
    case any
}

public enum CompletionActionDTO: Codable, Sendable, Equatable {
    case holdOnLastStep
    case transitionTo(phase: String, visibility: VisibilityStateDTO)
    case autoAdvance(nextChapterId: String)
    case dismissToHome

    private enum CodingKeys: String, CodingKey { case kind, phase, visibility, nextChapterId }
    private enum Kind: String, Codable {
        case holdOnLastStep, transitionTo, autoAdvance, dismissToHome
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .holdOnLastStep:
            try c.encode(Kind.holdOnLastStep, forKey: .kind)
        case .transitionTo(let phase, let visibility):
            try c.encode(Kind.transitionTo, forKey: .kind)
            try c.encode(phase, forKey: .phase)
            try c.encode(visibility, forKey: .visibility)
        case .autoAdvance(let nextChapterId):
            try c.encode(Kind.autoAdvance, forKey: .kind)
            try c.encode(nextChapterId, forKey: .nextChapterId)
        case .dismissToHome:
            try c.encode(Kind.dismissToHome, forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .holdOnLastStep:
            self = .holdOnLastStep
        case .transitionTo:
            self = .transitionTo(
                phase: try c.decode(String.self, forKey: .phase),
                visibility: try c.decode(VisibilityStateDTO.self, forKey: .visibility)
            )
        case .autoAdvance:
            self = .autoAdvance(nextChapterId: try c.decode(String.self, forKey: .nextChapterId))
        case .dismissToHome:
            self = .dismissToHome
        }
    }
}

/// SharedVisions's existing VisibilityState is a fixed snapshot of named entity flags.
/// In the format we generalize to a string-keyed map so any experience can declare its own
/// entity names. Players may use a subset they recognize.
public struct VisibilityStateDTO: Codable, Sendable, Equatable {
    public var entities: [String: Bool]

    public init(_ entities: [String: Bool] = [:]) {
        self.entities = entities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.entities = (try? c.decode([String: Bool].self)) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entities)
    }
}
