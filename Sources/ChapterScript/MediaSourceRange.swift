//
//  MediaSourceRange.swift
//  ChapterScript
//
//  MARK IN / MARK OUT — ONE MEANING, EVERY MEDIUM.
//
//  An asset is a MASTER SOURCE. A use of that asset on a timeline is an
//  INSTANCE of a RANGE of that master. Video already had this shape
//  (`VideoActionDTO.sourceIn/.sourceOut`); audio and backdrop cues did not,
//  so an author could mark a range on a movie and not on a WAV, and the two
//  behaved differently for no reason a user could see.
//
//  This is the range itself, lifted out of `VideoActionDTO` so there is ONE
//  set of rules — validation, clamping, duration, and the sequence-time →
//  source-time mapping — instead of one set per playback system. The fade-out
//  bug that came from duplicated timing semantics is the reason this type
//  exists rather than three private helpers.
//
//  WIRE COMPATIBILITY IS NON-NEGOTIABLE.
//
//  This type is NOT how a range is stored. Every carrier keeps its own two
//  flat `sourceIn` / `sourceOut` keys exactly where they already were, so
//  documents written before this pass decode byte-for-byte unchanged and
//  documents written after it are still readable by an older player (which
//  simply ignores the keys it does not know). `MediaSourceRange` is the
//  in-memory lens over those two fields — see the `sourceRange` accessors on
//  `VideoActionDTO`, `AudioActionDTO` and `BackdropCue`.
//
//  BOTH ENDS ARE OPTIONAL, AND THAT IS MEANINGFUL.
//
//    sourceIn  == nil  →  from the master's first frame
//    sourceOut == nil  →  through the master's natural end
//
//  `nil` is not a synonym for a probed number. A document is authored before
//  its media is necessarily probed, and an asset can be relinked to a longer
//  or shorter master later; writing "0 → 43.7" at authoring time would freeze
//  a technical measurement into an authored decision. "Whole source" stays
//  expressible.
//

import Foundation

/// A non-destructive window into a master media file, in master-file seconds.
///
/// The master's bytes are never re-encoded or duplicated — a range is pure
/// metadata, so asset hashes (and live-sync caches) stay stable, and any
/// number of instances can cut different windows out of one master without
/// affecting each other.
public struct MediaSourceRange: Codable, Sendable, Equatable {

    /// Seconds into the master where this instance begins. `nil` means the
    /// master's start.
    public var sourceIn: Double?

    /// Exclusive end in master-file seconds. `nil` means the master's natural
    /// end. Looping loops the `[sourceIn, sourceOut)` window, never the whole
    /// file.
    public var sourceOut: Double?

    public init(sourceIn: Double? = nil, sourceOut: Double? = nil) {
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }

    /// The whole master — the default for every medium, and what every
    /// pre-existing document means.
    public static let full = MediaSourceRange()

    /// True when neither end is marked. Editors use this to draw a clip as
    /// "full source" rather than showing redundant in/out numbers.
    public var isFullSource: Bool { sourceIn == nil && sourceOut == nil }

    /// True when either end is marked.
    public var isMarked: Bool { !isFullSource }

    // MARK: - Resolution

    /// Where playback starts, in master seconds. Always defined — an unmarked
    /// in-point is the file's start.
    public var resolvedIn: Double { max(0, sourceIn ?? 0) }

    /// Where playback ends, in master seconds, given what is known about the
    /// master. Returns `nil` only when the out-point is unmarked AND the
    /// master duration is unknown — i.e. genuinely "play until it ends".
    ///
    /// A marked out-point past the end of a known master is clamped rather
    /// than honoured: a player cannot show frames that do not exist, and
    /// silently reporting an unreachable end makes held-tail and loop math
    /// wrong everywhere downstream.
    public func resolvedOut(masterDuration: Double?) -> Double? {
        switch (sourceOut, masterDuration) {
        case let (out?, master?): return min(out, master)
        case let (out?, nil):     return out
        case let (nil, master?):  return master
        case (nil, nil):          return nil
        }
    }

    /// How much content this range actually offers, or `nil` when that cannot
    /// be known yet (unmarked out-point on an unprobed master).
    ///
    /// This — not the master's length — is what a timeline means by "content
    /// available": a 60-second master cut 20 → 27 offers 7 seconds, and loop
    /// divisions and held tails must both divide against 7.
    ///
    /// Never returns a negative number. A reversed range is a validation
    /// failure, not a negative duration to propagate into layout math.
    public func duration(masterDuration: Double?) -> Double? {
        guard let out = resolvedOut(masterDuration: masterDuration) else { return nil }
        return max(0, out - resolvedIn)
    }

    // MARK: - Sequence time → source time

    /// The master-file time to show for `elapsed` seconds into this instance.
    ///
    /// THE mapping, in one place. A clip placed at sequence t=10 using source
    /// 30 → 40 shows source 30 at sequence 10 and source 35 at sequence 15 —
    /// not source 5. Every preview, scrub compositor and runtime path routes
    /// here rather than re-deriving `sourceIn + elapsed`, because the version
    /// that forgets the `+ sourceIn` looks correct on an unmarked clip and
    /// fails only on marked ones.
    ///
    /// - Parameters:
    ///   - elapsed: seconds since this instance began. Negative values clamp
    ///     to the in-point.
    ///   - masterDuration: probed master length, if known.
    ///   - looping: when true, `elapsed` past the window's end wraps back to
    ///     the in-point — looping the SELECTED window, not the whole file.
    ///     When false, time past the end holds the last available instant,
    ///     which is what a held tail shows.
    /// FL-13: THE ONE MAPPING GAINS PARAMETERS — NEVER A SIBLING.
    ///
    ///   - retime: the occurrence's authored curve. `.identity` (the
    ///     default) is a branch and costs nothing — today's exact
    ///     behaviour for every existing Chapter.
    ///   - clipSpan: the occurrence's CURRENT Timeline span in seconds.
    ///     The curve's domain is normalized 0…1 across the span, so a
    ///     keyed curve needs it; identity ignores it.
    ///   - nativeRateCorrection: FL-03's A5 factor (chapter ÷ source fps),
    ///     composed multiplicatively with ELAPSED on the identity path. A
    ///     keyed curve states ABSOLUTE source positions — authored facts —
    ///     and is not corrected.
    ///
    /// Under a keyed curve the result is clamped to the authored window:
    /// the curve chooses WHEN within the window each output frame samples,
    /// and can never sample outside it. Looping does not apply under a
    /// keyed curve — the curve is the complete statement of the mapping.
    public func sourceTime(
        forElapsed elapsed: Double,
        masterDuration: Double?,
        looping: Bool = false,
        retime: RetimeCurve = .identity,
        clipSpan: Double? = nil,
        nativeRateCorrection: Double = 1
    ) -> Double {
        if !retime.isIdentity, let span = clipSpan, span > 0 {
            let fraction = min(max(elapsed / span, 0), 1)
            if let position = retime.sourcePosition(atFraction: fraction) {
                let lower = resolvedIn
                if let upper = resolvedOut(masterDuration: masterDuration) {
                    return min(max(position, lower), upper)
                }
                return max(position, lower)
            }
        }
        let start = resolvedIn
        let factor = (nativeRateCorrection > 0 && nativeRateCorrection.isFinite)
            ? nativeRateCorrection : 1
        let offset = max(0, elapsed) * factor
        guard let window = duration(masterDuration: masterDuration), window > 0 else {
            // No known end: the window is open, so elapsed maps straight
            // through. This is the unprobed-master case, and it degrades to
            // exactly the pre-source-range behaviour.
            return start + offset
        }
        if offset < window { return start + offset }
        if looping { return start + offset.truncatingRemainder(dividingBy: window) }
        return start + window
    }

    // MARK: - Validation

    public enum Problem: Error, Equatable, Sendable, CustomStringConvertible {
        /// Out-point at or before the in-point. Reported rather than silently
        /// swapped: an author who drags Out past In means to shorten the
        /// clip, and swapping would move the frames they were watching.
        case outNotAfterIn(sourceIn: Double, sourceOut: Double)
        /// The window is shorter than one frame. A sub-frame clip has no
        /// showable content but still occupies a timeline span.
        case shorterThanMinimum(duration: Double, minimum: Double)
        /// The in-point is at or past the end of the master.
        case inPastEndOfMedia(sourceIn: Double, masterDuration: Double)
        /// An operation needed the master's length and it has not been probed.
        case masterDurationUnknown

        public var description: String {
            switch self {
            case let .outNotAfterIn(i, o):
                return String(format: "Out point (%.3fs) must come after In point (%.3fs).", o, i)
            case let .shorterThanMinimum(d, m):
                return String(format: "Selected range is %.3fs — shorter than the %.3fs minimum (one frame).", d, m)
            case let .inPastEndOfMedia(i, master):
                return String(format: "In point (%.3fs) is past the end of the media (%.3fs).", i, master)
            case .masterDurationUnknown:
                return "The media's duration is not known yet."
            }
        }
    }

    /// One frame at the editor's default 24 fps. Callers that own a timebase
    /// should pass their own frame duration instead of relying on this.
    public static let defaultMinimumDuration: Double = 1.0 / 24.0

    /// Slack for comparisons on times that were produced by subtraction.
    /// Well below a frame at any plausible rate, well above double error at
    /// media timescales.
    public static let timeEpsilon: Double = 1e-9

    /// Throws the first thing wrong with this range, or returns.
    ///
    /// `masterDuration` is optional so a range can be sanity-checked before
    /// the probe lands; the checks that need it are simply skipped, and a
    /// caller that requires it asks for it explicitly.
    public func validate(
        masterDuration: Double? = nil,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) throws {
        let start = resolvedIn
        if let master = masterDuration, start >= master {
            throw Problem.inPastEndOfMedia(sourceIn: start, masterDuration: master)
        }
        if let out = sourceOut, out <= start {
            throw Problem.outNotAfterIn(sourceIn: start, sourceOut: out)
        }
        // Compared with a tolerance because an exactly-one-frame window is
        // legal and is routinely PRODUCED by subtraction (a clamp against the
        // master's end). Without the slack, the range this type just built to
        // satisfy the minimum would fail its own validation.
        if let length = duration(masterDuration: masterDuration),
           length < minimumDuration - MediaSourceRange.timeEpsilon {
            throw Problem.shorterThanMinimum(duration: length, minimum: minimumDuration)
        }
    }

    public func isValid(
        masterDuration: Double? = nil,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) -> Bool {
        (try? validate(masterDuration: masterDuration, minimumDuration: minimumDuration)) != nil
    }

    // MARK: - Constrained edits

    /// This range confined to a known master, preserving the marks that are
    /// already legal.
    ///
    /// Clamping never turns a marked range into an invalid one: if the
    /// in-point would land past the last frame, it is pulled back so at least
    /// `minimumDuration` of content remains.
    public func clamped(
        toMasterDuration masterDuration: Double,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) -> MediaSourceRange {
        guard masterDuration > 0 else { return .full }
        let floorIn = max(0, min(resolvedIn, max(0, masterDuration - minimumDuration)))
        var out = sourceOut.map { min($0, masterDuration) }
        if let candidate = out, candidate <= floorIn {
            out = min(masterDuration, floorIn + minimumDuration)
        }
        return MediaSourceRange(sourceIn: sourceIn == nil && floorIn == 0 ? nil : floorIn,
                                sourceOut: out)
    }

    /// Move both marks through the master without changing the window's
    /// length — a SLIP. The instance's timeline start, end and duration are
    /// the caller's business and must not move.
    ///
    /// Slipping against an unknown master is refused rather than guessed: a
    /// slip that cannot be clamped will happily run off the end of the file
    /// and produce a clip that plays black.
    public func slipped(
        by delta: Double,
        masterDuration: Double?,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) -> MediaSourceRange {
        guard let window = duration(masterDuration: masterDuration), window > 0 else {
            // Open-ended window: only the in-point can move, and only forward
            // of zero.
            let moved = max(0, resolvedIn + delta)
            return MediaSourceRange(sourceIn: moved, sourceOut: sourceOut)
        }
        guard let master = masterDuration else {
            let moved = max(0, resolvedIn + delta)
            return MediaSourceRange(sourceIn: moved, sourceOut: moved + window)
        }
        let highestIn = max(0, master - window)
        let moved = min(max(0, resolvedIn + delta), highestIn)
        return MediaSourceRange(sourceIn: moved, sourceOut: min(master, moved + window))
    }

    /// Move the in-point only — a left-edge trim. The out-point holds, so the
    /// window's length changes.
    public func trimmingStart(
        to newIn: Double,
        masterDuration: Double?,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) -> MediaSourceRange {
        var candidate = max(0, newIn)
        if let out = resolvedOut(masterDuration: masterDuration) {
            candidate = min(candidate, max(0, out - minimumDuration))
        } else if let master = masterDuration {
            candidate = min(candidate, max(0, master - minimumDuration))
        }
        return MediaSourceRange(sourceIn: candidate, sourceOut: sourceOut)
    }

    /// Move the out-point only — a right-edge trim. The in-point holds.
    ///
    /// A normal trim does not run past the end of the master. Going beyond
    /// available content is Loop or Hold, and those are separate, explicit
    /// authoring choices rather than a side effect of dragging far enough.
    public func trimmingEnd(
        to newOut: Double,
        masterDuration: Double?,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) -> MediaSourceRange {
        var candidate = max(resolvedIn + minimumDuration, newOut)
        if let master = masterDuration { candidate = min(candidate, master) }
        return MediaSourceRange(sourceIn: sourceIn, sourceOut: candidate)
    }

    /// Both marks at once, clamped to the master when it is known.
    public func setting(
        sourceIn newIn: Double?,
        sourceOut newOut: Double?,
        masterDuration: Double?,
        minimumDuration: Double = MediaSourceRange.defaultMinimumDuration
    ) -> MediaSourceRange {
        let candidate = MediaSourceRange(sourceIn: newIn, sourceOut: newOut)
        guard let master = masterDuration else { return candidate }
        return candidate.clamped(toMasterDuration: master, minimumDuration: minimumDuration)
    }
}

// MARK: - Carriers

//  Each carrier keeps its own flat `sourceIn` / `sourceOut` fields — the wire
//  format does not change — and exposes them through one lens so authoring
//  code never touches the pair directly. Setting `.full` clears both marks
//  rather than writing zeros, which keeps "whole source" distinguishable from
//  "marked to the whole source" and keeps clean documents free of noise.

extension VideoActionDTO {
    public var sourceRange: MediaSourceRange {
        get { MediaSourceRange(sourceIn: sourceIn, sourceOut: sourceOut) }
        set { sourceIn = newValue.sourceIn; sourceOut = newValue.sourceOut }
    }
}

extension AudioActionDTO {
    public var sourceRange: MediaSourceRange {
        get { MediaSourceRange(sourceIn: sourceIn, sourceOut: sourceOut) }
        set { sourceIn = newValue.sourceIn; sourceOut = newValue.sourceOut }
    }
}

extension BackdropCue {
    /// The cue's window into its video master. Always `.full` for image and
    /// USDZ cues — reading a range off a static backdrop returns "whole
    /// source" rather than trapping, and writing one to it is dropped, so a
    /// mis-routed editor control cannot corrupt a static cue.
    public var sourceRange: MediaSourceRange {
        get {
            guard supportsSourceRange else { return .full }
            return MediaSourceRange(sourceIn: sourceIn, sourceOut: sourceOut)
        }
        set {
            guard supportsSourceRange else { return }
            sourceIn = newValue.sourceIn
            sourceOut = newValue.sourceOut
        }
    }
}
