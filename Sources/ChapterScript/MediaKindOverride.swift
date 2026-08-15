//
//  MediaKindOverride.swift
//  ChapterScript
//
//  THE AUTHOR'S MEDIA-KIND CORRECTION — the persisted half of media
//  classification.
//
//  Lives in the format package because documents contain it: an author who
//  says "author this .mov as Audio" has made a decision that must survive a
//  save, reach a peer and open on another machine. What the file's TRACKS say
//  is re-read from the bytes on every open and is therefore NOT persisted —
//  see `MaestroKit.MediaTrackComposition`.
//
//  Keeping the two apart is the same rule `AudioInterpretation` follows, and
//  for the same reason: a fact about the bytes and a person's decision are
//  different things, and neither may silently overwrite the other.
//

import Foundation

/// The author's correction, kept apart from the detector's reading for the
/// same reason `AudioInterpretation` is: a person's decision and a fact about
/// the bytes are two different things, and one must never overwrite the other.
public enum MediaKindOverride: String, Codable, Sendable, Equatable, CaseIterable {
    /// Defer to the probe. The default, and what absence encodes to.
    case automatic
    case audio
    case video

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .audio:     return "Audio"
        case .video:     return "Video"
        }
    }

    /// Unknown values decode as `.automatic` — the same forward-compatibility
    /// rule the rest of the format follows, and the safe landing place: a file
    /// classified by its own tracks is never worse than one classified by a
    /// value this build cannot read.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaKindOverride(rawValue: raw) ?? .automatic
    }
}
