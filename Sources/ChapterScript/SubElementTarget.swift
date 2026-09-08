//
//  SubElementTarget.swift
//  ChapterScript
//
//  A TYPED REFERENCE TO ONE PART OF ONE OBJECT (FL-16).
//
//  The pair is indivisible: a prim path is unique only inside the USD stage
//  loaded for one authored Object. A RealityKit entity name and a leaf name
//  are realization details and never appear here.
//

import Foundation

public struct SubElementTarget: Codable, Sendable, Equatable, Hashable {
    public var objectId: String
    public var primPath: String

    public init(objectId: String, primPath: String) {
        self.objectId = objectId
        self.primPath = primPath
    }
}

/// One composable Action directed at a stored USD part.
///
/// This is deliberately a patch rather than a second family of show/move/
/// material commands. Every non-nil field is applied atomically to the one
/// typed target; absent fields mean "leave that authored fact alone". The
/// loaded USD bytes and the Object's stored `SubElementOverride` are never
/// rewritten by runtime execution.
public struct SubElementActionDTO: Codable, Sendable, Equatable {
    public var target: SubElementTarget
    public var isVisible: Bool?
    public var transformOffset: TransformData?
    public var materialOverrides: [MaterialOverrideSpec]?

    public init(
        target: SubElementTarget,
        isVisible: Bool? = nil,
        transformOffset: TransformData? = nil,
        materialOverrides: [MaterialOverrideSpec]? = nil
    ) {
        self.target = target
        self.isVisible = isVisible
        self.transformOffset = transformOffset
        self.materialOverrides = materialOverrides
    }

    public var isEmpty: Bool {
        isVisible == nil && transformOffset == nil
            && (materialOverrides?.isEmpty ?? true)
    }
}
