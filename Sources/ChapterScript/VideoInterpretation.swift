//
//  VideoInterpretation.swift
//  ChapterScript
//
//  THE AUTHOR'S READING OF A VIDEO SOURCE, KEPT WITH THE PROJECT.
//
//  Three properties of a source file are genuinely separate and were being
//  conflated:
//
//      STEREO      mono, or two eyes
//      LAYOUT      how those eyes are packed — side by side, over under,
//                  two coded views
//      PROJECTION  what the pixels mean — rectilinear, 180°, 360°, Apple
//                  Immersive
//
//  A projection does not imply stereo (a 360° monoscopic tour is ordinary
//  footage), and stereo does not imply a projection (an iPhone Spatial Video
//  is stereo through a 63° lens and belongs on a panel). Deriving either from
//  the other is how a 63° capture came to be recommended for a hemisphere.
//
//  WHAT IS DETECTED AND WHAT IS DECIDED. Multiview stereo, projection kind,
//  camera baseline, field of view and disparity adjustment are all recorded in
//  a file's format description, so they are READ, every time, and never stored
//  here. Frame packing is not: a side-by-side master is indistinguishable from
//  a wide mono movie, and no amount of inspection will ever say otherwise. So
//  that is a DECISION, and this is where the decision lives — beside
//  `audioInterpretations`, which exists for exactly the same reason and keeps
//  exactly the same rule: absent means Automatic, and nothing here ever
//  overwrites what detection found.
//
//  IT BELONGS TO THE SOURCE, NOT TO A CLIP. "This file is packed side by side"
//  is true of the file, so every occurrence inherits it and reinterpreting the
//  source updates them all. The per-clip stereo decision — convergence — is a
//  different thing in a different place (`VideoActionDTO.convergence`).
//

import Foundation

/// What the source's pixels MEAN geometrically.
///
/// Carried so that a projected source can be recognised, never so that it can
/// be silently pasted onto a rectangle: half-equirectangular pixels on a flat
/// panel are a distorted picture, not a window into a scene.
public enum SourceProjection: String, Codable, Sendable, Equatable, CaseIterable {
    case rectilinear
    case halfEquirectangular
    case equirectangular
    case appleImmersive

    public var isProjected: Bool { self != .rectilinear }

    /// How this reads in a message to an author.
    public var displayName: String {
        switch self {
        case .rectilinear:         return "Rectilinear"
        case .halfEquirectangular: return "180° Equirectangular"
        case .equirectangular:     return "360° Equirectangular"
        case .appleImmersive:      return "Apple Immersive Video"
        }
    }
}

/// Which eye a frame-packed source puts first.
///
/// Only meaningful for `sideBySide` and `overUnder`: a multiview file tags its
/// views and the tags are read, so there is nothing to decide. Where it IS
/// ambiguous the wrong answer inverts depth, which looks entirely plausible on
/// a Mac and is wrong only through a headset — so it is offered as a choice
/// rather than assumed.
public enum StereoEyeOrder: String, Codable, Sendable, CaseIterable, Hashable {
    /// Left eye first: the left half, or the top half. The convention every
    /// frame-packed file this format has described uses.
    case leftFirst
    /// Right eye first.
    case rightFirst

    public var displayName: String {
        switch self {
        case .leftFirst:  return "Left / Right"
        case .rightFirst: return "Right / Left"
        }
    }
}

/// Where the author wants a source presented, kept with the project.
///
/// The session-scoped version of this could not survive a reopen, so a project
/// containing a 180° source had to be re-told what it was every time anything
/// new was placed from it.
public enum VideoPlacementPreference: Codable, Sendable, Equatable, Hashable {
    /// A quad in the scene.
    case panel
    /// A shell around the viewer, at the given coverage.
    case immersive(field: ImmersiveField)
    /// The Sequence's environment.
    case backdrop

    private enum CodingKeys: String, CodingKey { case kind, field }
    private enum Kind: String, Codable { case panel, immersive, backdrop }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .panel:
            try c.encode(Kind.panel, forKey: .kind)
        case .immersive(let field):
            try c.encode(Kind.immersive, forKey: .kind)
            try c.encode(field, forKey: .field)
        case .backdrop:
            try c.encode(Kind.backdrop, forKey: .kind)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognised kind reads as a PANEL rather than throwing: a
        // preference written by a newer tool must not stop a project opening,
        // and a panel is the reading that shows the picture undistorted.
        switch try? c.decode(Kind.self, forKey: .kind) {
        case .immersive:
            self = .immersive(field: try c.decodeIfPresent(ImmersiveField.self, forKey: .field)
                              ?? .equirect180)
        case .backdrop: self = .backdrop
        case .panel, nil: self = .panel
        }
    }
}

/// One source file's authored interpretation. Every field absent means
/// "Automatic": defer entirely to what the file itself says.
public struct VideoInterpretation: Codable, Sendable, Equatable {

    /// How the eyes are packed. Only `mono`, `sideBySide` and `overUnder` are
    /// ever stored: `multiviewHEVC` is a detected fact and storing it would
    /// let a document out-argue the container about how many views it has.
    public var layout: VideoLayout?

    /// Which eye comes first in a frame-packed source. Absent means
    /// `leftFirst`, and it is only consulted for a frame-packed layout.
    public var eyeOrder: StereoEyeOrder?

    /// Where the author wants this source presented.
    public var placement: VideoPlacementPreference?

    /// WHAT THE PIXELS MEAN, when the container does not say.
    ///
    /// This file's own header has always named projection as one of the three
    /// separate properties of a source, and this struct did not store it — so a
    /// 360 or 180 master whose container declares no `ProjectionKind` could
    /// never be told what it was. Two such files sit in the owner's corpus:
    /// both are exactly 2:1 and both classified as flat, correctly and
    /// uselessly.
    ///
    /// IT IS A DECISION, NOT A DETECTION, and it is stored for exactly the
    /// reason `layout` is: the fact is unrecoverable by inspection. A declared
    /// `ProjectionKind` still WINS — a document must never out-argue the
    /// container about something the container states — so this is consulted
    /// only when the file is silent. Absent means Automatic.
    ///
    /// NOTHING GUESSES IT. An aspect ratio is not evidence: a 2:1 movie may be
    /// a letterboxed panorama, a scan, or a title card. Detection recommends
    /// and the author decides.
    public var projection: SourceProjection?

    /// HOW THE SOURCE'S COLOUR RELATES TO ITS COVERAGE (FL-04), when the
    /// container does not say. A DECISION, stored for the reason `layout` is:
    /// where the file is silent, no inspection can settle it. A declared
    /// alpha mode still wins. Absent means Automatic.
    public var alpha: SourceAlpha?

    public init(layout: VideoLayout? = nil,
                eyeOrder: StereoEyeOrder? = nil,
                placement: VideoPlacementPreference? = nil,
                projection: SourceProjection? = nil,
                alpha: SourceAlpha? = nil) {
        self.layout = layout
        self.eyeOrder = eyeOrder
        self.placement = placement
        self.projection = projection
        self.alpha = alpha
    }

    /// True when the author has decided nothing — so the record can be dropped
    /// rather than written as an empty object.
    public var isEmpty: Bool {
        layout == nil && eyeOrder == nil && placement == nil && projection == nil
            && alpha == nil
    }

    // Tolerant by hand: an `alpha` case written by a NEWER tool decodes as
    // ABSENT (Automatic) rather than failing the document — and Automatic is
    // the fallback that MEANS the right thing here, per the standing rule
    // that a tolerant decoder that merely parses is not automatically
    // correct. The other fields keep their synthesized strictness.
    private enum CodingKeys: String, CodingKey {
        case layout, eyeOrder, placement, projection, alpha
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.layout = try c.decodeIfPresent(VideoLayout.self, forKey: .layout)
        self.eyeOrder = try c.decodeIfPresent(StereoEyeOrder.self, forKey: .eyeOrder)
        self.placement = try c.decodeIfPresent(VideoPlacementPreference.self, forKey: .placement)
        self.projection = try c.decodeIfPresent(SourceProjection.self, forKey: .projection)
        self.alpha = (try? c.decodeIfPresent(String.self, forKey: .alpha))
            .flatMap { SourceAlpha(rawValue: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(layout, forKey: .layout)
        try c.encodeIfPresent(eyeOrder, forKey: .eyeOrder)
        try c.encodeIfPresent(placement, forKey: .placement)
        try c.encodeIfPresent(projection, forKey: .projection)
        try c.encodeIfPresent(alpha, forKey: .alpha)
    }
}
