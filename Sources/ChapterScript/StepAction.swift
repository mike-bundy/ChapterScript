import Foundation

/// A single composable step action. Mirrors the runtime `StepAction` enum from the
/// player's ChapterEngine, but uses primitive value types (Vec3, ColorRGBA, VisibilityKind)
/// so the format has no RealityKit / SwiftUI / AVFoundation dependencies.
///
/// JSON wire format is externally tagged: `{"kind": "showEntity", ...}`.
/// Unknown future cases parse into `.unknown(name:raw:)` rather than failing decode.
public indirect enum StepActionDTO: Sendable, Equatable {
    // Entity
    case showEntity(name: String)
    case hideEntity(name: String)
    case moveEntity(MoveActionDTO)
    case scaleEntity(name: String, multiplier: Float, duration: Double, timing: StepTimingFunction)
    case fadeEntity(FadeActionDTO)
    case persistEntity(name: String)
    case unpersistEntity(name: String)
    case revealEntity(RevealActionDTO)
    case animateMotion(AnimateMotionActionDTO)

    // Attachments
    case showAttachment(id: String)
    case hideAttachment(id: String)
    case fadeAttachment(id: String, opacity: Float, duration: Double)
    case setAttachmentView(id: String, viewId: String)
    case positionAttachment(id: String, headRelativePosition: Vec3, headYOnly: Bool)

    // Audio
    case playAudio(AudioActionDTO)
    case stopAudio(channel: String)
    case fadeAudio(channel: String, to: Float, duration: Double)
    case onAudioComplete(channel: String, then: [StepActionDTO])

    // Video
    case playVideo(VideoActionDTO)
    case prepareVideo(VideoActionDTO)
    case stopVideo(channel: String)

    // Effects (built-in example library)
    case showPulseRing(PulseRingConfigDTO)
    case hidePulseRing
    case startSparkBurst(SparkBurstConfigDTO)
    case stopSparkBurst

    // Audio Mix
    case setMasterVolume(Float)
    case setCategoryVolume(category: String, volume: Float)

    // Audio Zones
    case addAudioZone(AudioZoneDTO)
    case removeAudioZone(id: String)
    case removeAllAudioZones

    // Audio Bus
    case setBusVolume(busId: String, volume: Float)
    case setBusEffect(busId: String, effect: AudioEffectDTO)
    case removeBusEffect(busId: String, effect: AudioEffectDTO)

    // Gesture
    case enableGesture(entity: String)
    case disableGesture(entity: String)

    // System
    case setUpperLimbVisibility(VisibilityKind)
    case setKeyboardPassthrough(Bool)

    // Custom escape hatch
    case custom(id: String, parameters: [String: AnyCodableValue]?)

    /// Forward-compat sink for any case the current decoder doesn't recognize.
    /// Editors should preserve and re-emit `raw` unchanged. Players should log + skip.
    case unknown(name: String, raw: AnyCodableValue)
}

// MARK: - Codable

extension StepActionDTO: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case name, id, channel, busId, category, viewId
        case multiplier, opacity, duration, timing, volume, to
        case headRelativePosition, headYOnly
        case action, audio, video, fade, reveal, move, motion
        case config, zone, effect, then
        case visibility, enabled, on
        case parameters
    }

    private enum Kind: String, Codable {
        case showEntity, hideEntity, moveEntity, scaleEntity, fadeEntity
        case persistEntity, unpersistEntity, revealEntity, animateMotion
        case showAttachment, hideAttachment, fadeAttachment, setAttachmentView, positionAttachment
        case playAudio, stopAudio, fadeAudio, onAudioComplete
        case playVideo, prepareVideo, stopVideo
        case showPulseRing, hidePulseRing, startSparkBurst, stopSparkBurst
        case setMasterVolume, setCategoryVolume
        case addAudioZone, removeAudioZone, removeAllAudioZones
        case setBusVolume, setBusEffect, removeBusEffect
        case enableGesture, disableGesture
        case setUpperLimbVisibility, setKeyboardPassthrough
        case custom
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .showEntity(let name):
            try c.encode(Kind.showEntity, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .hideEntity(let name):
            try c.encode(Kind.hideEntity, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .moveEntity(let m):
            try c.encode(Kind.moveEntity, forKey: .kind)
            try c.encode(m, forKey: .move)
        case .scaleEntity(let name, let mult, let dur, let timing):
            try c.encode(Kind.scaleEntity, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(mult, forKey: .multiplier)
            try c.encode(dur, forKey: .duration)
            try c.encode(timing, forKey: .timing)
        case .fadeEntity(let f):
            try c.encode(Kind.fadeEntity, forKey: .kind)
            try c.encode(f, forKey: .fade)
        case .persistEntity(let name):
            try c.encode(Kind.persistEntity, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .unpersistEntity(let name):
            try c.encode(Kind.unpersistEntity, forKey: .kind)
            try c.encode(name, forKey: .name)
        case .revealEntity(let r):
            try c.encode(Kind.revealEntity, forKey: .kind)
            try c.encode(r, forKey: .reveal)
        case .animateMotion(let m):
            try c.encode(Kind.animateMotion, forKey: .kind)
            try c.encode(m, forKey: .motion)
        case .showAttachment(let id):
            try c.encode(Kind.showAttachment, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .hideAttachment(let id):
            try c.encode(Kind.hideAttachment, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .fadeAttachment(let id, let opacity, let duration):
            try c.encode(Kind.fadeAttachment, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(opacity, forKey: .opacity)
            try c.encode(duration, forKey: .duration)
        case .setAttachmentView(let id, let viewId):
            try c.encode(Kind.setAttachmentView, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(viewId, forKey: .viewId)
        case .positionAttachment(let id, let pos, let yOnly):
            try c.encode(Kind.positionAttachment, forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(pos, forKey: .headRelativePosition)
            try c.encode(yOnly, forKey: .headYOnly)
        case .playAudio(let a):
            try c.encode(Kind.playAudio, forKey: .kind)
            try c.encode(a, forKey: .audio)
        case .stopAudio(let channel):
            try c.encode(Kind.stopAudio, forKey: .kind)
            try c.encode(channel, forKey: .channel)
        case .fadeAudio(let channel, let to, let duration):
            try c.encode(Kind.fadeAudio, forKey: .kind)
            try c.encode(channel, forKey: .channel)
            try c.encode(to, forKey: .to)
            try c.encode(duration, forKey: .duration)
        case .onAudioComplete(let channel, let then):
            try c.encode(Kind.onAudioComplete, forKey: .kind)
            try c.encode(channel, forKey: .channel)
            try c.encode(then, forKey: .then)
        case .playVideo(let v):
            try c.encode(Kind.playVideo, forKey: .kind)
            try c.encode(v, forKey: .video)
        case .prepareVideo(let v):
            try c.encode(Kind.prepareVideo, forKey: .kind)
            try c.encode(v, forKey: .video)
        case .stopVideo(let channel):
            try c.encode(Kind.stopVideo, forKey: .kind)
            try c.encode(channel, forKey: .channel)
        case .showPulseRing(let cfg):
            try c.encode(Kind.showPulseRing, forKey: .kind)
            try c.encode(cfg, forKey: .config)
        case .hidePulseRing:
            try c.encode(Kind.hidePulseRing, forKey: .kind)
        case .startSparkBurst(let cfg):
            try c.encode(Kind.startSparkBurst, forKey: .kind)
            try c.encode(cfg, forKey: .config)
        case .stopSparkBurst:
            try c.encode(Kind.stopSparkBurst, forKey: .kind)
        case .setMasterVolume(let v):
            try c.encode(Kind.setMasterVolume, forKey: .kind)
            try c.encode(v, forKey: .volume)
        case .setCategoryVolume(let category, let volume):
            try c.encode(Kind.setCategoryVolume, forKey: .kind)
            try c.encode(category, forKey: .category)
            try c.encode(volume, forKey: .volume)
        case .addAudioZone(let zone):
            try c.encode(Kind.addAudioZone, forKey: .kind)
            try c.encode(zone, forKey: .zone)
        case .removeAudioZone(let id):
            try c.encode(Kind.removeAudioZone, forKey: .kind)
            try c.encode(id, forKey: .id)
        case .removeAllAudioZones:
            try c.encode(Kind.removeAllAudioZones, forKey: .kind)
        case .setBusVolume(let busId, let volume):
            try c.encode(Kind.setBusVolume, forKey: .kind)
            try c.encode(busId, forKey: .busId)
            try c.encode(volume, forKey: .volume)
        case .setBusEffect(let busId, let effect):
            try c.encode(Kind.setBusEffect, forKey: .kind)
            try c.encode(busId, forKey: .busId)
            try c.encode(effect, forKey: .effect)
        case .removeBusEffect(let busId, let effect):
            try c.encode(Kind.removeBusEffect, forKey: .kind)
            try c.encode(busId, forKey: .busId)
            try c.encode(effect, forKey: .effect)
        case .enableGesture(let entity):
            try c.encode(Kind.enableGesture, forKey: .kind)
            try c.encode(entity, forKey: .name)
        case .disableGesture(let entity):
            try c.encode(Kind.disableGesture, forKey: .kind)
            try c.encode(entity, forKey: .name)
        case .setUpperLimbVisibility(let v):
            try c.encode(Kind.setUpperLimbVisibility, forKey: .kind)
            try c.encode(v, forKey: .visibility)
        case .setKeyboardPassthrough(let on):
            try c.encode(Kind.setKeyboardPassthrough, forKey: .kind)
            try c.encode(on, forKey: .on)
        case .custom(let id, let params):
            try c.encode(Kind.custom, forKey: .kind)
            try c.encode(id, forKey: .id)
            if let params { try c.encode(params, forKey: .parameters) }
        case .unknown(let name, let raw):
            // Round-trip preservation: emit the original kind + its raw payload.
            // We re-flatten into the keyed container by re-encoding raw as a single value.
            // Editors that preserve `unknown` cases keep forward-compat round-trips.
            try c.encode(name, forKey: .kind)
            // Use a separate single-value encoder under the same parent to write raw fields.
            try raw.encode(to: UnknownPassthroughEncoder(parent: encoder))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kindString = try c.decode(String.self, forKey: .kind)

        guard let kind = Kind(rawValue: kindString) else {
            // Forward-compat: read whole object as AnyCodableValue and stash.
            let raw = try AnyCodableValue(from: decoder)
            self = .unknown(name: kindString, raw: raw)
            return
        }

        switch kind {
        case .showEntity:
            self = .showEntity(name: try c.decode(String.self, forKey: .name))
        case .hideEntity:
            self = .hideEntity(name: try c.decode(String.self, forKey: .name))
        case .moveEntity:
            self = .moveEntity(try c.decode(MoveActionDTO.self, forKey: .move))
        case .scaleEntity:
            self = .scaleEntity(
                name: try c.decode(String.self, forKey: .name),
                multiplier: try c.decode(Float.self, forKey: .multiplier),
                duration: try c.decode(Double.self, forKey: .duration),
                timing: try c.decode(StepTimingFunction.self, forKey: .timing)
            )
        case .fadeEntity:
            self = .fadeEntity(try c.decode(FadeActionDTO.self, forKey: .fade))
        case .persistEntity:
            self = .persistEntity(name: try c.decode(String.self, forKey: .name))
        case .unpersistEntity:
            self = .unpersistEntity(name: try c.decode(String.self, forKey: .name))
        case .revealEntity:
            self = .revealEntity(try c.decode(RevealActionDTO.self, forKey: .reveal))
        case .animateMotion:
            self = .animateMotion(try c.decode(AnimateMotionActionDTO.self, forKey: .motion))
        case .showAttachment:
            self = .showAttachment(id: try c.decode(String.self, forKey: .id))
        case .hideAttachment:
            self = .hideAttachment(id: try c.decode(String.self, forKey: .id))
        case .fadeAttachment:
            self = .fadeAttachment(
                id: try c.decode(String.self, forKey: .id),
                opacity: try c.decode(Float.self, forKey: .opacity),
                duration: try c.decode(Double.self, forKey: .duration)
            )
        case .setAttachmentView:
            self = .setAttachmentView(
                id: try c.decode(String.self, forKey: .id),
                viewId: try c.decode(String.self, forKey: .viewId)
            )
        case .positionAttachment:
            self = .positionAttachment(
                id: try c.decode(String.self, forKey: .id),
                headRelativePosition: try c.decode(Vec3.self, forKey: .headRelativePosition),
                headYOnly: try c.decode(Bool.self, forKey: .headYOnly)
            )
        case .playAudio:
            self = .playAudio(try c.decode(AudioActionDTO.self, forKey: .audio))
        case .stopAudio:
            self = .stopAudio(channel: try c.decode(String.self, forKey: .channel))
        case .fadeAudio:
            self = .fadeAudio(
                channel: try c.decode(String.self, forKey: .channel),
                to: try c.decode(Float.self, forKey: .to),
                duration: try c.decode(Double.self, forKey: .duration)
            )
        case .onAudioComplete:
            self = .onAudioComplete(
                channel: try c.decode(String.self, forKey: .channel),
                then: try c.decode([StepActionDTO].self, forKey: .then)
            )
        case .playVideo:
            self = .playVideo(try c.decode(VideoActionDTO.self, forKey: .video))
        case .prepareVideo:
            self = .prepareVideo(try c.decode(VideoActionDTO.self, forKey: .video))
        case .stopVideo:
            self = .stopVideo(channel: try c.decode(String.self, forKey: .channel))
        case .showPulseRing:
            self = .showPulseRing(try c.decode(PulseRingConfigDTO.self, forKey: .config))
        case .hidePulseRing:
            self = .hidePulseRing
        case .startSparkBurst:
            self = .startSparkBurst(try c.decode(SparkBurstConfigDTO.self, forKey: .config))
        case .stopSparkBurst:
            self = .stopSparkBurst
        case .setMasterVolume:
            self = .setMasterVolume(try c.decode(Float.self, forKey: .volume))
        case .setCategoryVolume:
            self = .setCategoryVolume(
                category: try c.decode(String.self, forKey: .category),
                volume: try c.decode(Float.self, forKey: .volume)
            )
        case .addAudioZone:
            self = .addAudioZone(try c.decode(AudioZoneDTO.self, forKey: .zone))
        case .removeAudioZone:
            self = .removeAudioZone(id: try c.decode(String.self, forKey: .id))
        case .removeAllAudioZones:
            self = .removeAllAudioZones
        case .setBusVolume:
            self = .setBusVolume(
                busId: try c.decode(String.self, forKey: .busId),
                volume: try c.decode(Float.self, forKey: .volume)
            )
        case .setBusEffect:
            self = .setBusEffect(
                busId: try c.decode(String.self, forKey: .busId),
                effect: try c.decode(AudioEffectDTO.self, forKey: .effect)
            )
        case .removeBusEffect:
            self = .removeBusEffect(
                busId: try c.decode(String.self, forKey: .busId),
                effect: try c.decode(AudioEffectDTO.self, forKey: .effect)
            )
        case .enableGesture:
            self = .enableGesture(entity: try c.decode(String.self, forKey: .name))
        case .disableGesture:
            self = .disableGesture(entity: try c.decode(String.self, forKey: .name))
        case .setUpperLimbVisibility:
            self = .setUpperLimbVisibility(try c.decode(VisibilityKind.self, forKey: .visibility))
        case .setKeyboardPassthrough:
            self = .setKeyboardPassthrough(try c.decode(Bool.self, forKey: .on))
        case .custom:
            self = .custom(
                id: try c.decode(String.self, forKey: .id),
                parameters: try c.decodeIfPresent([String: AnyCodableValue].self, forKey: .parameters)
            )
        }
    }
}

// MARK: - Unknown round-trip helper

/// Internal encoder shim that lets `unknown.raw` re-flatten into a parent's keyed container.
/// We delegate to the parent's underlying writer by re-encoding into the same encoder.
private struct UnknownPassthroughEncoder: Encoder {
    let parent: Encoder
    var codingPath: [CodingKey] { parent.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { parent.userInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        parent.container(keyedBy: type)
    }
    func unkeyedContainer() -> UnkeyedEncodingContainer { parent.unkeyedContainer() }
    func singleValueContainer() -> SingleValueEncodingContainer { parent.singleValueContainer() }
}
