//
//  VideoTransitionSpec.swift
//  ChapterScript
//
//  FL-12: one genuine two-source picture transition, stored on the
//  INCOMING occurrence beside its source range — it describes an edit
//  point, so it lives with the occurrence whose arrival does the fading.
//
//  The kind travels as a RAW STRING: an unrecognised kind must not
//  decode to any shipped look (that would invent a picture the author
//  did not author) — it means NO transition, the Inspector reports, and
//  the raw value re-saves verbatim. The G7 shape.
//

import Foundation

public struct VideoTransitionSpec: Codable, Sendable, Equatable, Hashable {
    /// The wire kind. `"crossDissolve"` is the one this build renders.
    public var kindRaw: String
    /// The OVERLAP length, Timeline seconds.
    public var duration: Double

    public static let crossDissolveKind = "crossDissolve"

    public init(kindRaw: String = VideoTransitionSpec.crossDissolveKind,
                duration: Double) {
        self.kindRaw = kindRaw
        self.duration = duration
    }

    /// Whether THIS build can render the kind. False ⇒ no transition is
    /// applied and the spec rides along untouched.
    public var isRenderable: Bool { kindRaw == Self.crossDissolveKind }

    private enum CodingKeys: String, CodingKey { case kindRaw = "kind", duration }
}
