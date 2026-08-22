//
//  SequenceStereoAutomation.swift
//  ChapterScript
//
//  KEYFRAMED CONVERGENCE, AS SEQUENCE STATE.
//
//  A stereo source arrives with its own left/right relationship — a camera
//  baseline it was shot with, and often an authored disparity adjustment
//  saying where its scene should sit relative to the window it is shown in.
//  Convergence is the author's ride ON TOP of that: it moves where the
//  content appears in depth relative to its Video Panel, and it moves nothing
//  else.
//
//  WHY IT LIVES HERE AND NOT ON THE ENTITY. Animation 2.0 already had
//  everything this needs — bezier curves with (dt,dv) handles at ABSOLUTE
//  sequence seconds, one evaluator, one graph editor — and it was unreachable
//  because `EntityAnimationTrack` is keyed by `entity`. A screen IS an entity,
//  but convergence is not a property of the screen: it is a property of the
//  MEDIA on the screen, so two clips on one panel can want different values
//  and a panel with no clip on it has no convergence at all. Audio hit exactly
//  this and solved it by keying automation on the playback identity rather
//  than on an entity; this is the same answer for the same reason.
//
//  KEYED BY DESTINATION, because playback identity IS destination identity —
//  the rule `DestinationChannelNaming` already states. One screen is one
//  voice: two films on one screen share a track and are told apart by time,
//  exactly as two clips on one audio channel are.
//
//  COMPOSITION IS ADDITIVE, NOT MULTIPLICATIVE.
//
//      effective = playVideo.convergence + destinationCurve(t)
//
//  Convergence is a DISPLACEMENT of the zero-parallax plane, so its identity
//  is 0 and rides sum — the same distinction `AudioAutomationChannel.restValue`
//  draws between volume (multiplies, rest 1) and pan (displaces, rest 0).
//
//  THERE IS NO MASTER CONVERGENCE, deliberately, and for the reason there is
//  no master pan: "push the whole film back a bit" is not a note anyone gives,
//  and a global term summed into every clip would move a carefully judged
//  stereo window with no way to see why.
//
//  ZERO MEANS THE SOURCE'S OWN INTENT. It does not mean "no disparity": the
//  file's embedded adjustment is still honoured underneath. Nothing here ever
//  writes to source media.
//

import Foundation

/// What can be automated on a video destination's stereo presentation.
///
/// One case today. The enum exists rather than a bare curve for the same
/// reason `AudioAutomationChannel` does: the decoder DROPS unknown parameter
/// names instead of throwing, so a document written by a later tool with a
/// second stereo parameter still opens here.
public enum StereoAutomationChannel: String, Codable, Sendable, CaseIterable, Hashable {
    /// Where the source's content sits in depth relative to its panel, as a
    /// fraction of image width. Positive pushes the scene further away.
    case convergence

    /// The value used where the curve has no keys — the IDENTITY for this
    /// parameter's composition. Convergence displaces, so its identity is 0;
    /// a rest of 1 would silently shove every un-automated clip a whole image
    /// width out of alignment.
    public var restValue: Float { 0 }

    /// The range a value is clamped into before it is stored or applied.
    ///
    /// A quarter of image width is already far past anything comfortable; the
    /// clamp exists so a bezier handle overshooting past a key cannot produce
    /// a frame sampled from outside its own picture. The Inspector offers a
    /// much narrower slider — a creative range and a safety range are
    /// different numbers and should not be confused.
    public var range: ClosedRange<Float> { -0.25...0.25 }
}

/// Automation curves for ONE video destination, over the sequence's timeline.
///
/// `destination` matches `MediaDestination.key` — the screen, not the file.
public struct StereoAutomationTrack: Codable, Sendable, Equatable {

    public var destination: String
    public var curves: [StereoAutomationChannel: AnimationCurve]

    public init(destination: String, curves: [StereoAutomationChannel: AnimationCurve] = [:]) {
        self.destination = destination
        self.curves = curves
    }

    /// Setting an emptied curve REMOVES it, so `hasAnyKeys` cannot be fooled
    /// by a track full of empty curves — the same rule `EntityAnimationTrack`
    /// and `AudioAutomationTrack` use.
    public subscript(_ channel: StereoAutomationChannel) -> AnimationCurve {
        get { curves[channel] ?? AnimationCurve() }
        set { curves[channel] = newValue.isAnimated ? newValue : nil }
    }

    public var hasAnyKeys: Bool { curves.values.contains { $0.isAnimated } }

    /// Union of key times across channels, sorted and deduplicated within the
    /// curve epsilon.
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

    // Dictionary-with-enum-key encodes as an array pair in JSON, which is
    // unreadable in a hand-inspected document. Encode as a keyed object.
    private enum CodingKeys: String, CodingKey { case destination, curves }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.destination = try c.decode(String.self, forKey: .destination)
        let raw = try c.decodeIfPresent([String: AnimationCurve].self, forKey: .curves) ?? [:]
        var curves: [StereoAutomationChannel: AnimationCurve] = [:]
        for (key, curve) in raw {
            guard let channel = StereoAutomationChannel(rawValue: key) else { continue }
            curves[channel] = curve
        }
        self.curves = curves
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(destination, forKey: .destination)
        var raw: [String: AnimationCurve] = [:]
        for (channel, curve) in curves where curve.isAnimated {
            raw[channel.rawValue] = curve
        }
        try c.encode(raw, forKey: .curves)
    }
}

/// Resolves automated stereo values at a point in sequence time.
public enum SequenceStereoAutomation {

    /// The convergence ride for `destination` at `time`.
    ///
    /// Returns 0 when nothing is animated, so this can be applied
    /// unconditionally on every frame without asking whether a document uses
    /// stereo automation at all.
    public static func convergenceRide(
        for destination: String,
        at time: Double,
        in tracks: [StereoAutomationTrack]
    ) -> Float {
        guard let track = tracks.first(where: { $0.destination == destination }) else { return 0 }
        let curve = track[.convergence]
        guard curve.isAnimated else { return 0 }
        return SequenceAnimationEvaluator.evaluate(
            curve, at: time, rest: StereoAutomationChannel.convergence.restValue)
    }

    /// Effective convergence for a playing clip: its authored base plus the
    /// destination's ride.
    ///
    /// THIS IS THE ONE RULE. The Viewer, the offline renderer and any future
    /// runtime all call it, so they cannot disagree about where a stereo
    /// window sits — the same reason `effectiveVolume` exists for audio.
    public static func effectiveConvergence(
        base: Float,
        destination: String,
        at time: Double,
        in tracks: [StereoAutomationTrack]
    ) -> Float {
        let range = StereoAutomationChannel.convergence.range
        let summed = base + convergenceRide(for: destination, at: time, in: tracks)
        return min(max(summed, range.lowerBound), range.upperBound)
    }
}
