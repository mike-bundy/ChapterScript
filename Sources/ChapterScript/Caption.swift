//
//  Caption.swift
//  ChapterScript
//
//  FL-08: timed text. Caption timing truth lives in exactly one place —
//  `Sequence.captionTracks` — and a cue is NOT an Action and NOT a Clip:
//  its times are absolute Sequence seconds, which is why a cue never moves
//  because something else moved.
//
//  Everything here is additive and tolerant. Absent means "no captions",
//  and a Chapter never told about captions re-saves byte-identically.
//
//  STRUCTURAL RULE: this file holds NO reference to `TextSpec`. Captions
//  and Titles share a shaping path in the editor, never a model.
//

import Foundation

// MARK: - Kind

/// Same-language captions carry speech and non-speech information; subtitles
/// are a translation. A player advertises them differently, so conflating
/// them is a loss of meaning.
///
/// An unrecognised kind decodes as `.subtitles` — the WEAKER claim.
/// Mislabelling a translation as an accessibility artefact would over-claim.
public enum CaptionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case captions
    case subtitles

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptionKind(rawValue: raw) ?? .subtitles
    }
}

// MARK: - Attributed runs (never markup)

/// Per-run styling as data. There is no inline markup mini-language in the
/// model, and there must never be one; SRT/WebVTT tags convert to and from
/// these runs at the interchange boundary.
///
/// `start`/`length` are UTF-16 code-unit offsets into the cue's `text` —
/// the unit both `NSAttributedString` and WebVTT's DOM-ish tags agree on.
public struct CaptionStyleRun: Codable, Sendable, Equatable, Hashable {
    public var start: Int
    public var length: Int
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var color: ColorRGBA?
    /// A WebVTT voice (`<v Speaker>`) — the speaker label, carried as data.
    public var voice: String?

    public init(start: Int, length: Int,
                bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil,
                color: ColorRGBA? = nil, voice: String? = nil) {
        self.start = start
        self.length = length
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.color = color
        self.voice = voice
    }
}

// MARK: - Cue

/// One cue. Its id is durable and minted — never an index, never a hash of
/// the text (the text changes when it is corrected; the identity must not).
/// Times are absolute Sequence seconds, the same clock as Sequence Markers
/// and animation Keys. Cues on one Track may touch but never overlap.
public struct CaptionCue: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var start: Double
    public var end: Double
    public var text: String
    public var runs: [CaptionStyleRun]?
    public var regionId: String?

    public init(id: String = UUID().uuidString,
                start: Double, end: Double, text: String,
                runs: [CaptionStyleRun]? = nil, regionId: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.runs = runs
        self.regionId = regionId
    }
}

// MARK: - Track

/// One language, one Track, one row. Multiple languages are multiple
/// Tracks — never one track with per-cue translations, which would make
/// "delete this cue" ambiguous and break per-language interchange.
public struct CaptionTrack: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Minted, opaque, durable. `EditorMetadata` row properties and
    /// `styleId` references key off this, so it survives a rename.
    public var id: String
    /// BCP-47, REQUIRED from day one. Localization later without a
    /// migration depends on this field existing now.
    public var language: String
    public var kind: CaptionKind
    /// What the author reads. NEVER identity.
    public var label: String?
    /// A reference into the Chapter's caption style library. Unresolved ⇒
    /// the bundled default, and the reference is KEPT.
    public var styleId: String?
    public var cues: [CaptionCue]

    public init(id: String = UUID().uuidString,
                language: String,
                kind: CaptionKind = .captions,
                label: String? = nil,
                styleId: String? = nil,
                cues: [CaptionCue] = []) {
        self.id = id
        self.language = language
        self.kind = kind
        self.label = label
        self.styleId = styleId
        self.cues = cues
    }

    private enum CodingKeys: String, CodingKey {
        case id, language, kind, label, styleId, cues
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        language = try c.decode(String.self, forKey: .language)
        // Absent or unrecognised ⇒ the weaker claim.
        kind = (try? c.decodeIfPresent(CaptionKind.self, forKey: .kind)).flatMap { $0 } ?? .subtitles
        label = try c.decodeIfPresent(String.self, forKey: .label)
        styleId = try c.decodeIfPresent(String.self, forKey: .styleId)
        cues = try c.decodeIfPresent([CaptionCue].self, forKey: .cues) ?? []
    }
}

// MARK: - Presentation

/// Where the words live. This is Maestro's own layer — nothing here is
/// expressible in an SRT or WebVTT sidecar, which is exactly why the model
/// splits: a cue is a (time, text, language) triple that always exports
/// correctly, and presentation is layered on top.
public enum CaptionPresentationMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// The default for immersive content: follows the head at an authored
    /// comfortable distance, so it stays readable as the audience turns.
    case viewerFacing
    /// The words stay with the Screen the speech comes from.
    case screenAttached
    /// Composited flat into the frame; burn-in on export.
    case composited

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CaptionPresentationMode(rawValue: raw) ?? .viewerFacing
    }
}

/// The presentation layer. Referenced by a Track through `styleId`, never
/// inlined on a cue — the same rule a preset follows. Every field is
/// optional and absent means the bundled default.
public struct CaptionStyle: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String?

    // Type
    public var fontFamily: String?
    public var fontWeight: Int?
    /// Metres of cap height, the FL-07 unit.
    public var fontSize: Float?
    public var color: ColorRGBA?
    public var backgroundColor: ColorRGBA?
    public var outlineColor: ColorRGBA?
    public var outlineWidth: Float?

    // Layout
    public var maxLineCount: Int?
    /// Metres.
    public var maxWidth: Float?
    /// Fraction of the frame kept clear when composited flat.
    public var safeAreaInset: Float?

    // Space
    public var mode: CaptionPresentationMode?
    /// Metres from the viewer, for `.viewerFacing`.
    public var distance: Float?
    /// Degrees of visual angle the text block should subtend.
    public var angularSize: Float?
    /// The Screen a `.screenAttached` caption belongs to.
    public var screenEntityId: String?

    public init(id: String = UUID().uuidString, name: String? = nil,
                fontFamily: String? = nil, fontWeight: Int? = nil,
                fontSize: Float? = nil, color: ColorRGBA? = nil,
                backgroundColor: ColorRGBA? = nil,
                outlineColor: ColorRGBA? = nil, outlineWidth: Float? = nil,
                maxLineCount: Int? = nil, maxWidth: Float? = nil,
                safeAreaInset: Float? = nil,
                mode: CaptionPresentationMode? = nil,
                distance: Float? = nil, angularSize: Float? = nil,
                screenEntityId: String? = nil) {
        self.id = id
        self.name = name
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = color
        self.backgroundColor = backgroundColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.maxLineCount = maxLineCount
        self.maxWidth = maxWidth
        self.safeAreaInset = safeAreaInset
        self.mode = mode
        self.distance = distance
        self.angularSize = angularSize
        self.screenEntityId = screenEntityId
    }
}
