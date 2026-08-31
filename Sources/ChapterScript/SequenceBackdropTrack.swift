//
//  SequenceBackdropTrack.swift
//  ChapterScript
//
//  BACKDROPS ON A TIMELINE — STILL ONE AT A TIME.
//
//  A sequence used to have exactly one backdrop (`immersiveBackdrop`), untimed,
//  covering the whole sequence. So a chapter that opens on a 360° establishing
//  shot, moves into a USDZ set, and ends on a still could only be authored as
//  three sequences — splitting the timeline for a reason that has nothing to do
//  with the content's structure.
//
//  This is a backdrop TRACK: an ordered list of cues, each at an absolute
//  sequence time, each carrying any backdrop kind (video 360/180, image, USDZ)
//  or `nil` for "no backdrop from here".
//
//  EXCLUSIVITY IS BY CONSTRUCTION, NOT BY VALIDATION.
//
//  A cue has a start and no end: it runs until the next cue begins, or until
//  the sequence ends. Two backdrops cannot overlap because an overlap cannot be
//  written down. That is the whole reason the model is a list of start times
//  rather than a list of ranges — a range model would need a validator, a
//  conflict UI, and a rule for what to show when the author produces an
//  overlap anyway. Here there is nothing to validate and nothing to resolve.
//
//  Editors present this as a pinned lane whose clips tile the sequence
//  end-to-end: dragging a cue moves the boundary between two backdrops, which
//  is exactly what the author means.
//

import Foundation

/// One backdrop change at a point in sequence time.
public struct BackdropCue: Codable, Sendable, Equatable, Identifiable {

    /// Stable identity so an editor can select and drag a cue across a
    /// re-sort. Positional indices are not usable for this — retiming a cue
    /// past its neighbour reorders the list underneath the selection.
    public var id: String

    /// Absolute seconds from sequence start. Clamped at zero on decode: a
    /// negative cue could never be reached and would silently shadow the one
    /// the author expected to see first.
    public var startTime: Double

    /// What to show from `startTime` onward. `nil` means NO backdrop — the
    /// explicit "clear it" cue. Without this, a backdrop could be started but
    /// never stopped within a sequence.
    public var spec: ImmersiveBackdropSpec?

    /// Non-destructive source trim for a VIDEO backdrop, in master-file
    /// seconds. `nil` means the whole source, which is what every cue written
    /// before this field existed means.
    ///
    /// The range lives on the CUE, not on the spec, for the same reason it
    /// lives on `playVideo` rather than on the asset: it belongs to the
    /// INSTANCE. The same 360° master can open one sequence at 00:10 and close
    /// another at 02:40, and neither edit may disturb the other.
    ///
    /// Meaningless for `.image` and `.usdz` cues — they have no temporal
    /// extent, so an editor must not offer In/Out controls for them and a
    /// player ignores these fields. See `supportsSourceRange`.
    public var sourceIn: Double?
    /// Exclusive end in master-file seconds. `nil` plays to the master's end.
    public var sourceOut: Double?

    /// Seconds to CROSS-FADE from whatever was showing into this cue.
    ///
    /// `nil` (and 0) mean a hard cut, which is what every cue written before
    /// this field existed means — so old documents keep their exact behaviour
    /// and the key is simply absent unless an author asked for a fade.
    ///
    /// The fade belongs to the INCOMING cue, not to a transition object sitting
    /// between two of them. A cue can be moved, deleted or have its media
    /// swapped, and a between-cues object would have to be found and repaired on
    /// every one of those edits — whereas "this backdrop arrives over 1.5s" is a
    /// property of the cue and travels with it. It also composes with the clear
    /// cue for free: `spec == nil` with a fade is a fade to nothing, so fading
    /// OUT needs no separate concept. Same idiom as `RevealActionDTO.fadeIn`.
    ///
    /// A player that has never heard of this ignores the key and cuts.
    public var fadeIn: Double?
    /// THE EFFECT STACK (FL-09) on this backdrop occurrence. Same contract
    /// as `VideoActionDTO.effects`.
    public var effects: [EffectInstance]?

    public init(
        id: String = UUID().uuidString,
        startTime: Double,
        spec: ImmersiveBackdropSpec?,
        sourceIn: Double? = nil,
        sourceOut: Double? = nil,
        fadeIn: Double? = nil
    ) {
        self.id = id
        self.startTime = max(0, startTime)
        self.spec = spec
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.fadeIn = fadeIn.map { max(0, $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, spec, sourceIn, sourceOut, fadeIn, effects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A cue written without an id (hand-authored JSON) still has to be
        // addressable, so mint one rather than failing the document.
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.startTime = max(0, try c.decodeIfPresent(Double.self, forKey: .startTime) ?? 0)
        self.spec = try c.decodeIfPresent(ImmersiveBackdropSpec.self, forKey: .spec)
        self.sourceIn = try c.decodeIfPresent(Double.self, forKey: .sourceIn)
        self.sourceOut = try c.decodeIfPresent(Double.self, forKey: .sourceOut)
        self.fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn).map { max(0, $0) }
        self.effects = try c.decodeIfPresent([EffectInstance].self, forKey: .effects)
    }

    /// Whether this cue actually fades rather than cutting. The one place that
    /// decides, so a zero and a nil can never disagree across the editor, the
    /// preview and the player.
    public var isCrossFaded: Bool { (fadeIn ?? 0) > 0.0005 }

    /// How far through the incoming fade `time` is, 0…1. Returns 1 (fully in)
    /// for a cue that cuts, so a caller can multiply by this unconditionally.
    public func fadeProgress(at time: Double) -> Double {
        guard isCrossFaded, let fade = fadeIn else { return 1 }
        let elapsed = time - startTime
        if elapsed <= 0 { return 0 }
        if elapsed >= fade { return 1 }
        return elapsed / fade
    }

    /// Whether marking In/Out on this cue means anything. Only video backdrops
    /// run on a clock; an editor asks this instead of pattern-matching the
    /// spec in every view that draws a trim control.
    public var supportsSourceRange: Bool {
        if case .video = spec { return true }
        return false
    }
}

/// Resolves which backdrop is showing at a point in sequence time.
public enum SequenceBackdropTimeline {

    /// The cue list to actually evaluate, folding the legacy single backdrop
    /// into the track so there is ONE resolution path.
    ///
    /// A document written before the track existed carries
    /// `immersiveBackdrop` and an empty `backdropTrack`; it resolves to that
    /// one backdrop for the whole sequence, which is exactly the old
    /// behaviour. When a track IS authored it wins outright — an editor that
    /// writes cues also clears the legacy field, and a reader that sees both
    /// must not composite them.
    public static func effectiveCues(
        track: [BackdropCue],
        legacy: ImmersiveBackdropSpec?
    ) -> [BackdropCue] {
        if !track.isEmpty {
            return track.sorted { $0.startTime < $1.startTime }
        }
        guard let legacy else { return [] }
        return [BackdropCue(id: "legacy", startTime: 0, spec: legacy)]
    }

    /// The backdrop showing at `time`, or nil when none is.
    ///
    /// Nil before the first cue is deliberate: an author whose first cue is at
    /// 4s gets no backdrop for the first four seconds, which is what a cue at
    /// 4s means. Starting at zero instead would make the first cue's time
    /// unauthorable.
    public static func backdrop(
        at time: Double,
        track: [BackdropCue],
        legacy: ImmersiveBackdropSpec? = nil
    ) -> ImmersiveBackdropSpec? {
        activeCue(at: time, track: track, legacy: legacy)?.spec
    }

    /// The cue governing `time` — the last one that has started.
    public static func activeCue(
        at time: Double,
        track: [BackdropCue],
        legacy: ImmersiveBackdropSpec? = nil
    ) -> BackdropCue? {
        effectiveCues(track: track, legacy: legacy)
            .last { $0.startTime <= time + AnimationCurve.timeEpsilon }
    }

    /// What is on screen at `time` when cross-fades are honoured.
    ///
    /// `incoming` is the governing cue, exactly as `activeCue` reports it, so a
    /// caller that ignores fades is never wrong — only less pretty. `outgoing`
    /// is non-nil ONLY while the incoming cue's fade is still running, and is
    /// the cue that was governing immediately before it; `progress` is 0…1
    /// across that fade.
    ///
    /// Resolving this here rather than in each player means the editor's
    /// preview and the device agree about what a fade looks like at a given
    /// instant — the same reason `SequenceAnimationEvaluator` is one truth.
    public static func transition(
        at time: Double,
        track: [BackdropCue],
        legacy: ImmersiveBackdropSpec? = nil
    ) -> (outgoing: BackdropCue?, incoming: BackdropCue?, progress: Double) {
        let cues = effectiveCues(track: track, legacy: legacy)
        guard let index = cues.lastIndex(where: {
            $0.startTime <= time + AnimationCurve.timeEpsilon
        }) else { return (nil, nil, 1) }

        let incoming = cues[index]
        let progress = incoming.fadeProgress(at: time)
        guard progress < 1, index > 0 else { return (nil, incoming, 1) }
        return (cues[index - 1], incoming, progress)
    }

    /// Each cue paired with the instant it stops governing — the next cue's
    /// start, or `sequenceDuration` for the last one. This is what an editor
    /// draws: contiguous, non-overlapping regions tiling the sequence.
    public static func regions(
        track: [BackdropCue],
        legacy: ImmersiveBackdropSpec? = nil,
        sequenceDuration: Double
    ) -> [(cue: BackdropCue, endTime: Double)] {
        let cues = effectiveCues(track: track, legacy: legacy)
        return cues.enumerated().map { index, cue in
            let next = index + 1 < cues.count ? cues[index + 1].startTime : sequenceDuration
            // A cue retimed past its neighbour would otherwise draw a negative
            // width; clamping keeps the lane renderable mid-drag.
            return (cue, max(next, cue.startTime))
        }
    }

    /// Asset filenames every cue references — what a bundle has to ship and
    /// what a player should preload.
    public static func referencedAssets(
        track: [BackdropCue],
        legacy: ImmersiveBackdropSpec? = nil
    ) -> [String] {
        var seen: [String] = []
        for cue in effectiveCues(track: track, legacy: legacy) {
            let file: String?
            switch cue.spec {
            case .video(let f, _, _, _, _, _): file = f
            case .image(let f, _, _):          file = f
            case .usdz(let assetId):           file = assetId
            // A placeholder references NO file — that is the whole point of
            // it — so it contributes nothing to preload.
            case .placeholder:                 file = nil
            case .none:                        file = nil
            @unknown default:                  file = nil
            }
            if let file, !seen.contains(file) { seen.append(file) }
        }
        return seen
    }
}
