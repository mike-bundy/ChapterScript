//
//  SubElementOverride.swift
//  ChapterScript
//
//  A NAMED PART OF AN IMPORTED MODEL (FL-16).
//
//  THE PRIM PATH IS THE IDENTITY - unique by construction, authored by
//  whoever built the model, stable across re-export from the same tool.
//  A RealityKit entity name is NOT identity (names need not be unique and
//  the first depth-first match wins), and no entity name is ever stored.
//  A Maestro reference is (objectId, primPath): the objectId is the
//  EntityDefinition this list rides on, so two Objects using one file
//  address their parts independently.
//
//  The transform offset COMPOSES ON TOP of the part's own transform and
//  never rewrites the file's - the same shape as FL-15's bind: authored
//  value on top, imported value read every time. The file is never
//  written; the part list itself is a per-session projection of the stage
//  and is never persisted (a stored hierarchy is a stale fact).
//
//  An unresolved path is KEPT and reported - the missing-media doctrine
//  one level down; the file may be relinked back.
//

import Foundation

public struct SubElementOverride: Codable, Sendable, Equatable {
    /// THE IDENTITY: the complete prim path, e.g. "/Car/Door_Left".
    public var primPath: String
    /// nil = the file's own visibility.
    public var isVisible: Bool?
    /// A TRS OFFSET composed on top of the part's own transform (F-7:
    /// the existing type - the same Inspector, Keys and evaluator as every
    /// other authored transform). nil = no offset. Only a part whose path
    /// resolves with an EMPTY residual is independently transformable;
    /// the write path refuses an offset for any other.
    public var transformOffset: TransformData?
    /// FL-14's per-slot overrides, one level down. nil = none.
    public var materialOverrides: [MaterialOverrideSpec]?

    public init(primPath: String,
                isVisible: Bool? = nil,
                transformOffset: TransformData? = nil,
                materialOverrides: [MaterialOverrideSpec]? = nil) {
        self.primPath = primPath
        self.isVisible = isVisible
        self.transformOffset = transformOffset
        self.materialOverrides = materialOverrides
    }

    /// True when nothing is authored - an empty override is dropped by
    /// authoring rather than stored.
    public var isEmpty: Bool {
        isVisible == nil && transformOffset == nil
            && (materialOverrides?.isEmpty ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case primPath, isVisible, transformOffset, materialOverrides
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.primPath = try c.decode(String.self, forKey: .primPath)
        self.isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible)
        self.transformOffset = try c.decodeIfPresent(TransformData.self,
                                                     forKey: .transformOffset)
        self.materialOverrides = try c.decodeIfPresent(
            [MaterialOverrideSpec].self, forKey: .materialOverrides)
    }
}
