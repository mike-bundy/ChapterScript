import Foundation

public struct SequenceDefinitionDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var phase: String
    /// Whether this sequence expects the player to be in an immersive space
    /// or in a flat / windowed presentation. Players consult this on sequence
    /// start to open / dismiss the immersive space as the experience moves
    /// between presentation modes.
    public var presentation: SequencePresentation
    /// Optional immersive backdrop (skybox video or USDZ scene) shown while
    /// this sequence plays. Only meaningful when `presentation == .immersive`;
    /// players may ignore for `.windowed` sequences.
    public var immersiveBackdrop: ImmersiveBackdropSpec?
    public var steps: [StepDefinitionDTO]
    /// Sequence-level keyframe animation, one track per animated entity.
    /// Keys sit at absolute seconds from sequence start — independent of the
    /// step grid, so retiming steps never bends an animation curve.
    public var animationTracks: [EntityAnimationTrack]
    /// Sequence-level audio automation, one track per audio channel plus an
    /// optional `master` bus track. Keys sit at absolute seconds from sequence
    /// start, exactly like `animationTracks` — so a volume ride survives step
    /// retiming, and the same curve editor edits both.
    public var audioTracks: [AudioAutomationTrack]

    /// Keyframed stereo presentation per video DESTINATION — convergence.
    /// Keyed by the screen rather than by an entity for the reason set out in
    /// `SequenceStereoAutomation`: convergence belongs to the media on a
    /// screen, not to the screen.
    public var stereoTracks: [StereoAutomationTrack]
    /// Timed backdrop changes. Each cue runs from its `startTime` until the
    /// next one begins, so exactly one backdrop is ever active — exclusivity
    /// by construction rather than by validation. Empty means "use
    /// `immersiveBackdrop` for the whole sequence", which is what every
    /// document written before this existed says.
    public var backdropTrack: [BackdropCue]
    /// EXPLORE SPANS — the parts of this Sequence where the viewer may look
    /// around and narrative progression may stall at the span's boundary.
    ///
    /// Empty means the Sequence is entirely DIRECTED, which is what every
    /// document written before Story Regions existed says and what most
    /// Sequences will always say. Directed is the ABSENCE of a region, never a
    /// region of its own — an author never draws a block to get ordinary
    /// playback. See `StoryRegion`.
    public var storyRegions: [StoryRegion]
    /// SEQUENCE-LOCAL REST PLACEMENT, keyed by entity id: where an
    /// object sits IN THIS SEQUENCE when nothing animates it.
    ///
    /// The entity's own `transform` is the Chapter-global rest — one
    /// object, one pose, every Sequence. That was the recorded defect
    /// (EDITOR_CONTRACTS §18): moving a prop at rest in Sequence 1
    /// silently moved it in Sequences 2 and 3. An entry here OVERRIDES
    /// the global rest for this Sequence only; an absent entry falls
    /// back to it, so every existing Chapter behaves identically.
    ///
    /// Additive and tolerant: `nil` (every document written before this
    /// existed) emits NO key on save, and an emptied map normalizes to
    /// `nil` (`didSet`) so a Chapter never told about local placement
    /// re-saves byte-identically. Animation composes ON TOP of the
    /// resolved rest — keys still override channels wholesale, and a
    /// keyed channel never reads rest at all.
    ///
    /// This map is AUTHORED CONTENT (document truth, synced, undoable) —
    /// never a place for editor view state, Stage scale, or Viewer
    /// alignment offsets.
    public var restPlacements: [String: TransformData]? {
        didSet { if restPlacements?.isEmpty == true { restPlacements = nil } }
    }
    public var visibility: VisibilityStateDTO
    public var onComplete: CompletionActionDTO
    /// EDITOR-ONLY organizational color, as an index into the authoring
    /// tool's sequence palette. `nil` means "no explicit color" — editors
    /// fall back to coloring by sequence position.
    ///
    /// Runtime MUST ignore this. It exists so an author can color-code a
    /// long chapter in Chapter Studio / ChapterVision and have that survive
    /// save, reopen, and live sync. It has no visual effect on playback and
    /// ChapterPlayer never reads it.
    ///
    /// An index rather than an RGB triple, so the two editors agree on the
    /// same palette and a color can't arrive as an unrenderable value.
    public var editorColorIndex: Int?

    public init(
        id: String,
        name: String,
        phase: String,
        presentation: SequencePresentation = .immersive,
        immersiveBackdrop: ImmersiveBackdropSpec? = nil,
        steps: [StepDefinitionDTO],
        animationTracks: [EntityAnimationTrack] = [],
        audioTracks: [AudioAutomationTrack] = [],
        stereoTracks: [StereoAutomationTrack] = [],
        backdropTrack: [BackdropCue] = [],
        storyRegions: [StoryRegion] = [],
        restPlacements: [String: TransformData]? = nil,
        visibility: VisibilityStateDTO = VisibilityStateDTO(),
        onComplete: CompletionActionDTO = .holdOnLastStep,
        editorColorIndex: Int? = nil
    ) {
        self.editorColorIndex = editorColorIndex
        self.id = id
        self.name = name
        self.phase = phase
        self.presentation = presentation
        self.immersiveBackdrop = immersiveBackdrop
        self.steps = steps
        self.animationTracks = animationTracks
        self.audioTracks = audioTracks
        self.stereoTracks = stereoTracks
        self.backdropTrack = backdropTrack
        self.storyRegions = storyRegions
        self.restPlacements = (restPlacements?.isEmpty == true) ? nil : restPlacements
        self.visibility = visibility
        self.onComplete = onComplete
    }

    public var totalDuration: Double {
        steps.reduce(0) { $0 + $1.duration }
    }

    /// THE one resolution of an entity's rest pose in this Sequence:
    /// the Sequence-local placement when one exists, the given
    /// Chapter-global rest otherwise. Every consumer — evaluator hosts,
    /// editors, the runtime — resolves through this so no two surfaces
    /// can disagree about where an unanimated object sits.
    public func restTransform(for entityId: String, chapterRest: TransformData) -> TransformData {
        restPlacements?[entityId] ?? chapterRest
    }

    // Decode-if-present for `presentation` and `immersiveBackdrop` so docs
    // authored before this format revision keep loading. `phase` is kept
    // independent — it remains a free-form routing tag — but if a legacy
    // doc explicitly used `phase == "windowed"`, fall back to that.
    private enum CodingKeys: String, CodingKey {
        case id, name, phase, presentation, immersiveBackdrop
        case steps, animationTracks, audioTracks, stereoTracks, backdropTrack, visibility, onComplete
        case storyRegions
        case restPlacements
        case editorColorIndex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        let phase = try c.decode(String.self, forKey: .phase)
        self.phase = phase
        if let decoded = try c.decodeIfPresent(SequencePresentation.self, forKey: .presentation) {
            self.presentation = decoded
        } else {
            self.presentation = phase == "windowed" ? .windowed : .immersive
        }
        self.immersiveBackdrop = try c.decodeIfPresent(ImmersiveBackdropSpec.self, forKey: .immersiveBackdrop)
        self.steps = try c.decode([StepDefinitionDTO].self, forKey: .steps)
        self.animationTracks = try c.decodeIfPresent([EntityAnimationTrack].self, forKey: .animationTracks) ?? []
        // Absent in every document written before audio automation existed —
        // an empty list means "no rides", which mixes to exactly the previous
        // behaviour.
        self.audioTracks = try c.decodeIfPresent([AudioAutomationTrack].self, forKey: .audioTracks) ?? []
        // Absent in every document written before convergence existed. An
        // empty list means every clip keeps its source's own stereo
        // relationship — exactly the previous behaviour.
        self.stereoTracks = try c.decodeIfPresent([StereoAutomationTrack].self, forKey: .stereoTracks) ?? []
        self.backdropTrack = try c.decodeIfPresent([BackdropCue].self, forKey: .backdropTrack) ?? []
        // Absent in every document written before Explore existed. An empty
        // list is a fully Directed Sequence — exactly the previous behaviour.
        self.storyRegions = try c.decodeIfPresent([StoryRegion].self, forKey: .storyRegions) ?? []
        // Absent in every document written before Sequence-local rest
        // placement existed — and normalized so empty and absent are the
        // same fact.
        let decodedPlacements = try c.decodeIfPresent([String: TransformData].self, forKey: .restPlacements)
        self.restPlacements = (decodedPlacements?.isEmpty == true) ? nil : decodedPlacements
        self.visibility = try c.decodeIfPresent(VisibilityStateDTO.self, forKey: .visibility) ?? VisibilityStateDTO()
        self.onComplete = try c.decodeIfPresent(CompletionActionDTO.self, forKey: .onComplete) ?? .holdOnLastStep
        // Tolerant, like every other additive field: documents written before
        // sequence colors existed simply have no color.
        self.editorColorIndex = try c.decodeIfPresent(Int.self, forKey: .editorColorIndex)
    }
}

/// Whether a sequence expects the player in an immersive space, a mixed
/// (passthrough) space, or a flat windowed scene. The SharedVisions
/// player maps these to visionOS `ImmersionStyle` values:
///
///   • `.immersive` → `.full` — the user's real environment is hidden;
///     ideal for skybox videos and fully-authored 3D backdrops.
///   • `.mixed` → `.mixed` — passthrough stays visible while RealityKit
///     content places into world space. Good for sequences that need
///     3D depth (entities anchored in the user's room) without
///     replacing the real environment.
///   • `.windowed` — the immersive space is dismissed entirely, so
///     only flat windowed UI remains.
///
/// Decode is tolerant: unknown raw values fall back to `.immersive` so
/// a v0.3.1 doc containing `.mixed` loads on a v0.3.0 player as full
/// immersive (the safest interpretation of "needs 3D space").
public enum SequencePresentation: String, Codable, Sendable, Equatable, CaseIterable {
    case immersive
    case mixed
    case windowed

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        self = SequencePresentation(rawValue: raw) ?? .immersive
    }
}

/// Ambient backdrop content for an immersive sequence. The player binds
/// one of these at sequence start (and tears down the previous one):
///
///   • `.video` — a flat video projected onto a sphere (360° / 180°)
///     or a stereoscopic MV-HEVC / Apple Immersive Video file. Player
///     uses `VideoPlayerComponent` for proper per-eye projection.
///   • `.image` — a static equirectangular image (HEIC / JPG / PNG)
///     wrapped onto a sphere mesh via an UnlitMaterial. Cheap, no
///     stereo. Good for matte-painting style environments and
///     360° photos.
///   • `.usdz` — a USDZ scene loaded under the immersive scene root.
///
/// Players may ignore for `.windowed` sequences.
public enum ImmersiveBackdropSpec: Codable, Sendable, Equatable {
    /// Immersive video. `file` references an entry in the asset manifest.
    /// `layout` and `field` mirror the same hints used by `VideoActionDTO`
    /// for skybox playback; `radius` controls the sphere size in meters.
    /// `audioEnabled` lets the backdrop's own soundtrack play (default
    /// false — historically backdrops were always muted).
    case video(file: String, layout: VideoLayout, field: ImmersiveField, radius: Float, loop: Bool, audioEnabled: Bool)
    /// Static equirectangular image skybox. `field` is `.equirect360` for
    /// full-sphere panoramas, `.equirect180` for half-sphere captures.
    /// `radius` is the sphere size in meters (Player default ~1000m).
    case image(file: String, field: ImmersiveField, radius: Float)
    /// USDZ scene loaded under the immersive scene root. The asset id
    /// must exist in the document's manifest. The player parents the
    /// loaded entity under the immersive root before the first sequence
    /// step runs.
    case usdz(assetId: String)
    /// Blocking content: an immersive shot that has not been shot yet. Carries
    /// the projection and radius the finished plate will use, so the sequence
    /// is framed correctly before the media exists, and NO file reference —
    /// nothing enters the manifest. Replaced in place by `.video` once the
    /// plate lands, preserving the cue's id, start time and source range.
    case placeholder(spec: PlaceholderSpec)

    private enum CodingKeys: String, CodingKey {
        case kind, file, layout, field, radius, loop, audioEnabled, assetId, placeholder
    }
    private enum Kind: String, Codable { case video, image, usdz, placeholder }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .video(let file, let layout, let field, let radius, let loop, let audioEnabled):
            try c.encode(Kind.video, forKey: .kind)
            try c.encode(file, forKey: .file)
            try c.encode(layout, forKey: .layout)
            try c.encode(field, forKey: .field)
            try c.encode(radius, forKey: .radius)
            try c.encode(loop, forKey: .loop)
            try c.encode(audioEnabled, forKey: .audioEnabled)
        case .image(let file, let field, let radius):
            try c.encode(Kind.image, forKey: .kind)
            try c.encode(file, forKey: .file)
            try c.encode(field, forKey: .field)
            try c.encode(radius, forKey: .radius)
        case .usdz(let assetId):
            try c.encode(Kind.usdz, forKey: .kind)
            try c.encode(assetId, forKey: .assetId)
        case .placeholder(let spec):
            try c.encode(Kind.placeholder, forKey: .kind)
            try c.encode(spec, forKey: .placeholder)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognised kind resolves to a placeholder rather than throwing:
        // a backdrop written by a newer tool reads as "something goes here,
        // but this build doesn't know what", which is exactly true and is far
        // better than refusing to open the chapter.
        let rawKind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        switch Kind(rawValue: rawKind) ?? .placeholder {
        case .video:
            self = .video(
                file: try c.decode(String.self, forKey: .file),
                layout: try c.decodeIfPresent(VideoLayout.self, forKey: .layout) ?? .mono,
                field: try c.decodeIfPresent(ImmersiveField.self, forKey: .field) ?? .equirect360,
                radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? 1000,
                loop: try c.decodeIfPresent(Bool.self, forKey: .loop) ?? true,
                audioEnabled: try c.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? false
            )
        case .image:
            self = .image(
                file: try c.decode(String.self, forKey: .file),
                field: try c.decodeIfPresent(ImmersiveField.self, forKey: .field) ?? .equirect360,
                radius: try c.decodeIfPresent(Float.self, forKey: .radius) ?? 1000
            )
        case .usdz:
            self = .usdz(assetId: try c.decode(String.self, forKey: .assetId))
        case .placeholder:
            self = .placeholder(
                spec: try c.decodeIfPresent(PlaceholderSpec.self, forKey: .placeholder)
                    ?? .immersiveVideo(label: "Immersive Placeholder", field: .equirect360)
            )
        }
    }

    /// The placeholder this backdrop is, if it is one. Views ask this instead
    /// of pattern-matching the enum in every place that needs to draw a proxy.
    public var placeholderSpec: PlaceholderSpec? {
        if case .placeholder(let spec) = self { return spec }
        return nil
    }
}

public struct StepDefinitionDTO: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var duration: Double
    /// THE canonical action list (format v4). One array, ordered: `at` is the
    /// time and the array position is the authored tie-break for actions that
    /// share one. See `AuthoredAction`.
    ///
    /// There is exactly ONE persisted representation. `actions` and
    /// `scheduledActions` below are computed views for callers that have not
    /// been converted yet — they are never encoded, never decoded into, and
    /// carry no state of their own.
    public var authoredActions: [AuthoredAction]
    public var gate: StepGateDTO?

    public init(
        id: String,
        name: String,
        duration: Double,
        authoredActions: [AuthoredAction],
        gate: StepGateDTO? = nil
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.authoredActions = authoredActions
        self.gate = gate
    }

    /// Legacy-shaped initializer, kept so the many existing construction sites
    /// (and every test fixture) keep compiling while they are converted.
    /// Produces the same layout the v3 → v4 migration does: step-start actions
    /// first, in order, then the scheduled ones.
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
        self.authoredActions =
            actions.enumerated().map {
                AuthoredAction(id: AuthoredAction.migratedID(stepId: id, isScheduled: false,
                                                             index: $0.offset),
                               at: 0, action: $0.element)
            }
            + scheduledActions.enumerated().map {
                AuthoredAction(id: AuthoredAction.migratedID(stepId: id, isScheduled: true,
                                                             index: $0.offset),
                               at: $0.element.at, action: $0.element.action)
            }
        self.gate = gate
    }

    // MARK: - Compatibility views (NOT stored, NOT encoded)

    /// Actions at the step's start. A computed VIEW over `authoredActions`.
    ///
    /// **Assigning PRESERVES identity positionally.** The overwhelmingly common
    /// legacy pattern is a same-length rewrite —
    /// `step.actions = step.actions.map { … }` — which is an EDIT of existing
    /// actions, not a replacement of them. Minting fresh ids there silently
    /// destroyed every action's identity in the sequence; renaming an entity
    /// did it to a whole document at once. So a rewrite reuses the ids of the
    /// entries it overwrites, and only genuinely new entries get new ones.
    @available(*, deprecated, message: "Use authoredActions — position is no longer identity")
    public var actions: [StepActionDTO] {
        get { authoredActions.filter { $0.at <= 0 }.map(\.action) }
        set {
            let existing = authoredActions.filter { $0.at <= 0 }
            let rest = authoredActions.filter { $0.at > 0 }
            authoredActions = newValue.enumerated().map { index, action in
                index < existing.count
                    ? AuthoredAction(id: existing[index].id, at: 0, action: action)
                    : AuthoredAction(at: 0, action: action)
            } + rest
        }
    }

    /// Actions after the step's start. A computed VIEW over `authoredActions`.
    /// Assigning preserves identity positionally, for the same reason as above.
    @available(*, deprecated, message: "Use authoredActions — position is no longer identity")
    public var scheduledActions: [ScheduledActionDTO] {
        get {
            authoredActions.filter { $0.at > 0 }
                .map { ScheduledActionDTO(at: $0.at, action: $0.action) }
        }
        set {
            let head = authoredActions.filter { $0.at <= 0 }
            let existing = authoredActions.filter { $0.at > 0 }
            authoredActions = head + newValue.enumerated().map { index, entry in
                index < existing.count
                    ? AuthoredAction(id: existing[index].id, at: entry.at, action: entry.action)
                    : AuthoredAction(at: entry.at, action: entry.action)
            }
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, duration, authoredActions, gate
        // v3 and earlier. Decoded when `authoredActions` is absent; NEVER written.
        case actions, scheduledActions
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(duration, forKey: .duration)
        try c.encode(authoredActions, forKey: .authoredActions)
        try c.encodeIfPresent(gate, forKey: .gate)
    }

    /// Accepts BOTH shapes.
    ///
    /// The migrator handles documents, but documents are not the only way a
    /// `StepDefinitionDTO` arrives: live-sync `EditOp` payloads are decoded
    /// directly and never see it. `AudioScope` already carries this exact
    /// lesson in its own decoder. A peer still running a v3 build would
    /// otherwise send a step whose actions all silently vanish.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.duration = try c.decode(Double.self, forKey: .duration)
        self.gate = try c.decodeIfPresent(StepGateDTO.self, forKey: .gate)

        if let authored = try c.decodeIfPresent([AuthoredAction].self, forKey: .authoredActions) {
            self.authoredActions = authored
            return
        }
        let legacyImmediate = try c.decodeIfPresent([StepActionDTO].self, forKey: .actions) ?? []
        let legacyScheduled = try c.decodeIfPresent([ScheduledActionDTO].self,
                                                    forKey: .scheduledActions) ?? []
        self.authoredActions = StepDefinitionDTO.unify(
            immediate: legacyImmediate, scheduled: legacyScheduled, stepId: self.id)
    }

    /// The v3 → v4 layout rule, in one place so the JSON migrator, the legacy
    /// initializer and the tolerant decoder cannot disagree.
    ///
    /// ORDER IS THE CONTRACT. At runtime v3 awaited every `actions` entry in
    /// array order BEFORE the timing loop began, and only then fired
    /// `scheduledActions` whose `at` had elapsed — so at t = 0 the step-start
    /// actions ran first, in order, then the scheduled ones. Laying them out in
    /// that same order and sorting stably by `at` reproduces it exactly.
    public static func unify(immediate: [StepActionDTO],
                             scheduled: [ScheduledActionDTO],
                             stepId: String) -> [AuthoredAction] {
        immediate.enumerated().map {
            AuthoredAction(id: AuthoredAction.migratedID(stepId: stepId, isScheduled: false,
                                                         index: $0.offset),
                           at: 0, action: $0.element)
        }
        + scheduled.enumerated().map {
            AuthoredAction(id: AuthoredAction.migratedID(stepId: stepId, isScheduled: true,
                                                         index: $0.offset),
                           at: $0.element.at, action: $0.element.action)
        }
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
    /// Entity the gate watches — the thing to face (`.viewerFacing`), walk up
    /// to (`.proximity`), or pinch-grab (`.grab`). Ignored by the other
    /// types. (Optional fields decode tolerantly — older documents load
    /// unchanged.)
    public var targetEntity: String?
    /// Trigger distance in meters for `.proximity` (player default ~1 m).
    public var radius: Float?
    /// WHAT THE STORY MUST ALREADY REMEMBER before this boundary may pass.
    ///
    /// A gate is the ONE place authored progression stalls, so a Story State
    /// requirement belongs on it rather than in a second stall mechanism. Two
    /// shapes, and both are the same field:
    ///
    /// * `type == .storyCondition` — the conditions are the WHOLE requirement.
    ///   No physical act continues the story; it continues when the facts hold.
    /// * any other type — the conditions are an ADDITIONAL requirement, so
    ///   "tap the door, once you have the key" is a `.tap` gate carrying one
    ///   condition. That is mixed authoring, and it falls out of one field.
    ///
    /// Absent in every Chapter authored before Story State, and encoded only
    /// when present.
    public var storyConditions: StoryConditionGroup?

    public init(
        type: GateType,
        timeout: Double? = nil,
        prompt: String? = nil,
        targetEntity: String? = nil,
        radius: Float? = nil,
        storyConditions: StoryConditionGroup? = nil
    ) {
        self.type = type
        self.timeout = timeout
        self.prompt = prompt
        self.targetEntity = targetEntity
        self.radius = radius
        self.storyConditions = storyConditions
    }

    private enum CodingKeys: String, CodingKey {
        case type, timeout, prompt, targetEntity, radius, storyConditions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(GateType.self, forKey: .type)
        self.timeout = try c.decodeIfPresent(Double.self, forKey: .timeout)
        self.prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        self.targetEntity = try c.decodeIfPresent(String.self, forKey: .targetEntity)
        self.radius = try c.decodeIfPresent(Float.self, forKey: .radius)
        self.storyConditions = try c.decodeIfPresent(StoryConditionGroup.self,
                                                     forKey: .storyConditions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(timeout, forKey: .timeout)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encodeIfPresent(targetEntity, forKey: .targetEntity)
        try c.encodeIfPresent(radius, forKey: .radius)
        // An EMPTY group is not written. It imposes nothing, and a key that
        // means nothing is a key a future reader has to decide about.
        if let storyConditions, !storyConditions.isEmpty {
            try c.encode(storyConditions, forKey: .storyConditions)
        }
    }
}

/// How a waiting step's gate is satisfied. Advisory metadata for the
/// player (the engine itself is timeout-or-`satisfyGate()`): the type
/// tells the consumer WHAT input to wire to `satisfyGate()`.
public enum GateType: String, Codable, Sendable, Equatable {
    /// A pinch-tap anywhere targetable.
    case tap
    /// An external controller (companion device / show-control) message.
    case orchestrator
    /// Tap OR orchestrator — whichever arrives first.
    case any
    /// THE VIEWER FACES `targetEntity` for a dwell time.
    ///
    /// **SYSTEM-EYE-INPUT: not eye tracking.** Measured from the forward spatial
    /// direction (the device pose), never from where the eyes are pointed —
    /// visionOS does not give an app that, and Maestro must not imply it does.
    /// See `ChapterScript.InteractionTrigger.viewerFacing`, which this shares a
    /// detector with.
    ///
    /// LEGACY-INTERACTION-VOCAB: the raw value stays `"gaze"` deliberately.
    /// Existing chapters carry it, and a player built before this rename
    /// decodes an unknown gate type as `.tap` — which would silently turn a
    /// facing gate into a tap gate on someone's device. The WIRE is
    /// compatibility vocabulary; every Swift name and every user-visible string
    /// says Viewer Facing.
    case viewerFacing = "gaze"   // LEGACY-INTERACTION-VOCAB
    /// Come within `radius` meters of `targetEntity`.
    case proximity
    /// Pinch-grab `targetEntity`.
    case grab
    /// THE STORY'S OWN MEMORY IS THE CONDITION. No physical act continues this
    /// boundary; it continues when `StepGateDTO.storyConditions` hold.
    ///
    /// ── WHAT AN OLDER PLAYER DOES WITH THIS, STATED PLAINLY ─────────────────
    ///
    /// A build predating Story State decodes this raw value as `.tap` (the rule
    /// below) and ignores `storyConditions` entirely, so the boundary continues
    /// on a tap instead of on the facts. That is a real degradation and it is
    /// named here rather than discovered later.
    ///
    /// It is also unavoidable: an older player cannot evaluate a condition it
    /// has never heard of, so EVERY representation of a state gate degrades on
    /// it. The choice is between continuing on a tap and waiting forever, and a
    /// chapter that can still be finished is the better of the two. Unlike
    /// `.viewerFacing`, there is no legacy spelling to inherit — this concept
    /// did not exist before.
    case storyCondition

    /// Tolerant decode: an unknown raw value (a document authored by a
    /// NEWER tool) falls back to `.tap` instead of failing the whole
    /// document — gate types are advisory, and tap is the one gate
    /// every player can satisfy.
    ///
    /// LEGACY-INTERACTION-VOCAB: `"viewerFacing"` is accepted as well as the
    /// stored spelling, so a
    /// document hand-edited to the accurate spelling still loads.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "viewerFacing" { self = .viewerFacing; return }
        self = GateType(rawValue: raw) ?? .tap
    }
}

public enum CompletionActionDTO: Codable, Sendable, Equatable {
    case holdOnLastStep
    case transitionTo(phase: String, visibility: VisibilityStateDTO)
    case autoAdvance(nextSequenceId: String)
    case dismissToHome

    /// WHERE THE STORY GOES WHEN THIS SEQUENCE ENDS.
    ///
    /// The four cases above predate Experience Flow and between them can only
    /// say "hold", "go to this one Sequence" and "dismiss". They cannot express
    /// **Return** or **Restart**, which is why those were missing from the
    /// Sequence-end authoring surface — an expressive gap in the format, not a
    /// missing menu item.
    ///
    /// This carries a `NavigationIntent` verbatim, exactly as
    /// `StepActionDTO.navigate` does for an Interaction, so a Sequence's ending
    /// and an object's response speak one vocabulary and reach one navigator.
    ///
    /// Additive and tolerant. `autoAdvance` is NOT deprecated: it is what every
    /// existing chapter contains, it still means `.goTo`, and it is still what
    /// the editor writes for a plain "Continue to" so those documents stay
    /// byte-identical.
    case navigate(NavigationIntent)

    private enum CodingKeys: String, CodingKey { case kind, phase, visibility, nextSequenceId, navigation }
    private enum Kind: String, Codable {
        case holdOnLastStep, transitionTo, autoAdvance, dismissToHome, navigate
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
        case .autoAdvance(let nextSequenceId):
            try c.encode(Kind.autoAdvance, forKey: .kind)
            try c.encode(nextSequenceId, forKey: .nextSequenceId)
        case .dismissToHome:
            try c.encode(Kind.dismissToHome, forKey: .kind)
        case .navigate(let intent):
            try c.encode(Kind.navigate, forKey: .kind)
            try c.encode(intent, forKey: .navigation)
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
            self = .autoAdvance(nextSequenceId: try c.decode(String.self, forKey: .nextSequenceId))
        case .dismissToHome:
            self = .dismissToHome
        case .navigate:
            self = .navigate((try? c.decode(NavigationIntent.self, forKey: .navigation))
                             ?? .unsupported(kind: "navigate", raw: nil))
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
