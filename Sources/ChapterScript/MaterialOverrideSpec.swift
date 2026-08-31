//
//  MaterialOverrideSpec.swift
//  ChapterScript
//
//  PER-SLOT MATERIAL OVERRIDES (FL-14).
//
//  Three layers, one rule: the FILE declares its materials and is NEVER
//  written; an Object occurrence overrides per slot, per field; a
//  sub-element override is FL-16's. `nil` on any field means "the file's
//  own value" — which is what makes Reset to Source exact by construction:
//  clearing a field restores the file's value because the file's value was
//  never overwritten.
//
//  THE SLOT IS THE IDENTITY; the name is a label. A mesh guarantees its
//  material count and order; names are whatever the file happened to say.
//  An override whose slot exceeds a (relinked) file's count is KEPT and
//  REPORTED, never dropped — the file may be relinked back.
//
//  `PrimitiveSpec.material` is unchanged: a primitive's one slot keeps its
//  existing full `MaterialSpec`, and no document changes shape for it.
//

import Foundation

public struct MaterialOverrideSpec: Codable, Sendable, Equatable {
    /// The slot index this overrides — THE identity.
    public var slot: Int
    /// The file's material name at authoring time. REPORTING ONLY,
    /// never a key.
    public var slotName: String?

    public var baseColor: ColorRGBA?
    public var roughness: Float?
    public var metallic: Float?
    public var opacity: Float?
    public var emissiveColor: ColorRGBA?
    public var emissiveIntensity: Float?
    /// The blend mode. An unrecognised value decodes as nil (the weakest
    /// visual claim — the file's own) and its raw string round-trips
    /// verbatim through `unknownBlending`.
    public var blending: MaterialBlending?
    /// "Ignores Lighting" — realized as `UnlitMaterial`.
    public var unlit: Bool?
    /// Texture references: ordinary Source ids, relinking as media does.
    public var baseColorTextureSourceId: String?
    public var normalTextureSourceId: String?
    /// A ShaderGraphMaterial's exposed named inputs. Preserved verbatim
    /// when unrecognised (G7's discipline one level down).
    public var shaderInputs: [String: EffectValue]?

    /// The verbatim raw value of an unrecognised `blending` — kept so a
    /// document written by a newer build re-saves byte-identically.
    public var unknownBlending: String?

    public init(slot: Int,
                slotName: String? = nil,
                baseColor: ColorRGBA? = nil,
                roughness: Float? = nil,
                metallic: Float? = nil,
                opacity: Float? = nil,
                emissiveColor: ColorRGBA? = nil,
                emissiveIntensity: Float? = nil,
                blending: MaterialBlending? = nil,
                unlit: Bool? = nil,
                baseColorTextureSourceId: String? = nil,
                normalTextureSourceId: String? = nil,
                shaderInputs: [String: EffectValue]? = nil) {
        self.slot = slot
        self.slotName = slotName
        self.baseColor = baseColor
        self.roughness = roughness
        self.metallic = metallic
        self.opacity = opacity
        self.emissiveColor = emissiveColor
        self.emissiveIntensity = emissiveIntensity
        self.blending = blending
        self.unlit = unlit
        self.baseColorTextureSourceId = baseColorTextureSourceId
        self.normalTextureSourceId = normalTextureSourceId
        self.shaderInputs = shaderInputs
        self.unknownBlending = nil
    }

    /// True when no field overrides anything — an empty override is
    /// dropped by authoring rather than stored.
    public var isEmpty: Bool {
        baseColor == nil && roughness == nil && metallic == nil
            && opacity == nil && emissiveColor == nil
            && emissiveIntensity == nil && blending == nil
            && unknownBlending == nil && unlit == nil
            && baseColorTextureSourceId == nil
            && normalTextureSourceId == nil
            && (shaderInputs?.isEmpty ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case slot, slotName, baseColor, roughness, metallic, opacity
        case emissiveColor, emissiveIntensity, blending, unlit
        case baseColorTextureSourceId, normalTextureSourceId, shaderInputs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.slot = try c.decode(Int.self, forKey: .slot)
        self.slotName = try c.decodeIfPresent(String.self, forKey: .slotName)
        self.baseColor = try c.decodeIfPresent(ColorRGBA.self, forKey: .baseColor)
        self.roughness = try c.decodeIfPresent(Float.self, forKey: .roughness)
        self.metallic = try c.decodeIfPresent(Float.self, forKey: .metallic)
        self.opacity = try c.decodeIfPresent(Float.self, forKey: .opacity)
        self.emissiveColor = try c.decodeIfPresent(ColorRGBA.self, forKey: .emissiveColor)
        self.emissiveIntensity = try c.decodeIfPresent(Float.self, forKey: .emissiveIntensity)
        if let raw = try c.decodeIfPresent(String.self, forKey: .blending) {
            if let known = MaterialBlending(rawValue: raw) {
                self.blending = known
                self.unknownBlending = nil
            } else {
                // The weakest visual claim, and the raw value survives.
                self.blending = nil
                self.unknownBlending = raw
            }
        } else {
            self.blending = nil
            self.unknownBlending = nil
        }
        self.unlit = try c.decodeIfPresent(Bool.self, forKey: .unlit)
        self.baseColorTextureSourceId = try c.decodeIfPresent(
            String.self, forKey: .baseColorTextureSourceId)
        self.normalTextureSourceId = try c.decodeIfPresent(
            String.self, forKey: .normalTextureSourceId)
        self.shaderInputs = try c.decodeIfPresent(
            [String: EffectValue].self, forKey: .shaderInputs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(slot, forKey: .slot)
        try c.encodeIfPresent(slotName, forKey: .slotName)
        try c.encodeIfPresent(baseColor, forKey: .baseColor)
        try c.encodeIfPresent(roughness, forKey: .roughness)
        try c.encodeIfPresent(metallic, forKey: .metallic)
        try c.encodeIfPresent(opacity, forKey: .opacity)
        try c.encodeIfPresent(emissiveColor, forKey: .emissiveColor)
        try c.encodeIfPresent(emissiveIntensity, forKey: .emissiveIntensity)
        if let unknownBlending {
            try c.encode(unknownBlending, forKey: .blending)
        } else {
            try c.encodeIfPresent(blending?.rawValue, forKey: .blending)
        }
        try c.encodeIfPresent(unlit, forKey: .unlit)
        try c.encodeIfPresent(baseColorTextureSourceId, forKey: .baseColorTextureSourceId)
        try c.encodeIfPresent(normalTextureSourceId, forKey: .normalTextureSourceId)
        try c.encodeIfPresent(shaderInputs, forKey: .shaderInputs)
    }
}
