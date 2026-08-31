import Foundation

/// THE CHAPTER'S ONE TIMEBASE (FL-03): an exact rational frame rate — an
/// integer numerator over an integer denominator, e.g. 30000/1001 for 29.97.
/// The grid the author EDITS on; Sequence time itself stays seconds, and the
/// runtime consumes seconds and never sees this field.
///
/// Why a pair and not a `CMTime`: this format is pure and cross-platform and
/// must decode with no Core Media; and `CMTime`'s flags (indefinite,
/// infinity) are states a timebase must not be able to hold. Every adapter
/// builds a `CMTime` FROM the pair; nothing stores one. The NTSC family are
/// exact fractions here, never rounded decimals.
///
/// ABSENT MEANS 24/1 — byte-for-byte today's behaviour. Validation lives at
/// the AUTHORING boundary; the decoder is tolerant and consumers resolve an
/// invalid pair to 24/1 and REPORT it, never silently accept it.
public struct ChapterTimebase: Codable, Sendable, Equatable {
    public var numerator: Int      // e.g. 30000
    public var denominator: Int    // e.g. 1001

    public init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// The default every untold Chapter edits on.
    public static let `default` = ChapterTimebase(numerator: 24, denominator: 1)

    /// Display convenience ONLY — never the source of truth.
    public var fps: Double { Double(numerator) / Double(denominator) }

    /// Whether this pair may be authored: positive, and in a sane authoring
    /// range. (The DECODER does not enforce this — tolerance is the
    /// decoder's job; refusing nonsense is the authoring boundary's.)
    public var isValid: Bool {
        numerator > 0 && denominator > 0 && fps >= 1 && fps <= 1000
    }
}

/// Top-level immersive experience document. Lives at `chapter.json` inside a `.chapterscript` bundle.
public struct ChapterDocument: Codable, Sendable, Equatable {
    public var formatVersion: Int
    public var id: String
    public var displayName: String
    public var description: String?
    public var entities: [EntityDefinition]
    public var sequences: [SequenceDefinitionDTO]
    public var particlePresets: [ParticleEmitterPreset]
    /// Global scene environment (lighting preset + fog). Optional and additive:
    /// documents authored before this field existed decode as `nil`, and
    /// players fall back to their own defaults.
    public var environment: EnvironmentSpec?
    public var manifest: AssetManifest
    /// WHAT THE STORY CAN REMEMBER. Chapter-scoped, because memory that reset
    /// when the audience walked into another room would not be memory.
    ///
    /// DEFINITIONS ONLY — what facts exist, of what kind, and what a fresh run
    /// starts from. The values a viewer's run has reached live in
    /// `StoryStateLedger` and are never written here. Additive and tolerant:
    /// absent in every Chapter authored before this, and encoded only when
    /// non-empty so those Chapters re-save byte-identically.
    public var storyState: [StoryStateDefinition]
    /// Initial sequence id played when the experience loads. Defaults to first sequence.
    public var defaultSequenceId: String?
    /// EDITOR-ONLY organisation. Never read by ChapterPlayer.
    ///
    /// Optional and tolerant: documents authored before this field existed
    /// decode as `nil`, and a player that has never heard of it ignores the
    /// key. It lives in the document rather than in `UserDefaults` so a
    /// project's organisation travels with the bundle — open the same
    /// `.chapterscript` on another Mac and the Bins are still there.
    public var editorMetadata: EditorMetadata?

    /// The Chapter's one editing timebase (FL-03). ABSENT ⇒ 24/1, and absent
    /// re-saves absent — see `ChapterTimebase` and PD-1
    /// (`architecture-resolution/11`). There is no per-Sequence and no
    /// per-Track override, by decision. ChapterPlayer never reads this: the
    /// timebase is an authoring concept, not a playback concept.
    public var timebase: ChapterTimebase?

    /// THE MARKER CATEGORY TABLE (FL-06): one Chapter-wide, author-editable
    /// list of name + colour, referenced BY ID from every Marker. Absent ⇒
    /// the bundled default is in use and nothing is written.
    public var markerCategories: [MarkerCategory]?

    /// THE CAPTION STYLE LIBRARY (FL-08): the presentation layer, one
    /// Chapter-wide list referenced BY ID from every Caption Track. A style
    /// is reused across Tracks and Sequences — putting it beside the Track
    /// would give two Tracks two copies of one look. Absent means the
    /// bundled default is in use and nothing is written. (FL-21's preset
    /// catalog adopts this array when it lands.)
    public var captionStyles: [CaptionStyle]?

    /// THE PRESET LIBRARY (FL-21, R4): one catalog shape for every kind.
    /// Chapter-scoped presets live here; user presets live in Application
    /// Support in the same shape. Absent means only the bundled essentials
    /// — and a Chapter that never saved a preset re-saves byte-identically.
    public var presets: [PresetEntry]?

    public init(
        formatVersion: Int = ChapterScriptFormat.currentFormatVersion,
        id: String,
        displayName: String,
        description: String? = nil,
        entities: [EntityDefinition] = [],
        sequences: [SequenceDefinitionDTO] = [],
        particlePresets: [ParticleEmitterPreset] = [],
        environment: EnvironmentSpec? = nil,
        manifest: AssetManifest = AssetManifest(),
        storyState: [StoryStateDefinition] = [],
        defaultSequenceId: String? = nil,
        editorMetadata: EditorMetadata? = nil,
        timebase: ChapterTimebase? = nil,
        markerCategories: [MarkerCategory]? = nil,
        captionStyles: [CaptionStyle]? = nil,
        presets: [PresetEntry]? = nil
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.displayName = displayName
        self.description = description
        self.entities = entities
        self.sequences = sequences
        self.particlePresets = particlePresets
        self.environment = environment
        self.manifest = manifest
        self.storyState = storyState
        self.defaultSequenceId = defaultSequenceId
        self.editorMetadata = editorMetadata
        self.timebase = timebase
        self.markerCategories = markerCategories
        self.captionStyles = captionStyles
        self.presets = presets
    }

    // Decode-if-present for `environment` so documents authored before
    // this format revision keep loading. Encode stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, displayName, description
        case entities, sequences, particlePresets, environment
        case manifest, storyState, defaultSequenceId, editorMetadata
        case timebase
        case markerCategories
        case captionStyles
        case presets
    }

    /// Hand-written so `storyState` emits NO key when empty — every Chapter
    /// authored before Story State existed re-saves byte-identically, which is
    /// the same promise `EntityDefinition.displayName` and
    /// `EntityDefinition.interactions` already keep.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(entities, forKey: .entities)
        try c.encode(sequences, forKey: .sequences)
        try c.encode(particlePresets, forKey: .particlePresets)
        try c.encodeIfPresent(environment, forKey: .environment)
        try c.encode(manifest, forKey: .manifest)
        if !storyState.isEmpty { try c.encode(storyState, forKey: .storyState) }
        try c.encodeIfPresent(defaultSequenceId, forKey: .defaultSequenceId)
        try c.encodeIfPresent(editorMetadata, forKey: .editorMetadata)
        // ABSENT NEVER BECOMES PRESENT BY ACCIDENT (PD-1): only the rate
        // control writes this field, and a Chapter never told a rate
        // re-saves byte-identically.
        try c.encodeIfPresent(timebase, forKey: .timebase)
        try c.encodeIfPresent(markerCategories, forKey: .markerCategories)
        try c.encodeIfPresent(captionStyles, forKey: .captionStyles)
        try c.encodeIfPresent(presets, forKey: .presets)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.entities = try c.decode([EntityDefinition].self, forKey: .entities)
        self.sequences = try c.decode([SequenceDefinitionDTO].self, forKey: .sequences)
        // TOLERANT. This field arrived with the particle pass, so every
        // Chapter saved before it lacks the key — and required, that
        // meant a document authored in an earlier Maestro could not be
        // opened at all. Every other late-added field on this type is
        // already `decodeIfPresent`; this one was the exception.
        self.particlePresets = try c.decodeIfPresent(
            [ParticleEmitterPreset].self, forKey: .particlePresets) ?? []
        self.environment = try c.decodeIfPresent(EnvironmentSpec.self, forKey: .environment)
        // Tolerant: an absent manifest unambiguously means a Chapter with
        // no asset files, which is what a placeholder-only or
        // primitives-only Chapter is. `entities` and `sequences` above
        // stay REQUIRED on purpose — a document without them is not a
        // Chapter, and decoding it as empty would hide a corrupt file
        // behind a blank editor.
        self.manifest = try c.decodeIfPresent(AssetManifest.self, forKey: .manifest)
            ?? AssetManifest(entries: [])
        self.storyState = try c.decodeIfPresent([StoryStateDefinition].self,
                                                forKey: .storyState) ?? []
        self.defaultSequenceId = try c.decodeIfPresent(String.self, forKey: .defaultSequenceId)
        self.editorMetadata = try c.decodeIfPresent(EditorMetadata.self, forKey: .editorMetadata)
        // Tolerant: absent means 24/1 (PD-1 — no migration on open, and an
        // old build ignores the unknown key the other way). An INVALID pair
        // is kept as decoded here; consumers resolve it to 24/1 and REPORT —
        // the validator belongs at the authoring boundary, not in the
        // decoder's tolerance path.
        self.timebase = try c.decodeIfPresent(ChapterTimebase.self, forKey: .timebase)
        self.markerCategories = try c.decodeIfPresent([MarkerCategory].self, forKey: .markerCategories)
        self.captionStyles = try c.decodeIfPresent([CaptionStyle].self, forKey: .captionStyles)
        self.presets = try c.decodeIfPresent([PresetEntry].self, forKey: .presets)
    }
}

/// EDITOR-ONLY project organisation. Runtime-inert by contract: ChapterPlayer
/// must never read this, and nothing here may affect playback.
///
/// Kept deliberately small. Anything that changes what the experience DOES
/// belongs in the document proper, not here.
public struct EditorMetadata: Codable, Sendable, Equatable {
    /// Virtual asset collections. Bins never move or copy files inside the
    /// bundle — they are labels over `manifest` entries, so deleting a Bin
    /// cannot delete media.
    public var bins: [MediaBin]

    /// Author-created Timeline track groups. Purely a way to fold rows away;
    /// grouping a track never changes when anything happens.
    public var timelineGroups: [TimelineTrackGroup]

    /// Author-created Scene folders, by name.
    ///
    /// STORED, not derived. Folders used to exist only as the set of distinct
    /// `folder` values across the assets — which meant an EMPTY folder was
    /// unrepresentable, so creating one and then filling it (the obvious
    /// order) was impossible: the folder simply never appeared. Naming a place
    /// before you put anything in it is the whole point of a folder.
    ///
    /// Membership still lives on the asset (`SceneAsset.folder`); this is only
    /// the record that the folder EXISTS. A folder with members is listed here
    /// too, so the two can never disagree about which folders there are.
    public var sceneFolders: [SceneFolder]

    /// Author-created Scene BROWSER folders — the organisational tree over
    /// everything the author has made: Sequences, entities, placeholders and
    /// backdrop-bound objects alike.
    ///
    /// This supersedes `sceneFolders`, which could only ever hold *assets*
    /// (membership lived in `SceneAsset.folder`, a plain string) and split the
    /// world into "scene" and "backdrop" scopes. Neither survives contact with
    /// the browser: a Sequence has no `folder` field to write into, and
    /// backdrops are no longer a separate section to scope against.
    ///
    /// PURELY ORGANISATIONAL. A Scene folder is not a Group Rig and not a
    /// Timeline group: it never parents a RealityKit entity, never changes a
    /// transform, never appears in the runtime scene graph, and never affects
    /// playback, gates or animation. Runtime ignores this field entirely.
    public var sceneFolderTree: [SceneFolderNode]

    /// Author color tags for individual Timeline clips, keyed by the clip's
    /// OPENING action id (stable since format v4 — this keying is one of the
    /// things stable action ids exist for). The value is a palette index, not
    /// an RGB value: color is organisation, and organisation should not be
    /// able to encode arbitrary meaning. Runtime-inert.
    public var clipColors: [String: Int]

    /// Clips protected from Timeline edits, as opening action ids. Lock is an
    /// AUTHORING guard only — a locked clip still plays, still renders, and is
    /// still selectable and inspectable. Runtime-inert.
    public var lockedClips: [String]

    /// Author-created CLIP edit groups: clips that move as one, preserving
    /// their relative timing. NOT a Timeline track group (folds rows), NOT
    /// linked A/V (a media relationship), NOT a Group Rig (a spatial
    /// hierarchy) — the four are deliberately distinct concepts. Runtime-inert.
    public var clipGroups: [ClipEditGroup]

    /// True when there is nothing worth writing.
    ///
    /// Callers use this to decide whether to emit the field at all. It exists
    /// because the obvious hand-rolled version — checking ONE collection — is a
    /// silent data-loss bug waiting to happen: the Mac's bridge tested only
    /// `bins`, so once Bins left the UI every Scene folder and Timeline group an
    /// author made was dropped on save. Anything added to this type must be
    /// added here too, which is why it lives beside the properties.
    /// AUTHOR INTERPRETATION OF AN AUDIO SOURCE, keyed by filename.
    ///
    /// A source-level decision, not an occurrence one: "these eight channels
    /// are a first-order AmbiX bed" is a statement about the FILE, and every
    /// use of it inherits the answer. It lives here rather than beside the
    /// probe's reading because detection is re-derived from the bytes on every
    /// open and this is not — it is a thing a person decided, and losing it
    /// would mean asking them again.
    ///
    /// Absent (the common case) means "Automatic": defer entirely to what the
    /// probe reads. Nothing here ever overwrites detection; the two are
    /// resolved together by `AudioInterpretation.resolved(detected:source:)`,
    /// which reports an override as `.userDefined` rather than laundering it
    /// into `.detected`.
    public var audioInterpretations: [String: AudioInterpretation]

    /// THE AUTHOR'S MEDIA-KIND CORRECTION, keyed by filename.
    ///
    /// Separate from the probe's reading for the same reason
    /// `audioInterpretations` is: "this container holds one audio track and no
    /// video track" is a fact about the bytes, re-read on every open; "author
    /// this as Audio" is a decision, and losing it would mean asking again.
    ///
    /// Absent (overwhelmingly the common case) means Automatic — defer to the
    /// tracks. Nothing here overwrites detection; the two are resolved
    /// together by `MediaKindResolution.effectiveKind`.
    public var mediaKindOverrides: [String: MediaKindOverride]

    /// AUTHOR INTERPRETATION OF A VIDEO SOURCE, keyed by filename.
    ///
    /// The video sibling of `audioInterpretations`, and it exists for the one
    /// fact about a video file that inspection can never establish: frame
    /// packing. A side-by-side master is indistinguishable from a wide mono
    /// movie, so somebody has to say, and what they say has to survive a
    /// reopen. Eye order and the author's preferred placement ride along for
    /// the same reason.
    ///
    /// Absent (the common case) means Automatic. Detected facts — multiview
    /// views, projection kind, baseline, field of view, disparity adjustment —
    /// are re-read from the bytes on every open and never stored here.
    public var videoInterpretations: [String: VideoInterpretation]

    /// AUTHOR INTERPRETATION OF AN IMAGE SOURCE, keyed by filename.
    ///
    /// The still sibling of `videoInterpretations`, for the one fact about a
    /// picture that inspection can never establish: whether its pixels are a
    /// flat photograph or a horizontal sweep, and how wide that sweep is. A
    /// 2:1 image may be an equirectangular 360 and may equally be a panorama,
    /// so somebody has to say, and what they say has to survive a reopen. The
    /// author's preferred presentation rides along for the same reason.
    ///
    /// Absent (the common case) means Automatic. Detected facts — pixel
    /// dimensions, format, whether the file is an Apple Spatial Photo, a
    /// projection the container DECLARES — are re-read from the bytes on every
    /// open and never stored here.
    public var imageInterpretations: [String: ImageInterpretation]

    /// A SOURCE-LEVEL EFFECT SEEDS A NEW PLACEMENT AND NEVER LIVE-LINKS
    /// (FL-09, G2). Keyed by filename like every interpretation; the stack
    /// here is a DEFAULT copied (with fresh instance ids) into each new
    /// occurrence. Editing an occurrence never touches this, and the
    /// runtime never reads it — placement copies are what play.
    public var sourceSeedEffects: [String: [EffectInstance]]

    /// PER-TRACK EDITOR PROPERTIES (FL-17), keyed by TRACK SURFACE ID -
    /// the same key trackSurfaceOwners uses, so a rename never disturbs
    /// them. Editor-only: height, colour and lock change nothing the
    /// audience sees or hears (mute, which does, lives on the Sequence).
    public var trackProperties: [String: TrackProperties]

    /// PER-CHANNEL ANIMATION MUTES (FL-19), entityId -> muted channel raw
    /// names. EDITOR-ONLY working state: a muted channel resolves exactly
    /// as an unkeyed one does (the rest value) while an author isolates a
    /// problem - it never reaches the runtime, Chapter Preview or export,
    /// because a shipped Chapter silently ignoring authored Keys with
    /// nothing on screen saying so is the failure this rule prevents.
    public var channelMutes: [String: [String]]

    /// AUTHORED SOURCE METADATA (FL-20), keyed by Source id (filename).
    /// The manifest is REBUILT from disk at save, so authored keywords,
    /// ratings and favourites live HERE - the one durable home - and the
    /// build stamps them onto each AssetEntry for the wire.
    public var sourceMetadata: [String: SourceMetadata]

    /// WHICH SEQUENCE A TIMELINE TRACK SURFACE WAS CREATED FOR, keyed by the
    /// surface's entity id.
    ///
    /// A Timeline track is a DESTINATION, and a destination created with the
    /// Track button is a Timeline-only object (`PlaceholderOrigin.trackSurface`)
    /// — never a browser asset. It lives in the chapter-global entity list
    /// because that is where every entity lives, and that is exactly what made
    /// adding a track in Sequence A put an empty row in B and C: the Timeline
    /// projection seeded a row for the surface's EXISTENCE, and existence is
    /// chapter-wide.
    ///
    /// So ownership is recorded, and only the owning Sequence gets the empty
    /// row. A surface another Sequence actually routes media to still gets a
    /// row THERE, from its clips — membership follows references, exactly as
    /// `SequenceEntityUsage` decides everywhere else. Ownership only answers
    /// "who gets the row when there is nothing on it yet".
    ///
    /// Absent (a legacy surface, made before this was recorded) means UNOWNED
    /// and keeps the old chapter-wide seeding: we cannot know which Sequence
    /// an existing empty track was made for, and silently hiding an author's
    /// track is worse than leaving it where they last saw it.
    ///
    /// Editor-only. Runtime ignores this field entirely.
    public var trackSurfaceOwners: [String: String]

    /// Which Sequence each EMPTY AUDIO TRACK belongs to, keyed by channel.
    ///
    /// The exact counterpart of `trackSurfaceOwners`, and separate from it for
    /// a reason that is not tidiness: a surface is keyed by ENTITY ID and an
    /// audio track by CHANNEL NAME, and the pruning rule for the first checks
    /// its key against the chapter's entity list. Sharing one map would prune
    /// every audio track away the first time a document was cleaned.
    ///
    /// An audio track with a clip on it needs no entry — its row comes from
    /// the clip, exactly as a video destination's does. This answers only
    /// "who gets the empty row".
    ///
    /// Editor-only. Runtime ignores this field entirely.
    public var audioTrackOwners: [String: String]

    public var isEmpty: Bool {
        sourceSeedEffects.isEmpty &&
        bins.isEmpty && timelineGroups.isEmpty
            && sceneFolders.isEmpty && sceneFolderTree.isEmpty
            && clipColors.isEmpty && lockedClips.isEmpty && clipGroups.isEmpty
            && audioInterpretations.isEmpty && mediaKindOverrides.isEmpty
            && videoInterpretations.isEmpty
            && imageInterpretations.isEmpty
            && trackSurfaceOwners.isEmpty
            && trackProperties.isEmpty
            && channelMutes.isEmpty
            && sourceMetadata.isEmpty
            && audioTrackOwners.isEmpty
    }

    public init(
        bins: [MediaBin] = [],
        timelineGroups: [TimelineTrackGroup] = [],
        sceneFolders: [SceneFolder] = [],
        sceneFolderTree: [SceneFolderNode] = [],
        clipColors: [String: Int] = [:],
        lockedClips: [String] = [],
        clipGroups: [ClipEditGroup] = [],
        audioInterpretations: [String: AudioInterpretation] = [:],
        mediaKindOverrides: [String: MediaKindOverride] = [:],
        videoInterpretations: [String: VideoInterpretation] = [:],
        imageInterpretations: [String: ImageInterpretation] = [:],
        trackSurfaceOwners: [String: String] = [:],
        audioTrackOwners: [String: String] = [:]
    ) {
        self.bins = bins
        self.timelineGroups = timelineGroups
        self.sceneFolders = sceneFolders
        self.sceneFolderTree = sceneFolderTree
        self.clipColors = clipColors
        self.lockedClips = lockedClips
        self.clipGroups = clipGroups
        self.audioInterpretations = audioInterpretations
        self.mediaKindOverrides = mediaKindOverrides
        self.videoInterpretations = videoInterpretations
        self.imageInterpretations = imageInterpretations
        self.sourceSeedEffects = [:]
        self.trackProperties = [:]
        self.channelMutes = [:]
        self.sourceMetadata = [:]
        self.trackSurfaceOwners = trackSurfaceOwners
        self.audioTrackOwners = audioTrackOwners
    }

    private enum CodingKeys: String, CodingKey {
        case bins, timelineGroups, sceneFolders, sceneFolderTree
        case clipColors, lockedClips, clipGroups
        case audioInterpretations, mediaKindOverrides, videoInterpretations
        case imageInterpretations
        case trackSurfaceOwners, audioTrackOwners
        case sourceSeedEffects
        case trackProperties
        case channelMutes
        case sourceMetadata
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bins = try c.decodeIfPresent([MediaBin].self, forKey: .bins) ?? []
        self.timelineGroups = try c.decodeIfPresent([TimelineTrackGroup].self,
                                                    forKey: .timelineGroups) ?? []
        // Tolerant, like every other editor-metadata field: an older bundle
        // has no folder list and simply gets none.
        self.sceneFolders = try c.decodeIfPresent([SceneFolder].self,
                                                  forKey: .sceneFolders) ?? []
        self.sceneFolderTree = try c.decodeIfPresent([SceneFolderNode].self,
                                                     forKey: .sceneFolderTree) ?? []
        self.clipColors = try c.decodeIfPresent([String: Int].self,
                                                forKey: .clipColors) ?? [:]
        self.lockedClips = try c.decodeIfPresent([String].self,
                                                 forKey: .lockedClips) ?? []
        self.clipGroups = try c.decodeIfPresent([ClipEditGroup].self,
                                                forKey: .clipGroups) ?? []
        self.audioInterpretations = try c.decodeIfPresent(
            [String: AudioInterpretation].self, forKey: .audioInterpretations
        ) ?? [:]
        self.mediaKindOverrides = try c.decodeIfPresent(
            [String: MediaKindOverride].self, forKey: .mediaKindOverrides
        ) ?? [:]
        self.videoInterpretations = try c.decodeIfPresent(
            [String: VideoInterpretation].self, forKey: .videoInterpretations
        ) ?? [:]
        self.imageInterpretations = try c.decodeIfPresent(
            [String: ImageInterpretation].self, forKey: .imageInterpretations
        ) ?? [:]
        self.sourceSeedEffects = try c.decodeIfPresent(
            [String: [EffectInstance]].self, forKey: .sourceSeedEffects
        ) ?? [:]
        self.trackProperties = try c.decodeIfPresent(
            [String: TrackProperties].self, forKey: .trackProperties
        ) ?? [:]
        self.channelMutes = try c.decodeIfPresent(
            [String: [String]].self, forKey: .channelMutes
        ) ?? [:]
        self.sourceMetadata = try c.decodeIfPresent(
            [String: SourceMetadata].self, forKey: .sourceMetadata
        ) ?? [:]
        self.trackSurfaceOwners = try c.decodeIfPresent(
            [String: String].self, forKey: .trackSurfaceOwners
        ) ?? [:]
        self.audioTrackOwners = try c.decodeIfPresent(
            [String: String].self, forKey: .audioTrackOwners
        ) ?? [:]
    }
}

/// A CLIP edit group: Timeline occurrences that move as one, preserving
/// relative timing. Members are opening action ids. Purely organisational —
/// grouping never changes when anything plays.
public struct ClipEditGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Opening action ids of the member clips. A clip belongs to at most one
    /// group; the editing rules enforce it.
    public var members: [String]

    public init(id: String, members: [String]) {
        self.id = id
        self.members = members
    }
}

/// One thing the Scene browser can hold, referenced the way the FORMAT
/// references it.
///
/// Entities are named, not id'd, everywhere else in ChapterScript (actions,
/// `EntityAnimationTrack.entity`, `StepGateDTO.targetEntity`,
/// `VideoPresentation.entity`), so folder membership uses the name too — one
/// reference scheme, one thing to keep correct on rename. `EntityRenaming` is
/// the single substitution point and updates this along with the rest.
public struct SceneItemRef: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case sequence
        case entity
    }

    public var kind: Kind
    /// A Sequence's `id`, or an entity's `name`.
    public var id: String

    public init(kind: Kind, id: String) {
        self.kind = kind
        self.id = id
    }

    /// Unknown kinds from a newer tool degrade to `.entity` rather than failing
    /// the load, matching `GateType` and `EntityKind`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .kind)
        self.kind = Kind(rawValue: raw) ?? .entity
        self.id = try c.decode(String.self, forKey: .id)
    }

    private enum CodingKeys: String, CodingKey { case kind, id }
}

/// A folder in the Scene browser. Editor-only.
///
/// Membership is stored ON THE FOLDER rather than on each item, because the
/// things it holds do not share a field to write into — a Sequence has no
/// `folder` property and never will. Anything not named by some folder is at
/// the root, so the tree never has to be exhaustive and an item can never go
/// missing by failing to be listed.
public struct SceneFolderNode: Codable, Sendable, Equatable, Identifiable, Hashable {
    /// Stable and opaque. NOT the display name — renaming a folder must not
    /// re-parent its children or orphan its contents.
    public var id: String
    public var name: String
    /// Parent folder id, or `nil` for a top-level folder.
    public var parentId: String?
    /// Ordered membership. Order is the author's, so it is preserved verbatim.
    public var items: [SceneItemRef]

    public init(
        id: String = UUID().uuidString,
        name: String,
        parentId: String? = nil,
        items: [SceneItemRef] = []
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A hand-authored folder without an id still has to be addressable.
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Folder"
        self.parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        self.items = try c.decodeIfPresent([SceneItemRef].self, forKey: .items) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, name, parentId, items }
}

/// A named folder in the Scene panel. Editor-only, and purely organisational —
/// foldering an object never changes when or whether it appears.
///
/// Scene assets and backdrops are listed separately and can hold folders of the
/// same name without collision, so the scope is part of the identity.
public struct SceneFolder: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var name: String
    /// True when this folder belongs to the Backdrops list rather than Scene.
    public var isBackdrop: Bool

    public var id: String { "\(isBackdrop ? "backdrop" : "scene")/\(name)" }

    public init(name: String, isBackdrop: Bool = false) {
        self.name = name
        self.isBackdrop = isBackdrop
    }
}

/// A named, collapsible set of Timeline track rows. Editor-only.
///
/// Timeline tracks are a PROJECTION of the action stream, not authored
/// objects, so a group cannot own its members — it can only name them. That is
/// why membership is a list of track ids resolved at render time: a track that
/// stops existing (its last clip deleted, its entity removed) simply stops
/// appearing in the group, and a group that ends up empty renders as empty
/// rather than as a dangling row.
///
/// A group lives in exactly ONE section. Sections (Scene / Audio / Effects)
/// are the Timeline's top-level order, and a group spanning two of them would
/// have to be drawn twice or drawn in the wrong place.
public struct TimelineTrackGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// `TimelineSection.rawValue`. A raw string rather than the enum because
    /// the section type lives in the editor layer, above this one.
    public var section: String
    /// Track ids, in the order the author arranged them.
    public var trackIDs: [String]
    /// Folded state. Persisted because it is an organisational decision about
    /// the project, not transient view state — reopening a chapter with
    /// forty tracks should not reopen forty rows.
    public var isCollapsed: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        section: String,
        trackIDs: [String] = [],
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.section = section
        self.trackIDs = trackIDs
        self.isCollapsed = isCollapsed
    }

    private enum CodingKeys: String, CodingKey { case id, name, section, trackIDs, isCollapsed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Group"
        self.section = try c.decodeIfPresent(String.self, forKey: .section) ?? "Scene"
        self.trackIDs = try c.decodeIfPresent([String].self, forKey: .trackIDs) ?? []
        self.isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
    }
}

/// A virtual collection of project media. Editor-only.
public struct MediaBin: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Asset filenames, matching `AssetEntry` ids used elsewhere in the
    /// editor. An asset may belong to several Bins; membership is a label,
    /// not ownership.
    public var assets: [String]
    /// Marks the single built-in staging collection, so the editor can pin it
    /// and refuse to delete it. Free-form rather than a separate type: a
    /// staging Bin IS a Bin, and giving it its own persistence would be a
    /// second system for no gain.
    public var isStaging: Bool

    public init(id: String = UUID().uuidString, name: String, assets: [String] = [], isStaging: Bool = false) {
        self.id = id
        self.name = name
        self.assets = assets
        self.isStaging = isStaging
    }

    private enum CodingKeys: String, CodingKey { case id, name, assets, isStaging }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Bin"
        self.assets = try c.decodeIfPresent([String].self, forKey: .assets) ?? []
        self.isStaging = try c.decodeIfPresent(Bool.self, forKey: .isStaging) ?? false
    }
}

/// Global scene environment authored by editors: a free-form lighting preset
/// tag plus a simple distance-fog toggle. Players map `lighting` onto their
/// own rendering setup (image-based lighting, exposure, background tint) and
/// may ignore tags they don't recognize.
public struct EnvironmentSpec: Codable, Sendable, Equatable {
    /// Free preset tag (e.g. "studio", "natural", "sunset", "night", "overcast").
    public var lighting: String
    public var fogEnabled: Bool
    public var fogDensity: Float

    public init(
        lighting: String = "studio",
        fogEnabled: Bool = false,
        fogDensity: Float = 0.02
    ) {
        self.lighting = lighting
        self.fogEnabled = fogEnabled
        self.fogDensity = fogDensity
    }

    // Field-tolerant decode: partially-specified environments (or fields
    // added later) fall back to the defaults above.
    private enum CodingKeys: String, CodingKey {
        case lighting, fogEnabled, fogDensity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lighting = try c.decodeIfPresent(String.self, forKey: .lighting) ?? "studio"
        self.fogEnabled = try c.decodeIfPresent(Bool.self, forKey: .fogEnabled) ?? false
        self.fogDensity = try c.decodeIfPresent(Float.self, forKey: .fogDensity) ?? 0.02
    }
}

public struct AssetManifest: Codable, Sendable, Equatable {
    public var entries: [AssetEntry]

    public init(entries: [AssetEntry] = []) {
        self.entries = entries
    }

    public func entry(id: String) -> AssetEntry? {
        entries.first { $0.id == id }
    }
}

/// Where an externally stored source was last found on the authoring machine.
///
/// A Source is not a pathname: the manifest entry's `id` is the stable identity
/// every authored use references, and this record only describes where the
/// BYTES currently live when the author chose to leave the file in place
/// instead of copying it into the bundle's `assets/` folder.
///
/// Machine-affine by design: `bookmark` is macOS bookmark data (tracks a file
/// across moves and renames on the same volume) and `lastKnownPath` is an
/// absolute path on the machine that authored the reference. A player, or a
/// Mac that cannot resolve either, treats the source as not currently linked;
/// nothing here is required for a self-contained bundle, whose entries simply
/// carry no `external` record. All fields decode tolerantly so a future field
/// can be added without stranding older documents.
public struct ExternalMediaLocation: Codable, Sendable, Equatable {
    /// Absolute POSIX path where the source was last successfully resolved.
    public var lastKnownPath: String
    /// Earlier resolved paths, most recent first. Bounded by writers.
    public var previousPaths: [String]?
    /// macOS bookmark data for move/rename tracking. Opaque to players.
    public var bookmark: Data?
    /// Volume name at last resolution, so an unplugged disk can be told apart
    /// from a deleted file.
    public var volumeName: String?
    /// Content modification date at last resolution, milliseconds since 1970.
    public var contentModifiedMs: Int?

    public init(
        lastKnownPath: String,
        previousPaths: [String]? = nil,
        bookmark: Data? = nil,
        volumeName: String? = nil,
        contentModifiedMs: Int? = nil
    ) {
        self.lastKnownPath = lastKnownPath
        self.previousPaths = previousPaths
        self.bookmark = bookmark
        self.volumeName = volumeName
        self.contentModifiedMs = contentModifiedMs
    }

    private enum CodingKeys: String, CodingKey {
        case lastKnownPath, previousPaths, bookmark, volumeName, contentModifiedMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lastKnownPath = try c.decodeIfPresent(String.self, forKey: .lastKnownPath) ?? ""
        self.previousPaths = try c.decodeIfPresent([String].self, forKey: .previousPaths)
        self.bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        self.volumeName = try c.decodeIfPresent(String.self, forKey: .volumeName)
        self.contentModifiedMs = try c.decodeIfPresent(Int.self, forKey: .contentModifiedMs)
    }
}

public struct AssetEntry: Codable, Sendable, Equatable {
    public var id: String
    public var relativePath: String      // path within the .chapterscript/assets/ folder
    public var kind: AssetKind
    public var sha256: String?
    public var byteSize: Int64?
    public var durationMs: Int?           // for audio/video
    public var width: Int?                 // for images/video
    public var height: Int?
    /// Present when the source's bytes live OUTSIDE the bundle (the author
    /// chose to leave the file in place). Absent means the bytes are stored
    /// at `assets/<relativePath>` inside the bundle, exactly as before this
    /// field existed. `relativePath` remains the serving key either way.
    public var external: ExternalMediaLocation?

    /// AUTHORED SOURCE METADATA (FL-20): findable by more than a name.
    /// All optional and additive; absent means none / unrated / not a
    /// favourite, and existing manifests re-save byte-identically.
    public var keywords: [String]?
    /// 0...5; the write path clamps and reports an out-of-range value.
    public var rating: Int?
    public var isFavorite: Bool?

    public init(
        id: String,
        relativePath: String,
        kind: AssetKind,
        sha256: String? = nil,
        byteSize: Int64? = nil,
        durationMs: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        external: ExternalMediaLocation? = nil,
        keywords: [String]? = nil,
        rating: Int? = nil,
        isFavorite: Bool? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.kind = kind
        self.sha256 = sha256
        self.byteSize = byteSize
        self.durationMs = durationMs
        self.width = width
        self.height = height
        self.external = external
        self.keywords = keywords
        self.rating = rating
        self.isFavorite = isFavorite
    }

    /// True when the entry's bytes are stored outside the bundle.
    public var isExternal: Bool { external != nil }
}

public enum AssetKind: Codable, Sendable, Equatable, Hashable {
    case audio
    case video
    case usdz
    case image
    case other
    /// A kind this build does not know, preserved VERBATIM. Tolerant decode
    /// alone (degrading to `.other`) would silently rewrite a newer tool's
    /// kind on the next save — the `NavigationIntent.unsupported` rule
    /// applies: an older build must not downgrade a newer build's document.
    /// Treat it as `.other` for behavior; re-emit the original raw value.
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .audio: return "audio"
        case .video: return "video"
        case .usdz: return "usdz"
        case .image: return "image"
        case .other: return "other"
        case .unknown(let raw): return raw
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "audio": self = .audio
        case "video": self = .video
        case "usdz": self = .usdz
        case "image": self = .image
        case "other": self = .other
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AssetKind(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Particle emitter preset reference. Authored by editors (e.g. Maestro's Afterburn UI),
/// played back by the player as a `ParticleEmitterComponent`-equivalent.
///
/// The original 14 fields (id…loops) are the compact authoring surface and keep their
/// exact names/semantics. Everything after them is the full-fidelity Afterburn knob set
/// (mirroring Maestro's `SavedParticle.EmitterData`), added additively: every extended
/// field decodes-if-present with the Afterburn `EmitterSettings` default, so documents
/// authored before this revision decode unchanged and render identically.
///
/// Units/semantics worth calling out:
/// - `spreadAngle` is DEGREES (players convert to radians) — unchanged.
/// - `endSize` stays the absolute end-of-lifespan size; players derive RealityKit's
///   `sizeMultiplierAtEndOfLifespan` as `endSize / startSize` (end size wins when
///   `startSize == 0`). `sizeMultiplierAtEndOfLifespanPower` shapes that ramp.
/// - `gravity` remains the constant acceleration vector (RealityKit `acceleration`).
/// - `angle`/`angleVariation`/`angularSpeed`/`angularSpeedVariation` are RADIANS,
///   passed straight through to RealityKit — matching what Afterburn's viewport
///   actually renders (its `create(from:)` does no conversion).
/// - `colorSetting == .constant` (the default) preserves the legacy rendering:
///   a single `color` whose alpha ramps `startOpacity → endOpacity`. `.evolving`
///   (and `.random`, which players may approximate as evolving) blends
///   `color@startOpacity → color2@endOpacity` shaped by `colorEvolutionPower`.
/// - `burstCount == nil` keeps the legacy non-looping burst sizing
///   (`birthRate × lifeSpan`); a value overrides it.
/// - `mainImage`: `nil`/`"none"` = untextured; `"default"` = the soft radial
///   sprite; anything else is an SF Symbol name rendered white.
public struct ParticleEmitterPreset: Codable, Sendable, Equatable {
    // MARK: Original compact surface (unchanged)
    public var id: String
    public var displayName: String
    public var birthRate: Float
    public var lifeSpan: Float
    public var speed: Float
    public var emitterShape: ParticleEmitterShape
    public var spreadAngle: Float
    public var color: ColorRGBA
    public var startSize: Float
    public var endSize: Float
    public var startOpacity: Float
    public var endOpacity: Float
    public var blending: MaterialBlending
    public var gravity: Vec3
    public var loops: Bool

    // MARK: Emission
    public var birthRateVariation: Float
    public var emitterShapeSize: Vec3
    public var birthDirection: ParticleBirthDirection
    public var birthLocation: ParticleBirthLocation
    public var emissionDirection: Vec3
    public var radialAmount: Float
    public var torusInnerRadius: Float
    /// Burst size for non-looping presets (and explicit `burst()` calls).
    /// `nil` = derive `birthRate × lifeSpan` like the legacy player did.
    public var burstCount: Int?
    public var particlesInheritTransform: Bool

    // MARK: Lifespan & size
    public var lifeSpanVariation: Float
    public var sizeVariation: Float
    public var sizeMultiplierAtEndOfLifespanPower: Float

    // MARK: Physics
    public var mass: Float
    public var massVariation: Float
    public var angle: Float
    public var angleVariation: Float
    public var angularSpeed: Float
    public var angularSpeedVariation: Float
    public var dampingFactor: Float
    public var stretchFactor: Float

    // MARK: Color
    public var colorSetting: ParticleColorMode
    public var color2: ColorRGBA
    public var colorEvolutionPower: Float

    // MARK: Visual
    public var opacityCurve: ParticleOpacityCurve
    public var billboardMode: ParticleBillboardMode
    public var isLightingEnabled: Bool
    public var sortOrder: ParticleSortOrder
    public var mainImage: String?

    // MARK: Force fields
    public var noiseStrength: Float
    public var noiseScale: Float
    public var noiseAnimationSpeed: Float
    public var attractionStrength: Float
    public var attractionCenter: Vec3
    public var vortexStrength: Float
    public var vortexDirection: Vec3

    // MARK: Spawned (secondary) emitter
    public var spawn: SpawnedEmitterSpec?

    public init(
        id: String,
        displayName: String,
        birthRate: Float = 100,
        lifeSpan: Float = 1.5,
        speed: Float = 0.5,
        emitterShape: ParticleEmitterShape = .point,
        spreadAngle: Float = 30,
        color: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
        startSize: Float = 0.02,
        endSize: Float = 0.0,
        startOpacity: Float = 1,
        endOpacity: Float = 0,
        blending: MaterialBlending = .additive,
        gravity: Vec3 = Vec3(0, 0, 0),
        loops: Bool = true,
        birthRateVariation: Float = 0,
        emitterShapeSize: Vec3 = Vec3(0.1, 0.1, 0.1),
        birthDirection: ParticleBirthDirection = .normal,
        birthLocation: ParticleBirthLocation = .surface,
        emissionDirection: Vec3 = Vec3(0, 1, 0),
        radialAmount: Float = 6.283,
        torusInnerRadius: Float = 0.5,
        burstCount: Int? = nil,
        particlesInheritTransform: Bool = false,
        lifeSpanVariation: Float = 0,
        sizeVariation: Float = 0,
        sizeMultiplierAtEndOfLifespanPower: Float = 1.0,
        mass: Float = 1.0,
        massVariation: Float = 0,
        angle: Float = 0,
        angleVariation: Float = 0,
        angularSpeed: Float = 0,
        angularSpeedVariation: Float = 0,
        dampingFactor: Float = 0,
        stretchFactor: Float = 0,
        colorSetting: ParticleColorMode = .constant,
        color2: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
        colorEvolutionPower: Float = 1.0,
        opacityCurve: ParticleOpacityCurve = .constant,
        billboardMode: ParticleBillboardMode = .billboard,
        isLightingEnabled: Bool = false,
        sortOrder: ParticleSortOrder = .unsorted,
        mainImage: String? = nil,
        noiseStrength: Float = 0,
        noiseScale: Float = 1.0,
        noiseAnimationSpeed: Float = 0,
        attractionStrength: Float = 0,
        attractionCenter: Vec3 = Vec3(0, 0, 0),
        vortexStrength: Float = 0,
        vortexDirection: Vec3 = Vec3(0, 1, 0),
        spawn: SpawnedEmitterSpec? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.birthRate = birthRate
        self.lifeSpan = lifeSpan
        self.speed = speed
        self.emitterShape = emitterShape
        self.spreadAngle = spreadAngle
        self.color = color
        self.startSize = startSize
        self.endSize = endSize
        self.startOpacity = startOpacity
        self.endOpacity = endOpacity
        self.blending = blending
        self.gravity = gravity
        self.loops = loops
        self.birthRateVariation = birthRateVariation
        self.emitterShapeSize = emitterShapeSize
        self.birthDirection = birthDirection
        self.birthLocation = birthLocation
        self.emissionDirection = emissionDirection
        self.radialAmount = radialAmount
        self.torusInnerRadius = torusInnerRadius
        self.burstCount = burstCount
        self.particlesInheritTransform = particlesInheritTransform
        self.lifeSpanVariation = lifeSpanVariation
        self.sizeVariation = sizeVariation
        self.sizeMultiplierAtEndOfLifespanPower = sizeMultiplierAtEndOfLifespanPower
        self.mass = mass
        self.massVariation = massVariation
        self.angle = angle
        self.angleVariation = angleVariation
        self.angularSpeed = angularSpeed
        self.angularSpeedVariation = angularSpeedVariation
        self.dampingFactor = dampingFactor
        self.stretchFactor = stretchFactor
        self.colorSetting = colorSetting
        self.color2 = color2
        self.colorEvolutionPower = colorEvolutionPower
        self.opacityCurve = opacityCurve
        self.billboardMode = billboardMode
        self.isLightingEnabled = isLightingEnabled
        self.sortOrder = sortOrder
        self.mainImage = mainImage
        self.noiseStrength = noiseStrength
        self.noiseScale = noiseScale
        self.noiseAnimationSpeed = noiseAnimationSpeed
        self.attractionStrength = attractionStrength
        self.attractionCenter = attractionCenter
        self.vortexStrength = vortexStrength
        self.vortexDirection = vortexDirection
        self.spawn = spawn
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, birthRate, lifeSpan, speed, emitterShape, spreadAngle
        case color, startSize, endSize, startOpacity, endOpacity, blending, gravity, loops
        case birthRateVariation, emitterShapeSize, birthDirection, birthLocation
        case emissionDirection, radialAmount, torusInnerRadius, burstCount
        case particlesInheritTransform
        case lifeSpanVariation, sizeVariation, sizeMultiplierAtEndOfLifespanPower
        case mass, massVariation, angle, angleVariation, angularSpeed
        case angularSpeedVariation, dampingFactor, stretchFactor
        case colorSetting, color2, colorEvolutionPower
        case opacityCurve, billboardMode, isLightingEnabled, sortOrder, mainImage
        case noiseStrength, noiseScale, noiseAnimationSpeed
        case attractionStrength, attractionCenter, vortexStrength, vortexDirection
        case spawn
    }

    // Field-tolerant decode: every field beyond id/displayName is
    // decode-if-present with the default above, and enum strings fall back to
    // their default when unrecognized — so old documents decode unchanged and
    // future additive fields never break this revision.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.birthRate = try c.decodeIfPresent(Float.self, forKey: .birthRate) ?? 100
        self.lifeSpan = try c.decodeIfPresent(Float.self, forKey: .lifeSpan) ?? 1.5
        self.speed = try c.decodeIfPresent(Float.self, forKey: .speed) ?? 0.5
        self.emitterShape = c.tolerantEnum(.emitterShape, default: .point)
        self.spreadAngle = try c.decodeIfPresent(Float.self, forKey: .spreadAngle) ?? 30
        self.color = try c.decodeIfPresent(ColorRGBA.self, forKey: .color) ?? ColorRGBA(r: 1, g: 1, b: 1)
        self.startSize = try c.decodeIfPresent(Float.self, forKey: .startSize) ?? 0.02
        self.endSize = try c.decodeIfPresent(Float.self, forKey: .endSize) ?? 0.0
        self.startOpacity = try c.decodeIfPresent(Float.self, forKey: .startOpacity) ?? 1
        self.endOpacity = try c.decodeIfPresent(Float.self, forKey: .endOpacity) ?? 0
        self.blending = c.tolerantEnum(.blending, default: .additive)
        self.gravity = try c.decodeIfPresent(Vec3.self, forKey: .gravity) ?? Vec3(0, 0, 0)
        self.loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? true
        self.birthRateVariation = try c.decodeIfPresent(Float.self, forKey: .birthRateVariation) ?? 0
        self.emitterShapeSize = try c.decodeIfPresent(Vec3.self, forKey: .emitterShapeSize) ?? Vec3(0.1, 0.1, 0.1)
        self.birthDirection = c.tolerantEnum(.birthDirection, default: .normal)
        self.birthLocation = c.tolerantEnum(.birthLocation, default: .surface)
        self.emissionDirection = try c.decodeIfPresent(Vec3.self, forKey: .emissionDirection) ?? Vec3(0, 1, 0)
        self.radialAmount = try c.decodeIfPresent(Float.self, forKey: .radialAmount) ?? 6.283
        self.torusInnerRadius = try c.decodeIfPresent(Float.self, forKey: .torusInnerRadius) ?? 0.5
        self.burstCount = try c.decodeIfPresent(Int.self, forKey: .burstCount)
        self.particlesInheritTransform = try c.decodeIfPresent(Bool.self, forKey: .particlesInheritTransform) ?? false
        self.lifeSpanVariation = try c.decodeIfPresent(Float.self, forKey: .lifeSpanVariation) ?? 0
        self.sizeVariation = try c.decodeIfPresent(Float.self, forKey: .sizeVariation) ?? 0
        self.sizeMultiplierAtEndOfLifespanPower = try c.decodeIfPresent(Float.self, forKey: .sizeMultiplierAtEndOfLifespanPower) ?? 1.0
        self.mass = try c.decodeIfPresent(Float.self, forKey: .mass) ?? 1.0
        self.massVariation = try c.decodeIfPresent(Float.self, forKey: .massVariation) ?? 0
        self.angle = try c.decodeIfPresent(Float.self, forKey: .angle) ?? 0
        self.angleVariation = try c.decodeIfPresent(Float.self, forKey: .angleVariation) ?? 0
        self.angularSpeed = try c.decodeIfPresent(Float.self, forKey: .angularSpeed) ?? 0
        self.angularSpeedVariation = try c.decodeIfPresent(Float.self, forKey: .angularSpeedVariation) ?? 0
        self.dampingFactor = try c.decodeIfPresent(Float.self, forKey: .dampingFactor) ?? 0
        self.stretchFactor = try c.decodeIfPresent(Float.self, forKey: .stretchFactor) ?? 0
        self.colorSetting = c.tolerantEnum(.colorSetting, default: .constant)
        self.color2 = try c.decodeIfPresent(ColorRGBA.self, forKey: .color2) ?? ColorRGBA(r: 1, g: 1, b: 1)
        self.colorEvolutionPower = try c.decodeIfPresent(Float.self, forKey: .colorEvolutionPower) ?? 1.0
        self.opacityCurve = c.tolerantEnum(.opacityCurve, default: .constant)
        self.billboardMode = c.tolerantEnum(.billboardMode, default: .billboard)
        self.isLightingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isLightingEnabled) ?? false
        self.sortOrder = c.tolerantEnum(.sortOrder, default: .unsorted)
        self.mainImage = try c.decodeIfPresent(String.self, forKey: .mainImage)
        self.noiseStrength = try c.decodeIfPresent(Float.self, forKey: .noiseStrength) ?? 0
        self.noiseScale = try c.decodeIfPresent(Float.self, forKey: .noiseScale) ?? 1.0
        self.noiseAnimationSpeed = try c.decodeIfPresent(Float.self, forKey: .noiseAnimationSpeed) ?? 0
        self.attractionStrength = try c.decodeIfPresent(Float.self, forKey: .attractionStrength) ?? 0
        self.attractionCenter = try c.decodeIfPresent(Vec3.self, forKey: .attractionCenter) ?? Vec3(0, 0, 0)
        self.vortexStrength = try c.decodeIfPresent(Float.self, forKey: .vortexStrength) ?? 0
        self.vortexDirection = try c.decodeIfPresent(Vec3.self, forKey: .vortexDirection) ?? Vec3(0, 1, 0)
        self.spawn = try c.decodeIfPresent(SpawnedEmitterSpec.self, forKey: .spawn)
    }

    /// Secondary (spawned) particle emitter — RealityKit's `spawnedEmitter`
    /// plus the spawn-behavior knobs that live on the component. Mirrors
    /// Maestro's `SavedParticle.EmitterData.SpawnedEmitterData` + spawn
    /// settings. Presence of this spec = secondary particles enabled.
    ///
    /// Units match the parent preset: `spreadAngle` is degrees; `angle` /
    /// `angularSpeed` (and their variations) are radians passed straight
    /// through, matching Afterburn's viewport.
    public struct SpawnedEmitterSpec: Codable, Sendable, Equatable {
        // Spawn behavior (lives on the component)
        public var spawnOccasion: ParticleSpawnOccasion
        public var spawnSpreadFactor: Float
        public var spawnVelocityFactor: Float
        public var spawnInheritsParentColor: Bool
        /// Spawned-particle texture: nil/"none" = untextured, "default" = soft
        /// radial sprite, else SF Symbol name.
        public var image: String?

        // Emission
        public var birthRate: Float
        public var birthRateVariation: Float

        // Lifespan & size
        public var lifeSpan: Float
        public var lifeSpanVariation: Float
        public var size: Float
        public var sizeVariation: Float
        public var sizeMultiplierAtEndOfLifespan: Float
        public var sizeMultiplierAtEndOfLifespanPower: Float

        // Physics
        public var mass: Float
        public var massVariation: Float
        public var acceleration: Vec3
        public var angle: Float
        public var angleVariation: Float
        public var angularSpeed: Float
        public var angularSpeedVariation: Float
        public var dampingFactor: Float
        public var spreadAngle: Float
        public var stretchFactor: Float

        // Color
        public var colorSetting: ParticleColorMode
        public var color: ColorRGBA
        public var color2: ColorRGBA
        public var colorEvolutionPower: Float

        // Visual
        public var opacityCurve: ParticleOpacityCurve
        public var billboardMode: ParticleBillboardMode
        public var blending: MaterialBlending
        public var isLightingEnabled: Bool
        public var sortOrder: ParticleSortOrder

        // Force fields
        public var noiseStrength: Float
        public var noiseScale: Float
        public var noiseAnimationSpeed: Float
        public var attractionStrength: Float
        public var attractionCenter: Vec3
        public var vortexStrength: Float
        public var vortexDirection: Vec3

        public init(
            spawnOccasion: ParticleSpawnOccasion = .onBirth,
            spawnSpreadFactor: Float = 0,
            spawnVelocityFactor: Float = 0,
            spawnInheritsParentColor: Bool = false,
            image: String? = nil,
            birthRate: Float = 50,
            birthRateVariation: Float = 0,
            lifeSpan: Float = 1.0,
            lifeSpanVariation: Float = 0,
            size: Float = 0.03,
            sizeVariation: Float = 0,
            sizeMultiplierAtEndOfLifespan: Float = 1.0,
            sizeMultiplierAtEndOfLifespanPower: Float = 1.0,
            mass: Float = 1.0,
            massVariation: Float = 0,
            acceleration: Vec3 = Vec3(0, 0, 0),
            angle: Float = 0,
            angleVariation: Float = 0,
            angularSpeed: Float = 0,
            angularSpeedVariation: Float = 0,
            dampingFactor: Float = 0,
            spreadAngle: Float = 0,
            stretchFactor: Float = 0,
            colorSetting: ParticleColorMode = .constant,
            color: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
            color2: ColorRGBA = ColorRGBA(r: 1, g: 1, b: 1),
            colorEvolutionPower: Float = 1.0,
            opacityCurve: ParticleOpacityCurve = .constant,
            billboardMode: ParticleBillboardMode = .billboard,
            blending: MaterialBlending = .additive,
            isLightingEnabled: Bool = false,
            sortOrder: ParticleSortOrder = .unsorted,
            noiseStrength: Float = 0,
            noiseScale: Float = 1.0,
            noiseAnimationSpeed: Float = 0,
            attractionStrength: Float = 0,
            attractionCenter: Vec3 = Vec3(0, 0, 0),
            vortexStrength: Float = 0,
            vortexDirection: Vec3 = Vec3(0, 1, 0)
        ) {
            self.spawnOccasion = spawnOccasion
            self.spawnSpreadFactor = spawnSpreadFactor
            self.spawnVelocityFactor = spawnVelocityFactor
            self.spawnInheritsParentColor = spawnInheritsParentColor
            self.image = image
            self.birthRate = birthRate
            self.birthRateVariation = birthRateVariation
            self.lifeSpan = lifeSpan
            self.lifeSpanVariation = lifeSpanVariation
            self.size = size
            self.sizeVariation = sizeVariation
            self.sizeMultiplierAtEndOfLifespan = sizeMultiplierAtEndOfLifespan
            self.sizeMultiplierAtEndOfLifespanPower = sizeMultiplierAtEndOfLifespanPower
            self.mass = mass
            self.massVariation = massVariation
            self.acceleration = acceleration
            self.angle = angle
            self.angleVariation = angleVariation
            self.angularSpeed = angularSpeed
            self.angularSpeedVariation = angularSpeedVariation
            self.dampingFactor = dampingFactor
            self.spreadAngle = spreadAngle
            self.stretchFactor = stretchFactor
            self.colorSetting = colorSetting
            self.color = color
            self.color2 = color2
            self.colorEvolutionPower = colorEvolutionPower
            self.opacityCurve = opacityCurve
            self.billboardMode = billboardMode
            self.blending = blending
            self.isLightingEnabled = isLightingEnabled
            self.sortOrder = sortOrder
            self.noiseStrength = noiseStrength
            self.noiseScale = noiseScale
            self.noiseAnimationSpeed = noiseAnimationSpeed
            self.attractionStrength = attractionStrength
            self.attractionCenter = attractionCenter
            self.vortexStrength = vortexStrength
            self.vortexDirection = vortexDirection
        }

        private enum CodingKeys: String, CodingKey {
            case spawnOccasion, spawnSpreadFactor, spawnVelocityFactor
            case spawnInheritsParentColor, image
            case birthRate, birthRateVariation
            case lifeSpan, lifeSpanVariation, size, sizeVariation
            case sizeMultiplierAtEndOfLifespan, sizeMultiplierAtEndOfLifespanPower
            case mass, massVariation, acceleration, angle, angleVariation
            case angularSpeed, angularSpeedVariation, dampingFactor, spreadAngle, stretchFactor
            case colorSetting, color, color2, colorEvolutionPower
            case opacityCurve, billboardMode, blending, isLightingEnabled, sortOrder
            case noiseStrength, noiseScale, noiseAnimationSpeed
            case attractionStrength, attractionCenter, vortexStrength, vortexDirection
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.spawnOccasion = c.tolerantEnum(.spawnOccasion, default: .onBirth)
            self.spawnSpreadFactor = try c.decodeIfPresent(Float.self, forKey: .spawnSpreadFactor) ?? 0
            self.spawnVelocityFactor = try c.decodeIfPresent(Float.self, forKey: .spawnVelocityFactor) ?? 0
            self.spawnInheritsParentColor = try c.decodeIfPresent(Bool.self, forKey: .spawnInheritsParentColor) ?? false
            self.image = try c.decodeIfPresent(String.self, forKey: .image)
            self.birthRate = try c.decodeIfPresent(Float.self, forKey: .birthRate) ?? 50
            self.birthRateVariation = try c.decodeIfPresent(Float.self, forKey: .birthRateVariation) ?? 0
            self.lifeSpan = try c.decodeIfPresent(Float.self, forKey: .lifeSpan) ?? 1.0
            self.lifeSpanVariation = try c.decodeIfPresent(Float.self, forKey: .lifeSpanVariation) ?? 0
            self.size = try c.decodeIfPresent(Float.self, forKey: .size) ?? 0.03
            self.sizeVariation = try c.decodeIfPresent(Float.self, forKey: .sizeVariation) ?? 0
            self.sizeMultiplierAtEndOfLifespan = try c.decodeIfPresent(Float.self, forKey: .sizeMultiplierAtEndOfLifespan) ?? 1.0
            self.sizeMultiplierAtEndOfLifespanPower = try c.decodeIfPresent(Float.self, forKey: .sizeMultiplierAtEndOfLifespanPower) ?? 1.0
            self.mass = try c.decodeIfPresent(Float.self, forKey: .mass) ?? 1.0
            self.massVariation = try c.decodeIfPresent(Float.self, forKey: .massVariation) ?? 0
            self.acceleration = try c.decodeIfPresent(Vec3.self, forKey: .acceleration) ?? Vec3(0, 0, 0)
            self.angle = try c.decodeIfPresent(Float.self, forKey: .angle) ?? 0
            self.angleVariation = try c.decodeIfPresent(Float.self, forKey: .angleVariation) ?? 0
            self.angularSpeed = try c.decodeIfPresent(Float.self, forKey: .angularSpeed) ?? 0
            self.angularSpeedVariation = try c.decodeIfPresent(Float.self, forKey: .angularSpeedVariation) ?? 0
            self.dampingFactor = try c.decodeIfPresent(Float.self, forKey: .dampingFactor) ?? 0
            self.spreadAngle = try c.decodeIfPresent(Float.self, forKey: .spreadAngle) ?? 0
            self.stretchFactor = try c.decodeIfPresent(Float.self, forKey: .stretchFactor) ?? 0
            self.colorSetting = c.tolerantEnum(.colorSetting, default: .constant)
            self.color = try c.decodeIfPresent(ColorRGBA.self, forKey: .color) ?? ColorRGBA(r: 1, g: 1, b: 1)
            self.color2 = try c.decodeIfPresent(ColorRGBA.self, forKey: .color2) ?? ColorRGBA(r: 1, g: 1, b: 1)
            self.colorEvolutionPower = try c.decodeIfPresent(Float.self, forKey: .colorEvolutionPower) ?? 1.0
            self.opacityCurve = c.tolerantEnum(.opacityCurve, default: .constant)
            self.billboardMode = c.tolerantEnum(.billboardMode, default: .billboard)
            self.blending = c.tolerantEnum(.blending, default: .additive)
            self.isLightingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isLightingEnabled) ?? false
            self.sortOrder = c.tolerantEnum(.sortOrder, default: .unsorted)
            self.noiseStrength = try c.decodeIfPresent(Float.self, forKey: .noiseStrength) ?? 0
            self.noiseScale = try c.decodeIfPresent(Float.self, forKey: .noiseScale) ?? 1.0
            self.noiseAnimationSpeed = try c.decodeIfPresent(Float.self, forKey: .noiseAnimationSpeed) ?? 0
            self.attractionStrength = try c.decodeIfPresent(Float.self, forKey: .attractionStrength) ?? 0
            self.attractionCenter = try c.decodeIfPresent(Vec3.self, forKey: .attractionCenter) ?? Vec3(0, 0, 0)
            self.vortexStrength = try c.decodeIfPresent(Float.self, forKey: .vortexStrength) ?? 0
            self.vortexDirection = try c.decodeIfPresent(Vec3.self, forKey: .vortexDirection) ?? Vec3(0, 1, 0)
        }
    }
}

/// `cylinder` and `torus` are additive (Afterburn parity). `hemisphere` predates
/// the parity pass; players without a native hemisphere fall back to sphere.
public enum ParticleEmitterShape: String, Codable, Sendable, Equatable {
    case point, sphere, hemisphere, cone, plane, box, cylinder, torus
}

/// How newborn particles pick their initial travel direction.
public enum ParticleBirthDirection: String, Codable, Sendable, Equatable {
    case normal, world, local
}

/// Where on the emitter shape particles are born. Players without a native
/// `vertices` mode fall back to `surface` (matching Afterburn's viewport).
public enum ParticleBirthLocation: String, Codable, Sendable, Equatable {
    case surface, volume, vertices
}

/// Color behavior over a particle's lifetime. `.constant` keeps the legacy
/// single-color + opacity-ramp rendering; `.evolving` blends `color → color2`;
/// `.random` picks per-particle (players may approximate as evolving).
public enum ParticleColorMode: String, Codable, Sendable, Equatable {
    case constant, random, evolving
}

/// Opacity-over-lifetime curve, multiplied on top of the start/end opacity ramp.
public enum ParticleOpacityCurve: String, Codable, Sendable, Equatable {
    case constant, fadeIn, fadeOut, fadeInOut, linearFadeIn, linearFadeOut
}

/// Particle orientation mode. Players without free/velocity-aligned rotation
/// fall back to `billboard` (matching Afterburn's viewport).
public enum ParticleBillboardMode: String, Codable, Sendable, Equatable {
    case billboard, billboardYAligned, freeRotating, velocityAligned
}

/// Particle draw-order sorting.
public enum ParticleSortOrder: String, Codable, Sendable, Equatable {
    case unsorted, depthAscending, depthDescending, ageAscending, ageDescending
}

/// When a spawned (secondary) emitter emits relative to its parent particle.
public enum ParticleSpawnOccasion: String, Codable, Sendable, Equatable {
    case onBirth, onDeath, onUpdate
}

// Tolerant string-raw enum decoding: absent OR unrecognized values fall back
// to the field's documented default instead of failing the whole document.
private extension KeyedDecodingContainer {
    func tolerantEnum<E: RawRepresentable>(_ key: Key, default fallback: E) -> E where E.RawValue == String {
        guard let raw = ((try? decodeIfPresent(String.self, forKey: key)) ?? nil) else { return fallback }
        return E(rawValue: raw) ?? fallback
    }
}

// MARK: - Format constants

/// Static format-level constants and helpers.
/// Named distinctly from the `ChapterScript` module to avoid collision when the module is imported.
public enum ChapterScriptFormat {
    /// Current schema version. Increment when emitting a breaking change; pair with a `Migrator` rule.
    /// v3: Sequence vocabulary (`sequences` / `defaultSequenceId`). Migrated from
    /// v2 by `Migrator` — a pure rename, semantically identical. v2 documents
    /// (`segments` / `defaultSegmentId`) still open; v1 was never migrated by design.  LEGACY-VOCAB
    ///
    /// v4: one authored action list per step (`authoredActions`) replacing the
    /// `actions` / `scheduledActions` pair, each entry carrying a stable id.
    /// Migrated from v3 by `Migrator` — semantically identical, and ordering is
    /// the contract (see `StepDefinitionDTO.unify`).
    ///
    /// THE BUMP IS LOAD-BEARING, not decorative. A v4 document no longer writes
    /// `actions` / `scheduledActions` at all, so a v3-era player reading one
    /// would find a step with no actions and play silence rather than fail.
    /// The version is what lets it refuse instead.
    public static let currentFormatVersion: Int = 4

    /// File name inside a `.chapterscript` directory bundle.
    public static let documentFileName = "chapter.json"

    /// Subfolder inside a `.chapterscript` directory bundle that holds referenced media.
    public static let assetsFolderName = "assets"

    /// Encoder configured for stable, diffable format output: sorted keys, pretty-printed JSON.
    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    /// Decoder configured for the format. Currently default; reserved for future tuning.
    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

/// One track's editor-side properties (FL-17). Every field optional:
/// nil is the default, so an untouched track stores nothing.
public struct TrackProperties: Codable, Sendable, Equatable {
    /// Row height in points. nil = the editor's default (the old global
    /// multiplier becomes that default; per-track heights deviate from it).
    public var height: Double?
    /// A colour tag name. Decorative - no state may depend on it.
    public var colorTag: String?
    /// LOCK PROTECTS CONTENT, NOT STACKING POSITION: a locked track
    /// refuses edits in the one arbiter and can still be reordered.
    public var isLocked: Bool?

    public init(height: Double? = nil, colorTag: String? = nil,
                isLocked: Bool? = nil) {
        self.height = height
        self.colorTag = colorTag
        self.isLocked = isLocked
    }

    public var isEmpty: Bool {
        height == nil && colorTag == nil && isLocked == nil
    }
}

/// One Source's authored, findable metadata (FL-20). All optional; an
/// empty record is dropped by the write path rather than stored.
public struct SourceMetadata: Codable, Sendable, Equatable {
    public var keywords: [String]?
    /// 0...5; the write path clamps and reports.
    public var rating: Int?
    public var isFavorite: Bool?

    public init(keywords: [String]? = nil, rating: Int? = nil,
                isFavorite: Bool? = nil) {
        self.keywords = keywords
        self.rating = rating
        self.isFavorite = isFavorite
    }

    public var isEmpty: Bool {
        (keywords?.isEmpty ?? true) && rating == nil && (isFavorite != true)
    }
}
