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

    public init(layout: VideoLayout? = nil,
                eyeOrder: StereoEyeOrder? = nil,
                placement: VideoPlacementPreference? = nil) {
        self.layout = layout
        self.eyeOrder = eyeOrder
        self.placement = placement
    }

    /// True when the author has decided nothing — so the record can be dropped
    /// rather than written as an empty object.
    public var isEmpty: Bool {
        layout == nil && eyeOrder == nil && placement == nil
    }
}
