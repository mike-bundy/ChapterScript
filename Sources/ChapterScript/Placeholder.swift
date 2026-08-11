//
//  Placeholder.swift
//  ChapterScript
//
//  BLOCKING CONTENT BEFORE THE CONTENT EXISTS.
//
//  Most of a chapter's structure — where a panel hangs, how long a shot runs,
//  what the viewer must look at to advance — can be authored long before the
//  footage is shot or the model is built. A placeholder is that structure with
//  the media left out.
//
//  A PLACEHOLDER IS A REAL AUTHORED OBJECT, NOT A STAND-IN FILE.
//
//  The tempting shortcut is to drop a grey MP4 into the bundle and treat it as
//  ordinary media. That is wrong in a way that costs later: the manifest grows
//  entries for files nobody wants shipped, asset hashes churn, `playVideo`
//  points at a lie, and "is this real yet?" becomes a filename convention.
//  Instead a placeholder is its OWN entity kind (`EntityKind.placeholder`) and
//  its own backdrop case (`ImmersiveBackdropSpec.placeholder`), carrying no
//  file reference at all. Nothing in the manifest, nothing on disk.
//
//  IDENTITY IS WHAT MAKES REPLACEMENT CHEAP.
//
//  Every reference to a scene object in this format is BY NAME: step actions
//  target `EntityDefinition.id`, animation tracks key on the same string, gates
//  name a `targetEntity`. So swapping a placeholder for real media is a change
//  to ONE definition's kind and specs — the id stays, and therefore timing,
//  transform, animation curves and interactions are preserved by construction
//  rather than by a migration that walks the document and hopes. The same holds
//  for a backdrop placeholder: the cue keeps its id, start time and source
//  range; only its `spec` changes case.
//
//  See `MaestroKit.PlaceholderReplacement` for the editor-side operation.
//

import Foundation

/// What a placeholder is standing in for. This drives BOTH the editor's
/// neutral proxy visual and what a replacement is allowed to be.
public enum PlaceholderRole: String, Codable, Sendable, Equatable, CaseIterable {
    /// A flat video panel in the scene — replaced by a video file.
    case videoPanel
    /// A 360° / 180° / Apple Immersive surround — replaced by a video file.
    /// Note that a placeholder in this role can be authored either as a scene
    /// entity (an immersive clip) or as a backdrop cue; see
    /// `ImmersiveBackdropSpec.placeholder`.
    case immersiveVideo
    /// A 3D object — replaced by a USDZ model.
    case entity3D

    /// Tolerant decode: a role written by a newer tool degrades to the most
    /// inert proxy (a neutral box) rather than failing the whole document —
    /// the same rule `GateType` and `ImmersiveField` follow.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        self = PlaceholderRole(rawValue: raw) ?? .entity3D
    }
}

/// The authored description of a not-yet-existing piece of content.
///
/// Everything here is authoring intent. A player that encounters a placeholder
/// is expected to draw an obvious neutral proxy (or nothing at all) — a
/// placeholder must never be mistaken for finished content in a review build.
public struct PlaceholderSpec: Codable, Sendable, Equatable {

    /// What kind of content will eventually land here.
    public var role: PlaceholderRole

    /// Author-facing name shown on the proxy in the Viewer and on its timeline
    /// clip — "Interview A-roll", "Lobby set". Never a filename: a placeholder
    /// has no file.
    public var label: String

    /// Free-form production note ("shoot week of the 12th, 2-cam").
    public var notes: String?

    /// Intended runtime length in seconds, for roles that run on a clock.
    ///
    /// This is a PLANNING figure, not the authored duration: the clip's actual
    /// extent on the timeline is its step/scheduled placement, exactly like
    /// real media. It exists so an editor can size a freshly dropped
    /// placeholder sensibly and so a replacement can be flagged when the real
    /// file turns out to be a different length. `nil` for `.entity3D`.
    public var intendedDuration: Double?

    /// Proxy size in meters. For `.videoPanel` this is the panel's width and
    /// height (z ignored); for `.entity3D` it is the bounding box the model is
    /// expected to occupy. Ignored for `.immersiveVideo`, which is a shell.
    public var size: Vec3?

    /// Projection for `.immersiveVideo` — the same concept the real clip will
    /// use, so switching to the finished file changes nothing about how the
    /// sequence is framed. `nil` elsewhere.
    public var field: ImmersiveField?

    /// Expected eye packing for a video role, carried so a replacement starts
    /// from the author's intent rather than re-guessing. `nil` = mono.
    public var layout: VideoLayout?

    /// Shell radius in meters for `.immersiveVideo`. `nil` = the player's
    /// default (~1000 m).
    public var radius: Float?

    public init(
        role: PlaceholderRole,
        label: String,
        notes: String? = nil,
        intendedDuration: Double? = nil,
        size: Vec3? = nil,
        field: ImmersiveField? = nil,
        layout: VideoLayout? = nil,
        radius: Float? = nil
    ) {
        self.role = role
        self.label = label
        self.notes = notes
        self.intendedDuration = intendedDuration
        self.size = size
        self.field = field
        self.layout = layout
        self.radius = radius
    }

    // MARK: - Role-shaped constructors

    /// Default panel proxy: 16:9 at the same 1.6 × 0.9 m the real video panel
    /// defaults to, so replacing one does not resize the shot.
    public static func videoPanel(
        label: String,
        width: Float = 1.6,
        height: Float = 0.9,
        intendedDuration: Double? = nil
    ) -> PlaceholderSpec {
        PlaceholderSpec(
            role: .videoPanel,
            label: label,
            intendedDuration: intendedDuration,
            size: Vec3(width, height, 0)
        )
    }

    /// Immersive proxy at an explicit projection. `.appleImmersiveDefault`,
    /// `.equirect180` and `.equirect360` are the three the editor offers.
    public static func immersiveVideo(
        label: String,
        field: ImmersiveField,
        radius: Float = 1000,
        intendedDuration: Double? = nil
    ) -> PlaceholderSpec {
        PlaceholderSpec(
            role: .immersiveVideo,
            label: label,
            intendedDuration: intendedDuration,
            field: field,
            radius: radius
        )
    }

    /// Model proxy: a half-metre neutral box unless the author sizes it.
    public static func entity3D(
        label: String,
        size: Vec3 = Vec3(0.5, 0.5, 0.5)
    ) -> PlaceholderSpec {
        PlaceholderSpec(role: .entity3D, label: label, size: size)
    }

    // MARK: - Derived

    /// Whether this placeholder occupies time (and so gets in/out points, a
    /// duration and a media-shaped clip) rather than merely existing in space.
    public var isTimeBased: Bool {
        role != .entity3D
    }

    /// The file extension a replacement must have. An editor uses this to
    /// filter the Replace Asset… picker so a USDZ can't land on a video panel.
    public var replacementContentTypes: [String] {
        switch role {
        case .videoPanel, .immersiveVideo: return ["mov", "mp4", "m4v", "aivu"]
        case .entity3D:                    return ["usdz", "usda", "usdc", "reality"]
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case role, label, notes, intendedDuration, size, field, layout, radius
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Every field tolerant: a placeholder is authoring scaffolding, and a
        // document must never fail to open because scaffolding was written by
        // a newer tool.
        self.role = try c.decodeIfPresent(PlaceholderRole.self, forKey: .role) ?? .entity3D
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Placeholder"
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.intendedDuration = try c.decodeIfPresent(Double.self, forKey: .intendedDuration)
        self.size = try c.decodeIfPresent(Vec3.self, forKey: .size)
        self.field = try c.decodeIfPresent(ImmersiveField.self, forKey: .field)
        self.layout = try c.decodeIfPresent(VideoLayout.self, forKey: .layout)
        self.radius = try c.decodeIfPresent(Float.self, forKey: .radius)
    }
}
