//
//  Marker.swift
//  ChapterScript
//
//  THE CHEAPEST NOTE ABOUT TIME IN EXISTENCE (FL-06).
//
//  Two owners, one type. A Marker on a Sequence is at SEQUENCE seconds; a
//  Marker on a media occurrence is at SOURCE seconds — anchored to the
//  picture, so a slip moves the note with the frames, a trim HIDES it
//  rather than destroying it, and a retime redraws it without ever
//  rewriting it. Trim, slip and blade contain no marker mutation code at
//  all; that absence is the design.
//
//  Point or range is ONE type with an optional duration, not two types.
//  The category reference is BY ID, never by name.
//

import Foundation

public struct Marker: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// DURABLE — minted at creation and preserved through every mutation
    /// path: rename, recategorise, move, resize, trim, slip, blade, undo.
    /// Only an explicit duplicate mints a fresh one.
    public var id: String
    /// SOURCE seconds on a Clip Marker; SEQUENCE seconds on a Sequence
    /// Marker. The owner decides the clock; the value never moves for an
    /// edit that did not move the note.
    public var time: Double
    /// nil ⇒ a point. A value makes it a range.
    public var duration: Double?
    public var name: String?
    /// → `MarkerCategory.id`. nil ⇒ the default category. An id that names
    /// no category resolves to the default AND IS KEPT — a round trip
    /// through an older build must not destroy the reference.
    public var categoryId: String?

    public init(id: String, time: Double, duration: Double? = nil,
                name: String? = nil, categoryId: String? = nil) {
        self.id = id
        self.time = time
        self.duration = duration
        self.name = name
        self.categoryId = categoryId
    }
}

/// One row of the Chapter-wide, author-editable category table.
public struct MarkerCategory: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var color: ColorRGBA

    public init(id: String, name: String, color: ColorRGBA) {
        self.id = id
        self.name = name
        self.color = color
    }
}
