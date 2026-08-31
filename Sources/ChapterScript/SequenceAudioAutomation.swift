//
//  SequenceAudioAutomation.swift
//  ChapterScript
//
//  KEYFRAMED AUDIO, AS SEQUENCE STATE.
//
//  Audio volume used to be two things, neither of them editable as a curve:
//  a single static `volume` on `playAudio`, and `fadeAudio(channel:to:
//  duration:)` — a linear ramp authored as a discrete step action. Ducking
//  music under a voice-over and bringing it back meant hand-placing two ramp
//  actions with nothing to see on the timeline and nothing to drag.
//
//  Meanwhile Animation 2.0 already had everything this needs: bezier curves
//  with (dt,dv) handles at ABSOLUTE sequence seconds, one evaluator, and a
//  working graph editor. It was unreachable because `EntityAnimationTrack` is
//  keyed by `entity` — and an audio channel is not an entity.
//
//  So automation lives here, keyed by CHANNEL, reusing `AnimationCurve` and
//  `SequenceAnimationEvaluator` verbatim. Two namespaces stay two namespaces:
//  entities do not gain a volume channel they cannot use, and audio channels
//  do not have to masquerade as entities.
//
//  MIXING. A channel's effective volume is
//
//      playAudio.volume  ×  channelCurve(t)  ×  masterCurve(t)
//
//  Each factor defaults to 1.0 when absent, so a document with no automation
//  behaves exactly as before. The action's own `volume` stays the clip's base
//  level (what the author set when they placed it); the curves are rides on
//  top of it, which is what a mixer does and what makes "turn this clip down"
//  and "fade everything out" independent operations.
//

import Foundation

/// What can be automated on an audio channel.
///
/// The enum was written so pan could be added without a second track type or a
/// format break, and that is exactly what happened: `AudioAutomationTrack`'s
/// decoder already DROPS unknown parameter names rather than throwing, so a
/// document containing a `pan` curve opens in builds that predate it.
///
/// Pan is only meaningful for channel-based material that stays in front of
/// the listener — `AudioPlaybackModel.supportsPan` is true for `.headLocked`
/// and nothing else. A point source's direction comes from its emitter's
/// position, and a sound field's or an object mix's from the renderer; a pan
/// control on either would be a knob that lies. See
/// `docs/AUDIO_ARCHITECTURE.md` §4.
public enum AudioAutomationChannel: String, Codable, Sendable, CaseIterable, Hashable {
    case volume
    /// Stereo placement, −1 hard left … 0 centre … +1 hard right.
    case pan

    /// Value used where the curve has no keys — the IDENTITY for this
    /// parameter's mixing operation, which is not the same constant for every
    /// parameter. Volume composes by multiplication, so its identity is 1;
    /// pan composes by displacement, so its identity is 0. Giving pan a rest
    /// of 1 would silently hard-pan every un-automated channel right.
    public var restValue: Float {
        switch self {
        case .volume: return 1.0
        case .pan:    return 0.0
        }
    }

    /// The range a value is clamped into before it is stored or applied.
    public var range: ClosedRange<Float> {
        switch self {
        case .volume: return 0...1
        case .pan:    return -1...1
        }
    }
}

/// Automation curves for ONE audio channel, over the sequence's timeline.
///
/// `channel` matches `AudioActionDTO.channel`, except for the reserved
/// `AudioAutomationTrack.masterChannel`, which rides every channel at once.
public struct AudioAutomationTrack: Codable, Sendable, Equatable {

    /// The reserved channel id for the master bus. No `playAudio` may use this
    /// name as a real channel; it is a mix bus, not a voice.
    public static let masterChannel = "master"

    public var channel: String
    public var curves: [AudioAutomationChannel: AnimationCurve]

    public init(channel: String, curves: [AudioAutomationChannel: AnimationCurve] = [:]) {
        self.channel = channel
        self.curves = curves
    }

    /// Setting an emptied curve REMOVES it, so `hasAnyKeys` cannot be fooled by
    /// a track full of empty curves — the same rule `EntityAnimationTrack` uses.
    public subscript(_ channel: AudioAutomationChannel) -> AnimationCurve {
        get { curves[channel] ?? AnimationCurve() }
        set { curves[channel] = newValue.isAnimated ? newValue : nil }
    }

    public var isMaster: Bool { channel == Self.masterChannel }

    public var hasAnyKeys: Bool { curves.values.contains { $0.isAnimated } }

    /// Union of key times across channels, sorted and deduplicated within the
    /// curve epsilon — the timeline's automation diamonds.
    public var keyTimes: [Double] {
        var times: [Double] = []
        for curve in curves.values {
            for key in curve.keys where !times.contains(where: {
                abs($0 - key.time) <= AnimationCurve.timeEpsilon
            }) {
                times.append(key.time)
            }
        }
        return times.sorted()
    }

    /// First…last keyed instant, or nil when nothing is keyed.
    public var timeSpan: ClosedRange<Double>? {
        let times = keyTimes
        guard let lo = times.first, let hi = times.last else { return nil }
        return lo...max(hi, lo)
    }

    // Dictionary-with-enum-key encodes as an array pair in JSON, which is
    // unreadable in a hand-inspected document. Encode as a keyed object.
    private enum CodingKeys: String, CodingKey { case channel, curves }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.channel = try c.decode(String.self, forKey: .channel)
        let raw = try c.decodeIfPresent([String: AnimationCurve].self, forKey: .curves) ?? [:]
        var curves: [AudioAutomationChannel: AnimationCurve] = [:]
        for (key, curve) in raw {
            // Unknown parameter names are DROPPED, not thrown: a document
            // written by a newer tool with a `pan` curve must still open here.
            guard let channel = AudioAutomationChannel(rawValue: key) else { continue }
            curves[channel] = curve
        }
        self.curves = curves
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(channel, forKey: .channel)
        var raw: [String: AnimationCurve] = [:]
        for (channel, curve) in curves where curve.isAnimated {
            raw[channel.rawValue] = curve
        }
        try c.encode(raw, forKey: .curves)
    }
}

/// Resolves automated audio values at a point in sequence time.
public enum SequenceAudioAutomation {

    /// The automation multiplier for `channel` at `time`: the channel's own
    /// volume curve times the master curve.
    ///
    /// Returns 1.0 when neither is animated, so this can be applied
    /// unconditionally on every frame without checking whether a document uses
    /// automation at all.
    public static func volumeMultiplier(
        for channel: String,
        at time: Double,
        in tracks: [AudioAutomationTrack]
    ) -> Float {
        value(.volume, for: channel, at: time, in: tracks)
            * masterValue(.volume, at: time, in: tracks)
    }

    /// Effective volume for a playing clip: its authored base level rid by the
    /// channel and master curves. This is THE mixing rule — runtime and editor
    /// preview both call it so they cannot disagree about what a sequence
    /// sounds like.
    public static func effectiveVolume(
        base: Float,
        channel: String,
        at time: Double,
        in tracks: [AudioAutomationTrack],
        muted: Bool = false,
        trackGainDB: Float = 0
    ) -> Float {
        // TRACK MUTE (FL-17): one more scope of THE one formula, never a
        // second one. A muted destination is silent on the very next
        // evaluation - no derived data is consulted.
        if muted { return 0 }
        // TRACK GAIN (FL-18): one more multiply in THE one formula. dB to
        // linear; 0 dB is exactly 1 and costs nothing.
        let trackGain: Float = trackGainDB == 0 ? 1 : pow(10, trackGainDB / 20)
        // Clamped: curve handles can overshoot past a key (that is what makes
        // bezier interpolation useful), and a negative or >1 volume is either
        // a runtime error or silent clipping depending on the platform.
        return min(max(base * trackGain * volumeMultiplier(for: channel, at: time, in: tracks), 0), 1)
    }

    /// Stereo placement for `channel` at `time`, −1 (hard left) … +1 (hard
    /// right). Returns 0 — dead centre — when the channel has no pan curve, so
    /// this too can be applied unconditionally.
    ///
    /// THERE IS NO MASTER PAN, deliberately. Volume rides compose: ducking the
    /// music bus and then fading everything out are two independent, sensible
    /// operations, and multiplying them is exactly right. Panning composes
    /// into nonsense — "pan the whole mix left" is not a mix note, it is a
    /// fault, and summing a master pan into every channel would swing a
    /// carefully placed stereo image sideways with no way to see why. Pan is a
    /// per-channel placement and stops there.
    public static func pan(
        for channel: String,
        at time: Double,
        in tracks: [AudioAutomationTrack]
    ) -> Float {
        let value = self.value(.pan, for: channel, at: time, in: tracks)
        // Clamped for the same reason volume is: bezier handles overshoot past
        // a key on purpose, and a pan beyond ±1 is not a wider image, it is a
        // renderer error.
        return min(max(value, -1), 1)
    }

    /// One parameter's value on one channel, ignoring the master bus.
    public static func value(
        _ parameter: AudioAutomationChannel,
        for channel: String,
        at time: Double,
        in tracks: [AudioAutomationTrack]
    ) -> Float {
        guard let track = tracks.first(where: { $0.channel == channel && !$0.isMaster }) else {
            return parameter.restValue
        }
        let curve = track[parameter]
        guard curve.isAnimated else { return parameter.restValue }
        return SequenceAnimationEvaluator.evaluate(curve, at: time, rest: parameter.restValue)
    }

    /// The master bus value at `time`.
    public static func masterValue(
        _ parameter: AudioAutomationChannel,
        at time: Double,
        in tracks: [AudioAutomationTrack]
    ) -> Float {
        guard let master = tracks.first(where: { $0.isMaster }) else { return parameter.restValue }
        let curve = master[parameter]
        guard curve.isAnimated else { return parameter.restValue }
        return SequenceAnimationEvaluator.evaluate(curve, at: time, rest: parameter.restValue)
    }

    /// True when any track carries a key — lets hosts skip per-frame sampling
    /// entirely for the overwhelmingly common un-automated sequence.
    public static func hasAutomation(_ tracks: [AudioAutomationTrack]) -> Bool {
        tracks.contains { $0.hasAnyKeys }
    }
}
