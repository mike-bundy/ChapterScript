//
//  SourceAlpha.swift
//  ChapterScript
//
//  TRANSPARENCY IS A DECLARED FACT, NOT A GUESS (FL-04).
//
//  Three states, and exactly three. There is no fourth `unknown` case,
//  because every consumer must always get an answer — the resolver's ladder
//  (declared ▸ decided ▸ default) produces one of these for every source,
//  and a fourth branch would just be the guess moved one level down.
//
//  `opaque` is a STATE, not "premultiplied with α = 1": it lets a pipeline
//  skip the unpremultiply/repremultiply bracket entirely and makes a
//  three-channel source structurally incapable of carrying an alpha bug.
//

import Foundation

/// How a source's color relates to its coverage (alpha).
public enum SourceAlpha: String, Codable, Sendable, Equatable, CaseIterable {
    /// No usable coverage channel. Alpha is 1 everywhere and is TREATED as 1
    /// rather than read.
    case opaque
    /// Unassociated. Color is the surface color; coverage is separate.
    case straight
    /// Associated. Color has already been multiplied by coverage.
    case premultiplied

    /// The author's word for it.
    public var displayName: String {
        switch self {
        case .opaque:        return "Opaque"
        case .straight:      return "Straight"
        case .premultiplied: return "Premultiplied"
        }
    }
}
